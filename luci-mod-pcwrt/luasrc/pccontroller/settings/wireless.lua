require "iwinfo"
require "luci.pcutil"
local http = require "luci.http"
local util = require "luci.util"
local uci = require "luci.pcuci"
local fs = require "nixio.fs"
local dt = require "luci.cbi.datatypes"
local jsonc = require "luci.jsonc"
local i18n = require "luci.i18n"

module("luci.pccontroller.settings.wireless", package.seeall)

ordering = 30
function display_name()
    return i18n.translate('Wireless')
end

local config = 'wireless'
local dhcp = 'dhcp'
local firewall = 'firewall'
local network = 'network'

local function tx_power_list(iw, devname)
    local new  = {}
    local list = iw.txpwrlist(devname) or {}
    local off  = tonumber(iw.txpower_offset(devname)) or 0
    local prev = -1
    local _, val
    for _, val in ipairs(list) do
	local dbm = val.dbm + off
	local mw  = math.floor(10 ^ (dbm / 10))
	if mw ~= prev then
	    prev = mw
	    new[#new+1] = {
		    display_dbm = dbm,
		    display_mw  = mw,
		    driver_dbm  = val.dbm,
		    driver_mw   = val.mw
	    }
	end
    end
    return new
end

function txpower_list(c, devname)
    local pl = {}

    local hwtype = c:get(config, devname, 'type')
    if hwtype == 'rt2860v2' or hwtype:starts('mt76') then
	pl[1] = {
	    value = '1',
	    text = '1%'
	}

	for p=10,100,10 do
	    pl[#pl+1] = {
		value = tostring(p),
		text = tostring(p)..'%'
	    }
	end
    else
	local api = iwinfo.type(devname)
	local iw = iwinfo[api]
	for _, p in ipairs(tx_power_list(iw, devname)) do
	    pl[#pl+1] = {
		value = p.driver_dbm,
		text = '%i dBm (%i mW)' % {p.display_dbm, p.display_mw},
	    }
	end
    end

    return pl
end

function channel_list(c, devname)
    local cl = {}

    local hwtype = c:get(config, devname, 'type')
    if hwtype == 'rt2860v2' or hwtype:starts('mt76') then
	local band = c:get(config, devname, 'band')
	if band == '5.0G' then
	    cl = channel_list_for_5g()
	else
	    cl = channel_list_for_24g()
	end
    else
	local api = iwinfo.type(devname)
	local iw = iwinfo[api]
	local fl = iw.freqlist(devname)
	for _, f in ipairs(fl) do
	    if not f.restricted then
		cl[#cl+1] = {
		    value = f.channel,
		    text = '%i (%.3f GHz)' % {f.channel, f.mhz/1000},
		}
	    end
	end
    end

    return cl
end

local function get_device_channel_width(c, devname)
    local hwtype = c:get(config, devname, 'type')
    local bw
    if hwtype == 'rt2860v2' or hwtype:starts('mt76') then
	bw = c:get(config, devname, 'bw')
	return bw ~= nil and bw or '0'
    else
	bw = c:get(config, devname, 'htmode')
	if bw == nil or bw:ends('20') then
	    return '0'
	elseif bw:ends('40') then
	    return '1'
	elseif bw:ends('80') then
	    return '2'
	else
	    return '0'
	end
    end
end

local function set_device_channel_width(c, devname, bw)
    local hwtype = c:get(config, devname, 'type')
    if hwtype == 'rt2860v2' or hwtype:starts('mt76') then
	c:set(config, devname, 'bw', bw)
    else
	local htmode = c:get(config, devname, 'htmode')
	if htmode then
	    htmode = htmode:match('%D*')
	else
	    htmode = 'HT'
	end

	if bw == '3' then
	    c:set(config, devname, 'htmode', htmode .. '160')
	elseif bw == '2' then
	    c:set(config, devname, 'htmode', htmode .. '80')
	elseif bw == '1' then
	    c:set(config, devname, 'htmode', htmode .. '40')
	else
	    c:set(config, devname, 'htmode', htmode .. '20')
	end
    end
