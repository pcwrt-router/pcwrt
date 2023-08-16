local dt = require "luci.cbi.datatypes"
local i18n = require "luci.i18n"

module("luci.pccontroller.settings.internet._dhcp", package.seeall)

function validate(v)
    local errs = {}

    if not string.is_empty(v.hostname) and not dt.hostname(v.hostname) then
	errs.hostname = i18n.translate('Hostname is in invalid format')
    end

    if v.randommac == '1' and (string.ends(v.macrefresh, 'h') or string.ends(v.macrefresh, 'd')) then
	local interval = v.macrefresh:sub(1, -2)
	if string.is_empty(interval) or not dt.integer(interval) then
	    errs.macrefresh = i18n.translate("Please enter a number")
	end
    end

    if v.peerdns ~= nil then
	if v.peerdns ~= '0' then
	    errs.peerdns = i18n.translate('Invalid input')
	else
	    if string.is_empty(v.dns1) then
		errs.dns1 = i18n.translate('Please enter the DNS server address')
	    else
		if not dt.ip4addr(v.dns1) then
		    errs.dns1 = i18n.translate('DNS server address is invalid')
		end
	    end

	    if not string.is_empty(v.dns2) and not dt.ip4addr(v.dns2) then
		errs.dns2 = i18n.translate('Alternative DNS server address is invalid')
	    end
	end
    end

    if v.broadcast ~= nil and v.broadcast ~= '1' then
	v.broadcast = i18n.translate('Invalid input')
    end

    if not string.is_empty(v.macaddr) and not dt.macaddr(v.macaddr) then
	errs.macaddr = i18n.translate('MAC address is invalid')
    end

    if not string.is_empty(v.mtu) and not dt.max(v.mtu, 9200) then
	errs.mtu = i18n.translate('Please enter a number not exceeding 9200')
    end

    local ok = true
    for _, v in pairs(errs) do
	ok = false
	break
    end

    return ok, errs
end
