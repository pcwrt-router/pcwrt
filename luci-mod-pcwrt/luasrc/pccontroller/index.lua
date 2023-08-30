-- Copyright (C) 2023 pcwrt.com
-- Licensed to the public under the Apache License 2.0.

local http = require "luci.http"
local util = require "luci.util"
local i18n = require "luci.i18n"

module("luci.pccontroller.index", package.seeall)

function index()
    http.redirect(build_url('status'))
end
