-- Copyright (C) 2023 pcwrt.com
-- Licensed to the public under the Apache License 2.0.

local http = require "luci.http"
local util = require "luci.util"
local jsonc = require "luci.jsonc"
local uci = require "luci.pcuci"
local dt = require "luci.cbi.datatypes"
local i18n = require "luci.i18n"
require "luci.pcutil"
require "nixio.fs"

module("luci.pccontroller.apps.upnp", package.seeall)

ordering = 40
function display_name()
    return nixio.fs.access('/etc/init.d/miniupnpd', 'x') and i18n.translate('UPnP') or nil
end

local config = 'upnpd'
local section = 'config'

local function get_enabled_network(c)
    local internal_ifs = get_internal_interfaces(c)
    local enabled_ifs = c:get('upnpd', 'config', 'internal_iface')
    if enabled_ifs ~= nil then
	enabled_ifs = enabled_ifs:split(' ')
    else
	enabled_ifs = {}
    end

    for _, nw in pairs(internal_ifs) do
	for _, enabled_if in ipairs(enabled_ifs) do
	    if nw.name == enabled_if then
		nw.enabled = true
		break
	    end
	end
	if nw.enabled == nil then
	    nw.enabled = false
	end
    end

    return internal_ifs
end

function _get_data(c)
    local disabled = is_upnpd_enabled(c) and '0' or '1'
    local rule = c:get_first(config, 'perm_rule')

    return {
	disabled = disabled,
	enabled_network = get_enabled_network(c),
	enable_natpmp = c:get(config, section, 'enable_natpmp'),
	enable_upnp = c:get(config, section, 'enable_upnp'),
	secure_mode = c:get(config, section, 'secure_mode'),
	ext_ports = c:get(config, rule, 'ext_ports'),
	int_addr = c:get(config, rule, 'int_addr'),
	int_ports = c:get(config, rule, 'int_ports'),
    }
end

function index()
    local c = uci.cursor()
    local t = template('apps/upnp')
    local ok, err = util.copcall(t.target, t, {
	title = i18n.translate('UPnP'),
	form_value_json = jsonc.stringify(_get_data(c)),
	page_script = 'apps/upnp.js',
    })
    assert(ok, 'Failed to render template ' .. t.view .. ': ' .. tostring(err))
end

local function is_port_range(v)
    if type(v) ~= 'string' then
	return false
    end

    local lo, hi = string.match(v, '^%s*(%d+)-(%d+)%s*$')
    if lo == nil then
	lo = string.match(v, '^%s*(%d+)%s*$')
    end

    if lo == nil or tonumber(lo) == 0 or tonumber(lo) > 65535 then
	return false
    end

    if hi ~= nil and (tonumber(hi) == 0 or tonumber(hi) > 65535) then
	return false
    end

    return true
end

local function valid_ip_cidr(v) -- Must be of the form n.n.n.n/n even for single IPs.
    if type(v) ~= 'string' then
	return false
    end

    v = v:trim()
    local parts = v:split('/')
    if #parts == 2 then
	return dt.ip4addr(parts[1]) and tonumber(parts[2]) ~= nil and tonumber(parts[2]) <= 32
    end

    return false
end

local function validate(v)
    local errs = {}
    if not is_port_range(v.ext_ports) then
	errs.ext_ports = i18n.translate('Invalid port range')
    end

    if not is_port_range(v.int_ports) then
	errs.int_ports = i18n.translate('Invalid port range')
    end

    if not valid_ip_cidr(v.int_addr) then
	errs.int_addr = i18n.translate('Invalid IP address')
    end

    return errs
end

function _update(c, v)
    local iiface

    if v.disabled ~= '1' then
	iiface = v.network

	if type(iiface) == 'table' then
	    iiface = table.concat(iiface, ' ')
	end

	if iiface == nil or #iiface == 0 then
	    v.disabled = '1'
	end
    end

    if v.disabled == '1' then
	local rc = fork_exec_wait("/etc/init.d/miniupnpd stop; /etc/init.d/miniupnpd disable")
	success = rc == 0
	if success then
	    c:set(config, section, 'enabled', '0')
	    success, msg = c:commit(config)
	end
	return {
	    status = success and 'success' or 'fail',
	    message = success and '' or i18n.translate('Failed to disable UPnP') 
	}
    end

    local errs = validate(v)
    if next(errs) ~= nil then
	return {
	    status = 'error',
	    message = errs
	}
    end

    require "luci.sys"
    success = luci.sys.init.enable('miniupnpd')
    if success then
	c:set(config, section, 'enabled', '1')
	c:set(config, section, 'internal_iface', iiface)
	c:set(config, section, 'enable_natpmp', v.enable_natpmp == '1' and '1' or '0')
	c:set(config, section, 'enable_upnp', v.enable_upnp == '1' and '1' or '0')
	c:set(config, section, 'secure_mode', v.secure_mode == '1' and '1' or '0')
	local rule = c:get_first(config, 'perm_rule')
	c:set(config, rule, 'ext_ports', v.ext_ports)
	c:set(config, rule, 'int_ports', v.int_ports)
	c:set(config, rule, 'int_addr', v.int_addr)
	success, msg = c:commit(config)
    end

    return {
	status = success and 'success' or 'fail',
	message = success and '' or i18n.translate('Failed to save configuration'),
	apply = config,
    }
end

function update()
    local success, msg
    local c = uci.cursor()
    local v = http.formvalue()

    http.prepare_content('application/json')
    http.write_json(_update(c, v))
end
