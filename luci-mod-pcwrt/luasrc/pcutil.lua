MAX_CFG_SIZE = 1024*1024

function bool_equivalent(b1, b2)
    local b1n = b1 and b1 ~= '0' or false
    local b2n = b2 and b2 ~= '0' or false
    return b1n == b2n
end

function string.is_empty(s)
    return s == nil or (type(s) == 'string' and s:trim() == '')
end

function string.trim(s)
  return s:match "^%s*(.-)%s*$"
end

function string.starts(String,Start)
    if type(String) ~= 'string' then return false end
    return string.sub(String,1,string.len(Start))==Start
end

function string.ends(String,End)
    if type(String) ~= 'string' then return false end
    return End=='' or string.sub(String,-string.len(End))==End
end

function string:split(sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end

function string:split2(sep)
    local words = {}
    local pattern = string.format("([^%s]*)%s", sep, sep)
    for w in (self..sep):gmatch(pattern) do
	table.insert(words, w)
    end
    return words
end

function map(inputArray, f)
    local result = {}
    for _, v in ipairs(inputArray) do
	result[#result+1] = f(v)
    end
    return result
end

function string:quote_apostrophe()
    return self:gsub("'", "'\"'\"'")
end

function string_in_array(s, a, f)
    if a == nil or type(a) ~= 'table' then
	return false
    end

    local function tr(v)
	if type(f) == 'function' then
	    return f(v)
	end
	return v
    end

    for _, v in ipairs(a) do
	if s == tr(v) then
	    return true
	end
    end

    return false
end

function remove_string_from_array(a, s)
    if a == nil or type(a) ~= 'table' then return false end

    local removed = false
    for i, v in ipairs(a) do
	if s == v then
	    table.remove(a, i)
	    removed = true
	    break
	end
    end

    return removed
end

function add_if_not_exists(tbl, entry, f)
    local found = false

    local function tr(v)
	if type(f) == 'function' then
	    return f(v)
	end
	return v
    end

    for i, v in ipairs(tbl) do
	if tr(v) == tr(entry) then
	    found = true
	    break
	end
    end

    if not found then
	tbl[#tbl+1] = entry
    end
end


function get_reload_list(c, cfgs)
    local util = require "luci.util"
    local reloads = {}

    local function _resolve_deps(name)
	local reload = { name }
	local deps = {}
	c:foreach('ucitrack', name, function(s)
	    if s.affects then
		for _, aff in ipairs(s.affects) do
		    deps[#deps+1] = aff
		end
	    end
	end)

	for _, dep in ipairs(deps) do
	    for _, add in ipairs(_resolve_deps(dep)) do
		reload[#reload+1] = add
	    end
	end

	return reload
    end

    if type(cfgs) == 'string' then
	cfgs = {cfgs}
    end

    for _, cfg in ipairs(cfgs) do
	for _, e in ipairs(_resolve_deps(cfg)) do
	    if not util.contains(reloads, e) then
		reloads[#reloads+1] = e
	    end
	end
    end

    return reloads
end

local freqlist_24g = {
    US = {
	{ channel = 1, mhz = 2412 },
	{ channel = 2, mhz = 2417 },
	{ channel = 3, mhz = 2422 },
	{ channel = 4, mhz = 2427 },
	{ channel = 5, mhz = 2432 },
	{ channel = 6, mhz = 2437 },
	{ channel = 7, mhz = 2442 },
	{ channel = 8, mhz = 2447 },
	{ channel = 9, mhz = 2452 },
	{ channel = 10, mhz = 2457 },
	{ channel = 11, mhz = 2462 },
    }
}

local freqlist_5g = {
    US = {
	{ channel = 36, mhz = 5180 },
	{ channel = 40, mhz = 5200 },
	{ channel = 44, mhz = 5220 },
	{ channel = 48, mhz = 5240 },
	{ channel = 52, mhz = 5260 },
	{ channel = 56, mhz = 5280 },
	{ channel = 60, mhz = 5300 },
	{ channel = 64, mhz = 5320 },
	{ channel = 100, mhz = 5500 },
	{ channel = 104, mhz = 5520 },
	{ channel = 108, mhz = 5540 },
	{ channel = 112, mhz = 5560 },
	{ channel = 116, mhz = 5580 },
	{ channel = 120, mhz = 5600 },
	{ channel = 124, mhz = 5620 },
	{ channel = 128, mhz = 5640 },
	{ channel = 132, mhz = 5660 },
	{ channel = 136, mhz = 5680 },
	{ channel = 140, mhz = 5700 },
	{ channel = 149, mhz = 5745 },
	{ channel = 153, mhz = 5765 },
	{ channel = 157, mhz = 5785 },
	{ channel = 161, mhz = 5805 },
	{ channel = 165, mhz = 5825 },
    }
}

function get_freq_for_channel(channel, band)
    if band == '2.4 GHz' then
	return (2412 + (channel - 1) * 5)/1000
    else
	return (5180 + (channel - 36) * 5)/1000
    end
end

local function get_country(country)
    return country and string.upper(country) or 'US'
end

function channel_list_for_24g(country)
    local cl = {}
    for _, f in ipairs(freqlist_24g[get_country(country)]) do
	if not f.restricted then
	    cl[#cl+1] = {
		value = f.channel,
		text = '%i (%.3f GHz)' % {f.channel, f.mhz/1000},
	    }
	end
    end
    return cl
end

function channel_list_for_5g(country)
    local cl = {}
    for _, f in ipairs(freqlist_5g[get_country(country)]) do
	if not f.restricted then
	    cl[#cl+1] = {
		value = f.channel,
		text = '%i (%.3f GHz)' % {f.channel, f.mhz/1000},
	    }
	end
    end
    return cl
end

function get_full_txpower(hwtype)
    if hwtype == 'rt2860v2' or hwtype:starts('mt76') then
	return '100'
    else
	return '20'
    end
end

function get_ifaces_for_dev(c, dev)
    local ifaces = {}

    c:foreach('wireless', 'wifi-iface', function(i)
	if i.device == dev then
	    ifaces[#ifaces+1] = i
	end
    end)

    return ifaces
end

local i18n = require "luci.i18n"
function encryption_list(hwtype)
    local fs = require "nixio.fs"
    local el = {}
    el[#el+1] = { value = 'none', text = i18n.translate('No Encryption') }

    if hwtype == 'atheros' or hwtype == 'mac80211' or hwtype == 'prism2' then
	local hostapd = fs.access('/usr/sbin/hostapd')
	if hostapd then
	    el[#el+1] = { value = 'psk', text = i18n.translate('WPA-PSK') }
	    el[#el+1] = { value = 'psk2', text = i18n.translate('WPA2-PSK') }
	    el[#el+1] = { value = 'psk-mixed', text = i18n.translate('WPA-PSK/WPA2-PSK Mixed Mode') }
	    if has_ap_eap then
		el[#el+1] = { value = 'wpa', i18n.translate('WPA-EAP') }
		el[#el+1] = { value = 'wpa2', i18n.translate('WPA2-EAP')}
	    end
	end
    elseif hwtype == 'broadcom' or hwtype == 'rt2860v2' or hwtype:starts('mt76') then
	el[#el+1] = { value = 'psk', text = i18n.translate('WPA-PSK') }
	el[#el+1] = { value = 'psk2', text = i18n.translate('WPA2-PSK') }
	el[#el+1] = { value = 'psk+psk2', text = i18n.translate('WPA-PSK/WPA2-PSK Mixed Mode') }
    end
    return el
end

function cipher_list()
    local cl = {}
    cl[#cl+1] = { value = 'auto', text = i18n.translate('Auto') }
    cl[#cl+1] = { value = 'ccmp', text = i18n.translate('CCMP (AES)') }
    cl[#cl+1] = { value = 'tkip', text = i18n.translate('TKIP') }
    cl[#cl+1] = { value = 'tkip+ccmp', text = i18n.translate('TKIP and CCMP (AES)') }
    return cl
end

function get_encryption_desc(enc)
    local encryption, cipher, enc_desc

    if enc ~= nil then
	if enc:starts('psk+psk2') then
	    encryption = 'psk+psk2'
	    cipher = enc:sub(#encryption+2)
	else
	    encryption, cipher = string.match(enc, '(.-)+(.*)')
	    if encryption == nil then
		encryption = enc
	    end
	end
    end

    if encryption == 'psk2' then
	enc_desc = "WPA2-PSK"
    else 
	if encryption == 'psk' then
	    enc_desc = "WPA-PSK"
	else
	    if encryption == 'psk+psk2' or encryption == 'psk-mixed' then
		end_desc = "WPA-PSK/WPA2-PSK" 
	    end
	end
    end

    if not enc_desc then return i18n.translate("No Encryption") end

    if cipher == 'ccmp' then
	enc_desc = enc_desc .. ' - ' .. 'CCMP (AES)'
    else
	if cipher == 'tkip' then
	    enc_desc = enc_desc .. ' - ' .. 'TKIP'
	else
	    if cipher == 'tkip+ccmp' then 
		enc_desc = enc_desc .. ' - ' .. i18n.translate('TKIP and CCMP (AES)')
	    end
	end
    end

    return enc_desc
end

function translate_time_slots(v)
    local t = nil
    v = v:sub(2)
    v:gsub('[^,]+', function(c) 
	local sh, sm, eh, em = c:match('(%d+):(%d+)-(%d+):(%d+)')
	if not sh or not sm or not eh or not em then return end
	sh, sm, eh, em = tonumber(sh), tonumber(sm), tonumber(eh), tonumber(em)

	local s = ''
	if sh ~= 0 or sm ~= 0 or eh ~= 0 or em ~= 0 then
	    local sp = 'am'
	    if sh >= 12 then 
		sp = 'pm' 
		if sh > 12 then sh = sh - 12 end
	    end
	    if sh == 0 then sh = 12 end

	    local ep = 'am'
	    if eh >= 12 then
		ep = 'pm'
		if eh > 12 then 
		    eh = eh - 12 
		    if (eh == 12) then
			ep = 'am'
		    end
		end
	    end
	    if eh == 0 then eh = 12 end
	    s = string.format('%02d:%02d%s-%02d:%02d%s', sh, sm, sp, eh, em, ep)
	end

	t = t ~= nil and t ..'\n'.. s or s
    end)
    return t
end

function get_conf_timeslots(t)
    local v = {}
    t:gsub('[^\r\n]+', function(c)
	if not c then return end
	c = c:gsub('%s', '')
	local sh, sm, sp, eh, em, ep = c:match('(%d+):(%d+)(%a+)-(%d+):(%d+)(%a+)')
	if not sh or not sm or not eh or not em then return end
	sp = sp:lower()
	ep = ep:lower()
	if (sp ~= 'am' and sp~= 'pm') or (ep ~= 'am' and ep ~= 'pm') then return end

	sh, sm, eh, em = tonumber(sh), tonumber(sm), tonumber(eh), tonumber(em)
	if sp == 'am' and sh == 12 then
	    sh = 0
	end

	if sp == 'pm' and sh ~= 12 then
	    sh = sh + 12
	end

	if ep == 'am' and eh == 12 then
	    eh = em == 0 and 24 or 0
	end

	if ep == 'pm' and eh ~= 12 then
	    eh = eh + 12
	end

	v[#v+1] = string.format('%02d:%02d-%02d:%02d', sh, sm, eh, em)
    end)

    return #v == 0 and '00:00-00:00' or table.concat(v, ',')
end

function load_vpn_users()
    local vpn_users = {}

    -- load openvpn users
    local f, pf, s
    local ccd = '/etc/openvpn/ccd'
    local fs = require "nixio.fs"

    local dir = fs.dir(ccd)
    if dir then
	for f in dir do
	    pf = io.open(ccd .. '/' .. f, 'r')
	    if pf then
		s = pf:read('*all')
		pf:close()
		s = s:split(' ')
		if #s == 3 and s[1] == 'ifconfig-push' then
		    vpn_users[#vpn_users+1] = {
			name = f,
			ip = s[2],
		    }
		end
	    end
	end
    end

    local uci = require "luci.pcuci"
    local c = uci.cursor()

    -- load ipsec users
    c:foreach('ipsec', 'user', function(u)
	vpn_users[#vpn_users+1] = {
	    name = u.name,
	    ip = u.ip,
	}
    end)

    -- load WireGuard users
    c:foreach('wg', 'peer', function(u)
	vpn_users[#vpn_users+1] = {
	    name = u.name,
	    ip = u.ip,
	}
    end)

    return vpn_users
end

function fork_exec(command)
	local pid = nixio.fork()
	if pid > 0 then
		return pid
	elseif pid == 0 then
		-- change to root dir
		nixio.chdir("/")

		-- patch stdin, out, err to /dev/null
		local null = nixio.open("/dev/null", "w+")
		if null then
			nixio.dup(null, nixio.stderr)
			nixio.dup(null, nixio.stdout)
			nixio.dup(null, nixio.stdin)
			if null:fileno() > 2 then
				null:close()
			end
		end

		-- replace with target command
		nixio.exec("/bin/sh", "-c", command)
	end
end

function fork_exec_wait(command)
	local pid = nixio.fork()
	if pid > 0 then
		local wpid, stat, rc = nixio.waitpid(pid)
		return rc
	elseif pid == 0 then
		-- change to root dir
		nixio.chdir("/")

		-- patch stdin, out, err to /dev/null
		local null = nixio.open("/dev/null", "w+")
		if null then
			nixio.dup(null, nixio.stderr)
			nixio.dup(null, nixio.stdout)
			nixio.dup(null, nixio.stdin)
			if null:fileno() > 2 then
				null:close()
			end
		end

		-- replace with target command
		nixio.exec("/bin/sh", "-c", command)
	end
end

function popen2(command)
    local r1, w1 = nixio.pipe()
    local r2, w2 = nixio.pipe()

    assert(w1 ~= nil and r2 ~= nil, "pipe() failed")

    pid = nixio.fork()
    assert(pid ~= nil, "fork() failed")

    if pid > 0 then
	r1:close()
	w2:close()
	return w1, r2
    elseif pid == 0 then
	w1:close()
	r2:close()
	nixio.dup(r1, nixio.stdin)
	nixio.dup(w2, nixio.stdout)
	r1:close()
	w2:close()
	nixio.exec("/bin/sh", "-c", command)
    end
end

function ip_in_network(ip, addr, mask)
    if type(ip) == 'string' then
	ip = ip:split('.')
    end

    if #ip ~= 4 then return false end

    if type(addr) == 'string' and type(mask) == 'string' then
	addr = addr:split('.')
	mask = mask:split('.')
    end

    if type(addr) ~= 'table' or #addr ~= 4 or type(mask) ~= 'table' or #mask ~= 4 then
	return false
    end

    require "nixio"
    local bit = nixio.bit

    return 
	bit.band(addr[1], mask[1]) == bit.band(ip[1], mask[1]) and 
	bit.band(addr[2], mask[2]) == bit.band(ip[2], mask[2]) and 
	bit.band(addr[3], mask[3]) == bit.band(ip[3], mask[3]) and 
	bit.band(addr[4], mask[4]) == bit.band(ip[4], mask[4])
end

function get_network_for_ip(c, ip)
    if type(ip) == 'string' then
	ip = ip:split('.')
    end

    if type(ip) ~= 'table' or #ip ~= 4 then
	return false
    end

    if c == nil then
	c = get_uci_cursor()
    end

    local net = nil
    local network = 'network'
    for _, n in ipairs(get_vlan_list()) do
	local addr = c:get(network, n.name, 'ipaddr')
	local mask = c:get(network, n.name, 'netmask')
	if ip_in_network(ip, addr, mask) then
	    net = n
	    break
	end
    end
    return net
end

function fix_ip(ipaddr, netaddr1, netmask1, netaddr2, netmask2)
    local dt = require "luci.cbi.datatypes"
    if not dt.ip4addr(ipaddr) or not dt.ip4addr(netaddr1) or not dt.ip4addr(netmask1) or not dt.ip4addr(netaddr2) or not dt.ip4addr(netmask2) then
	return nil
    end

    require "nixio"
    local bit = nixio.bit

    local ip = ipaddr:split('.')
    local netip1 = netaddr1:split('.')
    local netmk1 = netmask1:split('.')
    local netip2 = netaddr2:split('.')
    local netmk2 = netmask2:split('.')

    for i=1,4 do netip1[i] = bit.band(netip1[i], netmk1[i]) end
    for i=1,4 do netip2[i] = bit.band(netip2[i], netmk2[i]) end
    for i=1,4 do ip[i] = bit.bxor(ip[i], netip1[i]) end
    for i=1,4 do ip[i] = bit.bxor(ip[i], netip2[i]) end

    return table.concat(ip, '.')
end

local user_ip_start = 100
local user_ip_max = 255
function get_next_ip(netaddr, netmask, usedips)
    local dt = require "luci.cbi.datatypes"
    if not dt.ip4addr(netaddr) or not dt.ip4addr(netmask) then
	return nil
    end

    local netip = netaddr:split('.')
    local netmk = netmask:split('.')

    require "nixio"
    local bit = nixio.bit
    for i=1,4 do netip[i] = bit.band(netip[i], netmk[i]) end

    local newip = { netip[1], netip[2], netip[3], netip[4] }
    for n = user_ip_start, user_ip_max do
	newip[4] = bit.bor(netip[4], n)
	if not string_in_array(table.concat(newip, '.'), usedips) then
	    return table.concat(newip, '.')
	end
    end

    return nil
end

function get_new_ip(lanip, netmask, ip)
    if type(lanip) ~= 'string' or type(netmask) ~= 'string' or type(ip) ~= 'string' then 
       return nil
    end

    local dt = require "luci.cbi.datatypes"
    if not dt.ip4addr(lanip) or not dt.ip4addr(netmask) or not dt.ip4addr(ip) then
       return nil
    end

    local lanips = lanip:split('.')
    local masks = netmask:split('.')
    local ips = ip:split('.')

    require "nixio"
    local bit = nixio.bit
    local newip = { bit.band(lanips[1], masks[1]), bit.band(lanips[2], masks[2]), bit.band(lanips[3], masks[3]), bit.band(lanips[4], masks[4]) }
    local ipmasks = { 255, 255, 255, 255 }
    for i = 1, 4 do
       ipmasks[i] = bit.band(bit.bxor(ipmasks[i], masks[i]), ips[i])
    end

    for i = 1, 4 do
       newip[i] = newip[i] + ipmasks[i]
    end

    return table.concat(newip, '.')
end

local vlan_options = {
    { name = 'lan', id = '1', text = 'LAN' },
    { name = 'guest', id = '3', text = 'Guest', ip = '10.159.157.1', mask = '255.255.255.0' },
    { name = 'x1', id = '4', text = 'X1', ip = '10.159.158.1', mask = '255.255.255.0' },
    { name = 'x2', id = '5', text = 'X2', ip = '10.159.159.1', mask = '255.255.255.0' },
    { name = 'x3', id = '6', text = 'X3', ip = '10.159.160.1', mask = '255.255.255.0' },
}

local function get_vlan_forwarding(c, vidx, m)
    local from = {}
    local to = {}
    local network_cfg = 'network'

    if vidx < 1 or vidx > 5 then
	return from, to
    end

    if not m then
	local map = c:get(network_cfg, 'vlanctrl', 'map')
	if map then m = map:split(',') end
	if not m or #m ~= 25 then
	    m = string.split('1,1,1,1,1,0,1,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,1', ',')
	end
    end

    j = 0
    for i = vidx, #m, 5 do
	j = j + 1
	if m[i] == '1' and j ~= vidx then from[#from+1] = j end
    end

    j = 0
    for i = (vidx - 1)*5 + 1, vidx*5 do
	j = j + 1
	if m[i] == '1' and j ~= vidx then to[#to+1] = j end
    end

    return from, to
end

function get_vlan_list()
    return vlan_options
end

function get_vlan_options()
    local options = {}
    for _, v in ipairs(vlan_options) do
	options[#options+1] = {
	    value = v.id,
	    text = v.text,
	}
    end
    return options
end

function get_vlan_params(c, name, lanip)
    require "nixio"
    local bit = nixio.bit
    local network = 'network'

    if lanip then
	lanip = lanip:split('.')
    else
	lanip = c:get(network, 'lan', 'ipaddr'):split('.')
    end

    for i, v in ipairs(vlan_options) do
	if name == v.name then
	    local ip = nil
	    if v.ip then
		ip = v.ip:split('.')
		ip[2] = bit.bxor(bit.bxor(ip[2], 168), lanip[2])
		ip[3] = bit.bxor(bit.bxor(ip[3], 10), lanip[3])
	    end

	    return {
		name = v.name,
		id = v.id,
		text = v.text,
		ip = ip and table.concat(ip, '.') or nil,
		mask = v.mask,
	    }, i
	end
    end
    return nil
end

function get_vlan_ifaces(c)
    require "luci.ip"

    local network = 'network'
    local ifaces = {}
    c:foreach(network, 'interface', function(v)
	if string_in_array(v['.name'], get_vlan_list(), function(i) return i.name end) then
	    ifaces[#ifaces + 1] = {
		name = v['.name'],
		ipaddr = v.ipaddr,
		netmask = v.netmask,
		network = luci.ip.IPv4(v.ipaddr, v.netmask):network(),
	    }
	end
    end)
    return ifaces
end

function get_vlan_display_name(name)
    for _, v in ipairs(vlan_options) do
	if v.name == name then
	    return v.text
	end
    end
    return nil
end

function get_vlan_network_name(vlan_id)
    for _, v in ipairs(vlan_options) do
	if v.id == vlan_id then
	    return v.name
	end
    end
    return nil
end

function get_lanif_base()
    local ifbase = "eth0"
    local ifname = get_lan_ifname()
    if ifname then
	ifbase = string.match(ifname, '([^.]*)%.?%d?')
    end

    return ifbase
end

local function find_vlan_interface_name(c, ifname)
    local network = 'network'
    local nw_name = nil
    local w, p
    c:foreach(network, 'interface', function(i)
	if i.ifname then
	    for w in i.ifname:gmatch("([^%s][^%s]*)") do
		if w == ifname then
		    nw_name = i['.name']
		    return false
		end
	    end
	elseif i.device then
	    c:foreach(network, 'device', function(d)
		if d.name == i.device then
		    if type(d.ports) == 'table' then
			for _, p in ipairs(d.ports) do
			    if p == ifname then
				nw_name = i['.name']
				return false
			    end
			end
		    elseif d.ports == ifname then
			nw_name = i['.name']
		    end
		end
		if nw_name then return false end
	    end)
	else
	    return true
	end
    end)
    return nw_name
end

function get_canonical_vlan_id(c, eid)
    local network = 'network'
    local vifname = nil
    c:foreach(network, 'bridge-vlan', function(s)
	if s.device == 'br-lan' and s.vlan == eid then
	    c:foreach(network, 'interface', function(i)
		if i.device == 'br-lan.'..eid then
		    vifname = i['.name']
		    return false
		end
	    end)
	    return false
	end
    end)

    if not vifname then
	local ifbase = get_lanif_base()
	vifname = find_vlan_interface_name(c, ifbase .. '.' .. eid)
	if vifname == nil then
	    vifname = find_vlan_interface_name(c, ifbase)
	end
    end

    if not vifname then
	return nil
    end

    local p = get_vlan_params(c, vifname)
    return p ~= nil and p.id or nil
end

local function get_network_ifname(net)
    require "nixio.fs"
    local jsonc = require "luci.jsonc"

    local ifname = nil
    local b = jsonc.parse(nixio.fs.readfile("/etc/board.json"))

    if b and b.switch and b.switch.switch0 and b.switch.switch0.roles then
	for _, role in ipairs(b.switch.switch0.roles) do
	    if role.role == net then
		ifname = role.device
		break
	    end
	end
    end

    return ifname
end

function get_lan_ifname()
    local ifname = get_network_ifname('lan')
    return ifname and ifname or 'eth0.1'
end

function get_wan_ifname()
    local ifname = get_network_ifname('wan')
    return ifname and ifname or 'eth0.2'
end

function get_board_wan_ports()
    require "nixio.fs"
    local jsonc = require "luci.jsonc"

    local ports = {'4', '6t'}
    local device = 'eth0.2'
    local b = jsonc.parse(nixio.fs.readfile("/etc/board.json"))

    if b then
	if b.switch and b.switch.switch0 and b.switch.switch0.roles then
	    for _, role in ipairs(b.switch.switch0.roles) do
		if role.role == 'wan' then
		    ports = role.ports:split(' ')
		    device = role.device
		end
	    end
	elseif b.network and b.network.wan then
	    device = b.network.wan.device
	    ports = b.network.wan.ports
	    if not ports then ports = { device } end
	end
    end

    return ports, device
end

function get_wan_vlan_id_tag(c)
    local network = 'network'
    local ports = get_board_wan_ports()

    local vlantag = nil
    local vlanid = '2'
    if c:get_first(network, 'switch_vlan') then
	c:foreach(network, 'switch_vlan', function(v)
	    local vps = v.ports:split(' ')
	    if #vps == #ports then
		local found = true
		for i = 1, #vps do
		    if vps[i]:sub(1,1) ~= ports[i]:sub(1,1) then
			found = false
			break
		    end
		end

		if found then
		    vlanid = v.vlan
		    ports = vps
		    return false
		end
	    end
	end)

	if #ports > 0 and ports[1]:ends('t') then
	    vlantag = '1'
	end
    else
	c:foreach(network, 'bridge-vlan', function(s)
	    if s.device == 'br-wan' then
		vlanid = s.vlan
		if #s.ports > 0 and s.ports[1]:ends(':t') then
		    vlantag = '1'
		end
		return false
	    end
	end)
    end

    return vlanid, vlantag
end

function get_lan_mac()
    local mac
    local f = io.popen('[ -s /sys/class/net/br-lan/address ] && cat /sys/class/net/br-lan/address', 'r')
    if f then
	mac = f:read()
	f:close()
    end

    if #mac == 17 then
	return mac:upper()
    end

    local nw = require "luci.model.network"
    local ntm = nw.init()
    local nets = ntm:get_networks()
    for _, net in ipairs(nets) do
	if net.sid == 'lan' then
	    mac = net:get_interface():mac()
    	    break
	end
    end
    return mac ~= nil and mac:upper() or nil
end

function get_ipset_sectionname_by_name(c, name)
    local firewall = 'firewall'
    local sname = nil
    c:foreach(firewall, 'ipset', function(s)
	if s.name == name then
	    sname = s['.name']
	    return false
	end
    end)
    return sname
end

function update_vpn_guest_fw_rule(c, guests, vpnip, vpnmask)
    local firewall = 'firewall'
    local ipset = get_ipset_sectionname_by_name(c, 'vpnguest')
    if not ipset then
	ipset = c:section(firewall, 'ipset')
	c:set(firewall, ipset, 'enabled', '1')
	c:set(firewall, ipset, 'name', 'vpnguest')
	c:set(firewall, ipset, 'storage', 'hash')
	c:set(firewall, ipset, 'match', 'src_ip')
    end

    local ips = c:get_list(firewall, ipset, 'entry')
    local newips = {}
    for _, ip in ipairs(ips) do
	if not ip_in_network(ip:split('.'), vpnip, vpnmask) then
	    newips[#newips + 1] = ip
	end
    end

    for _, ip in ipairs(guests) do
	newips[#newips + 1] = ip
    end

    if #newips > 0 then c:set_list(firewall, ipset, 'entry', newips) else c:delete_all(firewall, ipset, 'entry') end
end

function update_firewall_lan_ipset(c, ip, is_add)
    local network = 'network'
    local firewall = 'firewall'
    local ipset = get_ipset_sectionname_by_name(c, 'lanips')
    if not ipset then
	ipset = c:section(firewall, 'ipset')
	c:set(firewall, ipset, 'enabled', '1')
	c:set(firewall, ipset, 'name', 'lanips')
	c:set(firewall, ipset, 'storage', 'hash')
	c:set(firewall, ipset, 'match', 'dest_ip')
    end

    local ips = {}
    c:foreach(firewall, 'zone', function(z)
	if z.name ~= 'wan' then
	    local ipaddr = c:get(network, z.name, 'ipaddr')
	    if ipaddr and ipaddr ~= '127.0.0.1' and ipaddr ~= ip then
		ips[#ips+1] = ipaddr
	    end
	end
    end)

    if is_add and ip then ips[#ips+1] = ip end
    c:set_list(firewall, ipset, 'entry', ips)
end

local function update_firewall_forwarding_for_vlan(c, vidx, m)
    local firewall = 'firewall'

    local zones = {}
    c:foreach(firewall, 'zone', function(z)
	zones[#zones+1] = z.name
    end)

    if not string_in_array(vlan_options[vidx].name, zones) then
	return
    end

    local vlans = {}
    for _, v in ipairs(vlan_options) do
	vlans[#vlans+1] = v.name
    end

    local from, to = get_vlan_forwarding(c, vidx, m)
    local p = vlan_options[vidx]
    local fw_delete = {}
    c:foreach(firewall, 'forwarding', function(f)
	if (f.src == p.name and string_in_array(f.dest, vlans)) or f.dest == p.name then
	    fw_delete[#fw_delete+1] = f['.name']
	end
    end)

    c:foreach(firewall, 'rule', function(r)
	if r.src == p.name and r.ipset == 'lanips' then
	    fw_delete[#fw_delete+1] = r['.name']
	end
    end)

    for _, d in ipairs(fw_delete) do
	c:delete(firewall, d)
    end

    for _, idx in ipairs(from) do
	local from_vlan_name = vlan_options[idx].name
	if string_in_array(from_vlan_name, zones) then
	    local forwarding = c:section(firewall, 'forwarding')
	    c:set(firewall, forwarding, 'src', from_vlan_name)
	    c:set(firewall, forwarding, 'dest', p.name)

	    if from_vlan_name == 'lan' then
		local z
		local vpn_zones = {}
		c:foreach(firewall, 'zone', function(z)
		    if z.name == 'vpn' then
			if c:get('openvpn', '@server[0]', 'enabled') ~= '0' then
			    vpn_zones[#vpn_zones+1] = z
			end
		    elseif z.name == 'wg' then
			if c:get('wg', '@server[0]', 'enabled') ~= '0' then
			    vpn_zones[#vpn_zones+1] = z
			end
		    end
		end)

		for _, z in ipairs(vpn_zones) do
		    forwarding = c:section(firewall, 'forwarding')
		    c:set(firewall, forwarding, 'src', z.name)
		    c:set(firewall, forwarding, 'dest', p.name)
		end
	    end
	end
    end

    local lan_allowed = false
    for _, idx in ipairs(to) do
	local to_vlan_name = vlan_options[idx].name
	if string_in_array(to_vlan_name, zones) then
	    if to_vlan_name == 'lan' then lan_allowed = true end
	    local forwarding = c:section(firewall, 'forwarding')
	    c:set(firewall, forwarding, 'src', p.name)
	    c:set(firewall, forwarding, 'dest', to_vlan_name)
	end
    end

    if p.name ~= 'lan' and not lan_allowed then
	rule = c:section(firewall, 'rule')
	c:set(firewall, rule, 'src', p.name)
	c:set(firewall, rule, 'proto', 'all')
	c:set(firewall, rule, 'family', 'ipv4')
	c:set(firewall, rule, 'ipset', 'lanips')
	c:set(firewall, rule, 'target', 'REJECT')
    end
end

function update_vlanmap(c, vlanmap)
    local network_cfg = 'network'
    local valid = vlanmap and #vlanmap == 25 or false
    if valid then
	for _, v in ipairs(vlanmap) do
	    if v ~= '0' and v ~= '1' then
		valid = false
		break
	    end
	end
    end

    if not valid then return false end

    local isolate = {}
    local j = 0
    for i = 1, 25, 6 do
	j = j + 1
	if vlanmap[i] == '0' then
	    isolate[#isolate + 1] = vlan_options[j].name
	end
    end

    if table.concat(vlanmap, ',') == c:get(network_cfg, 'vlanctrl', 'map') then return false end

    if not c:get(network_cfg, 'vlanctrl') then c:section(network_cfg, 'vlanctrl', 'vlanctrl') end
    c:set(network_cfg, 'vlanctrl', 'map', table.concat(vlanmap, ','))
    c:set(network_cfg, 'vlanctrl', 'isolate', table.concat(isolate, ' '))

    for k = 1, 5 do
	update_firewall_forwarding_for_vlan(c, k, vlanmap)
    end

    return true
end

local function is_switched_vlan(c, ncfg)
    return c:get_first(ncfg, 'switch_vlan') ~= nil
end

local function is_bridged_lan_device(c, ncfg)
    local landev = c:get(ncfg, 'lan', 'device')
    return landev and landev:starts('br-lan')
end

function rename_vlan(c, vlanid)
    local network_cfg = 'network'

    local ifname, new_vlanid, vlan2mv
    if is_switched_vlan(c, network_cfg) then
	local used_vlan_ids = {}
	c:foreach(network_cfg, 'switch_vlan', function(v)
	    used_vlan_ids[#used_vlan_ids+1] = v.vlan
	    if v.vlan == vlanid then
		vlan2mv = v['.name']
	    end
	end)

	if vlan2mv then
	    if vlanid == '7' then
		for i = 3, 6 do
		    new_vlanid = tostring(i)
		    if not string_in_array(new_vlanid, used_vlan_ids) then
			break
		    end
		end
	    else
		new_vlanid = '7'
	    end

	    c:set(network_cfg, vlan2mv, 'vlan', new_vlanid)

	    ifname = get_lanif_base()..'.'..vlanid
	    if is_bridged_lan_device(c, network_cfg) then
		c:foreach(network_cfg, 'device', function(d)
		    if type(d.ports) == 'table' then
			local update = false
			local ports = {}
			for _, p in ipairs(d.ports) do
			    if p ~= ifname then
				ports[#ports+1] = p
			    else
				ports[#ports+1] = get_lanif_base()..'.'..new_vlanid
				update = true
			    end
			end

			if update then
			    c:set_list(network_cfg, d['.name'], 'ports', ports)
			    return false
			end
		    end
		end)
	    else
		c:foreach(network_cfg, 'interface', function(i)
		    if i.ifname == ifname then
			c:set(network_cfg, i['.name'], 'ifname', get_lanif_base()..'.'..new_vlanid)
			return false
		    end
		end)
	    end
	end
    else
	local used_vlan_ids = {}
	c:foreach(network_cfg, 'bridge-vlan', function(v)
	    if v.device == 'br-lan' then
		used_vlan_ids[#used_vlan_ids+1] = v.vlan
		if v.vlan == vlanid then
		    vlan2mv = v['.name']
		end
	    end
	end)

	if vlan2mv then
	    if vlanid == '7' then
		for i = 3, 6 do
		    new_vlanid = tostring(i)
		    if not string_in_array(new_vlanid, used_vlan_ids) then
			break
		    end
		end
	    else
		new_vlanid = '7'
	    end

	    c:set(network_cfg, vlan2mv, 'vlan', new_vlanid)

	    ifname = 'br-lan.'..vlanid
	    c:foreach(network_cfg, 'interface', function(i)
		if i.device == ifname then
		    c:set(network_cfg, i['.name'], 'br-lan.'..new_vlanid)
		end
	    end)
	end
    end
end

function add_ifname_to_network(c, nw, ifname)
    local network_cfg = 'network'

    if not is_switched_vlan(c, network_cfg) then return end

    if is_bridged_lan_device(c, network_cfg) then -- LAN with a bridge device
	c:foreach(network_cfg, 'device', function(s)
	    if s.name == 'br-'..nw then
		c:set_list(network_cfg, s['.name'], 'ports', {ifname})
		return false
	    end
	end)
    else
	c:set(network_cfg, nw, 'ifname', ifname)
    end
end

function delete_ifname_from_network(c, nw)
    local network_cfg = 'network'

    if not is_switched_vlan(c, network_cfg) then return end

    if is_bridged_lan_device(c, network_cfg) then
	c:foreach(network_cfg, 'device', function(s)
	    if s.name == 'br-'..nw then
		c:delete(network_cfg, s['.name'], 'ports')
		return false
	    end
	end)
    else
	c:delete(network_cfg, nw, 'ifname')
    end
end

function create_vlan_network(c, nw_name, cfgs)
    local network_cfg = 'network'

    local p, vidx = get_vlan_params(c, nw_name)
    if p == nil then return end

    -- network config
    local iface = nil
    c:foreach(network_cfg, 'interface', function(i)
	if i['.name'] == p.name then
	    iface = i
	    return false
	end
    end)

    if iface ~= nil then
	if c:get(network_cfg, p.name, 'ipaddr') ~= p.ip then
	    c:set(network_cfg, p.name, 'ipaddr', p.ip)
	    update_firewall_lan_ipset(c, p.ip, true)
	    add_if_not_exists(cfgs, 'network')
	end
    end

    c:section(network_cfg, 'interface', p.name)
    c:set(network_cfg, p.name, 'proto', 'static')
    c:set(network_cfg, p.name, 'ipaddr', p.ip)
    c:set(network_cfg, p.name, 'netmask', p.mask)
    c:set(network_cfg, p.name, 'macaddr', get_lan_mac())

    if is_switched_vlan(c, network_cfg) and is_bridged_lan_device(c, network_cfg) then
	local d = nil
	c:foreach(network_cfg, 'device', function(s)
	    if s.name == 'br-'..p.name then
		d = s['.name']
		return false
	    end
	end)
	if not d then
	    d = c:section(network_cfg, 'device')
	    c:set(network_cfg, d, 'name', 'br-'..p.name)
	    c:set(network_cfg, d, 'type', 'bridge')
	end
	c:set(network_cfg, p.name, 'device', 'br-'..p.name)
    elseif not c:get(network_cfg, p.name, 'device') then
	c:set(network_cfg, p.name, 'type', 'bridge')
    end

    add_if_not_exists(cfgs, 'network')

    local dhcp = 'dhcp'
    c:section(dhcp, 'dhcp', p.name)
    c:set(dhcp, p.name, 'interface', p.name)
    c:set(dhcp, p.name, 'start', 50)
    c:set(dhcp, p.name, 'limit', 200)
    c:set(dhcp, p.name, 'leasetime', '2h')
    c:set(dhcp, p.name, 'ra', 'disabled')
    c:set(dhcp, p.name, 'dhcpv6', 'disabled')
    c:set_list(dhcp, p.name, 'dhcp_option', '6,'..c:get(network_cfg, 'lan', 'ipaddr'))

    add_if_not_exists(cfgs, dhcp)

    update_firewall_lan_ipset(c, p.ip, true)

    local firewall = 'firewall'
    local gzone = c:section(firewall, 'zone')
    c:set(firewall, gzone, 'name', p.name)
    c:set(firewall, gzone, 'network', p.name)
    c:set(firewall, gzone, 'input', 'ACCEPT')
    c:set(firewall, gzone, 'forward', 'REJECT')
    c:set(firewall, gzone, 'output', 'ACCEPT')

    local forwarding = c:section(firewall, 'forwarding')
    c:set(firewall, forwarding, 'src', p.name)

    local vpnc_ifaces = {}
    for _, iface in ipairs(get_vpn_ifaces(c, 'openvpn')) do
	vpnc_ifaces[iface] = 'vpnc'
    end
    for _, iface in ipairs(get_vpn_ifaces(c, 'wg')) do
	vpnc_ifaces[iface] = 'wgc'
    end

    if vpnc_ifaces[p.name] then
	c:set(firewall, forwarding, 'dest', vpnc_ifaces[p.name])
    else
	c:set(firewall, forwarding, 'dest', 'wan')
    end

    local rule = c:section(firewall, 'rule')
    c:set(firewall, rule, 'src', p.name)
    c:set(firewall, rule, 'proto', 'tcpudp')
    c:set(firewall, rule, 'dest_port', '53')
    c:set(firewall, rule, 'target', 'ACCEPT')

    -- UDP port 1900 & TCP port 5000 needed by UPnP
    -- We allow UPnP on Guest and X networks
    rule = c:section(firewall, 'rule')
    c:set(firewall, rule, 'src', p.name)
    c:set(firewall, rule, 'proto', 'udp')
    c:set(firewall, rule, 'dest_port', '67 68 1900')
    c:set(firewall, rule, 'target', 'ACCEPT')

    rule = c:section(firewall, 'rule')
    c:set(firewall, rule, 'src', p.name)
    c:set(firewall, rule, 'proto', 'tcp')
    c:set(firewall, rule, 'dest_port', '80 443 5000')
    c:set(firewall, rule, 'target', 'ACCEPT')

    rule = c:section(firewall, 'rule')
    c:set(firewall, rule, 'src', p.name)
    c:set(firewall, rule, 'proto', 'icmp')
    c:set(firewall, rule, 'icmp_type', 'echo-request')
    c:set(firewall, rule, 'family', 'ipv4')
    c:set(firewall, rule, 'target', 'ACCEPT')

    update_firewall_forwarding_for_vlan(c, vidx)

    add_if_not_exists(cfgs, firewall)
end

function delete_vlan_network(c, nw_name, wifi, cfgs)
    local network_cfg = 'network'
    local wireless_cfg = 'wireless'

    local p = get_vlan_params(c, nw_name)
    if p == nil then return true, false end

    -- network config
    local iface = nil
    c:foreach(network_cfg, 'interface', function(i)
	if i['.name'] == p.name then
	    iface = i
	    return false
	end
    end)

    if iface == nil then
	return true, false
    end

    local gnet = nil
    if not wifi then -- vlan delete
	c:foreach(wireless_cfg, 'wifi-iface', function(w)
	    if w.network == p.name then
		gnet = w['.name']
		return false
	    end
	end)
    else -- wireless vlan delete
	c:foreach(network_cfg, 'interface', function(v)
	    if v['.name'] == nw_name then
		if is_switched_vlan(c, network_cfg) and is_bridged_lan_device(c, network_cfg) then
		    c:foreach(network_cfg, 'device', function(d)
			if d.name == 'br-'..p.name and d.ports then
			    for _, p in ipairs(d.ports) do
				if p ~= get_lanif_base() then
				    gnet = v['.name']
				    return false
				end
			    end
			    return false
			end
		    end)
		else
		    if v.ifname or v.device then gnet = v['.name'] end
		end
		return false
	    end
	end)
    end

    if gnet ~= nil then	return false end

    local hosts_updated = false
    local firewall = 'firewall'
    local dhcp = 'dhcp'
    local fw_delete = {}

    if wifi then -- For network VLAN update, DHCP & redirect are handled in network controller
    	local dhcp_delete = {}
	local new_hosts = {}
	c:foreach(dhcp, 'host', function(d)
	    local net = get_network_for_ip(c, d.ip)
	    if not net or net.name == p.name then
	    	dhcp_delete[#dhcp_delete + 1] = d['.name']
	    else
	    	new_hosts[#new_hosts+1] = d
	    end
	end)

	if #dhcp_delete > 0 then
	    for _, host_entry in ipairs(dhcp_delete) do
	    	c:delete(dhcp, host_entry)
	    end
	    hosts_updated = new_hosts
	end

	c:foreach(firewall, 'redirect', function(r)
	    if r.dest == p.name then
	    	fw_delete[#fw_delete+1] = r['.name']
	    end
	end)
    end

    c:delete(dhcp, p.name)
    add_if_not_exists(cfgs, dhcp)

    c:foreach(firewall, 'zone', function(z)
    	if z.network == p.name then
    	    fw_delete[#fw_delete+1] = z['.name']
    	end
    end)

    c:foreach(firewall, 'forwarding', function(f)
    	if f.src == p.name or f.dest == p.name then
    	    fw_delete[#fw_delete+1] = f['.name']
    	end
    end)

    c:foreach(firewall, 'rule', function(r)
    	if r.src == p.name or r.dest == p.name then
    	    fw_delete[#fw_delete+1] = r['.name']
    	end
    end)

    for _, d in ipairs(fw_delete) do
	c:delete(firewall, d)
    end

    update_firewall_lan_ipset(c, p.ip, false)

    add_if_not_exists(cfgs, firewall)

    c:delete(network_cfg, p.name)
    if is_switched_vlan(c, network_cfg) and is_bridged_lan_device(c, network_cfg) then
	local todel
	c:foreach(network_cfg, 'device', function(d)
	    if d.name == 'br-'..p.name then
		todel = d['.name']
		return false
	    end
	end)

	if todel then c:delete(network_cfg, todel) end
    end
    add_if_not_exists(cfgs, 'network')

    local upnpd = 'upnpd'
    local upnp_enabled = is_upnpd_enabled(c)
    local upnpd_ifaces = c:get(upnpd, 'config', 'internal_iface')
    if upnpd_ifaces ~= nil then
    	local ifaces = {}
    	upnpd_ifaces = upnpd_ifaces:split(' ')
    	for _, iface in ipairs(upnpd_ifaces) do
    	    if iface ~= p.name then
    		ifaces[#ifaces+1] = iface
    	    end
    	end

    	if #upnpd_ifaces ~= #ifaces then
    	    if #ifaces > 0 then
    		c:set(upnpd, 'config', 'internal_iface', table.concat(ifaces, ' '))
    	    else
    		if upnp_enabled then
    		    require "luci.sys"
    		    luci.sys.init.stop('miniupnpd')
    		    luci.sys.init.disable('miniupnpd')
    		end
    	    end

    	    if upnp_enabled then
    		add_if_not_exists(cfgs, upnpd)
    	    end
    	end
    end

    return gnet == nil, hosts_updated
end

function is_upnpd_enabled(c)
    local fs = require "nixio.fs"
    if not fs.access("/etc/init.d/miniupnpd") then
	return false
    end

    require "luci.sys"
    return luci.sys.init.enabled('miniupnpd') and c:get('upnpd', 'config', 'enabled') ~= '0'
end

function get_internal_interfaces(c)
    local network = 'network'
    local internal_ifs = {}
    for _, v in ipairs(vlan_options) do
	c:foreach(network, 'interface', function(i)
	    if i['.name'] == v.name then
	    	internal_ifs[#internal_ifs+1] = {
		    name = v.name,
		    text = v.text,
	        }
		return false
	    end
	end)
    end
    return internal_ifs
end

function get_vpn_ifaces(c, vpn_name)
    local vpn_ifaces = 'vpn-ifaces'
    local ifaces = {}
    c:foreach(vpn_ifaces, 'vpn-iface', function(s)
	if s.vpn == vpn_name then
	    ifaces[#ifaces+1] = s.iface
	end
    end)
    return ifaces
end

function set_vpn_ifaces(c, vpn_name, ifaces, cfgs)
    local vpn_ifaces = 'vpn-ifaces'
    local vpnifcs = {}
    c:foreach(vpn_ifaces, 'vpn-iface', function(s)
	if s.vpn == vpn_name then
	    if not remove_string_from_array(ifaces, s.iface) then
		vpnifcs[#vpnifcs + 1] = s['.name']
	    end
	elseif string_in_array(s.iface, ifaces) then
	    vpnifcs[#vpnifcs + 1] = s['.name']
	end
    end)

    if #vpnifcs > 0 then
	for _, ifc in ipairs(vpnifcs) do
	    c:delete(vpn_ifaces, ifc)
	end
	add_if_not_exists(cfgs, 'firewall')
    end

    if ifaces ~= nil and #ifaces > 0 then
	for _, iface in ipairs(ifaces) do
	    local s = c:section(vpn_ifaces, 'vpn-iface')
	    c:set(vpn_ifaces, s, 'vpn', vpn_name)
	    c:set(vpn_ifaces, s, 'iface', iface)
	end
	add_if_not_exists(cfgs, 'firewall')
    end

    local success = c:commit(vpn_ifaces)
    if success then
	local updatefw = false
	local dels = {}
	c:foreach('firewall', 'redirect', function(s)
	    if s.target == 'DNAT' and
		string_in_array(s.src, {'wan','wgc','vpnc'}) and
		(s.enabled == nil or s.enabled == '1') then
		local net = get_network_for_ip(c, s.dest_ip)
		if net then
		    local wan = 'wan'
		    c:foreach('vpn-ifaces', 'vpn-iface', function(s2)
			if s2.iface == net.name then
			    if s2.vpn == 'openvpn' then
				wan = 'vpnc'
			    elseif s2.vpn == 'wg' then
				wan = 'wgc'
			    end
			    return false
			end
		    end)

		    if wan ~= s.src then
			updatefw = true
			c:set('firewall', s['.name'], 'src', wan)
		    end
		else
		    dels[#dels+1] = s['.name']
		end
	    end
	end)

	if #dels > 0 then
	    for _, del in ipairs(dels) do
		c:delete('firewall', del)
	    end
	end

	if updatefw or #dels > 0 then
	    success = c:commit('firewall')
	end
    end

    return success
end

function update_firewall_rules_for_vpns(c, vpn_name, ilist)
    local vpn_zone
    local fwd
    local firewall = 'firewall'

    local fwsecs = { 'forwarding', 'rule' }
    for _, sec in ipairs(fwsecs) do
	local dels = {}
	c:foreach(firewall, sec, function(s)
	    if s.src == vpn_name then
		dels[#dels+1] = s['.name']
	    end
	end)

	for _, del in ipairs(dels) do
	    c:delete(firewall, del)
	end
    end

    c:foreach(firewall, 'zone', function(z)
	if z.name == vpn_name then
	    vpn_zone = z['.name']
	    return false
	end
    end)

    if ilist ~= nil then
	if not vpn_zone then
	    vpn_zone = c:section(firewall, 'zone')
	    c:set(firewall, vpn_zone, 'name', vpn_name)
	    c:set_list(firewall, vpn_zone, 'network', vpn_name)
	    c:set(firewall, vpn_zone, 'output', 'ACCEPT')
	    c:set(firewall, vpn_zone, 'forward', 'REJECT')
	end

	local input_rule = 'REJECT'
	if ilist == true or string_in_array('lan', ilist) then
	    input_rule = 'ACCEPT'
	end
	c:set(firewall, vpn_zone, 'input', input_rule)

	if input_rule == 'REJECT' then
	    local rule = c:section(firewall, 'rule')
	    c:set(firewall, rule, 'src', vpn_name)
	    c:set(firewall, rule, 'proto', 'tcpudp')
	    c:set(firewall, rule, 'dest_port', '53')
	    c:set(firewall, rule, 'target', 'ACCEPT')

	    rule = c:section(firewall, 'rule')
	    c:set(firewall, rule, 'src', vpn_name)
	    c:set(firewall, rule, 'proto', 'tcp')
	    c:set(firewall, rule, 'dest_port', '80 443')
	    c:set(firewall, rule, 'target', 'ACCEPT')
	end

	if ilist == true or string_in_array('wan', ilist) then
	    fwd = c:section(firewall, 'forwarding')
	    c:set(firewall, fwd, 'src', vpn_name)
	    c:set(firewall, fwd, 'dest', 'wan')
	end

	local iif = get_internal_interfaces(c)
	for _, ifs in ipairs(iif) do
	    if ilist == true or string_in_array(ifs.name, ilist) then
		fwd = c:section(firewall, 'forwarding')
		c:set(firewall, fwd, 'src', vpn_name)
		c:set(firewall, fwd, 'dest', ifs.name)
	    end
	end
    else
	if vpn_zone then
	    c:delete(firewall, vpn_zone)
	end
    end
end

function update_firewall_rules_for_vpnc(c, vpn_name, dest)
    local firewall = 'firewall'
    local vpn_ifaces = 'vpn-ifaces'

    local internal_ifs = get_vpn_ifaces(c, vpn_name)
    local iifaces = {}
    local vpnc_ifs = {}

    for _, iface in ipairs(get_internal_interfaces(c)) do
	iifaces[#iifaces+1] = iface.name
    end

    for _, ifs in ipairs(internal_ifs) do
	if string_in_array(ifs, iifaces) then
	    vpnc_ifs[#vpnc_ifs+1] = {
		name = ifs
	    }
	end
    end

    local update_needed = false
    c:foreach(firewall, 'forwarding', function(fwd)
	if fwd.dest == dest then
	    local forwarded = false
	    for _, ifs in ipairs(vpnc_ifs) do
		if fwd.src == ifs.name then
		    forwarded = true
		    ifs.forwarded = true
		    break
		end
	    end
	    if not forwarded then
		update_needed = true
	    end
	end
    end)

    if not update_needed then
	for _, ifs in ipairs(vpnc_ifs) do
	    if not ifs.forwarded then
		update_needed = true
		break
	    end
	end
    end

    local updated = false
    if update_needed then
	c:foreach(firewall, 'forwarding', function(fwd)
	    if string_in_array(fwd.src, iifaces) then
		local fwan = true
		for _, ifs in ipairs(vpnc_ifs) do
		    if fwd.src == ifs.name and string_in_array(fwd.dest, { 'wan', 'vpnc', 'wgc' }) then
			if fwd.dest ~= dest then
			    c:set(firewall, fwd['.name'], 'dest', dest)
			end
			fwan = false
			break
		    end
		end

		if fwan and fwd.dest == dest and dest ~= 'wan' then
		    c:set(firewall, fwd['.name'], 'dest', 'wan')
		end
	    end
	end)
	updated = true
    end

    if updated then
	updated = c:commit(firewall)
    end

    return updated
end

function random_string(cs, length, group_size)
    local fs = require "nixio.fs"
    local rand = fs.readfile("/dev/urandom", length)
    local i, s, max = 1, '', #cs

    group_size = type(group_size) == 'number' and group_size or 0
    while i <= length do
	local idx = (rand:byte(i) % max) + 1
	s = s .. cs:sub(idx, idx)
	if group_size > 0 and i > 0 and i < length and i % group_size == 0 then
	    s = s .. '-'
	end
	i = i + 1
    end
    return s
end

function delay_exec(cmd, delay)
    require "ubus"
    local conn = ubus.connect(nil, 500)
    if not conn then return end

    conn:call('delayexec', 'set', { cmd = cmd, delay = delay })
    conn:close()
end

function exec_delayed()
    require "ubus"
    local conn = ubus.connect(nil, 500)
    if not conn then return end

    local now = os.time()
    local r = conn:call('delayexec', 'get', {})
    if r and r.jobs then
	for _, job in ipairs(r.jobs) do
	    if job.run <= now then
		conn:call('delayexec', 'del', { cmd = job.cmd, run = job.run })
		os.execute('(' .. job.cmd .. ') >/dev/null 2>&1')
	    end
	end
    end
    conn:close()
end

function save_tmp_data(key, value)
    local jsonc = require "luci.jsonc"
    require "nixio.fs".writefile(string.format('/tmp/log/%s.json', key), jsonc.stringify(value))
end

function get_tmp_data(key)
    local r
    local jsonc = require "luci.jsonc"
    local s = require "nixio.fs".readfile(string.format("/tmp/log/%s.json", key))
    if s then r = jsonc.parse(s) end
    return r and r or {}
end

function update_router_acl(c, m, utype)
    local uhttpd = 'uhttpd'
    local cfg = c:get_first(uhttpd, 'acl')
    if not cfg then return false end

    local ou = {}

    for _, s in ipairs(load_vpn_users()) do
	ou[#ou+1] = s.name
    end

    if utype ~= nil then
	c:foreach('dhcp', 'host', function(s)
	    ou[#ou+1] = s.name
	end)
    end

    for _, uname in ipairs(ou) do
	if m[uname] == false then m[uname] = nil end
    end

    local update = false
    local new_users = {}
    local users = c:get_list(uhttpd, cfg, 'user')
    for _, user in ipairs(users) do
	if m[user] == nil then
	    new_users[#new_users+1] = user
	else
	    update = true
	    if m[user] ~= false then
		new_users[#new_users+1] = m[user]
	    end
	end
    end

    if update then
	c:set_list(uhttpd, cfg, 'user', new_users)
	return c:commit(uhttpd)
    end

    return false
end
