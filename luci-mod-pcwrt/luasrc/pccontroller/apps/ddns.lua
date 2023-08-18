local http = require "luci.http"
local util = require "luci.util"
local jsonc = require "luci.jsonc"
local uci = require "luci.pcuci"
local fs = require "nixio.fs"
local i18n = require "luci.i18n"
require "luci.pcutil"

module("luci.pccontroller.apps.ddns", package.seeall)

ordering = 30
function display_name()
    return nixio.fs.access('/etc/init.d/ddns', 'x') and i18n.translate('Dynamic DNS') or nil
end

local config = 'ddns'
local section = 'wan'

local function combine_time_unit(t, u)
    if t == nil then
	return nil
    end

    if u == 'hours' then
	return t..'h'
    elseif u == 'minutes' then
	return t..'m'
    elseif u == 'seconds' then
	return t..'s'
    else
	return t..'m'
    end
end

local function separate_time_unit(tu)
    if tu == nil then
	return nil, nil
    end

    local t = tu:sub(1, #tu - 1)
    local u = tu:sub(#tu)
    
    if u == 'h' then
	return t, 'hours'
    elseif u == 'm' then
	return t, 'minutes'
    elseif u == 's' then
	return t, 'seconds'
    else
	return t, 'minutes'
    end
end

function _get_data(c)
    local enabled = c:get(config, section, 'enabled')
    local service_name = c:get(config, section, 'service_name') 

    return {
	service_name = enabled == '1' and service_name or '',
	username = c:get(config, section, 'username'),
	password = c:get(config, section, 'password'),
	force_interval = combine_time_unit(
			c:get(config, section, 'force_interval'), 
			c:get(config, section, 'force_unit')
		     ),
	check_interval = combine_time_unit(
			c:get(config, section, 'check_interval'), 
			c:get(config, section, 'check_unit')
		     ),
    }
end

function index()
    local c = uci.cursor()
    local t = template('apps/ddns')
    local ok, err = util.copcall(t.target, t, {
	title = i18n.translate('Dynamic DNS'),
	form_value_json = jsonc.stringify(_get_data(c)),
	page_script = 'apps/ddns.js',
    })
    assert(ok, 'Failed to render template ' .. t.view .. ': ' .. tostring(err))
end

function _update(c, v)
    local success, msg

    local service_name = v.service_name
    if not service_name then
	return {
	    status = 'error',
	    message = { 
		proto = i18n.translate('Unrecognized service name')
	    }
	}
    end

    if service_name == '' then
	c:set(config, section, 'enabled', '0')
	success, msg = c:commit(config)
	return {
	    status = success and 'success' or 'fail',
	    message = success and '' or i18n.translate('Failed to save configuration'),
	    apply = config,
	}
    end

    local ok, svc = pcall(require, 'luci.pccontroller.apps.ddns._'..service_name:gsub('%.', '_'))
    assert(ok, 'Failed to find validator for '..service_name..': '..tostring(err))

    v.force_interval, v.force_unit = separate_time_unit(v.force_interval)
    v.check_interval, v.check_unit = separate_time_unit(v.check_interval)

    local cfg, errs = svc.validate(v)
    if not cfg then
	return {
	    status = 'error',
	    message = errs
	}
    end

    c:delete(config, section)
    cfg.password = cfg.password
    c:section(config, 'service', section, cfg)
    success, msg = c:commit(config)

    if success and fs.access("/usr/lib/ddns/dynamic_dns_test.sh") then
    	local rc = fork_exec_wait("/usr/lib/ddns/dynamic_dns_test.sh "..section) 
    	if  rc ~= 0 then
	    local msg = i18n.translate('Failed to update Dynamic DNS, please check your network connection.')
	    if (rc == 2) then
		msg = i18n.translate('Failed to update Dynamic DNS, please check your username and password and try again.')
	    elseif (rc == 3) then
		msg = i18n.translate('Dynamic DNS internal error. Please contact pcWRT support.')
	    end

	    return {
		status = 'fail',
		message = msg,
	    }
	end
    end

    c:set(config, section, 'enabled', '1')
    success, msg = c:commit(config)

    return {
    	status = success and 'success' or 'fail',
    	message = success and '' or i18n.translate('Failed to save configuration'),
    	apply = config,
    }
end

function update()
    local v = http.formvalue()
    local c = uci.cursor()

    http.prepare_content('application/json')
    http.write_json(_update(c, v))
end
