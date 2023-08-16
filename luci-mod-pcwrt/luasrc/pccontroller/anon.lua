local http = require "luci.http"
local jsonc = require "luci.jsonc"
local sys = require "luci.sys"
local util = require "luci.util"

module("luci.pccontroller.anon", package.seeall)

need_authentication = false
anon_access = true

function index()
    local t = template("anon")
    local ok, err = util.copcall(t.target, t, {
	title = i18n.translate('Home'),
	no_banner = true,
    })
end
