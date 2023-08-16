local http = require "luci.http"
local util = require "luci.util"
local conf = require "luci.pcconfig"
local dt = require "luci.cbi.datatypes"
require "luci.pcutil"

module("luci.pccontroller.applyreboot", package.seeall)

need_authentication = false

function index()
    local cmd = get_command()
    if cmd ~= nil then
	if cmd.type == 'reboot' then
	    os.execute("(sleep 5;reboot) >/dev/null 2>&1 &")
	elseif cmd.type == 'fork_exec' then
	    fork_exec(cmd.command)
	end
	put_command(nil)
    end

    os.execute('sleep 1')

    local t = template("applyreboot")
    local v = http.formvalue();
    local ok, err = util.copcall(t.target, t, {
	addr = dt.ip4addr(v.addr) and v.addr or http.getenv("SERVER_NAME"),
	page = v.page,
    })
    assert(ok, "Failed to render template ".. t.view .. ': ' .. tostring(err))
end
