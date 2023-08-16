function add_field_error(f, msg) {
    var p = f.parent();
    if (p.hasClass('input-group')) {
	p = p.parent();
    }
    p.addClass('has-error')
    .append('<p class="form-control-error">'+msg+'</p>');
}

function is_valid_ip(ip, exclude_router_ip) {
    var valid = false;
    $.each(fv.ifaces, function(i, f) {
	if (is_ip_on_network(ip, f.ipaddr, f.netmask, exclude_router_ip)) {
	    valid = true;
	    return false;
	}
    });

    return valid;
}

function get_lan_if() {
    var lan = null;
    $.each(fv.ifaces, function(i, f) {
	if (f.name == 'lan') {
	    lan = f;
	    return false;
	}
    });

    return lan;
}

function update_ifaces() {
    var lan = get_lan_if();
    lan.ipaddr = $('#ipaddr').val();
    lan.netmask =  $('#netmask').val();
    fv.ipaddr = lan.ipaddr;
    fv.netmask = lan.netmask;

    var lanips = lan.ipaddr.split('.');
    $.each(fv.ifaces, function(i, f) {
	if ((f.name != 'lan') && f.ipaddr) {
	    var ips = f.ipaddr.split('.');
	    ips[1] = ips[1] ^ 168 ^ lanips[1];
	    ips[2] = ips[2] ^ 10 ^ lanips[2];
	    f.ipaddr = ips.join('.');
	}
    });
}

function get_new_ip(ip) {
    if (typeof(ip) != 'string' || !pcwrt.is_valid_ipaddr(ip)) {
	return ip;
    }

    var ipaddr = $('#ipaddr').val();
    var netmask =  $('#netmask').val();
    var ipaddrs = ipaddr.split('.');
    var masks = netmask.split('.');
    var ips = ip.split('.');

    var newip = ip;
    $.each(fv.ifaces, function(i, f) {
	if (is_ip_on_network(ip, f.ipaddr, f.netmask)) {
	    if (f.name != 'lan') {
		var ipaddrs2 = f.ipaddr.split('.');
		ipaddrs[0] = ipaddrs2[0];
		ipaddrs[1] = ipaddrs2[1] ^ 168 ^ ipaddrs[1];
		ipaddrs[2] = ipaddrs2[2] ^ 10 ^ ipaddrs[2];
		ipaddrs[3] = ipaddrs2[3];
		masks = f.netmask.split('.');
	    }

	    newip = [ ipaddrs[0] & masks[0], ipaddrs[1] & masks[1], ipaddrs[2] & masks[2], ipaddrs[3] & masks[3] ];
	    var ipmasks = [ 255, 255, 255, 255 ];
	    for (var i = 0; i < 4; i++) {
		ipmasks[i] = (ipmasks[i] ^ masks[i]) & ips[i];
	    }

	    for (var i = 0; i < 4; i++) {
		newip[i] += ipmasks[i];
	    }
	    newip = newip.join('.');

	    return false;
	}
    });

    return newip;
}

function update_leases() {
    $.each(fv.leases, function(i, v) {
	v.ipaddr = get_new_ip(v.ipaddr);
    });
}

function merge_hosts() {
    var l = [];
    $.each(fv.leases, function(i, v) {
	if (!v.idx) {
	    if (v.orig_hostname) {
		v.hostname = v.orig_hostname;
	    }
	    l.push(v);
	}
    });

    fv.leases = l;
    var len = fv.leases.length;
    $('#hosts tr:gt(0)').each(function(idx) {
	var found = false;
	for (var i = 0; i < len; i++) {
	    if (fv.leases[i].macaddr.toUpperCase() == $('td:first', $(this)).text().trim().toUpperCase()) {
		fv.leases[i].orig_hostname = fv.leases[i].hostname;
		fv.leases[i].ipaddr = $('td:eq(1)', $(this)).text().trim();
		fv.leases[i].hostname = $('td:eq(2)', $(this)).text().trim();
		found = true;
		break;
	    }
	}

	if (!found) {
	    fv.leases.push({
		hostname: $('td:eq(2)', $(this)).text().trim(),
		macaddr: $('td:first', $(this)).text().trim(),
		ipaddr: $('td:eq(1)', $(this)).text().trim(),
		idx: idx + 1
	    });
	}
    });
    fv.leases.sort(function(a, b) { return a.hostname.toUpperCase() > b.hostname.toUpperCase()?1:-1; });

    var supdt = [];
    $.each(fv.leases, function(i, v) {
	supdt.push({
	    value: v.hostname,
	    text: v.hostname
	});
    });
    $('#host-name').updatecombo(supdt);

    update_forward_hosts();
}

