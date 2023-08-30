-- Copyright (C) 2023 pcwrt.com
-- Licensed to the public under the Apache License 2.0.

local http = require "luci.http"
local util = require "luci.util"
local uci = require "luci.pcuci"
local jsonc = require "luci.jsonc"
local dt = require "luci.cbi.datatypes"
local i18n = require "luci.i18n"

require "nixio.fs"
require "luci.sys"
require "luci.pcutil"
require "luci.tools.dhcp"

module("luci.pccontroller.settings.network", package.seeall)

ordering = 20
function display_name()
    return i18n.translate('Network')
end

local network = 'network'
local dhcp = 'dhcp'
local firewall = 'firewall'
local lan = 'lan'

local function add_lan_dev(c, name, macaddr)
    local exists
    c:foreach(network, 'device', function(d)
	if d.name == name then
	    exists = d
	    return false
	end
    end)

    if not exists then
	local lan_dev = c:section(network, 'device', 'lan_dev')
	c:set(network, lan_dev, 'name', name)
	c:set(network, lan_dev, 'macaddr', macaddr)
    end
end

local function delete_lan_dev(c, name)
    local sname
    c:foreach(network, 'device', function(d)
	if d.name == name then
	    sname = d['.name']
	    return false
	end
    end)

    if sname then c:delete(network, sname) end
end

local function get_config_hosts(c)
    local hosts = {}
    c:foreach(dhcp, 'host', function(s)
 	for _, mac in ipairs(s.mac:split(' ')) do
  	    hosts[#hosts+1] = {
   		name = s.name,
    		mac = mac:upper(),
     		ip = s.ip,
      	    }
       	end
    end)
    return hosts
end

local function flattern_hosts(updt_vals)
    local hosts = {}
    for _, v in ipairs(updt_vals) do
     	local found = nil
      	for _, h in ipairs(hosts) do
	    if v.name:upper() == h.name:upper() and v.ip == h.ip then
		found = h
	 	break
	    end
	end

	if found then
	    found.mac = found.mac .. ' ' .. v.mac
	else
	    hosts[#hosts+1] = {
	  	name = v.name,
	   	mac = v.mac,
	    	ip = v.ip,
	    }
	end
    end

    return hosts
end

local function get_config_routes(c)
    local routes = {}
    c:foreach(network, 'route', function(s)
	routes[#routes+1] = {
	    interface = s.interface,
	    target = s.target,
	    netmask = s.netmask,
	    gateway = s.gateway,
	    metric = s.metric,
	}
    end)
    return routes
end

local function get_config_forwards(c)
    local forwards = {}
    c:foreach(firewall, 'redirect', function(s)
	if s.target == 'DNAT' and string_in_array(s.src, {'wan','wgc','vpnc'}) and
	   (s.enabled == nil or s.enabled == '1') then
	    forwards[#forwards+1] = {
		name = s.name,
		proto = s.proto,
		src_dport = s.src_dport,
		dest_ip = s.dest_ip,
		dest_port = s.dest_port,
		src = s.src,
	    }
	end
    end)
    return forwards
end

