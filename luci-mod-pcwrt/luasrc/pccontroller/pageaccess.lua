-- Copyright (C) 2023 pcwrt.com
-- Licensed to the public under the Apache License 2.0.

local http = require "luci.http"
local util = require "luci.util"
local uci = require "luci.pcuci"
local i18n = require "luci.i18n"

module("luci.pccontroller.pageaccess", package.seeall)

need_authentication = false

local config = 'mp'

local function show_page(title, msg)
    local t = template("pageaccess")
    local ok, err = util.copcall(t.target, t, {
	title = title;
	no_banner = true;
	message = msg;
	referer = http.formvalue('url');
    })
    assert(ok, "Failed to render template ".. t.view .. ': ' .. tostring(err)) 
end

function blocked()
    local c = uci.cursor()
    local mpname = c:get_first(config, 'mp')
    show_page(i18n.translate('Page Blocked'), c:get(config, mpname, 'url_blocked') or i18n.translate('The requested URL is blocked on this network.'))
end

function closed()
    local c = uci.cursor()
    local mpname = c:get_first(config, 'mp')
    show_page(i18n.translate('Site Not Available'), c:get(config, mpname, 'site_closed') or i18n.translate('Sorry, the requested site is not available at this time.'))
end

function nopermission()
    show_page(i18n.translate('No Permission'), i18n.translate('You don\'t have permission to access the Internet on this network.'))
end

function paused()
    show_page(i18n.translate('Internet Paused'), i18n.translate('The Internet is paused at this moment.'))
end
