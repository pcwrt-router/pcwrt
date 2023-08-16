local dt = require "luci.cbi.datatypes"
local i18n = require "luci.i18n"

module("luci.pccontroller.settings.internet._pppoa", package.seeall)

function validate(v)
    local errs = {}

    if string.is_empty(v.encaps) or (v.encaps ~= 'llc' and v.encaps ~= 'vc') then
	errs.encaps = i18n.translate('Invalid value for PPPoA Encapsulation')
    end

    if not string.is_empty(v.vci) and not dt.uinteger(v.vci) then
	errs.vci = i18n.translate('Invalid VCI value')
    end

    if not string.is_empty(v.vpi) and not dt.uinteger(v.vpi) then
	errs.vpi = i18n.translate('Invalid VPI value')
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
