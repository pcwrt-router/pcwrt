-- Copyright (C) 2023 pcwrt.com
-- Licensed to the public under the Apache License 2.0.

local http = require "luci.http"
local util = require "luci.util"
local conf = require "luci.pcconfig"
local uci = require "luci.pcuci"
local i18n = require "luci.i18n"
require "luci.jsonc"
require "luci.sys"
require "luci.pcutil"
require "nixio.fs"

module("luci.pccontroller.login", package.seeall)

need_authentication = false

local system = 'system'
local network = 'network'
local reset_counter = '/tmp/pw_reset_counter'

local function get_config_email(c)
    local email = nil
    local sys_notify = c:get_first(system, 'notifications')
    if sys_notify and c:get(system, sys_notify, 'email_password_reset') == '1' then
	email = c:get(system, sys_notify, 'email')
    end
    return email
end

local function mask_email(email)
    if string.is_empty(email) then
	return nil
    end

    local parts = email:split('@')
    if #parts ~= 2 then
	email = nil
    else
	email = (#(parts[1]) > 3 and parts[1]:sub(1, 3) or parts[1]) .. '*****@' .. parts[2]
    end

    return email
end

function index()
    local pass = http.formvalue('password')
    local token = http.formvalue('token')

    local user_valid = nil
    if pass then
	user_valid = login(conf.main.osuser, pass, token)
    end

    if user_valid then
	nixio.fs.remove(reset_counter)
	http.redirect(build_url())
    else
	local err_msg = nil

	if pass then
	    err_msg = "Invalid password"
	end

	local c = uci.cursor()
	local t = template("login")
	local ok, err = util.copcall(t.target, t, {
	    title = 'Login',
	    no_banner = true,
	    page_script = 'login.js',
	    err_msg = err_msg,
	    email = mask_email(get_config_email(c)),
	    not_dhcp = c:get(network, 'wan', 'proto') ~= 'dhcp'
	})
	assert(ok, "Failed to render template ".. t.view .. ': ' .. tostring(err)) 
    end
end

local function get_reset_times()
    local n, t = 0, 0
    local content = nixio.fs.readfile(reset_counter)
    if content ~= nil then
	local cp = content:split(' ')
	if #cp == 2 then
	    n = tonumber(cp[1])
	    if n == nil then n = 0 end
	    t = tonumber(cp[2])
	    if t == nil then t = 0 end
	end
    end

    if n <= 10 then
	return t, t + 5*60
    else
	return t, t + 10*60
    end
end

local function set_reset_times()
    local n = 0
    local content = nixio.fs.readfile(reset_counter)
    if content ~= nil then
	local cp = content:split(' ')
	if #cp == 2 then
	    n = tonumber(cp[1])
	    if n == nil then n = 0 end
	end
    end

    nixio.fs.writefile(reset_counter, (n + 1) .. ' ' .. os.time())
end

function reset_password()
    http.prepare_content('application/json')

    local lst, nxt = get_reset_times()
    local now = os.time()
    if now < nxt then
	local past = now - lst
	local before = (past - past % 60) / 60
	before = before == 1 and i18n.translate('1 minute') or before .. ' ' .. i18n.translate('minutes')

	nxt = nxt - now
	local after = nxt % 60 == 0 and nxt/60 or ((nxt - nxt % 60) / 60 + 1)
	after = after == 1 and i18n.translate('1 minute') or after .. ' ' .. i18n.translate('minutes')

	http.write_json({
	    status = 'success',
	    title = i18n.translate('Please Wait'),
	    message = i18n.translatef('You requested password reset %s ago. Please wait for %s before trying again.', before, after)
	})
	return
    end

    local status = 'success'
    local c = uci.cursor()
    local email = get_config_email(c)
    local password = luci.sys.exec('head /dev/urandom | tr -dc A-Za-z0-9 | head -c 24')

    if #password ~= 24 then
	status = 'fail'
    end

    if status == 'success' then
	if http.formvalue('switch_dhcp') == '1' and c:get(network, 'wan', 'proto') ~= 'dhcp' then
	    local ifname = c:get(network, 'wan', 'ifname')
	    c:delete(network, 'wan')
	    c:section(network, 'interface', 'wan')
	    c:set(network, 'wan', 'ifname', ifname)
	    c:set(network, 'wan', 'proto', 'dhcp')
	    if c:commit(network) then
		luci.sys.call("env -i /sbin/ifup wan >/dev/null 2>/dev/null")
		os.execute('sleep 10')
	    else
		status = 'fail'
	    end
	end
    end

    if status == 'success' then
	local rc = luci.sys.exec('updater -nn \'%s\'' % { luci.jsonc.stringify({
	    event = 'RESET',
	    password = password,
	    email = email,
	}):quote_apostrophe() })

	if rc == '{"status":"noop"}' then
	    status = 'noop'
	elseif rc ~= '{"status":"done"}' then
	    status = 'fail'
	end
    end

    if status == 'success' then
	if luci.sys.user.setpasswd(conf.main.osuser, password) ~= 0 then
	    status = 'fail'
	end
    end

    local title, message
    if status == 'success' then
	set_reset_times()
	message = i18n.translate('Router password was reset and sent to your email address at ') .. mask_email(email)
    elseif status == 'noop' then
	status = 'success'
	title = i18n.translate('No Change')
	message = i18n.translate('Router not properly configured to reset password by email. Please try a different method.')
    else
	message = i18n.translate('Failed to reset router password. Please try again later.')
    end

    http.write_json({
	status = status,
	title = title,
	message = message,
    })
end
