local http = require "luci.http"
local sys = require "luci.sys"
local util = require "luci.util"

module("luci.pccontroller.reboot", package.seeall)

function _trigger(c, v)
    if v.reboot then
	os.execute("(sleep 10;reboot) >/dev/null 2>&1 &")
    end

    return {
	status = v.reboot and 'success' or 'fail',
	message = v.reboot and '' or 'Failed to schedule reboot.',
	reboot = v.reboot and true or false,
    }
end

function index()
    http.prepare_content('application/json')

    put_command({type="reboot"})

    http.write_json({
    	status = 'success',
	reload_url = build_url('applyreboot'),
    })
end
