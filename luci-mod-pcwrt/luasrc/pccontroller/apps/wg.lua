-- Copyright (C) 2023 pcwrt.com
-- Licensed to the public under the Apache License 2.0.

require "nixio"
require "nixio.fs"
require "luci.pcutil"
require "luci.sys"
local http = require "luci.http"
local util = require "luci.util"
local jsonc = require "luci.jsonc"
local uci = require "luci.pcuci"
local dt = require "luci.cbi.datatypes"
local i18n = require "luci.i18n"

module("luci.pccontroller.apps.wg", package.seeall)

ordering = 70
function display_name()
    return nixio.fs.access('/etc/init.d/wg', 'x') and i18n.translate('WireGuard') or nil
end

local config = 'wg'
local firewall = 'firewall'

math.randomseed(os.time())

local function get_enabled_network(c)
    local internal_ifs = get_internal_interfaces(c)
    local enabled_ifs = get_vpn_ifaces(c, 'wg')
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

local function get_active_conn()
    local conn
    if nixio.fs.access('/tmp/wg_client', 'r') then
	local fp = io.open('/tmp/wg_client', 'r')
	conn = fp:read("*all")
	fp:close()
    end
    return conn and conn:trim() or ''
end

local function get_conn_state()
    local state = 'stopped'
    local rc = os.execute('wg show wg1 2>/dev/null | grep "latest handshake" >/dev/null 2>&1')
    if rc == 0 then
	state = 'connected'
    else
	rc = os.execute('wg show wg1 >/dev/null 2>&1')
	if rc == 0 then state = 'running' end
    end

    return state
end

