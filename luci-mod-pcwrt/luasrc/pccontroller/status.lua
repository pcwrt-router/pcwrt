-- Copyright (C) 2023 pcwrt.com
-- Licensed to the public under the Apache License 2.0.

local sys = require "luci.sys"
local http = require "luci.http"
local util = require "luci.util"
local nw = require "luci.model.network"
local jsonc = require "luci.jsonc"
local i18n = require "luci.i18n"
local uci = require "luci.pcuci"
local nixio = require "nixio"
require "luci.tools.arp"
require "luci.tools.dhcp"
require "luci.pcutil"
require "luci.ip"

module("luci.pccontroller.status", package.seeall)

local dhcp = 'dhcp'
local network = 'network'

local function is_wifi_net_up(net, dev)
    if net:get('disabled') == '1' or net:channel() == nil then
	return false
    end

    local devtype = dev:get('type')
    if devtype ~= 'rt2860v2' and not devtype:starts('mt') then
	return net:is_up()
    end

    return os.execute('ifconfig | grep '.. dev:name() .. ' >/dev/null 2>&1') == 0
end

local function get_wifinets(c, devs)
    local band, channel, frequency, encryption
    local wifinets = {}
    for _, dev in ipairs(devs) do
	for i, net in ipairs(dev:get_wifinets()) do
	    if is_wifi_net_up(net, dev) then
		channel = net:channel()
		band = channel > 20 and '5.0 GHz' or '2.4 GHz'
		frequency = net:frequency()
		if not frequency then frequency = get_freq_for_channel(channel, band) end
		encryption = net:active_encryption()
		if not encryption or encryption == '-' then encryption = get_encryption_desc(net:get('encryption')) end
		wifinets[#wifinets+1] = {
		    up = true,
		    ssid = net:active_ssid(),
		    mode = net:active_mode(),
		    channel = channel,
		    band = band,
		    frequency = frequency,
		    encryption = encryption,
		}
	    elseif net:get('network') == 'lan' then
		local freqlist = dev.iwinfo.freqlist
		if freqlist and #freqlist > 0 then
		    band = freqlist[1].channel > 20 and '5.0 GHz' or '2.4 GHz'
		else
		    band = c:get('wireless', dev:name(), 'band')
		    band = band == '5.0G' and '5.0 GHz' or '2.4 GHz'
		end

		wifinets[#wifinets+1] = {
		    up = false,
		    ssid = net:active_ssid(),
		    band = band,
		}
	    end
	end
    end
    return wifinets
end

