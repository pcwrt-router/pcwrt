require "nixio"
require "luci.pcutil"
require "luci.sys"
require "luci.ip"
local fs = require "nixio.fs"
local http = require "luci.http"
local util = require "luci.util"
local jsonc = require "luci.jsonc"
local uci = require "luci.pcuci"
local dt = require "luci.cbi.datatypes"
local i18n = require "luci.i18n"

module("luci.pccontroller.apps.vpn", package.seeall)

ordering = 50
function display_name()
    return nixio.fs.access('/etc/init.d/openvpn', 'x') and i18n.translate('OpenVPN') or nil
end

local config = 'openvpn'
local firewall = 'firewall'
local client_cfg = 'openvpnc'
local server_init = 'openvpn'
local client_init = 'openvpnc'

local tmp_dir = '/tmp/vpn-clients'
local client_dir = '/etc/openvpn/clients'

local required_files = {
    "/etc/easy-rsa/pki/ca.crt",
    "/etc/easy-rsa/pki/issued/pcwrt-openvpn-server.crt",
    "/etc/easy-rsa/pki/private/pcwrt-openvpn-server.key",
    "/etc/easy-rsa/pki/dh.pem",
    "/etc/easy-rsa/pki/tls-auth-key.pem",
}

local ccd_dir = '/etc/openvpn/ccd/'

local ip_pool = {
    {  5,  6}, {  9, 10}, { 13, 14}, { 17, 18},
    { 21, 22}, { 25, 26}, { 29, 30}, { 33, 34}, { 37, 38},
    { 41, 42}, { 45, 46}, { 49, 50}, { 53, 54}, { 57, 58},
    { 61, 62}, { 65, 66}, { 69, 70}, { 73, 74}, { 77, 78},
    { 81, 82}, { 85, 86}, { 89, 90}, { 93, 94}, { 97, 98},
    {101,102}, {105,106}, {109,110}, {113,114}, {117,118},
    {121,122}, {125,126}, {129,130}, {133,134}, {137,138},
    {141,142}, {145,146}, {149,150}, {153,154}, {157,158},
    {161,162}, {165,166}, {169,170}, {173,174}, {177,178},
    {181,182}, {185,186}, {189,190}, {193,194}, {197,198},
    {201,202}, {205,206}, {209,210}, {213,214}, {217,218},
    {221,222}, {225,226}, {229,230}, {233,234}, {237,238},
    {241,242}, {245,246}, {249,250}, {253,254},
}

local function openvpn_initialized()
    for _, f in ipairs(required_files) do
	local sz = fs.stat(f, 'size')
	if sz == nil or sz == 0 then
	    return false
	end
    end
    return true
end

local function easyrsa_running()
    local rc = fork_exec_wait("ps | grep gen-keys | grep -v grep")
    return rc == 0
end

local function is_vpn_server_enabled(c)
    if not fs.access("/etc/init.d/"..server_init) then
	return false
    end

    local sz = fs.stat('/etc/openvpn/server.conf', 'size')
    if sz == nil or sz == 0 then
	return false
    end

    local s = c:get_first(config, 'server')
    return luci.sys.init.enabled(server_init) and c:get(config, s, 'enabled') ~= '0'
end

local function render_server_conf(c, v)
    local dns = c:get('network', 'lan', 'ipaddr')

    local i = assert(io.open("/etc/openvpn/server.conf.template", "rb"))
    local c = i:read("*all")
    i:close()

    local o = io.open("/etc/openvpn/server.conf", "w")
    local tpl = require "luci.template".Template(nil, c)
    tpl.viewns = setmetatable({ write = function(s) o:write(s) end, tostring = tostring }, nil)
    tpl:render({
	port = v.port,
	ipaddr = v.ipaddr,
	netmask = v.netmask,
	dns = dns,
	scramble = v.scramble == '1' and 'scramble obfuscate '.. v.scrampass or '',
    })
    o:close()
