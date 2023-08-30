-- Copyright (C) 2023 pcwrt.com
-- Licensed to the public under the Apache License 2.0.

require "luci.sys"
require "nixio.fs"
require "nixio"
require "luci.pcutil"
local conf = require "luci.pcconfig"
local http = require "luci.http"
local util = require "luci.util"
local uci = require "luci.pcuci"
local dt = require "luci.cbi.datatypes"
local tz = require "luci.sys.zoneinfo"
local jsonc = require "luci.jsonc"
local i18n = require "luci.i18n"
local nw = require "luci.model.network"
local pctz = require "luci.pccontroller.timezone"

module("luci.pccontroller.settings.system", package.seeall)

ordering = 50
function display_name()
    return i18n.translate('System')
end

local config = 'system'
local dropbear = 'dropbear'
local image_tmp   = "/tmp/firmware.img"
local image_sz = "/tmp/firmware.sz"

function _get_data(c, q)
    local sys_cfg_name = c:get_first(config, 'system')
    local db_cfg_name = c:get_first(dropbear, 'dropbear')
    local ssh_avail = nixio.fs.access("/etc/config/dropbear")

    if ssh_avail then
	enable_ssh = luci.sys.init.enabled(dropbear) and 'true' or ''
	PasswordAuth = c:get(dropbear, db_cfg_name, 'PasswordAuth')
	ssh_keys = nixio.fs.readfile('/etc/dropbear/authorized_keys') or ''
    else
	enable_ssh = ''
	PasswordAuth = ''
	ssh_keys = ''
    end

    return {
    	all_timezones = q and pctz.get_timezones() or nil,
	filtered_timezones = q and pctz.get_timezones(q) or nil,
	localtime = os.date(),
	enable_server = c:get(config, 'ntp', 'enable_server'),
	hostname = c:get(config, sys_cfg_name, 'hostname'),
	zonename = c:get(config, sys_cfg_name, 'zonename'),
	enable_ssh = enable_ssh,
	PasswordAuth = PasswordAuth,
	ssh_keys = ssh_keys,
	hosts = nixio.fs.readfile('/etc/hosts') or '',
	ntp_servers = c:get(config, 'ntp', 'server'),
    }
end

function index()
    local c = uci.cursor()

    local upgrade_avail = nixio.fs.access("/lib/upgrade/platform.sh")
    local reset_avail   = os.execute([[grep '"rootfs_data"' /proc/mtd >/dev/null 2>&1]]) == 0
    local ssh_avail = nixio.fs.access("/etc/config/dropbear")

    local t = template('settings/system')
    local ok, err = util.copcall(t.target, t, {
	title = i18n.translate('System'),
	ssh_avail = ssh_avail,
	upgrade_avail = upgrade_avail,
	reset_avail = reset_avail,
	form_value_json = jsonc.stringify(_get_data(c)),
	page_script = 'settings/system.js',
    })

    assert(ok, 'Failed to render template '..t.view..': '..tostring(err))
end

function _sync_time(c, v)
    local success = true
    if v.current_time ~= nil then
	local current_time = os.date('%Y.%m.%d-%H:%M:%S', v.current_time)
	success = os.execute([[date -s '%s']] % current_time) == 0
    end

    return {
    	status = success and 'success' or 'fail',
	message = {
	    current_time = os.date()
	}
    }
end

function sync_time()
    http.prepare_content('application/json')
    local v = http.formvalue()
    http.write_json(_sync_time(nil, v))
end

local function validate_general(v)
    local errs = {}

    if not dt.hostname(v.hostname) then
	errs.hostname = i18n.translate('Invalid hostname')
    end

    if v.ntp_servers ~= nil then
	for _, s in ipairs(v.ntp_servers) do
	    if not dt.hostname(s) then
		errs.ntp_servers = i18n.translate('Invalid NTP server entry')
	    end
	end
    end

    local ok = true
    for _, v in pairs(errs) do
	ok = false
	break
    end

    return ok, errs
end

function _update_general(c, v)
    local ok, errs = validate_general(v)
    if not ok then
	return {
	    status = 'error',
	    message = errs,
	}
    end

    local sys_cfg_name = c:get_first(config, 'system')
    c:set(config, sys_cfg_name, 'hostname', v.hostname)

    local zonename = 'UTC'
    local timezone = nil
    for _, z in ipairs(tz.TZ) do
	if v.zonename == z[1] then
	    zonename = z[1]
	    timezone = z[2]
	    break
	end
    end
    c:set(config, sys_cfg_name, 'zonename', zonename)
    if timezone ~= nil then
	c:set(config, sys_cfg_name, 'timezone', timezone)
    else
	c:delete(config, sys_cfg_name, 'timezone')
    end

    c:set(config, 'ntp', 'enable_server', v.enable_server and '1' or '0')

    c:delete(config, 'ntp', 'server')
    if v.ntp_servers ~= nil then
	c:set_list(config, 'ntp', 'server', v.ntp_servers)
    end

    local success, err = nixio.fs.writefile("/etc/TZ", (timezone ~= nil and timezone or 'UTC') .. "\n")
    if success then
	success = c:commit(config)
    end

    if success then
	luci.sys.hostname(v.hostname)
    	return {
	    status = 'success',
	    apply = config,
	}
    else
    	return {
	    status = 'fail',
	    message = i18n.translate('Failed to save configuration'),
	}
    end
