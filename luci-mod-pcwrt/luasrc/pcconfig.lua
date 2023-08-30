--
-- Copyright (C) 2023 pcwrt.com
-- Licensed to the public under the Apache License 2.0.
--[[
PCWRT - Configuration

Description:
Read configuration values from uci file "pcwrt"

]]--

local util = require "luci.util"
module("luci.pcconfig",
function(m)
    if pcall(require, "luci.pcuci") then
	local config = util.threadlocal()
	setmetatable(m, {
	    __index = function(tbl, key)
		if not config[key] then
		    config[key] = luci.pcuci.cursor():get_all("pcwrt", key)
		end
		return config[key]
	    end
	})
    end
end)
