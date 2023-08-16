require "luci.pcutil"
local http = require "luci.http"
local util = require "luci.util"
local jsonc = require "luci.jsonc"
local fs = require "nixio.fs"
local sys = require "luci.sys"
local uci = require "luci.pcuci"
local tz = require "luci.sys.zoneinfo"
local i18n = require "luci.i18n"
local wireless = require "luci.pccontroller.settings.wireless"

module("luci.pccontroller.setup", package.seeall)

local sys_config = 'system'
local wifi_config = 'wireless'

function index()
    local c = uci.cursor()
    local t = template("setup")

    local devs = {}
    c:foreach(wifi_config, 'wifi-device', function(d)
	local dev = {}
	local channels = wireless.channel_list(c, d['.name'])
	dev['.name'] = d['.name']
	dev.band = channels[1].value > 20 and "5.0 GHz" or "2.4 GHz"
	dev.encryptions = encryption_list(d['type'])
	dev.ciphers = cipher_list()
	dev.encryption = 'psk2'
	dev.cipher = 'ccmp'
	local ifaces = get_ifaces_for_dev(c, d['.name'])
	if #ifaces > 0 then
	    dev.ssid = ifaces[1].ssid
	else
	    dev.ssid = 'pcwrt'
	end
	devs[#devs+1] = dev
    end)

    local ok, err = util.copcall(t.target, t, {
	title = i18n.translate('Setup'),
	no_banner = true,
	form_value_json = jsonc.stringify({
	    devices = devs,
	}),
	page_script = 'setup.js',
    })

    assert(ok, "Failed to render template ".. t.view .. ': ' .. tostring(err)) 
end

function update()
    local c = uci.cursor()
    local v = http.formvalue()
    
    -- set timezone
    local sys_cfg_name = c:get_first(sys_config, 'system')
    local zonename = 'UTC'
    local timezone = nil
    for _, z in ipairs(tz.TZ) do
	if v.zonename == z[1] then
	    zonename = z[1]
	    timezone = z[2]
	    break
	end
    end
    c:set(sys_config, sys_cfg_name, 'zonename', zonename)
    if timezone ~= nil then
	c:set(sys_config, sys_cfg_name, 'timezone', timezone)
    else
	c:delete(sys_config, sys_cfg_name, 'timezone')
    end
    fs.writefile("/etc/TZ", (timezone ~= nil and timezone or 'UTC') .. "\n")

    c:commit(sys_config)

    -- set wifi SSID, encryption, key, power
    local devs = jsonc.parse(v.devices)
    for _, dev in ipairs(devs) do
	local devname = dev['.name']
	c:set(wifi_config, devname, 'disabled', dev.disabled and '1' or '0')
	if not dev.disabled then
	    local hwtype = c:get(wifi_config, devname, 'type')
	    if  hwtype ~= nil then
		local ifname
		local ifaces = get_ifaces_for_dev(c, devname)
		if #ifaces > 0 then
		    ifname = ifaces[1]['.name']
		else
		    ifname = c:section(wifi_config, 'wifi-iface')
		    c:set(wifi_config, ifname, 'mode', 'ap')
		    c:set(wifi_config, ifname, 'device', devname)
		end

		c:set(wifi_config, devname, 'txpower', get_full_txpower(hwtype))
		c:set(wifi_config, ifname, 'ssid', dev.ssid)
		c:set(wifi_config, ifname, 'key', dev.key)
		c:set(wifi_config, ifname, 'encryption', (dev.encryption == 'none' or dev.cipher == 'auto') and dev.encryption or dev.encryption .. '+' .. dev.cipher)
	    end
	end
    end
    c:commit(wifi_config)

    -- change password
    local conf = require "luci.pcconfig"
    sys.user.setpasswd(conf.main.osuser, v.password1)

    -- restart network
    os.execute("(sleep 3;/sbin/luci-restart network) >/dev/null 2>&1 &")

    logout()
    http.header('Set-Cookie', 'sysauth=; path='..build_cookie_path())

    local t = template("login")
    local ok, err = util.copcall(t.target, t, {
	title = i18n.translate('Login'),
	no_banner = true,
	info_msg = 'Setup successfully completed. You can start using your router now.',
	page_script = 'login.js',
    })

    assert(ok, "Failed to render tamplate ".. t.view .. ': ' .. tostring(err))
end
