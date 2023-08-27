local http = require "luci.http"
local sys = require "luci.sys"

module("luci.pccontroller.myip", package.seeall)

need_authentication = false
anon_access = true

function index()
    local myip = http.getenv('HTTP_X_FORWARDED_FOR')
    if not myip then
	myip = sys.getenv().REMOTE_ADDR
    end
    http.prepare_content('text/html')
    http.write('<!DOCTYPE html>')
    http.write('<head><title>Device IP Address</title>')
    http.write('<meta http-equiv="X-UA-Compatible" content="IE=edge"></meta>')
    http.write('<meta content=width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=0"></meta>')
    http.write('</head><body><h1 style="font-size:36px;text-align:center;margin-top:50px">')
    http.write(tostring(myip))
    http.write('</h1></body></html>')
end