end

local function assign_client_ips(v, old_ipaddr, old_netmask, guestips)
    local s, ccd

    local us = {}
    for _, u in ipairs(v.users) do
	us[u.name] = {
	    ip = false,
	    guest = u.guest,
	}
    end

    for f in fs.dir(ccd_dir) do
	if us[f] ~= nil then
	    ccd = assert(io.open(ccd_dir..f, 'rb'))
	    s = ccd:read("*all")
	    ccd:close()
	    us[f].ip = s:split(' ')[2]
	else
	    fs.remove(ccd_dir..f)
	end
    end

    local network = luci.ip.new(v.ipaddr, v.netmask):network()

    if v.ipaddr ~= old_ipaddr or v.netmask ~= old_netmask then
        local old_network = luci.ip.new(old_ipaddr, old_netmask):network()
	for uname, s in pairs(us) do
	    if s.ip ~= false then
		local valid = false
		local i = 1
	    	while i <= #ip_pool do
		    if s.ip == tostring(old_network:add(ip_pool[i][1])) then
			us[uname].ip = tostring(network:add(ip_pool[i][1]))
		    	ccd = assert(io.open(ccd_dir..uname, 'w'))
		    	ccd:write("ifconfig-push %s %s\n" % {us[uname].ip, tostring(network:add(ip_pool[i][2]))})
		    	ccd:close()
			valid = true
			break
		    end
		    i = i + 1
		end

		if not valid then
	    	    fs.remove(ccd_dir..uname)
		    us[uname] = false
		end
	    end
	end
    end

    local i = 1
    for uname, s in pairs(us) do
	if s.ip == false then
	    while i <= #ip_pool do
		local used = false
		for w, x in pairs(us) do
		    if x.ip ~= false then
			if x.ip == tostring(network:add(ip_pool[i][1])) then
			    used = true
			    i = i + 1
			    break
			end
		    end
		end

		if used == false then
		    us[uname].ip = tostring(network:add(ip_pool[i][1]))
		    ccd = assert(io.open(ccd_dir..uname, 'w'))
		    ccd:write("ifconfig-push %s %s\n" % {us[uname].ip, tostring(network:add(ip_pool[i][2]))})
		    ccd:close()
		    i = i + 1
		    break
		end
	    end
	end
    end

    for uname, s in pairs(us) do
	if s.guest and s.ip ~= false then guestips[#guestips + 1] = s.ip end
    end
end

local function get_enabled_network(c)
    local internal_ifs = get_internal_interfaces(c)
    local enabled_ifs = get_vpn_ifaces(c, 'openvpn')
    if enabled_ifs ~= nil and #enabled_ifs > 0 then
	for _, nw in pairs(internal_ifs) do
	    for _, enabled_if in ipairs(enabled_ifs) do
		if nw.name == enabled_if then
		    nw.enabled = true
		    break
		end
	    end
	end
    end

    return internal_ifs
end

local function get_active_vpn_config()
    local cfg
    if nixio.fs.access('/var/openvpn/client', 'r') then
	local fp = io.open('/var/openvpn/client', 'r')
	cfg = fp:read("*all")
	fp:close()
    end
    return cfg and cfg:trim() or ''
end

function _get_data(c)
    local s = c:get_first(config, 'server')
    local cli = c:get_first(config, 'client')

    local users = {}
    c:foreach(config, 'user', function(u)
	users[#users + 1] = {
	    name = u.name,
	    guest = u.guest == '1',
	    vpnout = u.vpnout == '1',
	}
    end)

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

    local clients = {}
    if cli then
	local cfgnames = c:get_list(config, cli, 'config')
	if cfgnames then
	    local cfg, ccfg, state
	    cfg = get_active_vpn_config()
	    if not string.is_empty(cfg) then
		ccfg = cfg:gsub('[^0-9A-Za-z.]', '-')
		if os.execute("ifconfig tun1 >/dev/null 2>&1") == 0 then
		    state = 'connected'
		elseif os.execute("ps -w | grep -v grep | grep -E 'openvpn.*"..ccfg.."' >/dev/null 2>&1") == 0 then
		    state = 'running'
		else
		    state = 'stopped'
		end
	    end

	    for _, cfgname in ipairs(cfgnames) do
		clients[#clients+1] = {
		    name = cfgname,
		    state = cfg == cfgname and state or nil,
		}
	    end
	end
    end

    local port = c:get(config, s, 'port')
    if not port then
	math.randomseed(os.time())
	port = math.random(11025, 65535)
    end

    return {
	server = {
	    enabled = is_vpn_server_enabled(c),
	    port = port,
	    extaddr = extaddr,
	    ipaddr = c:get(config, s, 'ipaddr'),
	    netmask = c:get(config, s, 'netmask'),
	    scramble = c:get(config, s, 'scramble') == '1' and '1' or nil,
	    scrampass = c:get(config, s, 'scrampass'),
	    users = users,
	},
	client = {
	    enabled_network = get_enabled_network(c),
	    clients = clients,
	    autostart = cli and c:get(config, cli, 'autostart') or nil,
	}
    }
end

function index()
    local init_status = nil
    if not openvpn_initialized() then
	init_status = easyrsa_running() and 'in_progress' or 'init_needed'
    end

    local c = uci.cursor()
    local t = template('apps/vpn')
    local ok, err = util.copcall(t.target, t, {
	title = translate('OpenVPN'),
	init_status = init_status,
	hide_prog_alert = init_status ~= 'in_progress' and 'hidden' or nil,
	form_value_json = jsonc.stringify(_get_data(c)),
	page_script = 'apps/vpn.js',
    })
    assert(ok, 'Failed to render template ' .. t.view .. ': ' .. tostring(err))
end

function init()
    fork_exec("/etc/init.d/openvpn stop")
    fork_exec("/usr/bin/gen-keys.sh")
    http.prepare_content('application/json')
    http.write_json({status = "success"})
end

local function validate(v)
    local errs = {}
    if not dt.port(v.port) then
	errs.port = i18n.translate('Invalid port number')
    end

    if not (dt.hostname(v.extaddr) or dt.ipaddr(v.extaddr)) then
	errs.extaddr = i18n.translate('Please enter a valid IP address or hostname')
    end

    if not dt.ipaddr(v.ipaddr) then
	errs.ipaddr = i18n.translate('Invalid IP address')
    end

    if not dt.ipaddr(v.netmask) then
	errs.netmask = i18n.translate('Invalid net mask')
    end

    if v.scramble == '1' and string.is_empty(v.scrampass) then
	errs.scrampass = i18n.translate('Please enter a password for scramble')
    end

    return errs
end

function _update(c, v)
    local success, msg

    local s = c:get_first(config, 'server')
    if s == nil then
	s = c:section(config, 'server')
    end

    if v.enabled == '0' then
	luci.sys.init.stop(server_init)
	success = luci.sys.init.disable(server_init)
	if success then
	    c:set(config, s, 'enabled', '0')
	    success = c:commit(config)
	    if success then
		update_firewall_rules_for_vpns(c, 'vpn', false)
		success = c:commit(firewall)
	    end
	end
	return {
	    status = success and 'success' or 'fail',
	    message = success and '' or i18n.translate('Failed to disable OpenVPN Server') 
	}
    end

    local errs = validate(v)
    if next(errs) ~= nil then
	return {
	    status = 'error',
	    message = errs,
	}
    end

    local old_ipaddr = c:get(config, s, 'ipaddr')
    local old_netmask = c:get(config, s, 'netmask')

    c:set(config, s, 'enabled', '1')
    c:set(config, s, 'port', v.port)
    c:set(config, s, 'extaddr', v.extaddr)
    c:set(config, s, 'ipaddr', v.ipaddr)
    c:set(config, s, 'netmask', v.netmask)
    c:set(config, s, 'scramble', v.scramble == '1' and '1' or '0')
    if v.scrampass then
	c:set(config, s, 'scrampass', v.scrampass)
    else
	c:delete(config, s, 'scrampass')
    end

    local passwords = {}
    c:foreach(config, 'user', function(u)
	passwords[u.name] = u.password
    end)

    local users = {}
    for _, user in ipairs(v.users) do
	if user.password then
	    user.password = nixio.crypt(user.password, '$1$'..luci.sys.uniqueid(5)..'$')
	elseif user.oldname and passwords[user.oldname] then
	    user.password = passwords[user.oldname]
	elseif passwords[user.name] then
	    user.password = passwords[user.name]
	end

	if user.password then
	    users[#users + 1] = {
		name = user.name,
		password = user.password,
		guest = user.guest,
		vpnout = user.vpnout,
	    }
	end
    end

    c:delete_all(config, 'user')
    for _, user in ipairs(users) do
	local u = c:section(config, 'user')
	c:set(config, u, 'name', user.name)
	c:set(config, u, 'password', user.password)
	if user.guest then
	    c:set(config, u, 'guest', '1')
	end
 	if user.vpnout then
  	    c:set(config, u, 'vpnout', '1')
   	end
    end

    success, msg = c:commit(config)

    if success then
	local guestips = {}
	assign_client_ips(v, old_ipaddr, old_netmask, guestips)
	update_vpn_guest_fw_rule(c, guestips, old_ipaddr, old_netmask)
	update_firewall_rules_for_vpns(c, 'vpn', true)
    end

    if success then
	success, msg = c:commit(firewall)
    end

    if success then
	success = luci.sys.init.enable(server_init)
    end

    if success then
	render_server_conf(c, v)
    end

    -- no need to restart mp manually. Firewall will restart because of vpn, which will
    -- trigger mp restart
    return {
        status = success and 'success' or 'fail',
	message = success and '' or translate('Failed to save configuration'),
	apply = success and config or '',
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

function download()
    local f = assert(io.open('/etc/easy-rsa/pki/ca.crt', 'rb'))
    local cacert = f:read('*all')
    f:close()

    f = assert(io.open('/etc/easy-rsa/pki/tls-auth-key.pem', 'rb'))
    local tlsauth = f:read('*all')
    f:close()

    f = assert(io.open('/etc/openvpn/client.conf.template', 'rb'))
    local tmpl = f:read('*all')
    f:close()

    local c = uci.cursor()
    local sname = c:get_first(config, 'server')

    http.header('Content-Disposition', 'attachment; filename="%s.ovpn"' % {luci.sys.hostname()})
    http.prepare_content("text/plain")
    local tpl = require "luci.template".Template(nil, tmpl)
    tpl.viewns = setmetatable({ write = http.write, tostring = tostring }, nil)
    tpl:render({
	server = c:get(config, sname, 'extaddr'),
	port = c:get(config, sname, 'port'),
	scramble = c:get(config, sname, 'scramble') == '1' and 'scramble obfuscate '..c:get(config, sname, 'scrampass') or '',
	cacert = cacert,
	tlsauth = tlsauth,
    })
end

function _update_client(c, v)
    local success, msg

    local iiface = v.network
    if type(iiface) == 'string' then
	iiface = { iiface }
    end

    local cfgs = {}
    success = set_vpn_ifaces(c, 'openvpn', iiface, cfgs)

    if success then
	local s = c:get_first(config, 'client')
	if s == nil then
	    s = c:section(config, 'client')
	end

	-- Add vpn names to UCI config
	if type(v.cfgname) == 'string' then
	    v.cfgname = { v.cfgname }
	end

	if v.cfgname then
	    c:set_list(config, s, 'config', v.cfgname)
	else
	    c:delete(config, s, 'config')
	end

	if v.autostart then
	    c:set(config, s, 'autostart', v.autostart)
	else
	    c:delete(config, s, 'autostart')
	end

	success, msg = c:commit(config)
    end

    local cfgname = {}
    if success then
	-- Move files
	if v.cfgname then
	    for _, cfg in ipairs(v.cfgname) do
		cfgname[#cfgname+1] = cfg:gsub('[^0-9A-Za-z.]', '-')
	    end
	end

	local remove = {}
	for f in nixio.fs.dir(client_dir) do
	    if f:ends(".ovpn") then
		local fname = f:gsub(".ovpn$", "")
		if not string_in_array(fname, cfgname) then
		    remove[#remove+1] = fname
		end
	    end
	end

	for _, f in ipairs(remove) do
	    nixio.fs.remove(client_dir .. '/' .. f .. '.ovpn')
	    nixio.fs.remove(client_dir .. '/' .. f .. '.auth')
	end

	if not nixio.fs.access(tmp_dir, 'r') then
	    nixio.fs.mkdir(tmp_dir)
	end

	local ff = nixio.fs.dir(tmp_dir)
	if ff then
	    for f in ff do
		if f:ends(".ovpn") then
		    local fname = f:gsub(".ovpn$", "")
		    if string_in_array(fname, cfgname) then
			nixio.fs.copy(tmp_dir..'/'..f, client_dir..'/'..f)
		    end
		elseif f:ends(".auth") then
		    local fname = f:gsub(".auth$", "")
		    if string_in_array(fname, cfgname) then
			nixio.fs.copy(tmp_dir..'/'..f, client_dir..'/'..f)
		    end
		end
	    end
	end
	nixio.fs.remover(tmp_dir)

	if v.autostart and not nixio.fs.access('/var/openvpn/client', 'r') then
	    nixio.fs.mkdir('/var/openvpn')
	    local fp = io.open('/var/openvpn/client', 'w')
	    if fp then
		fp:write(v.autostart)
		fp:close()
	    end
	end

	update_firewall_rules_for_vpnc(c, 'openvpn', 'vpnc')
    end

    add_if_not_exists(cfgs, client_cfg)
    return {
	status = success and 'success' or 'fail',
	message = success and '' or i18n.translate('Failed to save configuration'),
	apply = success and cfgs or '',
    }
end

function update_client()
    local c = uci.cursor()
    local v = http.formvalue()

    http.prepare_content('application/json')
    http.write_json(_update_client(c, v))
end

function add_config()
    if not nixio.fs.access(tmp_dir, 'r') then
	nixio.fs.mkdir(tmp_dir)
    end

    local fp, rc
    local tmpf = tmp_dir .. '/tmpf.ovpn'
    http.setfilehandler(
	function(meta, chunk, eof)
	    if not fp then
		fp = io.open(tmpf, 'w')
		rc = fp
	    end
	    if chunk and fp then rc = fp:write(chunk) end
	    if eof and fp then rc = fp:close() end
	end
    )

    local upload = http.formvalue('ovpn')

    local status = 'fail'
    local cfg = nil
    local oldcfgname = nil
    local v = http.formvalue()
    local fs_action = nixio.fs.move
    if rc == nil or upload == nil or #upload == 0 then
	if v.oldname ~= nil then
	    oldcfgname = v.oldname:gsub('[^0-9A-Za-z.]', '-')
	    if nixio.fs.access(tmp_dir .. '/' .. oldcfgname .. '.ovpn') then
		cfg = tmp_dir .. '/' .. oldcfgname .. '.ovpn'
		status = 'success'
	    elseif nixio.fs.access(client_dir .. '/' .. oldcfgname .. '.ovpn') then
		cfg = client_dir .. '/' .. oldcfgname .. '.ovpn'
		fs_action = nixio.fs.copy
		status = 'success'
	    end
	end
    else
	status = 'success'
    end

    http.prepare_content('application/json')

    if status ~= 'success' then
	http.write_json({
	    status = 'error',
	    message = {
		ovpnfile = i18n.translate('Please upload an OpenVPN configuration file'),
	    }
	})
	return
    end

    local needauth
    if cfg then
	needauth = fork_exec_wait('grep auth-user-pass '..cfg) == 0
    else
	needauth = fork_exec_wait('grep auth-user-pass '..tmpf) == 0
    end

    if needauth then
	local errs = {}
	if v.cfguser == nil or v.cfguser:trim() == '' then
	    errs.cfguser = i18n.translate('Username is required')
	end

	if v.cfgpass == nil or v.cfgpass:trim() == '' then
	    errs.cfgpass = i18n.translate('Password is required')
	end

	if next(errs) ~= nil then
	    http.write_json({
		status = 'error',
		message = errs
	    })
	    return
	end
    end

    local cfgname = v.cfgname:gsub('[^0-9A-Za-z.]', '-')
    if cfg then
	if v.cfgname ~= v.oldname then
	    fs_action(cfg, tmp_dir .. '/' .. cfgname .. '.ovpn')
	    if nixio.fs.access(tmp_dir .. '/' .. oldcfgname .. '.auth') then
		nixio.fs.move(tmp_dir .. '/' .. oldcfgname .. '.auth', tmp_dir .. '/' .. cfgname .. '.auth')
	    end
	end
    else
	fs_action(tmpf, tmp_dir .. '/' .. cfgname .. '.ovpn')
    end

    fork_exec_wait("sed -i -e 's/[;#].*$//' -e '/^$/d' -e 's#dev tun.*#dev tun1#' "..tmp_dir..'/'..cfgname..'.ovpn')

    if needauth then
	fp = io.open(tmp_dir .. '/' .. cfgname .. '.auth', 'w')
	fp:write(v.cfguser .. '\n' .. v.cfgpass .. '\n')
	fp:close()
    end

    local need_certs = {}
    if nixio.fs.access(tmp_dir .. '/' .. cfgname .. '.ovpn') then
	fork_exec_wait("sed -i -e 's#^up .*##' -e 's#^down .*##' -e 's#^script-security 2.*##' "..tmp_dir .. '/' .. cfgname .. '.ovpn')
	local dns_fix = "\nscript-security 2\nup /etc/openvpn/update-resolv-conf\ndown /etc/openvpn/update-resolv-conf\n"
	fork_exec_wait("echo \""..dns_fix.."\" >>"..tmp_dir .. '/' .. cfgname .. '.ovpn')

	if needauth then
	    fork_exec_wait("sed -i 's#auth-user-pass\\s*.*$#auth-user-pass /etc/openvpn/clients/client_auth#' "..tmp_dir .. '/' .. cfgname .. '.ovpn')
	end

	local line
	for line in io.lines(tmp_dir .. '/' .. cfgname .. '.ovpn') do
	    if line:find('^%s*ca%s+%S+') then
		need_certs[#need_certs+1] = 'cacert'
	    elseif line:find('^%s*cert%s+%S+') then
		need_certs[#need_certs+1] = 'clicert'
	    elseif line:find('^%s*key%s+%S+') then
		need_certs[#need_certs+1] = 'clikey'
	    elseif line:find('^%s*tls%-auth%s+%S+') then
		need_certs[#need_certs+1] = 'tlscert'
	    end
	end
    end

    if #need_certs > 0 then
	http.write_json({
	    status = 'error',
	    need_certs = need_certs,
	})
	return
    end

    http.write_json({
	status = 'success'
    })
end

function add_certs()
    if not nixio.fs.access(tmp_dir, 'r') then
	nixio.fs.mkdir(tmp_dir)
    end
    
    local tmpf = tmp_dir .. '/tmpf.ovpn'
    local fca = tmp_dir .. '/ca.crt'
    local ftls = tmp_dir .. '/tls.crt'
    local fcli = tmp_dir .. '/client.crt'
    local fclikey = tmp_dir .. '/client.key'

    local fp, rc
    http.setfilehandler(
	function(meta, chunk, eof)
	    if not fp then
		if meta then
		    if meta.name == 'cacert' then
			fp = io.open(fca, 'w')
		    elseif meta.name == 'tlscert' then
			fp = io.open(ftls, 'w')
		    elseif meta.name == 'clicert' then
			fp = io.open(fcli, 'w')
		    else
			fp = io.open(fclikey, 'w')
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

    local cacert = http.formvalue('cacert')
    local tlscert = http.formvalue('tlscert')
    local clicert = http.formvalue('clicert')
    local clikey = http.formvalue('clikey')

    local fovpn = nil
    local cfgname = http.formvalue('cfgname')
    if cfgname then
	cfgname = cfgname:gsub('[^0-9A-Za-z.]', '-')
	fovpn = tmp_dir .. '/' .. cfgname .. '.ovpn'
    end

    http.prepare_content('application/json')
    if not fovpn or not nixio.fs.access(fovpn, 'r') then
	http.write_json({
	    status = 'fail',
	    message = i18n.translate('OpenVPN configuration upload failed. Please try again.'),
	})
	return
    end

    local errs = {}

    fp = io.open(tmpf, 'w')
    local status = fp and 'success' or 'fail'
    
    if fp then
	local has_kd = false

	if cacert then
	    cacert = nixio.fs.readfile(fca)
	end

	if tlscert then
	    tlscert = nixio.fs.readfile(ftls)
	end

	if clicert then
	    clicert = nixio.fs.readfile(fcli)
	end

	if clikey then
	    clikey = nixio.fs.readfile(fclikey)
	end

	for line in io.lines(fovpn) do
	    if line:find('^%s*ca%s+%S+') then
		if cacert then
		    fp:write('<ca>\n')
		    fp:write(cacert)
		    if string.sub(cacert, -1) ~= '\n' then fp:write('\n') end
		    fp:write('</ca>\n')
		else
		    status = 'error'
		    errs.cacert = i18n.translate('Please upload CA certificate')
		end
	    elseif line:find('^%s*tls%-auth%s+%S+') then
		if tlscert then
		    if not has_kd then
			has_kd = true
			fp:write('key-direction 1\n')
		    end
		    fp:write('<tls-auth>\n')
		    fp:write(tlscert)
		    if string.sub(tlscert, -1) ~= '\n' then fp:write('\n') end
		    fp:write('</tls-auth>\n')
		else
		    status = 'error'
		    errs.cacert = i18n.translate('Please upload TLS Auth certificate')
		end
	    elseif line:find('^%s*cert%s+%S+') then
		if clicert then
		    fp:write('<cert>\n')
		    fp:write(clicert)
		    if string.sub(clicert, -1) ~= '\n' then fp:write('\n') end
		    fp:write('</cert>\n')
		else
		    status = 'error'
		    errs.cacert = i18n.translate('Please upload client certificate')
		end
	    elseif line:find('^%s*key%s+%S+') then
		if clikey then
		    fp:write('<key>\n')
		    fp:write(clikey)
		    if string.sub(clikey, -1) ~= '\n' then fp:write('\n') end
		    fp:write('</key>\n')
		else
		    status = 'error'
		    errs.cacert = i18n.translate('Please upload client key')
		end
	    elseif line:find('key%-direction 1') then
		if not has_kd then
		    has_kd = true
		    fp:write('key-direction 1\n')
		end
	    else
		fp:write(line..'\n')
	    end
	end
    end

    if status == 'error' then
	fp:close()
	http.write_json({
	    status = status,
	    message = errs,
	})
	return
    end

    if not fp:close() then
	status = 'fail'
    end

    if status == 'success' then
	nixio.fs.move(tmpf, fovpn)
    end

    http.write_json({
	status = status,
	message = status == 'success' and '' or i18n.translate('OpenVPN configuration upload failed. Please try again.')
    })
end

function get_config()
    local s = {}

    local v = http.formvalue()
    if v.cfg then
	local auth
	local cfgname = v.cfg:gsub('[^0-9A-Za-z.]', '-')
	if nixio.fs.access(tmp_dir..'/'..cfgname..'.auth', 'r') then
	    auth = nixio.fs.readfile(tmp_dir..'/'..cfgname..'.auth')
	    s = auth:split('\n')
	elseif nixio.fs.access(client_dir..'/'..cfgname..'.auth', 'r') then
	    auth = nixio.fs.readfile(client_dir..'/'..cfgname..'.auth')
	    s = auth:split('\n')
	end
    end

    http.prepare_content('application/json')
    http.write_json({
	status = 'success',
	data = {
	    cfguser = s and s[1] or nil,
	    cfgpass = s and s[2] or nil,
	}
    })
end

function view_ovpn()
    local content = 'Configuration file not found'

    local v = http.formvalue()
    if v.cfg then
	local cfgname = v.cfg:gsub('[^0-9A-Za-z.]', '-')
	if nixio.fs.access(tmp_dir..'/'..cfgname..'.ovpn', 'r') then
	    content = nixio.fs.readfile(tmp_dir..'/'..cfgname..'.ovpn')
	elseif nixio.fs.access(client_dir..'/'..cfgname..'.ovpn', 'r') then
	    content = nixio.fs.readfile(client_dir..'/'..cfgname..'.ovpn')
	end
    end

    http.prepare_content('text/plain')
    http.write(content)
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

    local status
    if v.action == 'start' then
	local ok = luci.sys.init.stop(client_init)

	if ok then
	    nixio.fs.mkdir('/var/openvpn')
	    local fp = io.open('/var/openvpn/client', 'w')
	    if fp then
		fp:write(v.cfg)
		fp:close()
		ok = luci.sys.init.start(client_init)
	    else
		ok = false
	    end
	end

	http.write_json({
	    status = ok and 'success' or 'fail',
	    message = ok and '' or i18n.translate('Failed to start client connection'),
	    state = 'running',
	})
    else
	status = luci.sys.init.stop(client_init) and 'success' or 'fail'
	if status == 'success' then nixio.fs.remove('/var/openvpn/client') end
	http.write_json({
	    status = status,
	    message = status == 'success' and '' or i18n.translate('Failed to stop client connection'),
	    state = 'stopped',
	})
    end
end

function vpn_state()
    http.prepare_content('application/json')

    local cfg = get_active_vpn_config()
    if string.is_empty(cfg) then
	http.write_json({
	    status = 'success',
	    data = {}
	})
	return
    end

    local state = 'stopped'
    local rc = os.execute("ifconfig tun1 >/dev/null 2>&1")
    if rc == 0 then
	state = 'connected'
    else
	local ccfg = cfg:gsub('[^0-9A-Za-z.]', '-')
	rc = os.execute("ps -w | grep -v grep | grep -E 'openvpn.*"..ccfg.."' >/dev/null 2>&1")
	if rc == 0 then state = 'running' end
    end

    http.write_json({
	status = 'success',
	data = {
	    cfg = cfg,
	    state = state,
	}
    })
end

function client_logs()
    http.prepare_content('application/json')

    local fp = io.popen("logread | grep openvpn | tail -8 | sed -r 's/.*openvpn\[\d*\]://g'", 'r')
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
    luci.sys.init.stop(server_init)
    local success = luci.sys.init.start(server_init)

    http.prepare_content('application/json')
    http.write_json({
	status = success and 'success' or 'fail',
	message = success and '' or i18n.translate('Failed to restart OpenVPN server'),
    })
end
