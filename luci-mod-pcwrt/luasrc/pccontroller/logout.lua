-- Copyright (C) 2023 pcwrt.com
-- Licensed to the public under the Apache License 2.0.

local http = require "luci.http"
local util = require "luci.util"

module("luci.pccontroller.logout", package.seeall)

function index()
    logout()
    http.header('Set-Cookie', 'sysauth=; path='..build_cookie_path())
    http.redirect(build_url())
end
