local dt = require "luci.cbi.datatypes"
local i18n = require "luci.i18n"

module("luci.pccontroller.settings.internet._static", package.seeall)

function validate(v)
    local errs = {}

    if string.is_empty(v.ipaddr) then
	errs.ipaddr = i18n.translate('Please enter the IP address')
    else
	if not dt.ip4addr(v.ipaddr) then
	    errs.ipaddr = i18n.translate('IP address is invalid')
	end
    end

    if string.is_empty(v.netmask) then
	errs.netmask = i18n.translate('Please enter IP netmask')
    else
	if not dt.ip4addr(v.netmask) then
	    errs.netmask = i18n.translate('IP netmask is invalid')
	end
    end

    if string.is_empty(v.gateway) then
	errs.gateway = i18n.translate('Please enter IP gateway')
    else
	if not dt.ip4addr(v.gateway) then
	    errs.gateway = i18n.translate('IP gateway is invalid')
	end
    end

    if string.is_empty(v.dns1) then
	errs.dns1 = i18n.translate('Please enter DNS server address')
    else
	if not dt.ip4addr(v.dns1) then
	    errs.dns1 = i18n.translate('DNS server address is invalid')
	end
    end

    if not string.is_empty(v.dns2) and not dt.ip4addr(v.dns2) then
	errs.dns2 = i18n.translate('Alternative DNS server address is invalid')
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