function _get_data(c)
    local peers = {}
    c:foreach(config, 'peer', function(p)
	peers[#peers + 1] = {
	    name = p.name,
	    guest = p.guest == '1',
	    vpnout = p.vpnout == '1',
	    qr = p.privatekey ~= nil
	}
    end)

    local aconn = get_active_conn()
    local conns = {}
    c:foreach(config, 'conn', function(conn)
	conns[#conns + 1] = {
	    name = conn.name,
	    autostart = conn.autostart,
	    state = conn.name == aconn and get_conn_state() or nil
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

    local port = c:get(config, s, 'port')
    if not port then port = math.random(11025, 65535) end
 
    return {
	server = {
	    enabled = c:get(config, s, 'enabled') == '1',
	    port = port,
	    extaddr = extaddr,
	    ipaddr = c:get(config, s, 'ipaddr'),
	    netmask = c:get(config, s, 'netmask'),
	    publickey = c:get(config, s, 'publickey'),
	    peers = peers,
	},
	client = {
	    enabled_network = get_enabled_network(c),
	    conns = conns,
	}
    }
end

function index()
    local c = uci.cursor()
    local t = template('apps/wg')
    local ok, err = util.copcall(t.target, t, {
	title = i18n.translate('WireGuard'),
	form_value_json = jsonc.stringify(_get_data(c)),
	page_script = 'apps/wg.js',
    })
    assert(ok, 'Failed to render template ' .. t.view .. ': ' .. tostring(err))
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

    return errs
end

local function create_new_peer(c, peer, netaddr, netmask, usedips, guestips)
    if not peer.pubkey then return end

    local ipaddr = get_next_ip(netaddr, netmask, usedips)
    usedips[#usedips + 1] = ipaddr

    local s = c:section(config, 'peer')
    c:set(config, s, 'name', peer.name)
    c:set(config, s, 'ip', ipaddr)
    c:set(config, s, 'publickey', peer.pubkey)
    if peer.privkey then
	c:set(config, s, 'privatekey', peer.privkey)
    end
    if peer.guest then
	c:set(config, s, 'guest', '1')
	guestips[#guestips + 1] = ipaddr
    end
    if peer.vpnout then
	c:set(config, s, 'vpnout', '1')
    end
end

function _update(c, v)
    local success, msg

    local s = c:get_first(config, 'server')

    if v.enabled == '0' then
	c:set(config, s, 'enabled', '0')
	success, msg = c:commit(config)
	if success then
	    update_firewall_rules_for_vpns(c, 'wg', false)
	    success, msg = c:commit(firewall)
	end
	return {
	    status = success and 'success' or 'fail',
	    message = success and '' or i18n.translate('Failed to disable WireGuard Server'),
	    apply = success and config or '',
	}
    end

    local errs = validate(v)
    if next(errs) ~= nil then
	return {
	    status = 'error',
	    message = errs,
	}
    end

    local oldip = c:get(config, s, 'ipaddr')
    local oldmask = c:get(config, s, 'netmask')

    c:set(config, s, 'enabled', '1')
    c:set(config, s, 'port', v.port)
    c:set(config, s, 'extaddr', v.extaddr)
    c:set(config, s, 'ipaddr', v.ipaddr)
    c:set(config, s, 'netmask', v.netmask)

    if c:get(config, s, 'privatekey') == nil or c:get(config, s, 'publickey') == nil then
	local privatekey = util.exec('wg genkey'):trim()
	local publickey = util.exec('echo '..privatekey..' | wg pubkey'):trim()
	c:set(config, s, 'privatekey', privatekey)
	c:set(config, s, 'publickey', publickey)
    end

    if v.peers == nil then
	v.peers = {}
    end

    local peernames = {}
    for _, peer in ipairs(v.peers) do
	if not peer.create then
	    peernames[#peernames+1] = peer.name
	end
    end

    local peers = {}
    local existing_peers = {}
    local guestips = {}
    local deleted = {}
    local usedips = {}
    c:foreach(config, 'peer', function(p)
	if not string_in_array(p.name, peernames) then
	    deleted[#deleted + 1] = p['.name']
	else
	    peers[#peers + 1] = p.name
	    p.ip = fix_ip(p.ip, oldip, oldmask, v.ipaddr, v.netmask)
	    existing_peers[#existing_peers + 1] = {
		section = p['.name'],
		name = p.name,
		ip = p.ip,
	    }
	    usedips[#usedips + 1] = p.ip
	end
    end)

    for _, d in ipairs(deleted) do
	c:delete(config, d)
    end

    for _, peer in ipairs(v.peers) do
	if not string_in_array(peer.name, peers) then
	    create_new_peer(c, peer, v.ipaddr, v.netmask, usedips, guestips)
	else
	    for _, ep in ipairs(existing_peers) do
		if ep.name == peer.name then
		    c:set(config, ep.section, 'ip', ep.ip)
		    if peer.guest then
			c:set(config, ep.section, 'guest', '1')
			guestips[#guestips + 1] = ep.ip
		    else
			c:delete(config, ep.section, 'guest')
		    end
		    if peer.vpnout then
			c:set(config, ep.section, 'vpnout', '1')
		    else
			c:delete(config, ep.section, 'vpnout')
		    end
		    if peer.pubkey then
			c:set(config, ep.section, 'publickey', peer.pubkey)
			if peer.privkey then
			    c:set(config, ep.section, 'privatekey', peer.privkey)
			else
			    c:delete(config, ep.section, 'privatekey')
			end
		    end
		    break
		end
	    end
	end
    end

    success, msg = c:commit(config)
    if success then
	update_vpn_guest_fw_rule(c, guestips, oldip, oldmask)
	update_firewall_rules_for_vpns(c, 'wg', true)
	success, msg = c:commit(firewall)
    end

    return {
        status = success and 'success' or 'fail',
	svrpubkey = c:get(config, s, 'publickey'),
	message = success and '' or i18n.translate('Failed to save configuration'),
	apply = success and config or '',
    }
end

function init_server()
    local c = uci.cursor()
    local s = c:get_first(config, 'server')
    local privatekey = util.exec('wg genkey'):trim()
    local publickey = util.exec('echo '..privatekey..' | wg pubkey'):trim()

    c:set(config, s, 'privatekey', privatekey)
    c:set(config, s, 'publickey', publickey)

    local ok = c:commit(config)

    http.prepare_content('application/json')
    http.write_json({
       status = ok and "success" or "fail",
       svrpubkey = ok and publickey or '',
       message = ok and '' or i18n.translate('Failed to regenerate server key'),
    })
end

function init_client()
    local privatekey = util.exec('wg genkey'):trim()
    local publickey = util.exec('echo '..privatekey..' | wg pubkey'):trim()
    http.prepare_content('application/json')
    http.write_json({
	status = "success",
	privatekey = privatekey,
	publickey = publickey,
    })
end

function get_peer_info()
    http.prepare_content('application/json')

    local v = http.formvalue()
    if not v.peername then
	http.write_json({
	    status = 'fail',
	    message = i18n.translate('Missing WireGuard peer name'),
	})
	return
    end

    local c = uci.cursor()
    local p
    c:foreach(config, 'peer', function(s)
	if s.name == v.peername then
	    p = s['.name']
	    return false
	end
    end)

    if p then
	http.write_json({
	    status = 'success',
	    data = {
		privatekey = c:get(config, p, 'privatekey'),
		publickey = c:get(config, p, 'publickey'),
		ip = c:get(config, p, 'ip'),
		dns = c:get('network', 'lan', 'ipaddr'),
	    },
	})
    else
	http.write_json({
	    status = 'fail',
	    message = i18n.translate('No WireGuard peer found'),
	})
    end
end

local function get_peer_by_name(c, peername)
    if not peername then
	http.prepare_content('text/html')
	http.write('Error: no WireGuard peer selected')
	return false
    end

    local p
    c:foreach(config, 'peer', function(s)
	if s.name == peername then
	    p = s['.name']
	    return false
	end
    end)

    if not p then
        http.prepare_content('text/html')
        http.write('Error: no WireGuard peer found')
 	return false
    end

    return p
end

function download_peer_conf()
    local c = uci.cursor()
    local v = http.formvalue()
    local p = get_peer_by_name(c, v.peername)
    if not p then return end

    local svr = c:get_first(config, 'server')
    local conf = '[Interface]\n'
    conf = conf .. 'Address = '.. c:get(config, p, 'ip') ..'/32\n'
    conf = conf .. 'ListenPort = '.. math.random(1025, 65535) ..'\n'
    conf = conf .. 'PrivateKey = '.. c:get(config, p, 'privatekey') ..'\n'
    conf = conf .. 'DNS = '.. c:get('network', 'lan', 'ipaddr') ..'\n\n'
    conf = conf .. '[Peer]\n'
    conf = conf .. 'PublicKey = '.. c:get(config, svr, 'publickey') .. '\n'
    conf = conf .. 'Endpoint = ' .. c:get(config, svr, 'extaddr') .. ':' .. c:get(config, svr, 'port') .. '\n'
    conf = conf .. 'AllowedIPs = 0.0.0.0/0\n'
    conf = conf .. 'PersistentKeepalive = 25\n'

    http.prepare_content('application/octet-stream')
    if string.is_empty(v.password) then
	http.header('Content-Disposition', 'attachment; filename="wg0.conf"')
	http.write(conf)
    else
	local o, i = popen2('openssl aes-256-cbc -md sha512 -pbkdf2 -a -pass pass:\'%s\' 2>/tmp/wg-encrypt.log' % v.password)
	if o == nil or i == nil then
	    if o ~= nil then o:close() end
	    if i ~= nil then i:close() end
	    return
	end
	
	o:write(conf)
	o:close()

	local encconf = ''
	local r = i:read(2048)
	while r ~= nil and r ~= '' do
	    encconf = encconf .. r
	    r = i:read(2048)
	end
	i:close()

	local f = io.open("/tmp/wg-encrypt.log", 'r')
	local log = f:read("*a")
	f:close()
	nixio.fs.remove('/tmp/wg-encrypt.log')

	if not string.is_empty(log) then
	    return
	end

	http.header('Content-Disposition', 'attachment; filename="wg0.conf.encrypted"')
	http.write(encconf)
    end
end

function download_peer_qr()
    local c = uci.cursor()
    local v = http.formvalue()
    local p = get_peer_by_name(c, v.peername)
    if not p then return end

    local svr = c:get_first(config, 'server')
    local o, i = popen2('qrencode -t SVG -o -')
    if o == nil or i == nil then
	if o ~= nil then o:close() end
	if i ~= nil then i:close() end
	return
    end

    http.prepare_content('image/svg+xml')
    o:write('[Interface]\n')
    o:write('Address = '.. c:get(config, p, 'ip') ..'/32\n')
    o:write('ListenPort = '.. math.random(1025, 65535) ..'\n')
    o:write('PrivateKey = '.. c:get(config, p, 'privatekey') ..'\n')
    o:write('DNS = '.. c:get('network', 'lan', 'ipaddr') ..'\n\n')
    o:write('[Peer]\n')
    o:write('PublicKey = '.. c:get(config, svr, 'publickey') .. '\n')
    o:write('Endpoint = ' .. c:get(config, svr, 'extaddr') .. ':' .. c:get(config, svr, 'port') .. '\n')
    o:write('AllowedIPs = 0.0.0.0/0\n')
    o:write('PersistentKeepalive = 25\n')
    o:close()

    local r = i:read(2048)
    while r ~= nil and r ~= '' do
       http.write(r)
       r = i:read(2048)
     end
    i:close()
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

function _update_client(c, v)
    local success, msg

    local iiface = v.networks
    if type(iiface) == 'string' then
	iiface = { iiface }
    end

    local cfgs = {}
    success = set_vpn_ifaces(c, 'wg', iiface, cfgs)

    if success then
	local nnames = {}
	for _, conn in ipairs(v.conns) do
	    nnames[#nnames + 1] = conn.name
	end

	local dconns = {}
	local cnames = {}
	local snames = {}
	c:foreach(config, 'conn', function(conn)
	    if not string_in_array(conn.name, nnames) then
		dconns[#dconns + 1] = conn['.name']
	    else
		cnames[#cnames + 1] = conn.name
		snames[conn.name] = conn['.name']
	    end
	end)

	local s
	for _, conn in ipairs(v.conns) do
	    if string_in_array(conn.name, cnames) then
		s = snames[conn.name]
	    else
		s = c:section(config, 'conn')
		c:set(config, s, 'name', conn.name)
	    end
	    if conn.ip then c:set(config, s, 'ip', conn.ip) end
	    if conn.port then c:set(config, s, 'port', conn.port) end
	    if conn.privatekey then c:set(config, s, 'privatekey', conn.privatekey) end
	    if conn.publickey then c:set(config, s, 'publickey', conn.publickey) end
	    if conn.dns then c:set(config, s, 'dns', conn.dns) end
	    if conn.presharedkey then c:set(config, s, 'presharedkey', conn.presharedkey) end
	    if conn.serverpubkey then c:set(config, s, 'serverpubkey', conn.serverpubkey) end
	    if conn.serverhost then c:set(config, s, 'serverhost', conn.serverhost) end
	    if conn.serverport then c:set(config, s, 'serverport', conn.serverport) end
	    if conn.autostart then
		c:set(config, s, 'autostart', '1')
	    else
		c:delete(config, s, 'autostart')
	    end
	end

	for _, s in ipairs(dconns) do
	    c:delete(config, s)
	end

	success, msg = c:commit(config)
    end

    if success then
	update_firewall_rules_for_vpnc(c, 'wg', 'wgc')
    end

    add_if_not_exists(cfgs, config)
    return {
	status = success and 'success' or 'fail',
	message = success and '' or i18n.translate('Failed to save configuration'),
	apply = success and cfgs or '',
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

function get_conn_parms()
    local params = {}
    local v = http.formvalue()
    if v.cfg then
	local c = uci.cursor()
	c:foreach(config, 'conn', function(s)
	    if s.name == v.cfg then
		params = {
		    name = s.name,
		    ip = s.ip,
		    port = s.port,
		    privatekey = s.privatekey,
		    publickey = s.publickey,
		    dns = s.dns,
		    presharedkey = s.presharedkey,
		    serverpubkey = s.serverpubkey,
		    serverhost = s.serverhost,
		    serverport = s.serverport,
		}
	    end
	end)
    end

    http.prepare_content('application/json')
    http.write_json({
	status = 'success',
	data = params,
    })
end

function add_conn_config()
    local content = '', rc
    http.setfilehandler(
	function(meta, chunk, eof)
	    if chunk then content = content .. chunk end
	end
    )

    http.prepare_content('application/json')

    local v = http.formvalue()
    if string.is_empty(v.wgconfig) then
	http.write_json({
	    status = 'error',
	    message = {
		wgconfigfile = i18n.translate('Please select a WireGuard config file')
	    }
	})
	return
    end

    if not content:match('%[Interface%]') then
	if string.is_empty(v.decpass) then
	    http.write_json({
		status = 'error',
		message = {
		    decpass = i18n.translate('Please enter the decryption password')
		}
	    })
	    return
	end

	local o, i = popen2('openssl aes-256-cbc -md sha512 -pbkdf2 -d -a -pass pass:\'%s\' 2>/tmp/wg-encrypt.log' % v.decpass)
	if o == nil or i == nil then
	    if o ~= nil then o:close() end
	    if i ~= nil then i:close() end
	    http.write_json({
		status = 'fail',
		message = i18n.translate('Failed to parse WireGuard config file'),
	    })
	    return
	end

	o:write(content)
	o:close()

	local decconf = ''
	local r = i:read(2048)
	while r ~= nil and r ~= '' do
	    decconf = decconf .. r
	    r = i:read(2048)
	end
	i:close()

	local f = io.open("/tmp/wg-encrypt.log", 'r')
	local log = f:read("*a")
	f:close()
	nixio.fs.remove('/tmp/wg-encrypt.log')

	if not string.is_empty(log) then
	    http.write_json({
		status = 'error',
		message = {
		    decpass = i18n.translate('Wrong decryption password')
		}
	    })
	    return
	end

	content = decconf
    end

    local line
    local section, address, port, privatekey, publickey, dns, presharedkey, serverpubkey, serverhost, serverport 
    for line in string.gmatch(content, '[^\r\n]+') do
	if line == '[Interface]' then
	    section = 'interface'
	elseif line == '[Peer]' then
	    section = 'peer'
	elseif section == 'interface' then
	    if line:match('%s*Address%s*=%s*(.*)') then
		address = line:match('%s*Address%s*=%s*(.*)')
		address = address:split('/')[1]
	    elseif line:match('%s*ListenPort%s*=%s*(.*)') then
		port = line:match('%s*ListenPort%s*=%s*(.*)')
	    elseif line:match('%s*PrivateKey%s*=%s*(.*)') then
		privatekey = line:match('%s*PrivateKey%s*=%s*(.*)')
	    elseif line:match('%s*PublicKey%s*=%s*(.*)') then
		publickey = line:match('%s*PublicKey%s*=%s*(.*)')
	    elseif line:match('%s*DNS%s*=%s*(.*)') then
		dns = line:match('%s*DNS%s*=%s*(.*)')
	    end
	elseif section == 'peer' then
	    if line:match('%s*PublicKey%s*=%s*(.*)') then
		serverpubkey = line:match('%s*PublicKey%s*=%s*(.*)')
	    elseif line:match('%s*PresharedKey%s*=%s*(.*)') then
		presharedkey = line:match('%s*PresharedKey%s*=%s*(.*)')
	    elseif line:match('%s*Endpoint%s*=%s*(.*)') then
		local endpoint = line:match('%s*Endpoint%s*=%s*(.*)'):split(':')
		serverhost = endpoint[1]
		serverport = endpoint[2]
	    end
	end
    end

    if not port or not tonumber(port) then port = math.random(11025, 65535) end

    http.write_json({
	status = 'success',
	ip = address,
	port = port,
	privatekey = privatekey,
	publickey = publickey,
	dns = dns,
	presharedkey = presharedkey,
	serverpubkey = serverpubkey,
	serverhost = serverhost,
	serverport = serverport,
    })
end

function connect()
    http.prepare_content('application/json')

    local v = http.formvalue()
    if not v.cfg then
	http.write_json({
	    status = 'error',
	    message = i18n.translate('Missing connection name')
	})
	return
    end

    local c = uci.cursor()
    local name
    c:foreach(config, 'conn', function(s)
	if s.name == v.cfg then
	    name = v.cfg
	    return false
	end
    end)

    if name == nil then return end

    local state, message, status
    message = ''
    status = 'success'

    luci.sys.init.stop('wg')
    local fp = io.open('/tmp/wg_client', 'w')
    if fp then
	if v.action == 'start' then
	    fp:write(name)
	    state = 'running'
	else
	    fp:write('')
	    state = 'stopped'
	end
	fp:close()
    else
	status = 'fail'
	message = v.action == 'start' and ii18n.translate('Failed to start client connection') or i18n.translate('Failed to stop client connection')
    end
    luci.sys.init.start('wg')

    http.write_json({
	status = status,
	message = message,
	state = state,
    })
end

function wg_state()
    http.prepare_content('application/json')

    local v = http.formvalue()
    if not v.cfg then
	http.write_json({
	    status = 'error',
	    message = i18n.translate('Missing configuration name') 
	})
	return
    end

    http.write_json({
	status = 'success',
	data = {
	    cfg = v.cfg,
	    state = get_conn_state(),
	}
    })
end

function client_logs()
    http.prepare_content('application/json')

    local fp = io.popen('wg show wg1 2>/dev/null', 'r')
    if fp then
	http.write_json({
	    status = 'success',
	    data = fp:read("*all"):gsub('\n', '<br>')
	})
	fp:close()
	return
    end

    http.write_json({
	status = 'fail',
	data = i18n.translate('Failed to read WireGuard logs')
    })
end

function restart_server()
    local success = luci.sys.init.stop('wg')
    if success then success = luci.sys.init.start('wg') end

    http.prepare_content('application/json')
    http.write_json({
	status = success and 'success' or 'fail',
	message = success and '' or i18n.translate('Failed to restart WireGuard server'),
    })
end
