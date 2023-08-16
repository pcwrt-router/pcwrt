local http = require "luci.http"
local util = require "luci.util"
local nw = require "luci.model.network"
local fs = require "nixio.fs"
local uci = require "luci.pcuci"
local jsonc = require "luci.jsonc"
local i18n = require "luci.i18n"

module("luci.pccontroller.settings.internet", package.seeall)

ordering = 10
function display_name()
    return i18n.translate('Internet')
end

local config = 'network'

local proto_order = {
    dhcp = 1,
    pppoe = 2,
    pppoa = 3,
    pptp = 4,
    l2tp = 5,
    static = 6,
    none = 7,
}

function index()
    local t = template('settings/internet')

    local fields = {}
    local c = uci.cursor()
    local w = c:get_all(config, 'wan')
    for k, v in pairs(w) do
	if not k:starts('.') then
	    if k == 'dns' then
		local cnt = 1
		for s in string.gmatch(v, '%S+') do
		    fields['dns'..cnt] = s
		    cnt = cnt + 1
		end
	    else 
		fields[k] = v
	    end
	end
    end

    if c:get(config, 'wan_dev') ~= nil and c:get(config, 'wan_dev', 'macaddr') ~= nil then
	fields['macaddr'] = c:get(config, 'wan_dev', 'macaddr')
    end

    if not fields.macrefresh then fields.macrefresh = 'o' end

    local protocols = {}
    for i, v in ipairs(nw:get_protocols()) do
	if v:is_installed() and fs.access(util.libpath()..'/view/settings/internet/_'..v:proto()..'.htm') then
	    protocols[#protocols+1] = v
	end
    end

    table.sort(protocols, function(a, b)
	return proto_order[a:proto()] < proto_order[b:proto()]
    end)

    local ok, err = util.copcall(t.target, t, {
	title = i18n.translate('Internet'),
	protocols = protocols,
	form_value_json = jsonc.stringify(fields),
	page_script = 'settings/internet.js',
    })
    assert(ok, 'Failed to render template ' .. t.view .. ': ' .. tostring(err))
end

function update()
    local ok, v

    local fv = http.formvalue()
    local proto = fv.proto

    if proto then
	ok, v = pcall(require, 'luci.pccontroller.settings.internet._'..proto)
    end

    http.prepare_content('application/json')
    if not proto or not ok then
	http.write_json({
	    status = 'error',
	    message = { 
		proto = 'Unrecognized protocol'
	    }
	})
	return
    end

    local ok, errs = v.validate(fv)
    if not ok then
	http.write_json({
	    status = 'error',
	    message = errs
	})
    else
	local c = uci.cursor()
	local proto = c:get(config, 'wan', 'proto')
	local old_macaddr = c:get(config, 'wan', 'macaddr')
	
	if fv.proto ~= proto then
	    local ifname = c:get(config, 'wan', 'ifname')
	    c:delete(config, 'wan')
	    c:section(config, 'interface', 'wan')
	    c:set(config, 'wan', 'ifname', ifname)
	end

	local dns = {}
	for k, v in pairs(fv) do
	    if k == 'dns1' then
		dns[1] = v
	    else
		if k == 'dns2' then
		    dns[2] = v
		else
		    c:set(config, 'wan', k, v)
		end
	    end
	end

	if fv.peerdns == '0' and #dns > 0 then
	    c:set(config, 'wan', 'dns', table.concat(dns, ' '))
	else
	    c:delete(config, 'wan', 'peerdns')
	    c:delete(config, 'wan', 'dns')
	end

	local new_macaddr
	if fv.macaddr ~= nil and #fv.macaddr > 0 then
	    new_macaddr = fv.macaddr
	else -- set to default MAC
	    local mac = get_lan_mac()
	    if mac ~= nil then
		local fh = mac:gsub(':', ''):sub(1, 6)
		local sh = mac:gsub(':', ''):sub(7)
		if sh == 'FFFFFF' then
		    sh = '000000'
		    if fh == 'FFFFFF' then
			fh = '000000'
		    else
			fh = string.format("%06X", tonumber(fh, 16) + 1)
		    end
		else
		    sh = string.format("%06X", tonumber(sh, 16) + 1)
		end
		mac = fh .. sh
		new_macaddr = mac:gsub('(..)', '%1:'):sub(1, -2)
	    end
	end

	if new_macaddr ~= nil and new_macaddr ~= old_macaddr then
	    c:set(config, 'wan', 'macaddr', new_macaddr)
	    if c:get(config, 'wan_dev') ~= nil then
		c:set(config, 'wan_dev', 'macaddr', new_macaddr)
	    end
	end

	local success = c:commit(config)
	if success then
	    put_command({
		type="fork_exec",
		command="sleep 3;/sbin/luci-restart network >/dev/null 2>&1",
	    })

	    http.write_json({
		status = 'success',
		reload_url = build_url('applyreboot'),
		addr = http.getenv("SERVER_NAME"),
	    })
	else
	    http.write_json({
		status = 'fail',
		message = i18n.translate('Failed to save configuration'),
		apply = '',
	    })
	end
    end
end