end

local function channel_width_list(band)
    local bw = {}
    bw[#bw + 1] = { value = '0', text = i18n.translate('20 MHz') }
    bw[#bw + 1] = { value = '1', text = i18n.translate('40 MHz') }
    if band == '5.0 GHz' then
       bw[#bw + 1] = { value = '2', text = i18n.translate('80 MHz') }
    end
    return bw
end

local function validate(devs, ssid_network)
    local ok = true
    local errs = {}

    for _, dev in ipairs(devs) do
	local err = { errs = {}, ifaces = {} }

	if not dev.disabled then
	    if dev.channel ~= 'auto' and (tonumber(dev.channel) == nil or tonumber(dev.channel) <= 0) then
		err.errs.channel = i18n.translate('Invalid channel')
		ok = false
	    end

	    if not dt.uinteger(dev.txpower) then
		err.errs.txpower = i18n.translate('Invalid transmission power')
		ok = false
	    end

	    for _, iface in ipairs(dev.ifaces) do
		local iface_errs = {}
		if string.is_empty(iface.ssid) then
		    iface_errs.ssid = i18n.translate('Please enter the SSID')
		    ok = false
		else
		    local net = ssid_network[iface.ssid]
		    if net == nil then
			ssid_network[iface.ssid] = iface.vlanid
		    elseif net ~= iface.vlanid then
			iface_errs.ssid = i18n.translate('SSID already used for another network')
			ok = false
		    end
		end

		if (iface.encryption == 'psk' or iface.encryption == 'psk2' or iface.encryption == 'psk+psk2' or iface.encryption == 'psk-mixed') and (iface.key == nil or not dt.wpakey(iface.key)) then
		    iface_errs.key = i18n.translate('Encryption key must be a string between 8 and 63 characters, or a hex string of length 64')
		    ok = false
		end
		table.insert(err.ifaces, iface_errs)
	    end
	end

	table.insert(errs, err)
    end

    return ok, errs
end

function _get_data(c)
    -- get maclist
    local hostnames = {}
    c:foreach(dhcp, 'host', function(s)
	for _, mac in ipairs(s.mac:split(' ')) do
	    hostnames[mac:upper()] = s.name
	end
    end)

    local devs = {}
    c:foreach(config, 'wifi-device', function(d)
	local dev = {}
	dev['.name'] = d['.name']
	dev.disabled = d.disabled == '1' and true or false
	dev.channel = d.channel
	dev.bw = get_device_channel_width(c, d['.name'])
	dev.txpower = d.txpower
	dev.channels = channel_list(c, d['.name'])
	dev.encryptions = encryption_list(d['type'])
	dev.ciphers = cipher_list()
	dev.txpowers = txpower_list(c, d['.name'])
	dev.band = dev.channels[1].value > 20 and '5.0 GHz' or '2.4 GHz'
	dev.cwidths = channel_width_list(dev.band)
	dev.interfaces = {}

	local ifaces = get_ifaces_for_dev(c, d['.name'])
	if #ifaces > 0 then
	    for _, iface in ipairs(ifaces) do
		local ifc = {}
		local vlan = get_vlan_params(c, iface.network)
		ifc.id = vlan.id
		ifc.display_name = vlan.text
		ifc.ssid = iface.ssid
		ifc.key = iface.key
		ifc.hidessid = iface.hidden
		ifc.isolate = iface.isolate

		local enc = iface.encryption
		if enc ~= nil then
		    if enc:starts('psk+psk2') then
			ifc.encryption = 'psk+psk2'
			ifc.cipher = enc:sub(#ifc.encryption+2)
		    else
			local encryption, cipher = string.match(enc, '(.-)+(.*)')
			if encryption == nil then
			    ifc.encryption = enc
			else
			    ifc.encryption = encryption
			    ifc.cipher = cipher
			end
		    end
		end

		-- backwards compatibility (get onefilter from interface)
		if iface.onefilter ~= nil then
		    dev.onefilter = iface.onefilter
		end

		if dev.macfilter == nil then
		    if iface.macfilter == 'allow' or iface.macfilter == 'deny' then
			dev.macfilter = iface.macfilter
		    else
			dev.macfilter = 'disable'
		    end

		    local maclist = {}
		    if type(iface.maclist) == 'table' then
			for _, v in ipairs(iface.maclist) do
			    maclist[#maclist+1] = {
				mac = v,
				hostname = hostnames[v:upper()] and hostnames[v:upper()] or nil
			    }
			end
		    elseif type(iface.maclist) == 'string' then
			for s in string.gmatch(iface.maclist, '%S+') do
			    maclist[#maclist+1] = {
				mac = s,
				hostname = hostnames[s:upper()] and hostnames[s:upper()] or nil
			    }
			end
		    end
		    dev.maclist = maclist
		end

		-- backwards compatibility. if onefilter already set at interface, don't get
		-- it again from device.
		if dev.onefilter == nil then
		    dev.onefilter = d.onefilter == '0' and '0' or '1'
		end

		table.insert(dev.interfaces, ifc)
	    end
	end
	devs[#devs+1] = dev
    end)

    return {
	devices = devs,
	vlans = get_vlan_options(),
    }
end

function index()
    local c = uci.cursor() 
    local t = template("settings/wireless")

    local ok, err = util.copcall(t.target, t, {
	title = i18n.translate('Wireless'),
	form_value_json = jsonc.stringify(_get_data(c)),
	page_script = 'settings/wireless.js',
    })

    assert(ok, 'Failed to render template ' .. t.view .. ': ' .. tostring(err))
end

function _update(c, v)
    local devname, success, message

    if v.disabled then -- disable wireless and return
	success = true
	devname = v.devname
 	if not c:get(config, devname) then
  	    success = false
   	    message = i18n.translate('Failed to find wireless device')
    	end

	if success then
    	    c:set(config, devname, 'disabled', '1')
   	    success = c:commit(config)
  	    message = success and '' or i18n.translate('Failed to save configuration')
 	end

	return {
	    status = success and 'success' or 'fail',
	    message = message,
	    apply = {config},
	}
    end

    local devs = jsonc.parse(v.devices)
    local ssid_network = {}
    local ok, errs = validate(devs, ssid_network)

    if not ok then
	return {
	    status = 'error',
	    message = errs
	}
    end

    local cfgs = {config}
    for _, dev in ipairs(devs) do
	devname = dev['.name']
	if not dev.disabled and c:get(config, devname, 'type') ~= nil then
	    c:set(config, devname, 'disabled', '0')
	    c:set(config, devname, 'channel', dev.channel)
	    set_device_channel_width(c, devname, dev.bw)
	    c:set(config, devname, 'txpower', dev.txpower)

	    -- use one filter for all interfaces
	    if dev.onefilter == '0' then
		c:set(config, devname, 'onefilter', '0')
	    else
		c:delete(config, devname, 'onefilter')
	    end

	    local iface
	    local ifcs = get_ifaces_for_dev(c, devname)
	    for _, iface in ipairs(dev.ifaces) do
		local ifc, nif = nil
		for _, ifc in ipairs(ifcs) do
		    if ifc.network == get_vlan_network_name(iface.vlanid) then
			ifc.keep = true
			nif = ifc
			break
		    end
		end

		local ifname
		if nif ~= nil then
		    ifname = nif['.name']
		else
		    ifname = c:section(config, 'wifi-iface')
		    c:set(config, ifname, 'mode', 'ap')
		    c:set(config, ifname, 'device', devname)
		end

		if (iface.hidessid == '1') then
		    c:set(config, ifname, 'hidden', '1')
		else
		    c:delete(config, ifname, 'hidden')
		end

		if (iface.isolate == '1') then
		    c:set(config, ifname, 'isolate', '1')
		else
		    c:delete(config, ifname, 'isolate')
		end

		c:delete(config, ifname, 'disabled')
		c:delete(config, ifname, 'onefilter')
		c:set(config, ifname, 'network', get_vlan_network_name(iface.vlanid))
		c:set(config, ifname, 'ssid', iface.ssid)
		c:set(config, ifname, 'key', iface.key)
		c:set(config, ifname, 'encryption', (iface.encryption == 'none' or iface.cipher == 'auto') and iface.encryption or iface.encryption .. '+' .. iface.cipher)

		-- mac address filter
		if dev.macfilter == 'allow' or dev.macfilter == 'deny' then
		    c:set(config, ifname, 'macfilter', dev.macfilter)
		    if (type(dev.maclist) == 'string') then
			dev.maclist = {dev.maclist}
		    end

		    if (type(dev.maclist) == 'table' and #dev.maclist > 0) then
			c:set_list(config, ifname, 'maclist', dev.maclist)
		    else
			c:delete(config, ifname, 'maclist')
		    end
		else
		    c:delete(config, ifname, 'macfilter')
		end
	    end

	    for _, ifc in ipairs(ifcs) do
		if ifc.network ~= 'lan' and not ifc.keep then
		    c:delete(config, ifc['.name'])
		end
	    end
	end
    end

    for _, vlan in ipairs(get_vlan_list()) do
	if vlan.name ~= 'lan' then
	    local add_vlan = false
	    for ssid, vlanid in pairs(ssid_network) do
		if vlan.id == vlanid then
		    add_vlan = true
		    break
		end
	    end

	    if add_vlan then
		create_vlan_network(c, vlan.name, cfgs)
	    else
		local deleted, hosts_updated = delete_vlan_network(c, vlan.name, true, cfgs)
		if hosts_updated then
		    update_mp_conf_users(c, hosts_updated, cfgs, true)
		end
	    end
	end
    end

    success = true
    table.foreach(cfgs, function(_, cfg)
	if cfg == 'network' then cfg = network end
	if not c:commit(cfg) then
	    success = false
	    return false
	end
    end)

    return {
	status = success and 'success' or 'fail',
	message = success and '' or i18n.translate('Failed to save configuration'),
	apply = success and cfgs or '',
    }
end

function update()
    http.prepare_content('application/json')
    local c = uci.cursor() 
    local v = http.formvalue()

    local r = _update(c, v)
    if r.status == 'success' then
	local reloads = get_reload_list(c, r.apply)
	put_command({
	    type="fork_exec",
	    command="sleep 3;/sbin/luci-restart %s >/dev/null 2>&1" % table.concat(reloads, ' '),
	})

	r.reload_url = build_url('applyreboot')
	r.addr = http.getenv("SERVER_NAME")
    end

    r.apply = nil
    http.write_json(r)
end

function _assocmacs(c)
    local hosts_lookup = {}
    c:foreach(dhcp, 'host', function(s)
	hosts_lookup[string.upper(s.mac)] = s.name
    end)

    require "luci.tools.status"
    local leases = luci.tools.status.dhcp_leases()
    local assocs = {}
    for _, v in ipairs(leases) do
	local mac = string.upper(v.macaddr)
	hosts_lookup[mac] = nil
	assocs[#assocs+1] = {
	    mac = mac,
	    name = v.hostname and v.hostname or '*unknown*',
	}
    end

    for k, v in pairs(hosts_lookup) do
	assocs[#assocs+1] = {
	    mac = k,
	    name = v,
	}
    end

    return assocs
end

function assocmacs()
    http.prepare_content('application/json')
    local c = uci.cursor() 

    http.write_json({
	status = 'success',
	assocmacs = _assocmacs(c)
    })
end
