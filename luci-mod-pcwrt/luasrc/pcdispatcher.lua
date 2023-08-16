--- LuCI web dispatcher.
require "luci.pcutil"
require "luci.tools.arp"
require "luci.version"
require "luci.xml"
local fs = require "nixio.fs"
local sys = require "luci.sys"
local util = require "luci.util"
local http = require "luci.http"
local nixio = require "nixio", require "nixio.util"

module("luci.pcdispatcher", package.seeall)
context = util.threadlocal()
uci = require "luci.pcuci"
i18n = require "luci.i18n"

function ltn12_popen(command)
	local fdi, fdo = nixio.pipe()
	local pid = nixio.fork()

	if pid > 0 then
		fdo:close()
		local close
		return function()
			local buffer = fdi:read(2048)
			local wpid, stat = nixio.waitpid(pid, "nohang")
			if not close and wpid and stat == "exited" then
				close = true
			end

			if buffer and #buffer > 0 then
				return buffer
			elseif close then
				fdi:close()
				return nil
			end
		end
	elseif pid == 0 then
		nixio.dup(fdo, nixio.stdout)
		fdi:close()
		fdo:close()
		nixio.exec("/bin/sh", "-c", command)
	end
end

--- Build the URL relative to the server webroot from given virtual path.
-- @param ...	Virtual path
-- @return 		Relative URL
function build_url(...)
	local path = {...}
	local url = { http.getenv("SCRIPT_NAME") or "" }

	local k, v
	for k, v in pairs(context.urltoken) do
		url[#url+1] = "/;"
		url[#url+1] = http.urlencode(k)
		url[#url+1] = "="
		url[#url+1] = http.urlencode(v)
	end

	local p
	for _, p in ipairs(path) do
		if p:match("^[a-zA-Z0-9_%-%.%%/,;]+$") then
			url[#url+1] = "/"
			url[#url+1] = p
		end
	end

	return table.concat(url, "")
end

function build_cookie_path(...)
	local path = {...}
	local url = { http.getenv("SCRIPT_NAME") or "" }

	local p
	for _, p in ipairs(path) do
		if p:match("^[a-zA-Z0-9_%-%.%%/,;]+$") then
			url[#url+1] = "/"
			url[#url+1] = p
		end
	end

	return table.concat(url, "")
end

function get_display_name(controller)
    if type(controller.display_name) == 'function' then
	return controller.display_name()
    end

    return controller.display_name
end

function generate_breadcrumbs()
    local ctx = context
    
    if ctx.path[#ctx.path] == 'index' then
	table.remove(ctx.path)
    end

    local bc = {}

    for i = 1, #ctx.path do
	if i == #ctx.path then
	    bc[#bc+1] = {
		display_name = ctx.current_name,
	    }
	else
	    local module_name = 'luci.pccontroller.'..table.concat(ctx.path, ".", 1, i)
	    local ok, controller = pcall(require, module_name)
	    if not ok then
		ok, controller = pcall(require, module_name .. '.index')
	    end
	    if ok and type(controller) == 'table' then
		bc[#bc+1] = {
		    url = build_url(unpack(ctx.path, 1, i)),
		    display_name = get_display_name(controller)
		}
	    end
	end
    end

    return bc
end

--- Send a 404 error code and render the "error404" template if available.
-- @param message	Custom error message (optional)
-- @return			false
function error404(message)
	luci.http.status(404, "Not Found")
	message = message or "Not Found"

	require("luci.template")
	if not luci.util.copcall(luci.template.render, "error404") then
		luci.http.prepare_content("text/plain")
		luci.http.write(message)
	end
	return false
end

--- Send a 500 error code and render the "error500" template if available.
-- @param message	Custom error message (optional)#
-- @return			false
function error500(message)
	luci.util.perror(message)
	if not context.template_header_sent then
		luci.http.status(500, "Internal Server Error")
		luci.http.prepare_content("text/plain")
		luci.http.write(message)
	else
		require("luci.template")
		if not luci.util.copcall(luci.template.render, "error500", {message=message}) then
			luci.http.prepare_content("text/plain")
			luci.http.write(message)
		end
	end
	return false
end

local _get_sdat = function()
    local sess = luci.http.getcookie("sysauth")
    sess = sess and sess:match("^[a-f0-9]*$")
    return (util.ubus("session", "get", {ubus_rpc_session=sess}) or {}).values
end

local _is_authenticated = function()
    local ctx = context
    local sdat = _get_sdat()
    return sdat ~= nil and sdat.user and ctx.urltoken.stok == sdat.token
end

local _is_acl_allowed = function()
    local mac = nil
    local uci = require "luci.pcuci"
    local c = uci.cursor_state()
    local env = sys.getenv()

    local ip = tostring(env.REMOTE_ADDR)
    if not ip then return false end

    local ipset = get_ipset_sectionname_by_name(c, 'lanips')
    local router_ips = c:get_list('firewall', ipset, 'entry')

    local arp = luci.tools.arp.arptable()
    for _, a in ipairs(arp) do
	if ip == a["IP address"] then
	    mac = a["HW address"]:upper()
	    break
	end
    end

    if mac then
	local net = get_network_for_ip(c, ip)
	if net then
	    local allowed = net.name == 'lan'
	    if not allowed then
		c:foreach('firewall', 'forwarding', function(s)
		    if s.src == net.name and s.dest == 'lan' then
			allowed = true
			return false
		    end
		end)
	    end

	    if not allowed and not string_in_array(ip, router_ips) then
		return false
	    end
	end
    else
	local vpns = {'wg', 'ipsec', 'openvpn'}
	local vpn
	for _, v in ipairs(vpns) do
	    if ip_in_network(ip, c:get_first(v, 'server', 'ipaddr'), c:get_first(v, 'server', 'netmask')) then
		vpn = v
		break
	    end
	end

	if vpn then
	    if vpn == 'ipsec' then
		local s = c:get_first(vpn, 'server')
		if not string_in_array('lan', c:get_list(vpn, s, 'nets')) then
		    return false
		end
	    else
		local has_lan
		local src = vpn == 'openvpn' and 'vpn' or vpn
		c:foreach('firewall', 'forwarding', function(f)
		    if f.src == src and f.dest == 'lan' then
			has_lan = true
			return false
		    end
		end)

		if not has_lan then return false end
	    end
	end
    end

    local acl_cfg_name = c:get_first('uhttpd', 'acl')
    if not acl_cfg_name or c:get('uhttpd', acl_cfg_name, 'enabled') ~= '1' then
	return true
    end

    local user = nil
    if string_in_array(ip, router_ips) then
	user = http.getenv('HTTP_X_USERNAME')
    end

    if not user then
	if mac then
	    c:foreach('dhcp', 'host', function(s)
		for _, hmac in ipairs(s.mac:split(' ')) do
		    if mac == hmac:upper() then
			user = s.name
			return false
		    end
		end
	    end)
	else
	    local vpn_users = load_vpn_users()
	    for _, vuser in ipairs(vpn_users) do
		if vuser.ip == ip then
		    user = vuser.name
		    break
		end
	    end
	end
    end

    if not user then return false end

    local allowed_users = c:get_list('uhttpd', acl_cfg_name, 'user')
    for _, auser in ipairs(allowed_users) do
	if auser:upper() == user:upper() then
	    return true
	end
    end

    return false
end

local _has_password = function()
    if sys.process.info("uid") == 0 
       and sys.user.getuser("root") 
       and not sys.user.getpasswd("root") then
	return false
    else
	return true
    end
end

function login(user, pass, token)
    local ctx = context
    local sdat = nil
    local user_valid

    if _has_password() then
	user_valid = sys.user.checkpasswd(user, pass)
    else
	user_valid = string.is_empty(pass)
    end

    if user_valid then
 	if token ~= nil then
   	    luci.http.header('Set-Cookie', 'token='..token..';path=/;Max-Age=2592000')
    	else
	    luci.http.header('Set-Cookie', 'token=;path=/;Max-Age=0')
      	end
    
	sdat = _get_sdat()
	if not sdat then
	    local ubus_sess = util.ubus("session","create",{timeout=tonumber(luci.pcconfig.sauth.sessiontime)})
	    if ubus_sess then
		sdat = {
		    user = nil,
		    token = nil,
		    session = ubus_sess.ubus_rpc_session,
		}
	    end
	end

	if sdat then
	    sdat.user = user
	    sdat.token = luci.sys.uniqueid(16)
	    util.ubus("session","set",{
		ubus_rpc_session = sdat.session,
		values = sdat,
	    })

	    ctx.urltoken.stok = sdat.token
	    sess = sdat.session
	    luci.http.header('Set-Cookie', 'sysauth='..sess..'; path='..build_cookie_path())
	end
    end

    return sdat
end

function logout()
    local sdat = _get_sdat()
    if sdat ~= nil then
	util.ubus("session", "destroy", {ubus_rpc_session=sdat.session})
	luci.http.header("Set-Cookie", "sysauth=%s; expires=%s; path=%s" % {
		'expired', 'Thu, 01 Jan 1970 01:00:00 GMT', build_cookie_path()
	})
    end
    context.urltoken.stok = nil
end

function save_session_data(key, value)
    local sdat = _get_sdat()
    if sdat ~= nil then
	sdat[key] = value
	util.ubus("session", "set", {
	    ubus_rpc_session = sdat.session,
	    values = sdat,
	})
    end
end

function get_session_data(key)
    local sdat = _get_sdat()
    return sdat ~= nil and sdat[key] or nil
end

function put_command(cmd)
    save_session_data('cmd', cmd)
end

function get_command()
    return get_session_data('cmd')
end

--- Dispatch an HTTP request.
-- @param request	LuCI HTTP Request object
function httpdispatch(request, prefix)
	luci.http.context.request = request

	local r = {}
	context.request = r
	context.urltoken = {}

	local pathinfo = http.urldecode(request:getenv("PATH_INFO") or "", true)

	if prefix then
		for _, node in ipairs(prefix) do
			r[#r+1] = node
		end
	end

	local tokensok = true
	for node in pathinfo:gmatch("[^/]+") do
		local tkey, tval
		if tokensok then
			tkey, tval = node:match(";(%w+)=([a-fA-F0-9]*)")
		end
		if tkey then
			context.urltoken[tkey] = tval
		else
			tokensok = false
			r[#r+1] = node
		end
	end

	local stat, err = util.coxpcall(function()
		dispatch(context.request)
	end, error500)

	luci.http.close()
end

--- Dispatches a LuCI virtual path.
-- @param request	Virtual path
function dispatch(request)
	local ctx = context
	ctx.path = request

	-- anything starts with a _ is private, therefore, not callable from URL
	for _, p in ipairs(ctx.path) do
	    if p:starts('_') then
		http.redirect(build_url())
		return
	    end
	end
	-- END path check

	local conf = require "luci.pcconfig"
	assert(conf.main,
		"/etc/config/pcwrt seems to be corrupt, unable to find section 'main'")

	local lang = conf.main.lang or "auto"
	if lang == "auto" then
		local aclang = http.getenv("HTTP_ACCEPT_LANGUAGE") or ""
		for lpat in aclang:gmatch("[%w-]+") do
			lpat = lpat and lpat:lower():gsub("-", "_")
			if conf.languages[lpat] then
				lang = lpat
				break
			end
		end
	end
	require "luci.i18n".setlanguage(lang)

	-- Init template engine
	local tpl = require("luci.template")
	local media = luci.pcconfig.main.mediaurlbase

	local function _ifattr(cond, key, val)
	    if cond then
		local env = getfenv(3)
		local scope = (type(env.self) == "table") and env.self
		return string.format(
			' %s="%s"', tostring(key),
			luci.xml.pcdata(tostring( val
			 or (type(env[key]) ~= "function" and env[key])
			 or (scope and type(scope[key]) ~= "function" and scope[key])
			 or "" ))
		)
		else
			return ''
	    end
	end

	tpl.context.viewns = setmetatable({
		   write       = luci.http.write;
		   include     = function(name) name=setfenv(assert(loadstring('return '.. name)), getfenv(2))() tpl.Template(name):render(getfenv(2)) end;
		   translate   = i18n.translate;
		   translatef  = i18n.translatef;
		   export      = function(k, v) if tpl.context.viewns[k] == nil then tpl.context.viewns[k] = v end end;
		   striptags   = util.striptags;
		   pcdata      = luci.xml.pcdata;
		   media       = media;
		   section     = #ctx.path >= 1 and ctx.path[1] or '';
		   theme       = fs.basename(media);
		   resource    = luci.pcconfig.main.resourcebase;
		   ifattr      = function(...) return _ifattr(...) end;
		   attr        = function(...) return _ifattr(true, ...) end;
	}, {__index=function(table, key)
		if key == "pccontroller" then
			return build_url()
		elseif key == "REQUEST_URI" then
			return build_url(unpack(ctx.path))
		else
			return rawget(luci.pcdispatcher, key) or rawget(table, key) or _G[key]
		end
	end})

	local ok, controller, err
	local module_name = table.concat(ctx.path, '.', 1, #ctx.path - 1) 
	local func_name = ctx.path[#ctx.path]
	
	if (module_name:len() > 0) then
	    module_name = 'luci.pccontroller.'..module_name
	    ok, controller = pcall(require, module_name)
	else
	    module_name = 'luci.pccontroller'
	    ok = false
	end
	
	if (not ok or not controller[func_name]) and func_name then
	    module_name = module_name .. '.' .. func_name
	    func_name = 'index'
	    ok, controller = pcall(require, module_name)
	end

	if not ok or not controller[func_name] then
	    module_name = module_name .. '.index'
	    func_name = 'index'
	    ok, controller = pcall(require, module_name)
	end

	if (not (ok and type(controller) == 'table')) then
	    http.prepare_content('text/plain')
	    http.write('File not found')
	    return
	end

	if not _has_password() then
	    local redirect = false
	    if not _is_authenticated() then
		local sdat = _get_sdat()
		if not sdat then
		    sdat = login(conf.main.osuser, nil)
		end
		ctx.urltoken.stok = sdat.token
		redirect = true
	    end

	    if not redirect then
		redirect = controller.need_authentication ~= false and module_name ~= 'luci.pccontroller.setup'
	    end

	    if redirect then http.redirect(build_url('setup')) return end
	end

	setmetatable(controller, {__index=luci.pcdispatcher})

	ctx.current_name = get_display_name(controller)

	local acl_allowed = _is_acl_allowed()
	if not acl_allowed and not controller.anon_access then
	    http.redirect(build_url('anon'))
	elseif controller.need_authentication == false or _is_authenticated() then
	    ok, err = util.copcall(controller[func_name])
	else
	    local accept = http.getenv('HTTP_ACCEPT')
	    if http.getenv('HTTP_X_REQUESTED_WITH') == 'XMLHttpRequest' or 
	       (accept ~= nil and accept:match('application/json')) then
		http.prepare_content('application/json')
		http.write_json({
		    status = 'login'
		})
	    else
		http.redirect(build_url('login'))
	    end
	end
	assert(ok, "Failed to execute controller function: " .. tostring(err))
end

local _template = function(self, ...)
	require "luci.template".render(self.view, ...)
end

--- Create a template render dispatching target.
-- @param	name	Template to be rendered
function template(name)
	return {type = "template", view = name, target = _template}
end

--- List all controller modules under a directory
-- @param dir Parent dir 
function render_controller_index(dir, scope)
    if not scope then
	scope = {}
    end

    local mods = {}
    for f in (fs.glob(dir..'/*.lua')) do
	if not f:ends('index.lua') then
	    mods[#mods+1] = f
	end
    end

    for f in (fs.glob(dir..'/*/index.lua')) do
	mods[#mods+1] = f
    end

    local base_dir = luci.util.libpath() .. '/pccontroller'
    local c = {}
    for i, m in ipairs(mods) do
	local module_name = 'luci.pccontroller'..m:sub(#base_dir+1,#m-4):gsub('/', '.')
	local ok, mod = pcall(require, module_name)
	if ok and type(mod) == 'table' and mod.ordering ~= nil and get_display_name(mod) then
	    mod.name = module_name:ends('index') and m:sub(#base_dir+2,#m-10) or m:sub(#base_dir+2,#m-4)
	    c[#c+1] = mod
	end
    end

    table.sort(c, function(a, b) return a.ordering < b.ordering end)

    scope.modules = c

    local t = template("index")
    local ok, err = util.copcall(t.target, t, scope)

    assert(ok, 'Failed to render template '.. t.view .. ': ' ..tostring(err))
end

--- Access the luci.i18n translate() api.
-- @class  function
-- @name   translate
-- @param  text    Text to translate
translate = i18n.translate

--- No-op function used to mark translation entries for menu labels.
-- This function does not actually translate the given argument but
-- is used by build/i18n-scan.pl to find translatable entries.
function _(text)
	return text
end
