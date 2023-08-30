-- Copyright (C) 2023 pcwrt.com
-- Licensed to the public under the Apache License 2.0.

require "luci.pcutil"

module("luci.tools.ini", package.seeall)

local function add_value(tbl, key, value)
    if key == nil or value == nil or value:trim() == '' then
	return
    end

    if tbl[key] == nil then
	tbl[key] = value
    elseif type(tbl[key]) == 'string' then
	tbl[key] = {tbl[key]}
	tbl[key][2] = value
    elseif type(tbl[key]) == 'table' then
	tbl[key][#tbl[key]+1] = value
    end
end

function parse(file)
    assert(type(file) == 'string', 'Parameter "file" must be a string.');
    local f = assert(io.open(file, 'r'), 'Error loading file : ' .. file);

    local section, key, value
    local data = {}

    for l in f:lines() do
	local s = l:match('^%[([^%[%]]+)%]$');
	if s then
	    section = s
	    data[section] = data[section] or {}
	elseif section ~= nil then
	    local comment = false
	    local v = l:match('^%s') == nil and '' or nil
	    value = v == nil and '' or nil
	    for c in l:gmatch('.') do
		if comment then
		    if value == nil then v = v..c else value = value..c end
		elseif c == '#' then
		    comment = true
		    if value == nil then v = v..c else value = value..c end
		elseif c == '=' then
		    value = value == nil and '' or value..c
		else
		    if value == nil then v = v..c else value = value..c end
		end
	    end

	    if value ~= nil then
		if v ~= nil then key = v:trim() end
		value = value:trim()
		if not comment or value:sub(1,1) ~= '#' then
		    add_value(data[section], key, value)
		end
	    else
		v = v:trim()
		if not comment or v:sub(1,1) ~= '#' then
		    add_value(data[section], key, v)
		end
	    end
	end
    end

    return data
end
