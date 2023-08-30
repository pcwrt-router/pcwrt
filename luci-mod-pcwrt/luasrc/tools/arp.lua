-- Copyright (C) 2023 pcwrt.com
-- Licensed to the public under the Apache License 2.0.

module("luci.tools.arp", package.seeall)

function arptable(callback)
    local fs = require "nixio.fs"
    local arp = (not callback) and {} or nil
    local e, r, v
    if fs.access("/proc/net/arp") then
	for e in io.lines("/proc/net/arp") do
	    local r = { }, v
	    for v in e:gmatch("%S+") do
		r[#r+1] = v
	    end

	    if r[1] ~= "IP" then
		local x = {
		    ["IP address"] = r[1],
		    ["HW type"]    = r[2],
		    ["Flags"]      = r[3],
		    ["HW address"] = r[4],
		    ["Mask"]       = r[5],
		    ["Device"]     = r[6]
		}

		if callback then
		    callback(x)
		else
		    arp = arp or { }
		    arp[#arp+1] = x
		end
	    end
	end
    end
    return arp
end
