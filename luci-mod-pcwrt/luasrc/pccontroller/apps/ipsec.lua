require "nixio"
require "nixio.fs"
require "luci.pcutil"
require "luci.sys"
require "luci.ip"
local http = require "luci.http"
local util = require "luci.util"
local jsonc = require "luci.jsonc"
local uci = require "luci.pcuci"
local dt = require "luci.cbi.datatypes"
local i18n = require "luci.i18n"
local conf = require "luci.pcconfig"

module("luci.pccontroller.apps.ipsec", package.seeall)

ordering = 60
function display_name()
    return return nixio.fs.access('/etc/init.d/ipsec', 'x') and i18n.translate('strongSwan (IPsec)') or nil
end

local config = 'ipsec'
local user_ip_start = 100
local user_ip_max = 255

local work_dir_root = '/tmp/ipsec-clients'
local work_dir = work_dir_root .. '/work'
local work_clidir = work_dir_root .. '/staging'
local ipsecd = '/etc/ipsec.d'
local root_ca = '/etc/ipsec.d/cacerts/pcwrt-root-ca.pem'

local required_files = {
    '/etc/ipsec.d/private/pcwrt-root-ca.pem',
    '/etc/ipsec.d/cacerts/pcwrt-root-ca.pem',
    '/etc/ipsec.d/private/pcwrt-strongswan-server.pem',
    '/etc/ipsec.d/certs/pcwrt-strongswan-server.pem',
}

local function ipsec_initialized()
    for _, f in ipairs(required_files) do
	local sz = nixio.fs.stat(f, 'size')
	if sz == nil or sz == 0 then
	    return false
	end
    end
    return true
end

local function get_p12_attr(line)
    local b, e = line:find('localKeyID: ')
    if e then
	return 'localKeyID', line:sub(e + 1):match('^%s*(.-)%s*$')
    end

    b, e = line:find('subject=')
    if e then
	return 'subject', line:sub(e + 1):match('^%s*(.-)%s*$')
    end

    b, e = line:find('issuer=')
    if e then
	return 'issuer', line:sub(e + 1):match('^%s*(.-)%s*$')
    end

    b, e = line:find('BEGIN CERTIFICATE')
    if e then
	return 'beginCert', line
    end

    b, e = line:find('END CERTIFICATE')
    if e then
	return 'endCert', line
    end

    b, e = line:find('BEGIN PRIVATE KEY')
    if e then
	return 'beginKey', line
    end

    b, e = line:find('END PRIVATE KEY')
    if e then
	return 'endKey', line
    end

    return nil
end

