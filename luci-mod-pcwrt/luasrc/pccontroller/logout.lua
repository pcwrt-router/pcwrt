local http = require "luci.http"
local util = require "luci.util"

module("luci.pccontroller.logout", package.seeall)

function index()
    logout()
    http.header('Set-Cookie', 'sysauth=; path='..build_cookie_path())
    http.redirect(build_url())
end
