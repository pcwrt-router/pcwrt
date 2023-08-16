local dt = require "luci.cbi.datatypes"
local i18n = require "luci.i18n"

module("luci.pccontroller.apps.ddns._dnsomatic_com", package.seeall)

function validate(v)
    local errs = {}

    local cfg = {
    	enabled = "0",
	interface = "wan",
	use_syslog = "1",
	service_name = "dnsomatic.com",
	domain = "myip.opendns.com",
	use_https = "1",
	force_interval = "72",
	force_unit = "hours",
	check_interval = "10",
	check_unit = "minutes",
	retry_interval = "60",
	retry_unit = "seconds",
	ip_source = "web",
	ip_url = "http://myip.dnsomatic.com/",
	cacert = "IGNORE",
	dns_server = "208.67.222.222",
    }

    if string.is_empty(v.username) then
	errs.username = i18n.translate('Please enter username')
    end

    if string.is_empty(v.password) then
	errs.password = i18n.translate('Please enter password')
    end

    if string.is_empty(v.force_interval) or not dt.integer(v.force_interval) then
	errs.force_interval = i18n.translate('Invalid value for force interval')
    end

    if string.is_empty(v.check_interval) or not dt.integer(v.check_interval) then
	errs.check_interval = i18n.translate('Invalid value for check interval')
    end

    local ok = true
    for _, v in pairs(errs) do
	return false, errs
    end

    cfg.username = v.username
    cfg.password = v.password
    cfg.force_interval = v.force_interval
    cfg.force_unit = v.force_unit
    cfg.check_interval = v.check_interval
    cfg.check_unit = v.check_unit

    return cfg
end
