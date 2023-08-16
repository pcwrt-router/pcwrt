local http = require "luci.http"
local util = require "luci.util"
local uci = require "luci.pcuci"
local i18n = require "luci.i18n"

module("luci.pccontroller.apply", package.seeall)

function index()
    http.prepare_content('application/json')

    local cursor = uci.cursor();
    local config = http.formvalue('config')
    
    local r = _apply_changes(cursor, config)

    http.write_json(r)
end

function _apply_changes(cursor, config)
    local ok = true

    if config ~= nil then
	local cfg = {}
	if type(config) == 'table' then
	    cfg = config
	elseif config:match('%S+') then
	    for c in config:gmatch('%S+') do
		cfg[#cfg+1] = c
	    end
	end

	local reloads = get_reload_list(cursor, cfg)
	ok = os.execute("/sbin/luci-restart %s >/dev/null 2>&1" % table.concat(reloads, ' ')) == 0
    end

    return {
    	status = ok and 'success' or 'fail',
	message = ok and "" or i18n.translate('Failed to apply changes'),
    }
end
