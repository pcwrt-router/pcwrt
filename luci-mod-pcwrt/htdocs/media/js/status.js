/*
 * Copyright (C) 2023 pcwrt.com
 * Licensed to the public under the Apache License 2.0.
 */

String.prototype.format = function() {
	if (!RegExp)
		return;

	var html_esc = [/&/g, '&#38;', /"/g, '&#34;', /'/g, '&#39;', /</g, '&#60;', />/g, '&#62;'];
	var quot_esc = [/"/g, '&#34;', /'/g, '&#39;'];

	function esc(s, r) {
		for( var i = 0; i < r.length; i += 2 )
			s = s.replace(r[i], r[i+1]);
		return s;
	}

	var str = this;
	var out = '';
	var re = /^(([^%]*)%('.|0|\x20)?(-)?(\d+)?(\.\d+)?(%|b|c|d|u|f|o|s|x|X|q|h|j|t|m))/;
	var a = b = [], numSubstitutions = 0, numMatches = 0;

	while( a = re.exec(str) )
	{
		var m = a[1];
		var leftpart = a[2], pPad = a[3], pJustify = a[4], pMinLength = a[5];
		var pPrecision = a[6], pType = a[7];

		numMatches++;

		if (pType == '%')
		{
			subst = '%';
		}
		else
		{
			if (numSubstitutions < arguments.length)
			{
				var param = arguments[numSubstitutions++];

				var pad = '';
				if (pPad && pPad.substr(0,1) == "'")
					pad = leftpart.substr(1,1);
				else if (pPad)
					pad = pPad;

				var justifyRight = true;
				if (pJustify && pJustify === "-")
					justifyRight = false;

				var minLength = -1;
				if (pMinLength)
					minLength = parseInt(pMinLength);

				var precision = -1;
				if (pPrecision && pType == 'f')
					precision = parseInt(pPrecision.substring(1));

				var subst = param;

				switch(pType)
				{
					case 'b':
						subst = (parseInt(param) || 0).toString(2);
						break;

					case 'c':
						subst = String.fromCharCode(parseInt(param) || 0);
						break;

					case 'd':
						subst = (parseInt(param) || 0);
						break;

					case 'u':
						subst = Math.abs(parseInt(param) || 0);
						break;

					case 'f':
						subst = (precision > -1)
							? ((parseFloat(param) || 0.0)).toFixed(precision)
							: (parseFloat(param) || 0.0);
						break;

					case 'o':
						subst = (parseInt(param) || 0).toString(8);
						break;

					case 's':
						subst = param;
						break;

					case 'x':
						subst = ('' + (parseInt(param) || 0).toString(16)).toLowerCase();
						break;

					case 'X':
						subst = ('' + (parseInt(param) || 0).toString(16)).toUpperCase();
						break;

					case 'h':
						subst = esc(param, html_esc);
						break;

					case 'q':
						subst = esc(param, quot_esc);
						break;

					case 'j':
						subst = String.serialize(param);
						break;

					case 't':
						var td = 0;
						var th = 0;
						var tm = 0;
						var ts = (param || 0);

						if (ts > 60) {
							tm = Math.floor(ts / 60);
							ts = (ts % 60);
						}

						if (tm > 60) {
							th = Math.floor(tm / 60);
							tm = (tm % 60);
						}

						if (th > 24) {
							td = Math.floor(th / 24);
							th = (th % 24);
						}

						subst = (td > 0)
							? String.format('%dd %dh %dm %ds', td, th, tm, ts)
							: String.format('%dh %dm %ds', th, tm, ts);

						break;

					case 'm':
						var mf = pMinLength ? parseInt(pMinLength) : 1000;
						var pr = pPrecision ? Math.floor(10*parseFloat('0'+pPrecision)) : 2;

						var i = 0;
						var val = parseFloat(param || 0);
						var units = [ '', 'K', 'M', 'G', 'T', 'P', 'E' ];

						for (i = 0; (i < units.length) && (val > mf); i++)
							val /= mf;

						subst = val.toFixed(pr) + ' ' + units[i];
						break;
				}
			}
		}

		out += leftpart + subst;
		str = str.substr(m.length);
	}

	return out + str;
}

String.format = function()
{
	var a = [ ];
	for (var i = 1; i < arguments.length; i++)
		a.push(arguments[i]);
	return ''.format.apply(arguments[0], a);
}

function showHosts() {
    $('#assocs tr:gt(0)').remove();
    $.each(fv.assocs, function(i, v) {
	if (v.complete) {
	    $('#assocs').append(String.format('<tr><td><a class="%s" href="#">%s</a></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>',
		    v.ip_assign, v.hostname, v.ipaddr, v.mac, v.net, v.signal
	    ));
	}
    });
}

function refreshHosts() {
    pcwrt.submit_form($('#refresh-hosts-form'), [], function(r) {
	if (r.status != 'success') {
	    return;
	}

	fv.netaddrs = r.data.netaddrs;
	fv.assocs = r.data.assocs;
	fv.assocs.sort(function(a, b) {return (""+a.hostname).toUpperCase() > (""+b.hostname).toUpperCase()?1:-1;});
	showHosts();
	updateIncompleteIps();
    }, null, false, window.msgs.refresh_hosts);
}

function updateIncompleteIps() {
    var n = 0;
    $.each(fv.netaddrs, function(i, a) {
	var ips = [];
	$.each(fv.assocs, function(j, h) {
	    if (is_ip_on_network(h.ipaddr, a.ip, a.mask) && !h.complete) {
		ips.push(h.ipaddr);
	    }
	});

	if (ips.length > 0) {
	    if (n == 0) {
		$('#refresh-hosts').unbind('click').startRotate();
	    }
	    n++;
	    var data = [];
	    data.push({	name: 'iface', value: a.name });
	    data.push({	name: 'ips', value: ips });
	    pcwrt.submit_form($('#get-ip-status-form'), data, function(r) {
		$.each(fv.assocs, function(j, h) {
		    if (r.data.ips[h.ipaddr]) {
			h.complete = true;
		    }
		});

		n--;
		if (n == 0) {
		    $('#refresh-hosts').stopRotate().on('click', function (e) {
			e.preventDefault();
			refreshHosts();
		    });
		    showHosts();
		}
	    }, "application/x-www-form-urlencoded", true);
	}
    });

    if (n == 0) {
	$('#refresh-hosts').on('click', function (e) {
	    e.preventDefault();
	    refreshHosts();
	});
    }
}

$(function() {
    $('#hostname').on('keypress', function() {
	$(this).parent().removeClass('has-error');
	$(this).siblings('.form-control-error').remove();
    });

    $('#assocs').on('click', 'a', function(e) {
	e.preventDefault();
	$('#ip').val($(this).parent().next().text());
	$('#mac').val($(this).parent().next().next().text());
	$('#hostname').val($(this).text())
	.siblings('.form-control-error').remove()
	.end().parent().removeClass('has-error');
	$('#hostname-modal').data('mac', $(this).parent().next().next().text()).modal('show');
    });

    $('#hostname-modal button[type=submit]').on('click', function(e) {
	e.preventDefault();
	var $form = $(this).parents('form');
	pcwrt.submit_form($form, $form.serialize(), function(r) {
	    var mac = $('#hostname-modal').data('mac');
	    $('#assocs tr:gt(0) a').each(function() {
		if ($(this).parent().next().next().text() == mac) {
		    $(this).text($('#hostname').val()).removeClass('dynamic').addClass('static');
		}
	    });

	    $.each(fv.assocs, function(i, v) {
		if (v.mac == mac) {
		    v.ip_assign = 'static';
		    v.hostname = $('#hostname').val();
		}
	    });
	    $('#hostname-modal').modal('hide');
	    pcwrt.apply_changes(r.apply);
	});
    });

    $('#localtime').text(fv.localtime);
    $('#uptime').text(String.format('%t', fv.uptime));
    $('#loadavg').text(String.format('%.02f, %.02f, %.02f', fv.loadavg[0], fv.loadavg[1], fv.loadavg[2]));
    var stat = $('#wan-stat tr:first');
    if (fv.wan_stat.up) {
	stat.hide();
	$('#wan-stat tr:eq(1) td:eq(1)').text(fv.wan_stat.proto);
	$('#wan-stat tr:eq(2) td:eq(1)').text(fv.wan_stat.ipaddr);
	$('#wan-stat tr:eq(3) td:eq(1)').text(fv.wan_stat.netmask);
	$('#wan-stat tr:eq(4) td:eq(1)').text(fv.wan_stat.gwaddr);
	if (fv.wan_stat.dns.length > 1) {
	    $('#wan-stat tr:eq(5) td:eq(1)').text(fv.wan_stat.dns[0] +', '+ fv.wan_stat.dns[1]);
	}
	else {
	    $('#wan-stat tr:eq(5) td:eq(1)').text(fv.wan_stat.dns[0]);
	}
	$('#wan-stat tr:eq(6) td:eq(1)').text(String.format('%t', fv.wan_stat.uptime));
	if (fv.wan_stat.macaddr) {
	    $('#wan-stat tr:eq(7) td:eq(1)').text(fv.wan_stat.macaddr);
	}
	else {
	    $('#wan-stat tr:eq(7)').hide();
	}
    }
    else {
	$('td:eq(1)', stat).text('down');
	stat.siblings().hide();
    }

    for (var i = 1; i < fv.wifinets.length; i++) {
	var p = $('#wifi-stat .nav-tabs>li:first').clone();
	p.removeClass('active');
	$('#wifi-stat .nav-tabs').append(p);

	var w = $('#wifi-stat .tab-content>div:first').clone();
	w.removeClass('in active');
	$('#wifi-stat .tab-content').append(w);
    }

    if (fv.wifinets.length > 1) {
	$('#wifi-stat .nav-tabs').show();
    }
    else {
	$('#wifi-stat .tab-content,#wifi-stat .tab-pane').css('padding-top', 0);
    }

    $.each(fv.wifinets, function(i, v) {
	var $tab = $('#wifi-stat')
	.find('.nav-tabs>li:eq('+i+') a')
	.attr('href', '#'+v.band.replace(/[^0-9a-zA-Z]/g, '-') + i)
	.attr('aria-controls', v.band)
	.text(v.band)
	.end()
	.find('.tab-pane:eq('+i+')')
	.attr('id', v.band.replace(/[^0-9a-zA-Z]/g, '-') + i);

	if (v.up) {
	    $('table tr:first td:eq(1)', $tab).text(v.ssid);
	    $('table tr:eq(1) td:eq(1)', $tab).text(v.mode);
	    $('table tr:eq(2) td:eq(1)', $tab).text(String.format('%s (%.03f GHz)', v.channel, v.frequency));
	    $('table tr:eq(3) td:eq(1)', $tab).text(v.encryption);
	}
	else {
	    $('table tr:first td:eq(1)', $tab)
	    .text(String.format('%s (disabled)', v.ssid))
	    .parent().siblings().hide();
	}
    });

    fv.assocs.sort(function(a, b) {return (""+a.hostname).toUpperCase() > (""+b.hostname).toUpperCase()?1:-1;});
    showHosts();
    updateIncompleteIps();
});