local function parse_p12pem(file)
    local key, cert = '', ''
    local content
    local attrs = {}
    local p12 = {
	certs = {},
	keys = {},
    }

    for line in io.lines(file) do
	local attr, value = get_p12_attr(line)
	if attr == 'beginCert' or attr == 'endCert' then
	    cert = cert .. value .. '\n'
	    content = attr == 'beginCert' and 'cert' or nil
	elseif attr == 'beginKey' or attr == 'endKey' then
	    key = key .. value .. '\n'
	    content = attr == 'beginKey' and 'key' or nil
	elseif attr ~= nil then
	    attrs[attr] = value
	elseif content == 'cert' then
	    cert = cert .. line .. '\n'
	elseif content == 'key' then
	    key = key .. line .. '\n'
	end

	if content == nil and (attr == 'endCert' or attr == 'endKey') and (#cert > 0 or #key > 0) then
	    local localKey = attrs['localKeyID']
	    if localKey then
		local p12key = p12.keys[localKey]
		if p12key == nil then
		    p12key = {}
		    p12.keys[localKey] = p12key
		end

		if #cert > 0 then
		    p12key.cert = cert
		elseif #key > 0 then
		    p12key.key = key
		end
	    elseif #cert > 0 then
		table.insert(p12.certs, cert)
	    end

	    cert, key = '', ''
	    attrs = {}
	end
    end

    return p12
end

local function get_enabled_network(c)
    local internal_ifs = get_internal_interfaces(c)
    local enabled_ifs = get_vpn_ifaces(c, 'ipsec')
    for _, nw in pairs(internal_ifs) do
	for _, enabled_if in ipairs(enabled_ifs) do
	    if nw.name == enabled_if then
		nw.enabled = true
		break
	    end
	end
    end

    return internal_ifs
end

local function get_users(c)
    local users = {}
    c:foreach(config, 'user', function(u)
	users[#users + 1] = {
	    type = u.type,
	    name = u.name,
	    password = unscramble_pwd(u.password),
	    ip = u.ip,
	    guest = u.guest == '1',
	    vpnout = u.vpnout == '1',
	}
    end)
    return users
end

local function server_init_running()
    local rc = fork_exec_wait("ps | grep gen-server-keys | grep -v grep")
    return rc == 0
end

local function unused_client_cert(f, cfgnames)
    f = f:match('conn@(.*)%.pem$')
    if not f then return false end

    local f2 = f:match('(.*)-%d*_ca$')
    if not f2 then f2 = f:match('(.*)_ca$') end
    if not f2 then f2 = f:match('(.*)_server$') end
    if not f2 then f2 = f:match('(.*)_client$') end
    if not f2 then return false end

    return not string_in_array(f2, cfgnames)
end

local function get_active_conn()
    local cs = {}
    local f = io.popen('ipsec status', 'r')
    local line = f:read()
    while line do
	local name, status = line:match('%s*(%S*)%[%d+%]:%s*(%S-)[, ]')
	if name and status then
	    cs[name] = status
	end
	line = f:read()
    end
    f:close()

    local c = uci.cursor()
    local conns = {}
    c:foreach(config, 'conn', function(conn)
	conns[#conns+1] = conn.name
    end)

    local cfg, cfg_state
    for name, state in pairs(cs) do
	for _, conn in ipairs(conns) do
	    if 'conn@' .. conn:gsub('[^0-9A-Za-z.]', '-') == name then
		cfg = conn
		cfg_state = state
		break
	    end
	end
	if cfg then break end
    end

    if cfg_state == 'ESTABLISHED' then
	cfg_state = 'connected'
    elseif cfg_state == 'CONNECTING' then
	cfg_state = 'running'
    else
	cfg_state = 'stopped'
    end

    return cfg, cfg_state
end

function init()
    local psk = random_string("ABCDEFGHJKLMNPQRSTUVWXYZ23456789", 25, 5)
    local c = uci.cursor()
    local s = c:get_first(config, 'server')
    if s ~= nil then
	c:set(config, s, 'psk', psk)
	c:commit(config)
    end

    fork_exec("/usr/share/ipsec/gen-server-keys.sh >/dev/null 2>&1")
    http.prepare_content('application/json')
    http.write_json({status = "success"})
end

function _get_data(c)
    local configs = {}
    c:foreach(config, 'authconfig', function(a)
	local cfgname = a.name:gsub('[^0-9A-Za-z.]', '-')
	local ca_subject, cli_subject
	if nixio.fs.access(ipsecd..'/cacerts/conn@'..cfgname..'_ca.pem') then
	    ca_subject = util.exec('openssl x509 -in '.. ipsecd..'/cacerts/conn@'..cfgname..'_ca.pem -subject -noout 2>/dev/null'):trim()
	elseif nixio.fs.access(ipsecd..'/certs/conn@'..cfgname..'_server.pem') then
	    ca_subject = util.exec('openssl x509 -in '.. ipsecd..'/certs/conn@'..cfgname..'_server.pem -subject -noout 2>/dev/null'):trim()
	end
	if nixio.fs.access(ipsecd..'/private/conn@'..cfgname..'_client.pem') and
	   nixio.fs.access(ipsecd..'/certs/conn@'..cfgname..'_client.pem') then
	    cli_subject = util.exec('openssl x509 -in '.. ipsecd..'/certs/conn@'..cfgname..'_client.pem -subject -noout 2>/dev/null'):trim()
	end
	configs[#configs + 1] = {
	    type = a.type,
	    name = a.name,
	    psk = a.psk,
	    username = a.username,
	    password = unscramble_pwd(a.password),
	    cadn = ca_subject,
	    clidn = cli_subject,
	}
    end)

    local cfg, cfg_state = get_active_conn()
    local conns = {}
    c:foreach(config, 'conn', function(n)
	conns[#conns + 1] = {
	    name = n.name,
	    host = n.host,
	    authconfig = n.authconfig,
	    autostart = n.autostart,
	    state = n.name == cfg and cfg_state or nil,
	}
    end)

    local s = c:get_first(config, 'server')
    local extaddr = c:get(config, s, 'extaddr')
    if string.is_empty(extaddr) then
	local sys_cfg_name = c:get_first('system', 'system')
	if c:get('system', sys_cfg_name, 'enable_ddns') == '1' then
	    extaddr = c:get('system', sys_cfg_name, 'ddnsname') .. '.pcwrt.net'
	else
	    local nw = require "luci.model.network"
	    local ntm = nw.init()
	    local wan_nets = ntm:get_wan_networks()
	    if #wan_nets > 0 then
		extaddr = wan_nets[1]:ipaddr()
	    end
	end
    end

    return {
	server = {
	    enabled = c:get(config, s, 'enabled') == '1',
	    extaddr = extaddr,
	    ipaddr = c:get(config, s, 'ipaddr'),
	    netmask = c:get(config, s, 'netmask'),
	    psk = c:get(config, s, 'psk'),
	    users = get_users(c),
	},
	client = {
	    enabled_network = get_enabled_network(c),
	    configs = configs,
	    conns = conns,
	}
    }
end

function index()
    local init_status = nil
    if not ipsec_initialized() then
	init_status = server_init_running() and 'in_progress' or 'init_needed'
    end

    local c = uci.cursor()
    local t = template('apps/ipsec')
    local ok, err = util.copcall(t.target, t, {
	title = translate('strongSwan (IPsec)'),
	init_status = init_status,
	hide_prog_alert = init_status ~= 'in_progress' and 'hidden' or nil,
	form_value_json = jsonc.stringify(_get_data(c)),
	page_script = 'apps/ipsec.js',
    })
    assert(ok, 'Failed to render template ' .. t.view .. ': ' .. tostring(err))
end

local function validate(v)
    local errs = {}

    if not (dt.hostname(v.extaddr) or dt.ipaddr(v.extaddr)) then
       errs.extaddr = i18n.translate('Please enter a valid IP address or hostname')
    end

    if not dt.ipaddr(v.ipaddr) then
	errs.ipaddr = i18n.translate('Invalid IP address')
    end

    if not dt.ipaddr(v.netmask) then
	errs.netmask = i18n.translate('Invalid net mask')
    end

    return errs
end

local function get_user_ip(users, user, ipaddr, netmask, usedips)
    local userip
    for _, u in ipairs(users) do
	if u.name == user then
	    userip = u.ip
	    break
	end
    end

    if userip == nil then
	userip = get_next_ip(ipaddr, netmask, usedips)
	usedips[#usedips + 1] = userip
    end

    return userip
end

function _update(c, v)
    local success, msg

    local s = c:get_first(config, 'server')
    if s == nil then
	s = c:section(config, 'server')
    end

    if v.enabled == '0' then
	c:set(config, s, 'enabled', '0')
	success, msg = c:commit(config)
	return {
	    status = success and 'success' or 'fail',
	    message = success and '' or i18n.translate('Failed to disable strongSwan Server') 
	}
    end

    local errs = validate(v)
    if next(errs) ~= nil then
	return {
	    status = 'error',
	    message = errs,
	}
    end

    local extaddr = c:get(config, s, 'extaddr')
    if extaddr ~= v.extaddr then
	c:set(config, s, 'extaddr', v.extaddr)
    end

    local oldip = c:get(config, s, 'ipaddr')
    local oldmask = c:get(config, s, 'netmask')

    c:set(config, s, 'enabled', '1')
    c:set(config, s, 'ipaddr', v.ipaddr)
    c:set(config, s, 'netmask', v.netmask)

    local users = get_users(c)
    local usedips = {}
    for _, u in ipairs(users) do
	if oldip ~= v.ipaddr or oldmask ~= v.netmask then
	    u.ip = fix_ip(u.ip, oldip, oldmask, v.ipaddr, v.netmask)
	end
	usedips[#usedips + 1] = u.ip
    end
    c:delete_all(config, 'user')

    local users2 = {}
    local create = {}
    local guestips = {}
    for _, user in ipairs(v.users) do
	if user.name and user.name:match('^[a-zA-Z0-9._%-\\%$@%%#&]*$') then
	    if user.type ~= 'ikev1' or not string.is_empty(user.password) then
		local ip = get_user_ip(users, user.name, v.ipaddr, v.netmask, usedips) 
		s = c:section(config, 'user')
		c:set(config, s, 'type', user.type == 'ikev1' and 'ikev1' or 'ikev2')
		c:set(config, s, 'name', user.name)
		if user.password then c:set(config, s, 'password', scramble_pwd(user.password)) end
		c:set(config, s, 'ip', ip) 
		if user.guest then
		    guestips[#guestips + 1] = ip
		    c:set(config, s, 'guest', '1')
		end
 		if user.vpnout then
  		    c:set(config, s, 'vpnout', '1')
   		end
		if user.type ~= 'ikev1' then
		    local cname = user.name:gsub('[^0-9A-Za-z.]', '-')
		    users2[#users2 + 1] = cname
		    create[cname] = user.create
		end
	    end
	end
    end

    local cert_dirs = { 'certs', 'private' }
    for _, dir in ipairs(cert_dirs) do
	for f in nixio.fs.glob(ipsecd..'/'..dir..'/user@*.pem') do
	    local u = f:match('/user@(.*)%.pem')
	    if not string_in_array(u, users2) or create[u] then
		nixio.fs.remove(f)
	    end
	end
    end

    local gen_certs = {}
    for _, user in ipairs(users2) do
	if not nixio.fs.access(ipsecd..'/certs/user@'..user..'.pem') or not nixio.fs.access(ipsecd..'/private/user@'..user..'.pem') then
	    gen_certs[#gen_certs + 1] = user
	end
    end

    if extaddr ~= v.extaddr then
	fork_exec('ipsec pki --pub --in /etc/ipsec.d/private/pcwrt-strongswan-server.pem | ipsec pki --issue --cacert /etc/ipsec.d/cacerts/pcwrt-root-ca.pem --cakey /etc/ipsec.d/private/pcwrt-root-ca.pem --dn "C=US, O=pcwrt.com, CN=pcWRT strongSwan server" --san dns:"'.. v.extaddr ..'" --flag serverAuth --flag ikeIntermediate --outform pem >/etc/ipsec.d/certs/pcwrt-strongswan-server.pem')
    end

    if #gen_certs > 0 then
	fork_exec("/usr/share/ipsec/gen-client-cert.sh "..table.concat(gen_certs, ' ').." >/dev/null 2>&1")
    end

    success, msg = c:commit(config)
    if success then
	update_vpn_guest_fw_rule(c, guestips, oldip, oldmask)
	success, msg = c:commit('firewall')
    end

    return {
        status = success and 'success' or 'fail',
	message = success and '' or translate('Failed to save configuration'),
	apply = config,
    }
end

function update()
    local c = uci.cursor()

    local content = ''
    local len = 0

    local function snk(chunk)
	if chunk then
	    content = content .. chunk
	    len = len + #chunk
	    if len > MAX_CFG_SIZE then
		return nil, "POST data length exceeds maximum allowed length"
	    end
	end
	return true
    end

    luci.ltn12.pump.all(http.source(), snk)
    local v = jsonc.parse(content)

    http.prepare_content('application/json')
    http.write_json(_update(c, v))
end

function download_cert()
    local v = http.formvalue()

    local user = v.user
    if not user then
	http.prepare_content('application/json')
	http.write_json({
	    status = 'fail',
	    message = i18n.translate('Unspecified user. Please try again.'),
	})
	return
    end

    user = user:gsub('[^0-9A-Za-z.]', '-')
    if not nixio.fs.access(ipsecd..'/certs/user@'..user..'.pem') or not nixio.fs.access(ipsecd..'/private/user@'..user..'.pem') then
	local cert_status
	if v.status then
	    if fork_exec_wait("ps | grep gen-client-cert | grep -v grep") == 0 then
		cert_status = 'in_progress'
	    else
		cert_status = 'unavailable'
	    end
	end
	http.prepare_content('application/json')
	http.write_json({
	    status = v.status and 'success' or 'fail',
	    cert_status = cert_status,
	    message = i18n.translate('User certificate not available.'),
	})
    elseif v.status then
	http.prepare_content('application/json')
	http.write_json({
	    status = 'success',
	    cert_status = 'ready',
	})
    else
	local password = v.password
	if password == nil then
	    password = ''
	elseif not password:match('^[a-zA-Z0-9._%-\\%$@%%#&]*$') then
	    password = ''
	end

	http.prepare_content('application/octet-stream')
	http.header('Content-Disposition', 'attachment; filename="%s.p12"' % {v.user})
	local reader = ltn12_popen("openssl pkcs12 -export -inkey "..ipsecd.."/private/user@"..user..".pem -in "..ipsecd.."/certs/user@"..user..".pem -name '"..v.user.."' -certfile "..ipsecd.."/cacerts/pcwrt-root-ca.pem -caname 'pcWRT IPsec CA' -passout pass:'"..password.."'")
	luci.ltn12.pump.all(reader, http.write)
    end
end

function download_cacert()
    http.prepare_content('application/octet-stream')
    http.header('Content-Disposition', 'attachment; filename="pcwrt-root-ca.pem"')
    local cacert = ''
    local f = io.open(root_ca, 'r')
    if f then
	cacert = f:read('*all')
	f:close()
    end
    http.write(cacert)
end

function _update_client(c, v)
    local success, msg

    local apply = {config}

    if not nixio.fs.access(ipsecd..'/cacerts') then
	nixio.fs.mkdirr(ipsecd..'/cacerts')
    end
    if not nixio.fs.access(ipsecd..'/certs') then
	nixio.fs.mkdirr(ipsecd..'/certs')
    end
    if not nixio.fs.access(ipsecd..'/private') then
	nixio.fs.mkdirr(ipsecd..'/private')
    end

    local iiface = v.networks
    if type(iiface) == 'string' then
	iiface = { iiface }
    end

    success = set_vpn_ifaces(c, 'ipsec', iiface, apply)
    if success then
	if update_firewall_rules_for_vpnc(c, 'ipsec', 'wan') then
	    add_if_not_exists(apply, 'firewall')
	end
    end

    local s
    local cfgnames = {}
    if success then
	c:delete_all(config, 'authconfig')
	for _, cfg in ipairs(v.configs) do
	    s = c:section(config, 'authconfig')
	    c:set(config, s, 'type', cfg.type == 'ikev1' and 'ikev1' or 'ikev2')
	    c:set(config, s, 'name', cfg.name)
	    if cfg.psk then
		c:set(config, s, 'psk', cfg.psk)
	    end
	    if cfg.cfguser then
		c:set(config, s, 'username', cfg.cfguser)
	    end
	    if cfg.cfgpass then
		c:set(config, s, 'password', scramble_pwd(cfg.cfgpass))
	    end
	    cfgnames[#cfgnames+1] = cfg.name
	end

	c:delete_all(config, 'conn')
	for _, conn in ipairs(v.conns) do
	    if string_in_array(conn.authconfig, cfgnames) and conn.name and (dt.hostname(conn.host) or dt.ipaddr(conn.host)) then
		s = c:section(config, 'conn')
		c:set(config, s, 'name', conn.name)
		c:set(config, s, 'host', conn.host)
		c:set(config, s, 'authconfig', conn.authconfig)
		if conn.autostart then
		    c:set(config, s, 'autostart', '1')
		else
		    c:delete(config, s, 'autostart')
		end
	    end
	end

	success, msg = c:commit(config)
    end

    if success then
	for i, v in ipairs(cfgnames) do
	    cfgnames[i] = v:gsub('[^0-9A-Za-z.]', '-')
	end

	local f
	local cert_dirs = { 'cacerts', 'certs', 'private' }
	for _, dir in ipairs(cert_dirs) do
	    for f in nixio.fs.dir(ipsecd..'/'..dir..'/') do
		if unused_client_cert(f, cfgnames) then
		    nixio.fs.remove(ipsecd..'/'..dir..'/'..f)
		end
	    end
	end

	for _, cfg in ipairs(v.configs) do
	    local cfgname = cfg.name:gsub('[^0-9A-Za-z.]', '-')
	    local cli_dir = work_clidir..'/'..cfgname
	    if nixio.fs.access(cli_dir..'/ca.pem') then
		if os.execute('openssl x509 -in '..cli_dir.."/ca.pem -noout -purpose | grep '^SSL server CA : Yes' >/dev/null 2>&1") == 0 then
		    local ci = 1
		    local line, ca_name, ca_content
		    for line in io.lines(cli_dir..'/ca.pem') do
			if line:find('BEGIN CERTIFICATE') then
			    ca_name = ipsecd..'/cacerts/conn@'..(ci == 1 and cfgname or cfgname ..'-'..ci)..'_ca.pem'
			    ca_content = line .. '\n'
			elseif line:find('END CERTIFICATE') then
			    ca_content = ca_content .. line .. '\n'
			    nixio.fs.writefile(ca_name, ca_content)
			    ci = ci + 1
			else
			    ca_content = ca_content .. line .. '\n'
			end
		    end
		else
		    nixio.fs.copy(cli_dir..'/ca.pem', ipsecd..'/certs/conn@'..cfgname..'_server.pem')
		end
	    end
	    if nixio.fs.access(cli_dir..'/client-cert.pem') then
		nixio.fs.copy(cli_dir..'/client-cert.pem', ipsecd..'/certs/conn@'..cfgname..'_client.pem')
	    end
	    if nixio.fs.access(cli_dir..'/client-key.pem') then
		os.execute('openssl rsa -in '..cli_dir..'/client-key.pem -out '..ipsecd..'/private/conn@'..cfgname..'_client.pem >/dev/null')
	    end
	end

	nixio.fs.remover(work_dir_root)
    end

    return {
	status = success and 'success' or 'fail',
	message = success and '' or i18n.translate('Failed to save configuration'),
	apply = apply,
    }
end

function update_client()
    local c = uci.cursor()

    local content = ''
    local len = 0

    local function snk(chunk)
	if chunk then
	    content = content .. chunk
	    len = len + #chunk
	    if len > MAX_CFG_SIZE then
		return nil, "POST data length exceeds maximum allowed length"
	    end
	end
	return true
    end

    luci.ltn12.pump.all(http.source(), snk)
    local v = jsonc.parse(content)

    http.prepare_content('application/json')
    http.write_json(_update_client(c, v))
end

function add_auth_config()
    local fp12 = work_dir .. '/ipsec.p12'
    local fp12pem = work_dir .. '/ipsec-p12.pem'
    local fca = work_dir .. '/ca.pem'
    local fccert = work_dir .. '/client-cert.pem'
    local fckey = work_dir .. '/client.pem'
    local fckey_dec = work_dir .. '/client-key.pem'

    nixio.fs.remover(work_dir)
    nixio.fs.mkdirr(work_dir)

    if not nixio.fs.access(ipsecd..'/cacerts') then
	nixio.fs.mkdirr(ipsecd..'/cacerts')
    end
    if not nixio.fs.access(ipsecd..'/certs') then
	nixio.fs.mkdirr(ipsecd..'/certs')
    end
    if not nixio.fs.access(ipsecd..'/private') then
	nixio.fs.mkdirr(ipsecd..'/private')
    end

    local fp, rc
    http.setfilehandler(
	function(meta, chunk, eof)
	    if not fp then
		if meta then
		    if meta.name == 'p12' then
			fp = io.open(fp12, 'w')
		    elseif meta.name == 'cacert' then
			fp = io.open(fca, 'w')
		    elseif meta.name == 'clicert' then
			fp = io.open(fccert, 'w')
		    elseif meta.name == 'clikey' then
			fp = io.open(fckey, 'w')
		    end
		end
		rc = fp
	    end
	    if chunk and fp then
		rc = fp:write(chunk)
	    end
	    if eof and fp then
		rc = fp:close()
		fp = nil
	    end
	end
    )

    local errs = {}
    local passin

    local v = http.formvalue()
    local cfgname = v.cfgname
    if cfgname then
	cfgname = cfgname:gsub('[^0-9A-Za-z.]', '-')
    else
	errs.cfgname = i18n.translate('Please enter a name for the VPN connection')
    end

    local oldcfgname = v.oldname
    if oldcfgname ~= nil then
	oldcfgname = oldcfgname:gsub('[^0-9A-Za-z.]', '-')
    end

    -- We need at least the server certificate or CA certificate
    local certtype = v.cert_type
    if certtype == 'p12' then
	passin = v.p12pass
	if string.is_empty(oldcfgname) and string.is_empty(v.p12) then
	    errs.p12file = i18n.translate('Please upload client PKCS12 file')
	end
    else
	passin = v.clikeypass
	if string.is_empty(oldcfgname) and string.is_empty(v.cacert) then
	    errs.cacertfile = i18n.translate('Please upload server certificate file')
	end
    end

    if passin == nil then
	passin = ''
    end

    http.prepare_content('application/json')

    local rc

    -- extract certs/key from P12 file
    if next(errs) == nil then
	if certtype == 'p12' then
	    if not string.is_empty(v.p12) then
		local rc = os.execute('openssl pkcs12 -in ' .. fp12 .. ' -out ' .. fp12pem .. " -passin pass:'" .. passin .. "' -nodes >/tmp/unpack-p12.log 2>&1")
		if rc ~= 0 then
		    local f = io.open('/tmp/unpack-p12.log', 'r')
		    local resp = f:read('*all')
		    f:close()
		    if resp:find('invalid password') then
			errs.p12pass = i18n.translate('Invalid PKCS12 password')
		    else
			errs.p12file = i18n.translate('Invalid PKCS12 file')
		    end
		end
		nixio.fs.remove('/tmp/unpack-p12.log')
	    end
	else
	    if not string.is_empty(v.cacert) then
		local cacert = nixio.fs.readfile(fca);
    		if not cacert:find('CERTIFICATE') then
		    rc = fork_exec_wait("openssl x509 -in "..fca.." -inform der >/tmp/ipsec.tmp")
		    if rc ~= 0 then
			errs.cacertfile = i18n.translate('Invalid server certification file')
		    else
			nixio.fs.move('/tmp/ipsec.tmp', fca)
		    end
    		end
	    end

	    if next(errs) == nil and not string.is_empty(v.clikey) then
		local clikey = nixio.fs.readfile(fckey);
		if string.is_empty(v.clicert) then
		    errs.clicertfile = i18n.translate('Please upload client certificate file')
		end

    		-- convert der to pem
    		if next(errs) == nil and not clikey:find('PRIVATE KEY') then
    		    rc = fork_exec_wait("openssl pkcs8 -in "..fckey.." -inform der -passin pass:'"..passin.."' >/tmp/ipsec.tmp")
    		    if rc ~= 0 then
    			errs.clikeyfile = i18n.translate('Invalid client key file')
    		    else
    			nixio.fs.move('/tmp/ipsec.tmp', fckey)
    		    end
    		end

    		if next(errs) == nil then
    		    if clikey:find('ENCRYPTED') then
    			if #passin < 4 then
    			    errs.clikeypass = i18n.translate('Please enter client key password')
    			else
    			    rc = fork_exec_wait('openssl pkcs8 -topk8 -nocrypt -in ' .. fckey .. ' -out ' .. fckey_dec .. " -passin pass:'" .. passin .. "'")
    			    if rc ~= 0 then
    				errs.clikeypass = i18n.translate('Invalid client key password')
    			    end
    			end
    		    else
    			nixio.fs.copy(fckey, fckey_dec)
    		    end
    		end

    		if next(errs) == nil then
    		    local clicert = nixio.fs.readfile(fccert)
    		    if not clicert:find('CERTIFICATE') then
    			rc = fork_exec_wait("openssl x509 -in "..fccert.." -inform der >/tmp/ipsec.tmp")
    			if rc ~= 0 then
    			    errs.clicertfile = i18n.translate('Invalid client certification file')
    			else
    			    nixio.fs.move('/tmp/ipsec.tmp', fccert)
    			end
    		    end
    		end
    	    end
	end
    end

    local p12
    local require_mschapv2 = false
    if next(errs) == nil then
	if certtype == 'p12' and not string.is_empty(v.p12) then
	    p12 = parse_p12pem(fp12pem)
	end

	if string.is_empty(oldcfgname) then
	    if certtype == 'p12' then
		if p12 == nil or #p12.certs == 0 then
		    errs.p12file = i18n.translate('PKCS12 file contains no server certificate file')
		else
		    local client_key_id, client_key = next(p12.keys)
		    if client_key == nil or client_key.key == nil or client_key.cert == nil then
			require_mschapv2 = true
		    end
		end
	    else
		if string.is_empty(v.clikey) or string.is_empty(v.clicert)  then
		    require_mschapv2 = true
		end
	    end
	elseif not nixio.fs.access(ipsecd..'/private/'..oldcfgname..'.pem') or
	       not nixio.fs.access(ipsecd..'/certs/'..oldcfgname..'.pem') then
	    require_mschapv2 = true
	end
    end

    if next(errs) == nil and require_mschapv2 then
	if string.is_empty(v.cfguser) then
	    errs.cfguser = i18n.translate('Username is required')
	end

	if string.is_empty(v.cfgpass) then
	    errs.cfgpass = i18n.translate('Password is required')
	end
    end

    if next(errs) ~= nil then
	http.write_json({
	    status = 'error',
	    message = errs,
	})
	return
    end

    local cli_dir = work_clidir..'/'..cfgname
    nixio.fs.mkdirr(cli_dir)
    if p12 ~= nil then
	if p12.certs[1] ~= nil then
	    nixio.fs.writefile(cli_dir .. '/ca.pem', p12.certs[1])
	end

	local client_key_id, client_key = next(p12.keys)
	if client_key ~= nil then
	    if client_key.key then
		nixio.fs.writefile(cli_dir .. '/client-key.pem', client_key.key)
	    end
	    if client_key.cert then
		nixio.fs.writefile(cli_dir .. '/client-cert.pem', client_key.cert)
	    end
	end
    else
	local sz
	sz = nixio.fs.stat(fca, 'size')
	if sz ~= nil and sz > 0 then
	    nixio.fs.move(fca, cli_dir .. '/ca.pem')
	else
	    sz = nixio.fs.stat(cli_dir .. '/ca.pem', 'size')
	    if not sz and oldcfgname ~= nil then
		if nixio.fs.access(ipsecd..'/cacerts/conn@'..oldcfgname..'_ca.pem') then
		    nixio.fs.copy(ipsecd..'/cacerts/conn@'..oldcfgname..'_ca.pem', cli_dir .. '/ca.pem')
		elseif nixio.fs.access(ipsecd..'/certs/conn@'..oldcfgname..'_server.pem') then
		    nixio.fs.copy(ipsecd..'/certs/conn@'..oldcfgname..'_server.pem', cli_dir .. '/ca.pem')
		end
	    end
	end

	sz = nixio.fs.stat(fccert, 'size')
	if sz ~= nil and sz > 0 then
	    nixio.fs.move(fccert, cli_dir .. '/client-cert.pem')
	elseif oldcfgname ~= nil and nixio.fs.access(ipsecd..'/certs/conn@'..oldcfgname..'_client.pem') then
	    nixio.fs.copy(ipsecd..'/certs/conn@'..oldcfgname..'_client.pem', cli_dir .. '/client-cert.pem')
	end

	sz = nixio.fs.stat(fckey_dec, 'size')
	if sz ~= nil and sz > 0 then
	    nixio.fs.move(fckey_dec, cli_dir .. '/client-key.pem')
	elseif oldcfgname ~= nil and nixio.fs.access(ipsecd..'/private/conn@'..oldcfgname..'_client.pem') then
	    nixio.fs.copy(ipsecd..'/private/conn@'..oldcfgname..'_client.pem', cli_dir .. '/client-key.pem')
	end
    end

    local ca_subject, cli_subject
    if nixio.fs.access(cli_dir .. '/ca.pem') then
	ca_subject = util.exec('openssl x509 -in '.. cli_dir ..'/ca.pem -subject -noout 2>/dev/null'):trim()
    end

    if nixio.fs.access(cli_dir .. '/client-cert.pem') then
	cli_subject = util.exec('openssl x509 -in '.. cli_dir ..'/client-cert.pem -subject -noout 2>/dev/null'):trim()
    end

    http.write_json({
	status = 'success',
	cadn = ca_subject,
	clidn = cli_subject,
    })
end

function connect()
    http.prepare_content('application/json')

    local v = http.formvalue()
    if not v.cfg then
	http.write_json({
	    status = 'error',
	    message = i18n.translate('Missing configuration name') 
	})
	return
    end

    local cfg = v.cfg:gsub('[^0-9A-Za-z.]', '-')
    if v.action == 'start' then
	local rc = 0
	for _, i in ipairs({1, 2, 3}) do -- in case more than 1 connection started!
	    local conn, state = get_active_conn()
	    if conn then
		conn = conn:gsub('[^0-9A-Za-z.]', '-')
		rc = os.execute('ipsec down conn@'..conn..' >/dev/null 2>&1')
		if rc ~= 0 then break end
	    else
		break
	    end
	    os.execute('sleep 1')
	end

	if rc == 0 then -- init scripts starts the connection
	    rc = os.execute('echo conn@'..cfg..' >/var/ipsec/ipsec.conn 2>/dev/null && /etc/init.d/ipsec restart >/dev/null 2>&1')
	end

	http.write_json({
	    status = rc == 0 and 'success' or 'fail',
	    message = rc == 0 and '' or i18n.translate('Failed to start IPsec VPN connection'),
	    cfg = cfg,
	    state = 'running',
	})
    else
	local rc = os.execute('ipsec down conn@'..cfg..' >/dev/null 2>&1; rm -f /var/ipsec/ipsec.conn >/dev/null 2>&1')
	http.write_json({
	    status = rc == 0 and 'success' or 'fail',
	    message = rc == 0 and '' or i18n.translate('Failed to stop IPsec VPN connection'),
	    cfg = cfg,
	    state = 'stopped',
	})
    end
end

function ipsec_state()
    http.prepare_content('application/json')

    local v = http.formvalue()
    if not v.cfg then
	http.write_json({
	    status = 'error',
	    message = i18n.translate('Missing configuration name') 
	})
	return
    end

    local cfg, cfg_state
    if util.exec('. /lib/functions.sh && is_service_running ipsec'):trim() ~= 'true' then
	cfg_state = 'running' -- tell UI to wait
    elseif not nixio.fs.stat('/var/ipsec/ipsec.conn.log', 'mtime') then
	cfg_state = 'stopped' -- no client active
    elseif os.time() - nixio.fs.stat('/var/ipsec/ipsec.conn.log', 'mtime') <= 10 then
	cfg_state = 'running' -- tell UI to wait, client conn newly started
    else
	cfg, cfg_state = get_active_conn()
    end

    http.write_json({
	status = 'success',
	data = {
	    cfg = cfg and cfg or v.cfg,
	    state = cfg_state,
	}
    })
end

function client_logs()
    http.prepare_content('application/json')

    local fp = io.popen("logread | grep -E '\\[(IKE|NET|CFG|ENC)\\]' | tail -15", 'r')
    if fp then
	http.write_json({
	    status = 'success',
	    data = fp:read("*all"):gsub('\n', '<br>'),
	})
	fp:close()
	return
    end

    http.write_json({
	status = 'fail',
	message = i18n.translate('Failed to read OpenVPN logs'),
    })
end

function restart_server()
    luci.sys.init.stop(config)
    local success = luci.sys.init.start(config)

    http.prepare_content('application/json')
    http.write_json({
	status = success and 'success' or 'fail',
	message = success and '' or i18n.translate('Failed to restart strongSwan server')
    })
end