end

function update_general()
    http.prepare_content('application/json')
    local c = uci.cursor()
    local v = http.formvalue()
    http.write_json(_update_general(c, v))
end

function _update_hosts(c, v)
    local success, err = nixio.fs.writefile('/etc/hosts', v.hosts == nil and '' or v.hosts:gsub("\r\n", "\n"))

    return {
	status = success and 'success' or 'fail',
	message = success and '' or i18n.translate('Failed to save changes'),
    }
end

function update_hosts()
    http.prepare_content('application/json')
    local v = http.formvalue()
    http.write_json(_update_hosts(nil, v))
end

local function validate_password(v)
    local errs = {}

    if not luci.sys.user.checkpasswd(conf.main.osuser, v.password) then
	errs.password = i18n.translate('Invalid password')
    else
	if v.password1 == nil or v.password1:match('^%s*$') then
	    errs.password1 = i18n.translate('Please enter new password')
	elseif v.password2 ~= v.password1 then
	    errs.password2 = i18n.translate('Confirm Password does not match New Password')
	end
    end

    local ok = true
    for _, v in pairs(errs) do
	ok = false
	break
    end

    return ok, errs
end

function _change_password(c, v)
    local ok, errs = validate_password(v)
    if not ok then
	return {
	    status = 'error',
	    message = errs,
	}
    end

    if luci.sys.user.setpasswd(conf.main.osuser, v.password1) == 0 then
	return {
	    status = 'success',
	    message = i18n.translate('Password successfully changed.'),
	}
    else
	return {
	    status = 'fail',
	    message = i18n.translate('Failed to change password.'),
	}
    end
end

function change_password()
    http.prepare_content('application/json')
    local v = http.formvalue()
    http.write_json(_change_password(nil, v))
end

function _update_ssh(c, v)
    if v.enable_ssh ~= 'true' then
	luci.sys.call('/etc/init.d/dropbear stop >/dev/null 2>&1')
	luci.sys.init.disable(dropbear)

	return {
	    status = 'success',
	}
    else
	local db_cfg_name = c:get_first(dropbear, 'dropbear')
	luci.sys.init.enable(dropbear)
	c:set(dropbear, db_cfg_name, 'PasswordAuth', v.PasswordAuth == 'on' and 'on' or 'off')
	local success, err = nixio.fs.writefile('/etc/dropbear/authorized_keys', v.ssh_keys == nil and '' or v.ssh_keys:gsub("\r\n", "\n"))
	if success then
	    success = c:commit(dropbear)
	end

	return {
	    status = success and 'success' or 'fail',
	    message = success and '' or i18n.translate('Failed to save changes'),
	    apply = dropbear,
	}
    end
end

function update_ssh()
    http.prepare_content('application/json')
    local c = uci.cursor()
    local v = http.formvalue()
    http.write_json(_update_ssh(c, v))
end

function _backup(c)
    local fp = io.popen('sysupgrade --create-backup - 2>/dev/null', 'r')
    local data = fp:read("*all")
    fp:close()

    return {
	contentType = 'application/x-targz',
	filename = 'backup-%s-%s.tar.gz' % {luci.sys.hostname(), os.date('%Y-%m-%d')},
	content = require "mime".b64(data),
    }
end

function backup()
    local reader = ltn12_popen('sysupgrade --create-backup - 2>/dev/null')
    http.header('Content-Disposition', 'attachment; filename="backup-%s-%s.tar.gz"' % {
	    luci.sys.hostname(), os.date("%Y-%m-%d")})
    http.prepare_content("application/x-targz")
    luci.ltn12.pump.all(reader, http.write)
end

function reset()
    http.prepare_content('application/json')

    put_command({
	type="fork_exec", 
	command="sleep 3;/etc/init.d/uhttpd stop;killall dropbear;sleep 1;mtd -r erase rootfs_data"
    })

    http.write_json({
	status = 'success',
	reload_url = build_url('applyreboot'),
	addr = get_default_ipaddr(),
    })
end

function _restore(c, d, v)
    os.execute("mkdir /tmp/config && cp /etc/config/system /tmp/config/")

    local fp = io.popen('tar -xzC/ >/dev/null 2>&1', "w")
    fp:write(d)
    fp:close()

    return {
	status = 'success',
	reboot = true,
    }