function update_forward_hosts() {
    var ips = [];
    var ip = get_new_ip(fv.ipaddr) + ' (Router)';
    ips.push({value: ip, text: ip});
    $('#hosts tr:gt(0)').each(function(idx) {
	ip = $('td:eq(1)', $(this)).text().trim();
	if (is_valid_ip(ip, false)) {
	    ip += ' (' + $('td:eq(2)', $(this)).text().trim() + ')';
	    ips.push({value: ip, text: ip});
	}
    });
    $('#forward-dest_ip').updatecombo(ips);
}

function add_options(e, opts) {
    $.each(opts, function(idx, opt) {
	e.append($('<option/>').attr('value', opt.value).text(opt.text));
    });
}

$(function() {
    $('label.required').add_required_mark(window.msgs.required);
    $('label.control-label[data-hint]').init_hint();
    $('input[data-units]').makeunit();

    for (var i = 0; i < fv.vlans.ports.length; i++) {
	var port = fv.vlans.ports[i].port;
	$("#vlan-ports").append('<div class="form-group col-md-3" style="white-space:nowrap;">'
	+ '<label class="control-label" for="port-'+port+'">'+window.msgs.port+' '+(i+1)+'</label>'
	+ '<span class="checkbox" style="margin-left:12px;display:inline"><label><input type="checkbox" name="port-'+port+'-tag" value="1" style="margin-left:-18px;top:0;">'+window.msgs.tagged+'</label></span>'
	+ '<select class="form-control" id="port-'+port+'" name="port-'+port+'"></select></div>');
    }

    for (var i = 0; i < fv.vlans.ports.length; i++) {
	var port = fv.vlans.ports[i].port;
	$('[name=port-'+port+']').data('name', fv.vlans.ports[i].name);
	add_options($('[name=port-'+port+']'), fv.vlans.options);
    }

    $('#vlansrc').html(window.msgs.vlan_source);
    $('select').makecombo();

    for (var i = 0; i < fv.vlans.ports.length; i++) {
	var port = fv.vlans.ports[i].port;
	$('[name=port-'+port+']').val(fv.vlans.ports[i].id);
	$('[name=port-'+port+'-tag').prop('checked', fv.vlans.ports[i].tagged);
    }

    if (fv.dnsrebind != null) {
	$('[name=dnsrebind]').parent().parent().show();
    }

    if (fv.mdns != null) {
	$('[name=mdns]').parent().parent().show();
    }

    if (fv.has_flow_offloading) {
	$('#nat-offloading').show();
    }

    pcwrt.populate_forms();

    $('#vlan-map [name=vlanmap]').each(function(idx, e) {
	$(e).prop('checked', fv.vlanmap[idx] == '1');
    });

    $('#host-name').on('selection.change', function(e, idx) {
	$('#host-mac').val(fv.leases[idx].macaddr);
	$('#host-ip').val(fv.leases[idx].ipaddr);
    });

    $('#forward-name').on('selection.change', function(e, idx) {
	var $row = $('#forwards tr:eq('+(idx+1)+')');
	$('#forward-proto').val($('td:eq(1)', $row).text().trim());
	$('#forward-src_dport').val($('td:eq(2)', $row).text().trim());
	$('#forward-dest_ip').val($('td:eq(3)', $row).text().trim());
	$('#forward-dest_port').val($('td:eq(4)', $row).text().trim());
    });

    fv.hostname_lookup = {};
    $.each(fv.hosts.sort(function(a,b) {
	if (a.name.toUpperCase() == b.name.toUpperCase()) {
	    return a.mac.toUpperCase() > b.mac.toUpperCase() ? 1 : -1;
	}
	else {
	    return a.name.toUpperCase() > b.name.toUpperCase() ? 1 : -1;
	}
    }), function(i, v) {
	fv.hostname_lookup[v.ip] = v.name;
	$('#hosts').append('<tr><td class="mac-addr">'+v.mac+'</td><td>'+v.ip+'</td><td><span class="list-remove pull-right">&nbsp;</span>'+v.name+'</td></tr>');
    });

    $.each(fv.leases, function(i, v) {
	if (!v.hostname) {
	    v.hostname = '*unknown*';
	}
    });

    merge_hosts();

    $.each(fv.routes, function(i, v) {
	$('#routes').append('<tr><td>'+v.interface+'</td><td>'+v.target+'</td><td>'+v.netmask+'</td><td>'+v.gateway+'</td><td><span class="list-remove pull-right">&nbsp;</span>'+v.metric+'</td></tr>');
    });

    $.each(fv.forwards, function(i, v) {
	$('#forwards').append('<tr><td>'+v.name+'</td><td>'+v.proto+'</td><td>'+v.src_dport+'</td><td>'+(fv.hostname_lookup[v.dest_ip]?v.dest_ip+' ('+fv.hostname_lookup[v.dest_ip]+')':v.dest_ip)+'</td><td><span class="list-remove pull-right">&nbsp;</span>'+v.dest_port+'</td></tr>');
    });

    $('#hosts').on('click', 'span.list-remove', function() {
	$(this).parent().parent().remove();
	merge_hosts();
    });

    $('#routes,#forwards').on('click', 'span.list-remove', function() {
	$(this).parent().parent().remove();
    });

    if (/applyreboot/.test(document.referrer)) {
	$('#status-modal .modal-title').text(window.msgs.success);
	$('#status-modal .modal-body p').text(window.msgs.apply_success);
	$('#status-modal').modal('show');
    }

    $('button.add-dialog').on('click', function(e) {
	e.preventDefault();
	var modalId = $(this).parent().prev().find('table').attr('id') + '-modal';
	$('#'+modalId)
	.find('p.form-control-error')
	.parent().removeClass('has-error')
	.end().remove()
	.end()
	.modal('show');
    });

    $('#hosts-modal').on('show.bs.modal', function() {
	$('#host-name,#host-ip,#host-mac').val('');
    });

    $('#forwards-modal').on('show.bs.modal', function() {
	var names = [];
	$('#forwards tr:gt(0)').each(function(idx) {
	    var nm = $('td:first', $(this)).text();
	    names.push({value: nm, text: nm});
	});
	$('#forward-name').updatecombo(names);
	$('input', $(this)).val('');
    });

    $('#hosts-modal button.btn-success').on('click', function(e) {
	e.preventDefault();

	$('#hosts-modal p.form-control-error')
	.parent().removeClass('has-error')
	.end().remove();

	var valid = true;
	var update_row = -1;
	if (!pcwrt.is_valid_macaddr($('#host-mac').val())) {
	    valid = false;
	    add_field_error($('#host-mac'), msgs.invalid_mac);
	}
	else {
	    $('#hosts tr:gt(0)').each(function(idx) {
		if ($('td:first', $(this)).text().trim().toUpperCase() == $('#host-mac').val().toUpperCase()) {
		    update_row = idx + 1;
		    return false;
		}
	    });
	}

	if (!pcwrt.is_valid_ipaddr($('#host-ip').val()) ||
	    !is_valid_ip($('#host-ip').val(), true)) {
	    valid = false;
	    add_field_error($('#host-ip'), msgs.invalid_ip);
	}

	if (!pcwrt.is_valid_hostname($('#host-name').val())) {
	    valid = false;
	    add_field_error($('#host-name'), msgs.invalid_host);
	}

	function update_hosts_table() {
	    if (update_row > 0) {
		$('td', '#hosts tr:eq('+update_row+')').each(function(idx) {
		    if (idx == 1) {
			$(this).text($('#host-ip').val());
		    }
		    else if (idx == 2) {
			$(this).html('<span class="list-remove pull-right">&nbsp;</span>'+$('#host-name').val()+'</td>');
		    }
		});
	    }
	    else {
		$('#hosts').append('<tr><td class="mac-addr">'+$('#host-mac').val()+'</td><td>'+$('#host-ip').val()+'</td><td><span class="list-remove pull-right">&nbsp;</span>'+$('#host-name').val()+'</td></tr>');
	    }

	    merge_hosts();
	    $('#hosts-modal').find('input:visible').val('').end().modal('hide');
	}

	var add_host_mac = -1;
	$('#hosts tr:gt(0)').each(function(idx) {
	    if ($('td:eq(2)', $(this)).text().trim().toUpperCase() == $('#host-name').val().toUpperCase() &&
		$('td:eq(1)', $(this)).text().trim() == $('#host-ip').val() &&
		$('td:first', $(this)).text().trim().toUpperCase() != $('#host-mac').val().toUpperCase()) {
		add_host_mac = idx + 1;
		return false;
	    }
	});

	if (add_host_mac > 0) {
	    var message = 'Do you want to add MAC address ' + $('#host-mac').val() + ' to '
			+ $('#hosts tr:eq('+add_host_mac+') td:eq(2)').text().trim() + '?';
	    pcwrt.confirm_action('Confirmation', message, function() {
		$('#host-name').val($('#hosts tr:eq('+add_host_mac+') td:eq(2)').text().trim());
		update_hosts_table();
	    });
	}
	else {
	    $('#hosts tr:gt(0)').each(function() {
		if ($('td:eq(1)', $(this)).text().trim() == $('#host-ip').val() &&
		    $('td:first', $(this)).text().trim().toUpperCase() != $('#host-mac').val().toUpperCase()) {
		    valid = false;
		    add_field_error($('#host-ip'), msgs.duplicate_ip);
		    return false;
		}
	    });

	    if (valid) {
		update_hosts_table();
	    }
	}
    });

    $('#routes-modal button.btn-success').on('click', function(e) {
	e.preventDefault();

	$('#routes-modal p.form-control-error')
	.parent().removeClass('has-error')
	.end().remove();

	var valid = true;
	$('#route-target,#route-netmask,#route-gateway').each(function() {
	    if (!pcwrt.is_valid_ipaddr($(this).val())) {
		valid = false;
		add_field_error($(this), msgs['invalid_'+$(this).attr('name')]);
	    }
	});

	if (!pcwrt.is_number($('#route-metric').val())) {
	    valid = false;
	    add_field_error($('#route-metric'), msgs.invalid_metric);
	}

	if (valid) {
	    $('#routes').append('<tr><td>'+$('#route-interface').val()+'</td><td>'+$('#route-target').val()+'</td><td>'+$('#route-netmask').val()+'</td><td>'+$('#route-gateway').val()+'</td><td><span class="list-remove pull-right">&nbsp;</span>'+$('#route-metric').val()+'</td></tr>');
	    $('#routes-modal').find('input:visible').val('').end().modal('hide');
	}
    });

    $('#forwards-modal button.btn-success').on('click', function(e) {
	e.preventDefault();

	$('#forwards-modal p.form-control-error')
	.parent().removeClass('has-error')
	.end().remove();

	var valid = true;
	var update_row = -1;

	$('#forwards tr:gt(0)').each(function(idx) {
	    if ($('td:first', $(this)).text().trim() == $('#forward-name').val().trim()) {
		update_row = idx + 1;
		return false;
	    }
	});

	if ($('#forward-proto').val().trim() == '') {
	    valid = false;
	    add_field_error($('#forward-proto'), msgs.missing_proto);
	}

	$('#forward-dest_port,#forward-src_dport').each(function() {
	    if (!pcwrt.is_valid_port($(this).val()) && !pcwrt.is_valid_port_range($(this).val())) {
		valid = false;
		add_field_error($(this), msgs.invalid_port);
	    }
	});

	var dest_ip = $('#forward-dest_ip').val().replace(/\s*\(.*\)/,''); 
	if (!pcwrt.is_valid_ipaddr(dest_ip) || !is_valid_ip(dest_ip, false)) {
	    valid = false;
	    add_field_error($('#forward-dest_ip'), msgs.invalid_ip);
	}

	if (valid) {
	    if (update_row > 0) {
		$('td', '#forwards tr:eq('+update_row+')').each(function(idx) {
		    switch(idx) {
		    case 1:
			$(this).text($('#forward-proto').val());
			break;
		    case 2:
			$(this).text($('#forward-src_dport').val());
			break;
		    case 3:
			$(this).text($('#forward-dest_ip').val());
			break;
		    case 4:
			$(this).html('<span class="list-remove pull-right">&nbsp;</span>'+$('#forward-dest_port').val());
			break;
		    }
		});
	    }
	    else {
		$('#forwards').append('<tr><td>'+$('#forward-name').val()+'</td><td>'+$('#forward-proto').val()+'</td><td>'+$('#forward-src_dport').val()+'</td><td>'+$('#forward-dest_ip').val()+'</td><td><span class="list-remove pull-right">&nbsp;</span>'+$('#forward-dest_port').val()+'</td></tr>');
	    }
	    $('#forwards-modal').find('input:visible').val('').end().modal('hide');
	}
    });

    $('#ipaddr,#netmask').on('change', function(e) {
	$('#hosts tr:gt(0)').each(function() {
	    var ip = $('td:eq(1)', $(this)).text().trim();
	    $('td:eq(1)', $(this)).text(get_new_ip(ip));
	});

	$('#forwards tr:gt(0)').each(function() {
	    var iptxt = $('td:eq(3)', $(this)).text().trim();
	    var ip = iptxt.replace(/\s*\(.*\)/,'');
	    $('td:eq(3)', $(this)).text(iptxt.replace(ip, get_new_ip(ip)));
	});

	update_forward_hosts();
	update_leases();
	update_ifaces();
    });

    $('button[type="submit"]').on('click', function(e) {
	e.preventDefault();
	var $form = $(this).parents('form');
	var data = $form.serializeArray().filter(function(e) { return e.name != 'vlanmap'});

	var vlans = [];
	$('#vlan-ports input[id*=port-]').each(function() {
	    var port = $(this).attr('name').replace('port-','');
	    vlans.push({
		port: port,
		id: $(this).val(),
		name: $('select[name=port-'+port+']').data('name'),
		tagged: $('#vlan-ports input[name='+$(this).prop('id')+'-tag'+']').prop('checked')
	    });
	});

	data.push({
	    name: 'vlans',
	    value: JSON.stringify(vlans)
	});

	$('#vlan-map [name=vlanmap]').each(function(idx, e) {
	    data.push({
		name: 'vlanmap',
		value: $(e).prop('checked') ? '1' : '0'
	    });
	});

	var host_attr = ['mac', 'ip', 'name'];
	var hosts = [];
	$('#hosts tr:gt(0)').each(function() {
	    var r = new Object();
	    $('td', $(this)).each(function(idx) {
		r[host_attr[idx]] = $(this).text().trim();
	    });
	    hosts.push(r);
	});

	data.push({
	    name: 'hosts',
	    value: JSON.stringify(hosts)
	});

	var route_attr = ['interface', 'target', 'netmask', 'gateway', 'metric'];
	var routes = [];
	$('#routes tr:gt(0)').each(function() {
	    var r = new Object();
	    $('td', $(this)).each(function(idx) {
		r[route_attr[idx]] = $(this).text().trim();
	    });
	    routes.push(r);
	});

	data.push({
	    name: 'routes',
	    value: JSON.stringify(routes)
	});

	var forward_attr = ['name', 'proto', 'src_dport', 'dest_ip', 'dest_port'];
	var forwards = [];
	$('#forwards tr:gt(0)').each(function() {
	    var r = new Object();
	    $('td', $(this)).each(function(idx) {
		if (idx == 3) {
		    r[forward_attr[idx]] = $(this).text().trim().replace(/\s*\(.*\)/,'');
		}
		else {
		    r[forward_attr[idx]] = $(this).text().trim();
		}
	    });
	    forwards.push(r);
	});

	data.push({
	    name: 'forwards',
	    value: JSON.stringify(forwards)
	});

	pcwrt.submit_form($form, data, function(r) {
	    if (r.reboot) {
		$('#spinner strong').html(window.msgs.rebooting);
		pcwrt.showOverlay($('#spinner'));
		$('<iframe/>', {src: r.reload_url+'?addr='+r.addr}).appendTo('#reloader');
	    }
	    else if (r.apply == null) {
		pcwrt.showOverlay($('#spinner'));
		$('<iframe/>', {src: r.reload_url+'?addr='+r.addr+'&page=settings%2Fnetwork'}).appendTo('#reloader');
	    }
	    else {
		fv.ifaces = r.ifaces;
		$('#hosts tr:gt(0)').each(function(idx) {
		    var ip = $('td:eq(1)', $(this)).text().trim();
		    if (!is_valid_ip(ip, true)) {
			$(this).remove();
		    }
		});

		$('#forwards tr:gt(0)').each(function(idx) {
		    var ip = $('td:eq(3)', $(this)).text().trim().replace(/\s*\(.*\)/,'');
		    if (!is_valid_ip(ip, false)) {
			$(this).remove();
		    }
		});
		pcwrt.apply_changes(r.apply);
	    }
	});
    });
});
