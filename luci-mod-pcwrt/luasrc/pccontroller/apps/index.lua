-- Copyright (C) 2023 pcwrt.com
-- Licensed to the public under the Apache License 2.0.

local debug = require "debug"
local http = require "luci.http"
local util = require "luci.util"
local i18n = require "luci.i18n"

module("luci.pccontroller.apps.index", package.seeall)

display_name = i18n.translate('Apps')

__file__ = debug.getinfo(1, 'S').source:sub(2)

function index()
    render_controller_index(require "nixio.fs".dirname(__file__), {
	title = i18n.translate('Apps'),
    })
end