local function update_config(c, cfgs, config, cfg_type, del_cmp, exist_vals, updt_vals, cmp)
    local change = false
    if #updt_vals ~= #exist_vals then
	change = true
    else
	for _, v1 in ipairs(exist_vals) do
	    for i, v2 in ipairs(updt_vals) do
		if cmp(v1, v2) then
		    v1.no_change = true
		    break
		end
	    end
	end

	for _, v1 in ipairs(exist_vals) do
	    if not v1.no_change then
		change = true
		break
	    end
	end
    end

    if change then
	local del = {}
	c:foreach(config, cfg_type, function(r)
	    if not del_cmp or del_cmp(r) then
		del[#del+1] = r['.name']
	    end
	end)

	for _, j in ipairs(del) do
	    c:delete(config, j)
	end

	if #updt_vals > 0 then
   	    if cfg_type == 'host' then
  		updt_vals = flattern_hosts(updt_vals)
 	    end
	
	    for _, vals in ipairs(updt_vals) do
		c:section(config, cfg_type, nil, vals)
	    end
	end
	add_if_not_exists(cfgs, config == network and 'network' or config)
    end

    return change
end

local function get_stealth_mode(c)
    local stealth = '0'
    c:foreach(firewall, 'zone', function(s)
	if s.name == 'wan' then
	    if s.input == 'DROP' then
		stealth = '1'
	    end
	    return false
	end
    end)
    return stealth
end

local function set_stealth_mode(c, stealth_mode)
    local target = stealth_mode == '1' and 'DROP' or 'REJECT'
    c:foreach(firewall, 'zone', function(s)
	if s.name == 'wan' then
	    c:set(firewall, s['.name'], 'input', target)
	    c:set(firewall, s['.name'], 'forward', target)
	    return false
	end
    end)
end

local function get_block_ping(c)
    local bp = '0'
    c:foreach(firewall, 'rule', function(s)
	if s.name == 'Allow-Ping' then
	    if s.target == 'DROP' then
		bp = '1'
	    end
	    return false
	end
    end)
    return bp
end

local function set_block_ping(c, block_ping)
    local target = block_ping == '1' and 'DROP' or 'ACCEPT'
    c:foreach(firewall, 'rule', function(s)
	if s.name == 'Allow-Ping' then
	    c:set(firewall, s['.name'], 'target', target)
	    return false
	end
    end)
end

local function get_mdns()
    if not nixio.fs.access("/etc/init.d/avahi-daemon") then
	return nil
    end

    if not luci.sys.init.enabled('avahi-daemon') then
	return '0'
    end

    return '1'
end

local function get_vlan_iface_for_ip(c, ifaces, ip)
    for _, iface in ipairs(ifaces) do
	local net = get_network_for_ip(c, ip)
	if net and net.name == iface.name then
	    return iface
	end
    end
    return nil
end

local function get_vlans(c)
    local tagged
    local port_info = {}
    local vlanid = get_wan_vlan_id_tag(c)
    if c:get_first(network, 'switch_vlan') then
	c:foreach(network, 'switch_vlan', function(v)
	    if v.vlan ~= vlanid and v.ports ~= nil then
		local ports = v.ports:split(' ')
		tagged = table.remove(ports)
		for _, port in ipairs(ports) do
		    local p, t = port:match('(%d)(t?)')
		    add_if_not_exists(port_info, {
			port = p,
			tagged = t == 't' and true or false,
			id = get_canonical_vlan_id(c, v.vlan),
		    }, function(pi) return pi.port end)
		end
	    end
	end)

	c:foreach(network, 'switch_port', function(v)
	    for _, pi in ipairs(port_info) do
		if v.port == pi.port then
		    pi.id = get_canonical_vlan_id(c, v.pvid)
		    break
		end
	    end
	end)
    else
	c:foreach(network, 'device', function(s)
	    if s.name == 'br-lan' and s.type == 'bridge' then
		local pno = 1
		local p = get_vlan_params(c, 'lan')
		local ports = c:get_list(network, s['.name'], 'ports')
		for _, port in ipairs(ports) do
		    port_info[pno] = {
			port = tostring(pno - 1),
			id = p.id,
			tagged = false,
			name = port,
		    }
		    pno = pno + 1
		end

		return false
	    end
	end)

	c:foreach(network, 'bridge-vlan', function(s)
	    if s.device == 'br-lan' then
		for _, port in ipairs(c:get_list(network, s['.name'], 'ports')) do
		    for _, pi in ipairs(port_info) do
			if port:starts(pi.name) then
			    local tag, pvid = port:match('(:t)(%*?)')
			    if tag == ':t' then
				pi.tagged = true
				if pvid then
				    pi.id = get_canonical_vlan_id(c, s.vlan)
				end
			    else
				pi.id = get_canonical_vlan_id(c, s.vlan)
			    end
			end
		    end
		end
	    end
	end)
    end

    table.sort(port_info, function(a, b) return a.port < b.port end)

    return { ports = port_info, options = get_vlan_options() }, tagged
end

local function get_vlan_map(c)
    local map = c:get(network, 'vlanctrl', 'map')
    if map then map = map:split(',') end

    if not map or #map ~= 25 then map = string.split('1,1,1,1,1,0,1,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,1', ',') end

    return map
end

local function set_effective_vlanid(c, vlan_ports)
    local i, eid
    local evlan_id = 3 -- effective vlan_id
    local wan_vlanid = get_wan_vlan_id_tag(c)
    for i = 3, 6 do
	local vlan_id = tostring(i)
	if vlan_ports[vlan_id] ~= nil then
	    eid = tostring(evlan_id)
	    if eid == wan_vlanid then
		eid = '7'
	    end
	    vlan_ports[vlan_id].eid = eid
	    evlan_id = evlan_id + 1
	end
    end
end

local function update_switch_vlan(c, lan_ports, vlan_ports, tagged)
    local vlan_name
    local vlanid = get_wan_vlan_id_tag(c)
    c:delete_all(network, 'switch_vlan', function(s)
	return s.vlan ~= vlanid
    end)

    if #lan_ports > 0 then
	vlan_name = c:section(network, 'switch_vlan')
	c:set(network, vlan_name, 'device', 'switch0')
	c:set(network, vlan_name, 'vlan', '1')
	c:set(network, vlan_name, 'ports', table.concat(map(lan_ports, function(v) return v.tagged and v.port .. 't' or v.port end), ' ') .. ' ' .. tagged)
    end

    for i = 3, 6 do -- vlans have id from 3 to 6, LAN has id 1
	local vlan_id = tostring(i)
	if vlan_ports[vlan_id] ~= nil then
	    vlan_name = c:section(network, 'switch_vlan')
	    c:set(network, vlan_name, 'device', 'switch0')
	    c:set(network, vlan_name, 'vlan', vlan_ports[vlan_id].eid)
	    c:set(network, vlan_name, 'ports', table.concat(map(vlan_ports[vlan_id], function(v) return v.tagged and v.port .. 't' or v.port end), ' ') .. ' ' .. tagged)
	end
    end
end

local function validate(v)
    local errs = {}

    if not dt.ip4addr(v.ipaddr) then
	errs.ipaddr = i18n.translate('Invalid IP address')
    end

    if not dt.ip4addr(v.netmask) then
	errs.netmask = i18n.translate('Invalid netmask')
    end

    if v.start == nil or not v.start:match('^%d+$')  then
	errs.start = i18n.translate('Invalid value for DHCP Start')
    end

    if v.limit == nil or not v.limit:match('^%d+$')  then
	errs.limit = i18n.translate('Invalid value for DHCP Limit')
    end

    if v.leasetime == nil or not v.leasetime:match('^%d+[h,m]$')  then
	errs.leasetime = i18n.translate('Invalid value for DHCP Lease Time')
    end

    local ok = true
    for _, v in pairs(errs) do
	ok = false
	break
    end

    return ok, errs
end

local function has_flow_offloading()
    local r = jsonc.parse(util.exec("ubus call luci offload_support"))
    return r and r.offload_support or nil
end

function _get_data(c)
    local dft = c:get_first(firewall, 'defaults')
    return {
	ipaddr = c:get(network, lan, 'ipaddr'),
	netmask = c:get(network, lan, 'netmask'),
	start = c:get(dhcp, lan, 'start'),
	limit = c:get(dhcp, lan, 'limit'),
	leasetime = c:get(dhcp, lan, 'leasetime'),
	ifaces = get_vlan_ifaces(c),
	routes = get_config_routes(c),
	hosts = get_config_hosts(c),
	forwards = get_config_forwards(c),
	leases = luci.tools.dhcp.dhcp_leases(),
	stealth_mode = get_stealth_mode(c),
	block_ping = get_block_ping(c),
	mdns = get_mdns(),
	vlans = get_vlans(c),
	vlanmap = get_vlan_map(c),
	has_flow_offloading = has_flow_offloading(),
	flow_offloading = c:get(firewall, dft, 'flow_offloading'),
    }
end

function index()
    local c = uci.cursor()

    local t = template("settings/network")
    local ok, err = util.copcall(t.target, t, {
	title = 'Network',
	form_value_json = jsonc.stringify(_get_data(c)),
	page_script = 'settings/network.js',
    })
    assert(ok, 'Failed to render template ' .. t.view .. ': ' .. tostring(err))
end

local function update_dhcp_option6(c, dhcp, oldip, newip)
    c:foreach(dhcp, 'dhcp', function(s)
	local opts = s.dhcp_option
	if type(opts) == 'table' then
	    local new_opts = {}
	    for _, opt in ipairs(opts) do
		if opt:starts('6,') then
		    new_opts[#new_opts + 1] = '6,'..newip
		else
		    new_opts[#new_opts + 1] = opt
		end
	    end
	    c:set_list(dhcp, s['.name'], 'dhcp_option', new_opts)
	end
    end)
end

local function create_bridge_vlan(c, vlan_ports, vlan_id)
    local ports = {}
    for _, vlan in ipairs(vlan_ports) do
	local port_name = vlan.name
	if vlan.tagged then
	    port_name = port_name .. ':t'
	    if vlan_id == vlan.id then port_name = port_name .. '*' end
	end
	ports[#ports+1] = port_name
    end

    local s = c:section(network, 'bridge-vlan')
    c:set(network, s, 'device', 'br-lan')
    c:set(network, s, 'vlan', vlan_id)
    c:set_list(network, s, 'ports', ports)
end

function _update(c, v)
    local reboot = false
    local ok, errs = validate(v)
    if not ok then
	return {
	    status = 'error',
	    message = errs
	}
    end

    local cfgs = {}

    local lanip = c:get(network, lan, 'ipaddr')
    local ifaces = get_vlan_ifaces(c)
    local lanip_changed = false
    local nt_cfgs = {'ipaddr', 'netmask'}
    for _, cfg in ipairs(nt_cfgs) do
	if v[cfg] ~= c:get(network, lan, cfg) then
	    lanip_changed = true
	    add_if_not_exists(cfgs, 'network')
	    break
	end
    end

    if #cfgs > 0 then -- ipaddr or netmask updated
	reboot = true

	-- Update LAN IP and VLAN IPs
	for _, cfg in ipairs(nt_cfgs) do
	    if v[cfg] ~= c:get(network, lan, cfg) then
		c:set(network, lan, cfg, v[cfg])
	    end
	end

	for _, iface in ipairs(ifaces) do
	    if iface.ipaddr then
		local vlan = get_vlan_params(c, iface.name, v['ipaddr'])
		if vlan and vlan.name ~= 'lan' then
		    c:set(network, iface.name, 'ipaddr', vlan.ip)
		end
	    end
	end

	-- Update DHCP option6 (DNS)
	update_dhcp_option6(c, dhcp, lanip, v['ipaddr'])
	add_if_not_exists(cfgs, dhcp)

	-- update lanip in firewall config
	if lanip ~= v['ipaddr'] then
	    update_firewall_lan_ipset(c, lanip, false)
	    add_if_not_exists(cfgs, firewall)
	end
    end

    if has_flow_offloading() then
	local dft = c:get_first(firewall, 'defaults')
	if v.flow_offloading ~= c:get(firewall, dft, 'flow_offloading') then
	    if v.flow_offloading then
		c:set(firewall, dft, 'flow_offloading', '1')
	    else
		c:delete(firewall, dft, 'flow_offloading')
	    end
	    add_if_not_exists(cfgs, firewall)
	end
    end

    local dhcp_cfgs = {'start', 'limit', 'leasetime'}
    for _, cfg in ipairs(dhcp_cfgs) do
	if v[cfg] ~= c:get(dhcp, lan, cfg) then
	    c:set(dhcp, lan, cfg, v[cfg])
	    add_if_not_exists(cfgs, dhcp)
	end
    end

    -- preprocess forwards
    local forwards = v.forwards == nil and {} or jsonc.parse(v.forwards)
    for _, f in ipairs(forwards) do
	local iface = get_vlan_iface_for_ip(c, ifaces, f.dest_ip)
	if iface then
	    local vpn = nil
	    c:foreach('vpn-ifaces', 'vpn-iface', function(s)
		if fwv() ~= 'full' or s.iface == iface.name then
		    vpn = s.vpn
		    return false
		end
	    end)

	    if vpn == 'openvpn' then
		f.src = 'vpnc'
	    elseif vpn == 'wg' then
		f.src = 'wgc'
	    else
		f.src = 'wan'
	    end

	    f.dest = iface.name
	    f.target = 'DNAT'
	else
	    f.dest = nil
	end
    end

    -- process vlans
    local vlan_id
    local vlan_ports = {}
    local lan_ports = {}
    local vlans, tagged = get_vlans(c)
    local vlan_updated = string_in_array('network', cfgs)

    local vvlans = jsonc.parse(v.vlans)
    for _, vlan in ipairs(vvlans) do
	if not vlan_updated then
	    for _, vl in ipairs(vlans.ports) do
		if vl.port == vlan.port then
		    if vl.id ~= vlan.id or vl.tagged ~= vlan.tagged then
			vlan_updated = true
			break
		    end
		end
	    end
	else
	    break
	end
    end

    local deleted_vlan = {}
    if vlan_updated then
	for _, vlan in ipairs(vvlans) do
	    if vlan.tagged then
		lan_ports[#lan_ports+1] = vlan
		for i = 3, 6 do -- vlans have id from 3 to 6, LAN has id 1
		    vlan_id = tostring(i)
		    local vports = vlan_ports[vlan_id]
		    if vports == nil then
			vlan_ports[vlan_id] = {vlan}
		    else
			vports[#vports + 1] = vlan
		    end
		end
	    else
		if vlan.id == '1' then
		    lan_ports[#lan_ports+1] = vlan
		else
		    local vports = vlan_ports[vlan.id]
		    if vports == nil then
			vlan_ports[vlan.id] = {vlan}
		    else
			vports[#vports + 1] = vlan
		    end
		end
	    end
	end

	set_effective_vlanid(c, vlan_ports)

	if tagged then
	    update_switch_vlan(c, lan_ports, vlan_ports, tagged)
	else
	    c:delete_all(network, 'bridge-vlan', function(s)
		return s.device == 'br-lan'
	    end)
	end

	for i = 3, 6 do -- vlans have id from 3 to 6, LAN has id 1
	    vlan_id = tostring(i)
	    local nw_name = get_vlan_network_name(vlan_id)
	    if vlan_ports[vlan_id] == nil then
		if delete_vlan_network(c, nw_name, false, cfgs) then
		    deleted_vlan[nw_name] = vlan_id
		elseif tagged then
		    delete_ifname_from_network(c, nw_name)
		else
		    c:delete(network, nw_name, 'device')
		    c:set(network, nw_name, 'type', 'bridge')
		end
	    else
		create_vlan_network(c, nw_name, cfgs)
		if tagged then
		    add_ifname_to_network(c, nw_name, get_lanif_base()..'.'..vlan_ports[vlan_id].eid)
		else
		    create_bridge_vlan(c, vlan_ports[vlan_id], vlan_ports[vlan_id].eid)
		    c:delete(network, nw_name, 'type')
		    c:set(network, nw_name, 'device', 'br-lan.'..vlan_ports[vlan_id].eid)
		end
	    end
	end

	if #lan_ports == 0 then
	    if tagged then
		delete_ifname_from_network(c, lan)
	    else
		c:delete(network, lan, 'device')
		c:set(network, lan, 'type', 'bridge')
	    end
	else
	    if tagged then
		add_ifname_to_network(c, lan, get_lan_ifname())
	    else
		create_bridge_vlan(c, lan_ports, '1')
		c:delete(network, lan, 'type')
		c:set(network, lan, 'device', 'br-lan.1')
	    end
	end

	if tagged then
	    c:delete_all(network, 'switch_port')
	    for _, vlan in ipairs(vvlans) do
		if vlan.tagged then
		    local s = c:section(network, 'switch_port')
		    c:set(network, s, 'device', 'switch0')
		    c:set(network, s, 'port', vlan.port)
		    if vlan.id == '1' then
			c:set(network, s, 'pvid', '1')
		    else
			c:set(network, s, 'pvid', vlan_ports[vlan.id].eid)
		    end
		end
	    end
	end

	add_if_not_exists(cfgs, 'network')
	ifaces = get_vlan_ifaces(c)
    end

    if update_vlanmap(c, v.vlanmap) then
	add_if_not_exists(cfgs, 'network')
	add_if_not_exists(cfgs, firewall)
    end

    -- process routes
    local routes = v.routes == nil and {} or jsonc.parse(v.routes)
    update_config(c, cfgs, network, 'route', nil, get_config_routes(c), routes, 
	function(r1, r2)
	    return r1.interface == r2.interface 
	       and r1.target == r2.target
	       and r1.netmask == r2.netmask
	       and r1.gateway == r2.gateway
	       and r1.metric == r2.metric
	end
    )

    -- process hosts
    local new_hosts = {}
    local hosts = v.hosts == nil and {} or jsonc.parse(v.hosts)
    for _, h in ipairs(hosts) do
	local iface = get_vlan_iface_for_ip(c, ifaces, h.ip)
	if iface and deleted_vlan[iface.name] == nil then
	    new_hosts[#new_hosts+1] = h
	end
    end

    local old_hosts = get_config_hosts(c)
    local hosts_updated = update_config(c, cfgs, dhcp, 'host', nil, old_hosts, new_hosts,
	function(h1, h2)
	    return h1.name == h2.name and h1.mac == h2.mac and h1.ip == h2.ip
	end
    )

    if hosts_updated then -- update router ACL
	local new_names = {}
	local mac, macs, hn, new_name

	for _, h in ipairs(new_hosts) do
	    new_names[h.mac] = h.name
	end

	local old_names = {}
	for _, h in ipairs(old_hosts) do
	    macs = old_names[h.name]
	    if macs then
		macs[#macs + 1] = h.mac
	    else
		old_names[h.name] = {h.mac}
	    end
	end

	local m = {}
	for name, macs in pairs(old_names) do
	    new_name = nil
	    for _, mac in ipairs(macs) do
		if new_names[mac] then
		    new_name = new_names[mac]
		    break
		end
	    end

	    if new_name == nil then
		m[name] = false
	    elseif name ~= new_name then
		m[name] = new_name
	    end
	end

	update_router_acl(c, m)
    end

    -- process forwards
    local add_forwards = {}
    for _, f in ipairs(forwards) do
	if f.dest ~= nil and deleted_vlan[f.dest] == nil then
	    add_forwards[#add_forwards+1] = f
	end
    end

    update_config(c, cfgs, firewall, 'redirect',
	function(section)
	    return section.target == 'DNAT' and
		   string_in_array(section.src, {'wan','wgc','vpnc'}) and
		   string_in_array(section.dest, get_vlan_list(), function(v) return v.name end)
	end,
	get_config_forwards(c),
	add_forwards,
	function(f1, f2)
	    return f1.name == f2.name
	       and f1.proto == f2.proto
	       and f1.src_dport == f2.src_dport
	       and f1.dest_ip == f2.dest_ip
	       and f1.dest_port == f2.dest_port
	       and f1.src == f2.src
	end
    )

    -- process security flags
    if v.stealth_mode ~= get_stealth_mode(c) then
	set_stealth_mode(c, v.stealth_mode)
	add_if_not_exists(cfgs, firewall)
    end

    if v.block_ping ~= get_block_ping(c) then
	set_block_ping(c, v.block_ping)
	add_if_not_exists(cfgs, firewall)
    end

    local mdns = get_mdns()
    if mdns ~= nil then
	if v.mdns == '1' then
	    if mdns ~= '1' then
		luci.sys.init.enable('avahi-daemon')
		luci.sys.init.restart('avahi-daemon')
		local s = c:get_first(network, 'mdns')
		if not s then c:section(network, 'mdns', 'mdns') end
		c:set(network, 'mdns', 'enabled', '1')
		add_if_not_exists(cfgs, 'network')
	    end
	else
	    if mdns == '1' then
		luci.sys.init.stop('avahi-daemon')
		luci.sys.init.disable('avahi-daemon')
		c:delete(network, 'mdns')
		add_if_not_exists(cfgs, 'network')
	    end
	end
    end

    local success = true
    for _, cfg in ipairs(cfgs) do
	if cfg == 'network' then cfg = network end
	if not c:commit(cfg) then
	    success = false
	    break
	end
    end

    return {
	status = success and 'success' or 'fail',
    	message = success and '' or i18n.translate('Failed to save configuration'),
	apply = success and cfgs or '',
	reboot = reboot,
	reload_url = build_url and build_url('applyreboot') or '',
	addr = v['ipaddr'],
	ifaces = ifaces,
    }
end

function update()
    http.prepare_content('application/json')
    local c = uci.cursor()
    local v = http.formvalue()
    local r = _update(c, v)
    if r.status == 'success' then
	if r.reboot then
	    put_command({type="reboot"})
	elseif #r.apply > 0 then
	    local reloads = get_reload_list(c, r.apply)
	    r.apply = nil
	    put_command({
		type = "fork_exec",
		command = "sleep 3;/sbin/luci-restart %s >/dev/null 2>&1" % table.concat(reloads, ' '),
	    })
	else
	    r.apply = ''
	end
    end

    http.write_json(r)
end

function _change_hostname(c, v)
    local ok, message
    local errs = {}
    if not dt.hostname(v.hostname) then
	errs.hostname = i18n.translate('Invalid hostname')
	return {
	    status = 'error',
	    message = errs,
	}
    end

    if not dt.macaddr(v.mac) or not dt.ipaddr(v.ip) then
	return {
	    status = 'fail',
	    mac = v.mac,
	    ip = v.ip,
	    message = i18n.translate('Failed to update hostname'),
	}
    end

    local hosts = {}
    local macs = {}
    c:foreach(dhcp, 'host', function(s)
       local hostname = s.name:upper()
       for _, mac in ipairs(s.mac:split(' ')) do
 	    mac = mac:upper()
  	    if hosts[hostname] == nil then
   		hosts[hostname] = {{
    		    cfgname = s['.name'],
     		    name = s.name,
      		    flat_mac = s.mac,
       		    mac = mac,
		    ip = s.ip,
	 	}}
	    else
	   	local idx = #hosts[hostname] + 1
	    	hosts[hostname][idx] = {
	     	    cfgname = s['.name'],
	      	    mac = mac,
	       	    ip = s.ip,
		}
	    end
	    macs[mac] = {
	     	cfgname = s['.name'],
	    }
	end
    end)

    local host = hosts[v.hostname:upper()]
    if host ~= nil then
     	for _, h in ipairs(host) do
    	    if h.mac == v.mac:upper() then
   		return { status = 'success' }
  	    end
 	end
    end

    local cfgs = { dhcp }

    ok = true
    v.mac = v.mac:upper()
    local mac = macs[v.mac]
    local new_hosts = get_config_hosts(c)
    if host ~= nil then
	ok = c:set(dhcp, host[1].cfgname, 'mac', host[1].flat_mac .. ' ' .. v.mac)

  	if ok then
	    ok = c:set(dhcp, host[1].cfgname, 'ip', v.ip)
    	end

     	if ok and mac then
	    local rmac = c:get(dhcp, mac.cfgname, 'mac'):upper()
	    rmac = rmac:gsub(v.mac .. ' *', ''):trim()
	    if #rmac == 0 then
		ok = c:delete(dhcp, mac.cfgname)
	    else
		ok = c:set(dhcp, mac.cfgname, 'mac', rmac)
	    end
       	end

	local existing_mac = false
	for _, h in ipairs(new_hosts) do
	    if h.mac == v.mac then
		existing_mac = true
		h.name = v.hostname
		h.ip = v.ip
		break
	    end
	end

	if not existing_mac then
	    new_hosts[#new_hosts + 1] = {
		name = v.hostname,
		mac = v.mac,
		ip = v.ip,
	    }
	end
    else
	if mac then
	    ok = c:set(dhcp, mac.cfgname, 'name', v.hostname)
	    if ok then
		ok = c:set(dhcp, mac.cfgname, 'ip', v.ip)
		if ok then
		    for _, h in ipairs(new_hosts) do
			if h.mac == v.mac then
			    local m = {}
			    m[h.name] = v.hostname
			    update_router_acl(c, m)
			    h.name = v.hostname
			    h.ip = v.ip
			    break
			end
		    end
		end
	    end
	else
	    local cfgname
	    ok = c:add(dhcp, 'host')
	    if ok then
		cfgname = ok
		ok = c:set(dhcp, cfgname, 'mac', v.mac)
	    end

	    if ok then
		ok = c:set(dhcp, cfgname, 'name', v.hostname) 
	    end

	    if ok then
		ok = c:set(dhcp, cfgname, 'ip', v.ip) 
	    end
	    
	    if ok then
		new_hosts[#new_hosts + 1] = {
		    name = v.hostname,
		    mac = v.mac,
		    ip = v.ip,
		}
	    end
	end
    end

    if ok then
	table.foreach(cfgs, function(_, cfg)
	    if cfg == 'network' then cfg = network end
	    if not c:commit(cfg) then
		ok = false
		return false
	    end
	end)
    end

    return {
    	status = ok and 'success' or 'fail',
    	message = ok and '' or i18n.translate('Failed to change hostname'),
	apply = ok and cfgs or '',
    }
end

function change_hostname()
    http.prepare_content('application/json')

    local v = http.formvalue()
    local c = uci.cursor()
    local r = _change_hostname(c, v)
    http.write_json(r)
end

function ip_status() 
    http.prepare_content('application/json')

    local resp = {}
    
    local v = http.formvalue()
    if type(v.ip) == 'string' then
	v.ip = {v.ip}
    end

    for _, v in ipairs(v.ip) do
	resp[v] = os.execute("ping -c 1 -W 1 %q >/dev/null 2>&1" % v) == 0 and 'on' or 'off'
    end

    http.write_json({
	status = 'success',
	ip_status = resp,
    })
end
