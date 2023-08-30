-- Copyright (C) 2023 pcwrt.com
-- Licensed to the public under the Apache License 2.0.

local http = require "luci.http"
local tz = require "luci.sys.zoneinfo"

module("luci.pccontroller.timezone", package.seeall)

need_authentication = false

function get_timezones(v)
    local tzs = {}

    -- Return all timezones
    if v == nil or v.tz_offset == nil then
	tzs[1] = 'UTC'
	for _, z in ipairs(tz.TZ) do
	   tzs[#tzs+1] = z[1]
	end

	return tzs
    end

    -- Return compatible timezones
    if v.tz_offset == '0' then
	tzs[1] = 'UTC'
    end

    for _, z in ipairs(tz.TZ) do
	local zn, offset, dst = z[2]:match('^(<.*>)([%d:-]+)([^,]*)')
	if not zn then
	    zn, offset, dst = z[2]:match('^([^%d-]+)([%d:-]+)([^,]*)')
	end

	local s, h, m = offset:match('(-?)(%d+):(%d+)')
	if s == nil then
	    s, h = offset:match('(-?)(%d+)')
	    m = 0
	end

	offset = 60*tonumber(h)+tonumber(m)
	if s == '-' then
	    offset = -offset
	end

	if offset == tonumber(v.tz_offset) then
	    if (v.dst == 'true' and #dst > 0) or 
	       (v.dst ~= 'true' and #dst == 0) then
		tzs[#tzs+1] = z[1]
	    end
	end
    end

    return tzs
end

function fetch_timezones()
    http.prepare_content('application/json')
    local v = http.formvalue()
    local tzs = get_timezones(v)

    http.write_json({
	status = 'success',
	data = tzs,
    })
end