end

function restore()
    local fp, rc
    local tmpf = '/tmp/config-restore.tgz'
    http.setfilehandler(
	function(meta, chunk, eof)
	    if not fp then
		fp = io.open(tmpf, 'w')
		rc = fp
	    end
	    if chunk then rc = fp:write(chunk) end
	    if eof then rc = fp:close() end
	end
    )

    local upload = http.formvalue('archive')
    local status = (rc ~= nil and upload and #upload > 0) and 'success' or 'fail'
    
    if status == 'success' then
	rc = os.execute('tar -xzC/ -f '..tmpf..' >/dev/null 2>&1')
  	status = rc == 0 and 'success' or 'fail'
    end
    nixio.fs.remove(tmpf)

    if status == 'success' then
	put_command({type="reboot"})
    end
    
    local c = uci.cursor()
    local addr = c:get('network', 'lan', 'ipaddr')

    http.prepare_content('application/json')
    http.write_json({
	status = status,
	message = status == 'success' and '' or i18n.translate('Failed to upload file!'),
	reload_url = build_url('applyreboot'),
	addr = addr,
    })
end

local function image_supported()
    return (0 == os.execute(
	". /lib/functions.sh; " ..
	"include /lib/upgrade; " ..
	"platform_check_image %q >/dev/null"
	% image_tmp
    ))
end

local function image_checksum()
    return (luci.sys.exec("md5sum %q" % image_tmp):match("^([^%s]+)"))
end

local function storage_size()
    local size = 0
    if nixio.fs.access("/proc/mtd") then
	for l in io.lines("/proc/mtd") do
	    local d, s, e, n = l:match('^([^%s]+)%s+([^%s]+)%s+([^%s]+)%s+"([^%s]+)"')
	    if n == "linux" or n == "firmware" then
		size = tonumber(s, 16)
		break
	    end
	end
    elseif nixio.fs.access("/proc/partitions") then
	for l in io.lines("/proc/partitions") do
	    local x, y, b, n = l:match('^%s*(%d+)%s+(%d+)%s+([^%s]+)%s+([^%s]+)')
	    if b and n and not n:match('[0-9]') then
		size = tonumber(b) * 1024
		break
	    end
	end
    end
    return size
end

local function get_default_ipaddr()
    ipaddr = util.exec("sed -n s'/.*lan) ipad=.*\"\\(.*\\)\"}.*/\\1/p' /bin/config_generate")
    return ipaddr and ipaddr:trim() or "192.168.1.1"
end

function upload_image()
    local fp, rc
    http.setfilehandler(
	function(meta, chunk, eof)
	    if not fp then
		fp = io.open(image_tmp, "w")
		rc = fp
	    end
	    if chunk then rc = fp:write(chunk) end
	    if eof then rc = fp:close() end
	end
    )

    local code
    local keep = http.formvalue('keep')
    local md5 = http.formvalue('md5')

    if rc == nil then
	nixio.fs.unlink(image_tmp)
	http.prepare_content('application/json')
	http.write_json({
	    status = 'fail',
	    message = i18n.translate('Failed to upload image file.'),
	})
	return
    end

    local storage = storage_size()

    if not image_supported() then
	code = 'unsupported'
    elseif storage > 0 and nixio.fs.stat(image_tmp).size > storage then
	code = 'nospace'
    elseif md5 ~= nil and #md5 == 32 and md5:match('^[0-9a-fA-F]*$') then
	local realmd5 = image_checksum()
	code = realmd5:lower() == md5:lower() and 'md5ok' or 'md5fail'
    else
	code = 'md5unchecked'
    end

    http.prepare_content('application/json')
    http.write_json({
	status = 'success',
	code = code,
	keep = keep,
    })
end

function upgrade()
    http.prepare_content('application/json')
    
    local fail = not image_supported()
    if not fail then
	local storage = storage_size()
	fail = storage > 0 and nixio.fs.stat(image_tmp).size > storage
    end

    if fail then
	nixio.fs.unlink(image_tmp)
	nixio.fs.unlink(image_sz)
	http.write_json({
	    status = 'fail',
	    message = i18n.translate('Upgrade image file corrupted.'),
	})
	return
    end

    local keep = http.formvalue('keep') == '1' and '' or '-n'
    put_command({
	type="fork_exec", 
	command="sleep 3;killall dropbear uhttpd;sleep 1;/sbin/sysupgrade %s %q" % {keep, image_tmp}
    })

    http.write_json({
	status = 'success',
	reload_url = build_url('applyreboot'),
	addr = #keep > 0 and get_default_ipaddr() or '',
    })
end

function cancel_upgrade()
    nixio.fs.unlink(image_tmp)
    nixio.fs.unlink(image_sz)
    http.prepare_content('application/json')
    http.write_json({
	status = 'success',
    })
end