function get_assocs(c, ntm, devs, netaddrs)
    local hosts_lookup = {}
    c:foreach(dhcp, 'host', function(s)
	for _, mac in ipairs(s.mac:split(' ')) do
	    hosts_lookup[string.upper(mac)] = s.name
	end
    end)

    local leases = luci.tools.dhcp.dhcp_leases()
    local lease_lookup = {}
    for _, v in ipairs(leases) do
	lease_lookup[v.ipaddr] = v
    end

    local arp = {}
    luci.tools.arp.arptable(function(e)
	local ip = e["IP address"]
	local mac = e["HW address"]:upper()
	local ok = false
	for _, v in ipairs(netaddrs) do
	    if luci.ip.IPv4(ip, v.netmask):network() == v.network then
		ok = true
		break
	    end
	end

	print("OK: "..tostring(ok))

	if ok and mac ~= '00:00:00:00:00:00' then
	    arp[#arp + 1] = {
		ip = ip,
		arp_mac = mac,
		dhcp_mac = lease_lookup[ip] and lease_lookup[ip].macaddr:upper() or nil,
		complete = e["Flags"] == '0x2' or e["Flags"] == '0x06',
	    }
	end
    end)

    local i, a, hostname, real_mac
    local assoc_map = {}
    for _, dev in ipairs(devs) do
	for _, net in ipairs(dev:get_wifinets()) do
	    if is_wifi_net_up(net, dev) then
		local netinfo = ntm.network(net:network()[1])
		local routermask = netinfo:netmask()
		local router_network = luci.ip.IPv4(netinfo:ipaddr(), routermask):network()
		local assoc = net:assoclist()
		for mac, v in pairs(assoc) do
		    ip = nil
		    for _, a in ipairs(arp) do
			if a.checked == nil and a.arp_mac == mac then
			    if luci.ip.IPv4(a.ip, routermask):network() == router_network then
				ip = a.ip
				real_mac = a.dhcp_mac and a.dhcp_mac or a.arp_mac
				hostname = hosts_lookup[real_mac]
				if not hostname then
				    hostname = lease_lookup[ip] and lease_lookup[ip].hostname or '*unknown*'
				end

				local vlan = get_network_for_ip(c, ip)
				assoc_map[ip] = {
				    ip_assign = hosts_lookup[real_mac] and 'static' or 'dynamic',
				    hostname = hostname,
				    ipaddr = ip,
				    mac = real_mac,
				    signal = v.signal .. ' dBm',
				    net = net:shortname(),
				    vlan = vlan and vlan.text or '*unknown*',
				    complete = a.complete,
				}
				a.checked = true
			    end
			end
		    end

		    if not ip then
			hostname = nil
			for _, l in ipairs(leases) do
			    if l.macaddr:upper() == mac then
				hostname = l.hostname
				ip = l.ipaddr
				break
			    end
			end

			local key = ip and ip or mac
			if not ip then ip = "*unknown*" end

			if hosts_lookup[mac] then hostname = hosts_lookup[mac] end
			if not hostname then hostname = '*unknown*' end

			local vlan = get_network_for_ip(c, ip)
			assoc_map[key] = {
				ip_assign = hosts_lookup[mac] and 'static' or 'dynamic',
				hostname = hostname,
				ipaddr = ip,
				mac = mac,
				signal = v.signal .. ' dBm',
				net = net:shortname(),
				vlan = vlan and vlan.text or '*unknown*',
				complete = true,
			}

			for _, a in ipairs(arp) do
			    if a.ip == ip then
				a.checked = true
				break
			    end
			end
		    end
		end
	    end
	end
    end

    local assocs = {}
    for ip, a in pairs(assoc_map) do -- Add all WiFi clients - "complete" or not "complete"
	assocs[#assocs+1] = a
    end

    for _, a in ipairs(arp) do -- Add everything in ARP but not in WiFi list
	if a.checked == nil then
	    mac = a.dhcp_mac and a.dhcp_mac or a.arp_mac
	    hostname = hosts_lookup[mac]
	    if not hostname then
		hostname = lease_lookup[a.ip] and lease_lookup[a.ip].hostname or '*unknown*'
	    end

	    local vlan = get_network_for_ip(c, a.ip)
	    assocs[#assocs+1] = {
		ip_assign = hosts_lookup[mac] and 'static' or 'dynamic',
		hostname = hostname,
		ipaddr = a.ip,
		mac = mac,
		signal = i18n.translate('N/A'),
		net = i18n.translate('Wired'),
		vlan = vlan and vlan.text or '*unknown*',
		complete = a.complete,
		wired = true,
	    }
	end
    end

    return assocs
end

local function get_wannet(ntm)
    local wan_nets = ntm:get_wan_networks()
    if #wan_nets > 0 then
	return wan_nets[1]
    end
    return nil
end

function _get_data(c)
    local ntm = nw.init()
    local wan = get_wannet(ntm)
    local wan_stat = {}

    if wan then
	wan_stat.up = true
	wan_stat.proto = wan:proto()
	wan_stat.ipaddr = wan:ipaddr()
	wan_stat.netmask = wan:netmask()
	wan_stat.gwaddr = wan:gwaddr()
	wan_stat.dns = wan:dnsaddrs()
	wan_stat.uptime = wan:uptime()
	if wan:get_interface() then
	    wan_stat.macaddr = wan:get_interface():mac()
	end
    else
	wan_stat.up = false
    end

    local devs = ntm:get_wifidevs()
    local wifinets = get_wifinets(c, devs)
    local netaddrs = get_vlan_ifaces(c)
    local assocs = get_assocs(c, ntm, devs, netaddrs)

    for _, n in ipairs(netaddrs) do
	n.network = nil
    end

    return {
	localtime = os.date(),
	uptime = sys.uptime(),
	loadavg = nixio.sysinfo().loads,
	wan_stat = wan_stat,
	wifinets = wifinets,
	assocs = assocs,
	netaddrs = netaddrs,
    }
end

function index()
    local c = uci.cursor()
    local t = template('status')
    local ok, err = util.copcall(t.target, t, {
	title = i18n.translate('Status'),
	form_value_json = jsonc.stringify(
	    _get_data(c)
	),
	status = true,
	page_script = 'status.js',
    })
end

function _refresh_hosts(c)
    local ntm = nw.init()
    local devs = ntm:get_wifidevs()
    local netaddrs = get_vlan_ifaces(c)
    local assocs = get_assocs(c, ntm, devs, netaddrs)

    for _, n in ipairs(netaddrs) do
	n.network = nil
    end

    return {
	assocs = assocs,
	netaddrs = netaddrs,
    }
end

function refresh_hosts()
    local c = uci.cursor()
    http.prepare_content('application/json')

    http.write_json({
	status = 'success',
	data = _refresh_hosts(c),
    })
end

function _get_ip_status(c, v)
    if not v.iface or not v.ips or #v.ips == 0 then
	return {
	    status = 'success',
	}
    end

    local ips
    if v.ips == 'all' then
	local ntm = nw.init()
	local n = ntm.network(v.iface)
	local routerip = n:ipaddr()
	local routermask = n:netmask()
	if not routerip or not routermask then
	    return {
		status = 'success',
	    }
	end

	ips = util.exec("/usr/bin/arp-scan --interface br-%s --bandwidth=20000 %s -N -q -r 3 2>/dev/null | awk '/^[0-9]+\\./ {print $1}'" % {v.iface, luci.ip.IPv4(routerip, routermask):string()})
    else
	local ipstr = type(v.ips) == 'table' and table.concat(v.ips, ' ') or v.ips:gsub(',', ' ')
	ips = util.exec("/usr/bin/arp-scan --interface br-%s --bandwidth=20000 %s -N -q -r 3 2>/dev/null | awk '/^[0-9]+\\./ {print $1}'" % {v.iface, ipstr})
    end

    local active_ip_map = {}
    ips:gsub("([^\n]+)", function(ip) active_ip_map[ip] = 1 end)

    return {
	status = 'success',
	ips = active_ip_map,
    }
end

function get_ip_status()
    http.prepare_content('application/json')

    local fv = http.formvalue()

    http.write_json({
	status = 'success',
	data = _get_ip_status(nil, fv),
    })
end
