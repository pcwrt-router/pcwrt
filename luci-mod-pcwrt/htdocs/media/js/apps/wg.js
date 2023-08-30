/*
 * Copyright (C) 2023 pcwrt.com
 * Licensed to the public under the Apache License 2.0.
 */
function display_disabled() {
    $('#wg-status').text(msgs.disabled)
    .parent().removeClass('alert-success').addClass('alert-danger');
    $('#enable-wg').removeClass('hidden');
    $('#disable-wg').addClass('hidden');
    $('#restart-wg').addClass('hidden');
    $('#wg-settings').slideUp();
}

function disable_wg($form) {
    pcwrt.submit_form($form, JSON.stringify({enabled: '0'}), function(r) {
	display_disabled();
	pcwrt.apply_changes(r.apply);
    });
}

function valid_wg_key(key) {
    return key.trim().length == 44;
}

$('#pubkey').on('change', function(e) {
    $('#privkey').val('');
});

$('#wg-conns').on('click', 'input', function(e) {
    if ($(this).prop('checked')) {
	$(this).parent().parent().siblings().find('input[type=checkbox]').prop('checked', false);
    }
});

$('#reinit-wg').on('click', function(e) {
    e.preventDefault();
    pcwrt.submit_form($('#wg-init'), {}, function(r) {
       $('#publickey').val(r.svrpubkey);
    });
});

$('#peers .btn').on('click', function(e) {
    e.preventDefault();
    $('#add-peer .form-group').removeClass('has-error').find('p.form-control-error').remove();
    $('#add-peer .modal-title').text(window.msgs.add_wg_peer);
    $('#add-peer').data('row', null).modal('show');
    $('[name=vpnout]:first').prop('checked', true);
    $('#privkey').val('');
    $('#pubkey').val('');
    $('#peerip').val('');
    $('#peerdns').val('');
    $('#peername').val('').focus();
});

$('#add-peer .btn-success').on('click', function(e) {
    e.preventDefault();
    $('#add-peer .form-group').removeClass('has-error').find('p.form-control-error').remove();

    if (!/^[a-zA-Z0-9._\-\\\$@%#&]+$/.test($('#peername').val())) {
	$('#peername').after('<p class="form-control-error">'+window.msgs.enter_valid_peer_name+'</p>').parent().addClass('has-error');
	return;
    }

    var $row;
    var row = $('#add-peer').data('row');
    if (row) {
       $row = $('#peers tr:eq('+$('#add-peer').data('row')+')');
       if ($row.length == 0) {
           $row = null;
       }
    }
    
    var err = null;
    $('#peers tr:gt(0)').each(function() {
	if (!$(this).is(':last-child')) {
	    if ($(this).index() != row && $('td:first', $(this)).text().trim() == $('#peername').val()) {
		err = 'duplicate';
	    }
	}
    });

    if (err == 'duplicate') {
        $('#peername').after('<p class="form-control-error">'+window.msgs.peer_name_exists+'</p>').parent().addClass('has-error');
	return;
    }

    if (!valid_wg_key($('#pubkey').val())) {
	$('#pubkey').after('<p class="form-control-error">'+window.msgs.invalid_peer_public_key+'</p>').parent().addClass('has-error');
	return;
    }

    if (!$row) {
	$row = $('<tr><td></td><td></td><td class="text-center"><input type="checkbox" name="guest"></td></tr>');
	$('#peers tr:last').before($row);
    }

    $('td:first', $row).html('<span class="pull-right list-remove" title="Delete peer">&nbsp;</span>'
	    + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>'
	    + '<span class="pull-right glyphicon glyphicon-download-alt control" title="Download WireGuard peer config"></span>'
	    + (pcwrt.is_empty($('#privkey').val()) ? '' : '<span class="pull-right glyphicon glyphicon-qrcode control" title="Download QR code"></span>')
	    +  $('#peername').val());
    $('td:eq(1)', $row).text($('[name=vpnout]:checked').val() == '1' ? window.msgs.vpn : window.msgs.isp);

    $row.data('peername', null);
    $row.data('pubkey', $('#pubkey').val().trim());
    $row.data('privkey', $('#privkey').val().trim());
    $('#add-peer').modal('hide');
});

$('#peers').on('click', '.list-remove', function(e) {
    e.preventDefault();
    $('#peers').data('deletePeer', $(this).parents('tr').index());
    pcwrt.confirm_action(window.msgs.delete_peer_title,
	window.msgs.delete_peer_confirm+' "' + $(this).parent().text().trim() + '"?',
	function() {
	    var idx = $('#peers').data('deletePeer');
	    var cfg = $('#peers tr:eq('+idx+') td:first').text().trim();
	    if (cfg == $('#connect-wg [name=cfg]').val()) {
		$('#connect-wg [name=cfg]').val('');
	    }
	    $('#peers tr:eq('+idx+')').remove();
	}
    );
});

$('#peers').on('click', '.list-edit', function(e) {
    e.preventDefault();
    $('#add-peer .form-group').removeClass('has-error').find('p.form-control-error').remove();
    var $row = $(this).parent().parent();
    var vpnout = $(this).parent().next().text() == window.msgs.vpn;
    if ($row.data('peername')) {
	$('#get-peer-info [name=peername]').val($(this).parent().text().trim());
	pcwrt.fetch_data($('#get-peer-info').attr('action'), { peername: $('#get-peer-info [name=peername]').val() }, function(r) {
	    $('#add-peer [name=peername]').val($('#get-peer-info [name=peername]').val());
	    $('#add-peer [name=privkey]').val(r.privatekey);
	    $('#add-peer [name=pubkey]').val(r.publickey);
	    $('#add-peer [name=peerip]').val(r.ip);
	    $('#add-peer [name=peerdns]').val(r.dns);
	    $row.data('peerip', r.ip);
	    $row.data('peerdns', r.dns);
 	    if (vpnout) {
  		$('[name=vpnout]:eq(1)').prop('checked', true);
   	    }
    	    else {
     		$('[name=vpnout]:eq(0)').prop('checked', true);
      	    }
	    $('#add-peer .modal-title').text(window.msgs.edit_wg_peer);
	    $('#add-peer').data('row', $row.index()).modal('show');
	});
    }
    else {
	$('#add-peer [name=peername]').val($('td:first', $row).text().trim());
	$('#add-peer [name=privkey]').val($row.data('privkey'));
	$('#add-peer [name=pubkey]').val($row.data('pubkey'));
	$('#add-peer [name=peerip]').val($row.data('ip'));
	$('#add-peer [name=peerdns]').val($row.data('dns'));
	$('#add-peer .modal-title').text(window.msgs.edit_wg_peer);
 	if (vpnout) {
  	    $('[name=vpnout]:eq(1)').prop('checked', true);
   	}
    	else {
     	    $('[name=vpnout]:eq(0)').prop('checked', true);
      	}
	$('#add-peer').data('row', $row.index()).modal('show');
    }
});

$('#peers').on('click', '.glyphicon-download-alt', function(e) {
    e.preventDefault();
    if ($(this).parent().parent().data('peername')) {
	$('#password').val('');
	$('#wg-password').data('peername', $(this).parent().parent().data('peername')).modal('show');
    }
    else {
	pcwrt.show_message(msgs.peer_not_saved_title, msgs.peer_not_saved);
    }
});

$('#wg-password .btn-success').on('click', function(e) {
    e.preventDefault();
    $('#wg-password').modal('hide');
    $('#download-peer-conf')
    .find('[name=peername]').val($('#wg-password').data('peername')).end()
    .find('[name=password]').val($('#password').val());
    window.location.href = $('#download-peer-conf').attr('action') + '?' + $('#download-peer-conf').serialize();
});

$('#peers').on('click', '.glyphicon-qrcode', function(e) {
    e.preventDefault();
    var peername = $(this).parent().text().trim();
    if ($(this).parent().parent().data('peername')) {
	$('#show-peer-qr')
	.find('h4').text(window.msgs.scan_qr_code_for + ' ' + peername).end()
	.find('img').remove().end();

	var img = new Image();
	img.onload = function() {
	    $('#show-peer-qr').find('.modal-body').append(img).end().modal('show');
	    pcwrt.hideOverlay();
	}
	$('#download-peer-qr [name=peername]').val(peername);
	img.src = $('#download-peer-qr').attr('action') + '?' + $('#download-peer-qr').serialize();
	$('#spinner strong').text(window.msgs.fetching_qr_code);
	pcwrt.showOverlay($('#spinner'));
    }
    else {
       pcwrt.show_message(msgs.peer_not_saved_title, msgs.peer_not_saved);
    }
});

$('#add-wg-conn').on('click', function(e) {
    e.preventDefault();
    $('#conn-modal')
    .find('.modal-title').text(window.msgs.add_wg_conn_title).end()
    .find('.form-group').removeClass('has-error').end()
    .find('.form-control-error').remove().end()
    .find('input:not([type=radio],[type=checkbox])').val('').end()
    .modal('show');

    var random_port = Math.floor(Math.random() * (65535 - 1024) + 1024);
    $('#cliport').val(random_port);
});

$('#upload-conn-config').on('click', function(e) {
    e.preventDefault();
    $('#conn-config-modal')
    .find('.form-group').removeClass('has-error').end()
    .find('.form-control-error').remove().end()
    .find('input:not([type=radio],[type=checkbox])').val('').end()
    .modal('show');
});

$('#gen-client-key').on('click', function(e) {
    e.preventDefault();
    pcwrt.submit_form($('#client-init'), {}, function(r) {
       $('#cliprivkey').val(r.privatekey);
       $('#clipubkey').val(r.publickey);
    });
});

$('#gen-peer-key').on('click', function(e) {
    e.preventDefault();
    pcwrt.submit_form($('#client-init'), {}, function(r) {
	$('#pubkey').val(r.publickey);
	$('#privkey').val(r.privatekey);
    });
});

$('#conn-config-modal').on('hidden.bs.modal', function (e) {
    $('#conn-modal').modal('hide').modal('show');
});

$('#conn-config-modal form').ajaxForm({
    beforeSubmit: function(formData, jqForm, options) {
	$('#conn-config-modal .form-control-error')
	.parent().removeClass('has-error')
	.end().remove();
    },
    complete: function(xhr) {
	var r = xhr.responseJSON;
	if (r.status == 'success') {
	    $('#svrhost').val(r.serverhost);
	    $('#svrport').val(r.serverport);
	    $('#svrpubkey').val(r.serverpubkey);
	    $('#presharedkey').val(r.presharedkey);
	    $('#cliprivkey').val(r.privatekey);
	    $('#clipubkey').val(r.publickey);
	    $('#cliip').val(r.ip);
	    $('#cliport').val(r.port);
	    $('#clidns').val(r.dns);
	    $('#conn-config-modal').modal('hide');
	}
	else if (r.status == 'error') {
	    if (r.message) {
		if (r.message.wgconfigfile) {
		    $('#wgconfig-group')
		    .addClass('has-error')
		    .append('<p class="form-control-error">'+r.message.wgconfigfile+'</p>');
		}

		if (r.message.decpass) {
		    $('#decpass').parent()
		    .addClass('has-error')
		    .append('<p class="form-control-error">'+r.message.decpass+'</p>');
		}
	    }
	}
	else if (r.status == 'login') {
	    location.reload(true);
	}
	else {
	    $('#status-modal .modal-title').text(window.msgs.oops);
	    $('#status-modal .modal-body p').text(r.message);
	    $('#status-modal').modal('show');
	}
    }
});

$('#conn-modal .btn-success').on('click', function(e) {
    e.preventDefault();
    $('#conn-modal .form-group').removeClass('has-error').find('p').remove();

    var valid = true;
    if (pcwrt.is_empty($('#connname').val())) {
	$('#conn-modal .form-group:first')
	.addClass('has-error')
	.append('<p class="form-control-error">'+window.msgs.empty_conn_name+'</p>');
	valid = false;
    }
    else if (!/^[a-zA-Z0-9._\-\\\$@%#& ]+$/.test($('#connname').val())) {
	$('#conn-modal .form-group:first')
	.addClass('has-error')
	.append('<p class="form-control-error">'+window.msgs.enter_valid_conn_name+'</p>');
	valid = false;
    }
    else {
	$('#wg-conns tr:gt(0)').each(function() {
	    if ($(this).is(':last-child')) {
		return false;
	    }

	    if ($(this).data('oldconnname') == $('#connname').val().trim() && $('#oldconnname').val() != $(this).data('oldconnname')) {
		$('#conn-modal .form-group:first')
		.addClass('has-error')
		.append('<p class="form-control-error">'+window.msgs.duplicate_conn+'</p>');
		valid = false;
		return false;
	    }
	});
    }

    if (!pcwrt.is_valid_hostname($('#svrhost').val().trim()) && !pcwrt.is_valid_ipaddr($('#svrhost').val().trim())) {
	$('#svrhost').parents('.form-group')
	.addClass('has-error')
	.append('<p class="form-control-error">'+window.msgs.invalid_host_name+'</p>');
	valid = false;
    }

    if (!pcwrt.is_valid_port($('#svrport').val().trim())) {
	$('#svrport').parents('.form-group')
	.addClass('has-error')
	.append('<p class="form-control-error">'+window.msgs.invalid_port+'</p>');
	valid = false;
    }

    if (!valid_wg_key($('#svrpubkey').val())) {
	$('#svrpubkey').parents('.form-group')
	.addClass('has-error')
	.append('<p class="form-control-error">'+window.msgs.empty_server_public_key+'</p>');
	valid = false;
    }

    if (!valid_wg_key($('#cliprivkey').val())) {
	$('#cliprivkey').parents('.form-group')
	.addClass('has-error')
	.append('<p class="form-control-error">'+window.msgs.empty_client_private_key+'</p>');
	valid = false;
    }

    if (!pcwrt.is_valid_ipaddr($('#cliip').val())) {
	$('#cliip').parents('.form-group')
	.addClass('has-error')
	.append('<p class="form-control-error">'+window.msgs.invalid_client_ip+'</p>');
	valid = false;
    }

    if (valid) {
	if (pcwrt.is_empty($('#clidns').val())) {
	    valid = false;
	    pcwrt.confirm_action(window.msgs.confirm_default_dns_title, window.msgs.confirm_default_dns, function() {
		$('#clidns').val('1.1.1.1, 1.0.0.1');
		$('#conn-modal .form-group').removeClass('has-error').find('p').remove();
		valid = true;
	    });
	}
	else {
	    var ips = $('#clidns').val().split(/[, ]+/);
	    $.each(ips, function(i, ip) {
		if (!pcwrt.is_valid_ipaddr(ip)) {
		    valid = false;
		    return false;
		}
	    });
	}

	if (valid) {
	    update_wg_conn();
	    $('#conn-modal').modal('hide');
	}
	else {
	    $('#clidns').parents('.form-group')
	    .addClass('has-error')
	    .append('<p class="form-control-error">'+window.msgs.invalid_client_dns+'</p>');
	}
    }
});

$('#conn-config-modal .btn-file:first :file').on('fileselect', function(e, numFiles, label) {
    $('#conn-config-modal [name=wgconfig-name]').val(label);
});

function update_wg_conn() {
    var row;
    $('#wg-conns tr:gt(0)').each(function() {
	if ($(this).is(':last-child')) {
	    return false;
	}

	if ($('#conn-modal input[name=oldconnname]').val() == $(this).data('oldconnname')) {
	    row = $(this);
	    return false;
	}
    });

    if (row) {
	$('td:first', row).html('<span class="glyphicon glyphicon-play pull-right control" title="Start"></span>'
	    + '<span class="pull-right list-remove" title="Remove">&nbsp;</span>'
	    + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>'
	    + '<span class="glyphicon glyphicon-list-alt pull-right logs" title="View log" style="display:none"></span>'
	    + $('#connname').val().trim());
    }
    else {
	row = $('<tr><td><span class="glyphicon glyphicon-play pull-right control" title="Start"></span>'
	    + '<span class="pull-right list-remove" title="Remove">&nbsp;</span>'
	    + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>'
	    + '<span class="glyphicon glyphicon-list-alt pull-right logs" title="View log" style="display:none"></span>'
	    + $('#connname').val().trim()+'</td><td class="text-center">'
	    + '<input type="checkbox" name="autostart"></td></tr>');
	$('#wg-conns tr:last').before(row);
    }
    row.data('oldconnname', $('#connname').val().trim());
    row.data('ip', $('#cliip').val().trim());
    row.data('port', $('#cliport').val().trim());
    row.data('privatekey', $('#cliprivkey').val().trim());
    row.data('publickey', $('#clipubkey').val().trim());
    row.data('dns', $('#clidns').val().trim());
    row.data('serverpubkey', $('#svrpubkey').val().trim());
    row.data('presharedkey', $('#presharedkey').val().trim());
    row.data('serverhost', $('#svrhost').val().trim());
    row.data('serverport', $('#svrport').val().trim());

    $('#wg-conns').data('uncommitted', true);
}

$('#wg-clients button[type="submit"]').on('click', function(e) {
    e.preventDefault();

    var data = {
	networks: [],
	conns: []
    };

    $('#wg-clients [name=network]').each(function() {
	if ($(this).prop('checked')) {
	    data.networks.push($(this).val());
	}
    });

    $('#wg-conns tr:gt(0)').each(function() {
	if ($(this).is(':last-child')) {
	    return false;
	}

	data.conns.push({
	    name: $(this).data('oldconnname'),
	    ip: $(this).data('ip'),
	    port: $(this).data('port'),
	    privatekey: $(this).data('privatekey'),
	    publickey: $(this).data('publickey'),
	    dns: $(this).data('dns'),
	    presharedkey: $(this).data('presharedkey'),
	    serverpubkey: $(this).data('serverpubkey'),
	    serverhost: $(this).data('serverhost'),
	    serverport: $(this).data('serverport'),
	    autostart: $(this).find('[name=autostart]').prop('checked')
	});
    });

    var $form = $(this).parents('form');
    pcwrt.submit_form($form, JSON.stringify(data), function(r) {
	$('#wg-conns').data('uncommitted', null);
	pcwrt.apply_changes(r.apply);
    }, 'application/json');
});

$('#wg-update button[type="submit"]').on('click', function(e) {
    e.preventDefault();

    var data = {
	extaddr: $('#extaddr').val().trim(),
	port: $('#port').val().trim(),
	ipaddr: $('#ipaddr').val().trim(),
	netmask: $('#netmask').val().trim(),
	peers: []
    };

    $('#peers tr:gt(0)').each(function() {
	if ($(this).is(':last-child')) {
	    return false;
	}

	data.peers.push({
	    name: $('td:first', $(this)).text().trim(),
	    pubkey: $(this).data('pubkey'),
	    privkey: $(this).data('privkey'),
	    create: $(this).data('peername') == null,
	    guest: $('[name=guest]', $(this)).prop('checked'),
	    vpnout: $('td:eq(1)', $(this)).text() == window.msgs.vpn
	});
    });

    var $form = $(this).parents('form');
    pcwrt.submit_form($form, JSON.stringify(data), function(r) {
        $('#peers tr').each(function() {
	    if ($(this).is(':last-child')) {
		return false;
	    }

	    $(this).data('peername', $('td:first', $(this)).text().trim());
	});

	$('#publickey').val(r.svrpubkey);

	$('#wg-status').text(msgs.enabled)
	.parent().removeClass('alert-danger').addClass('alert-success');
	$('#disable-wg').removeClass('hidden');
	$('#restart-wg').removeClass('hidden');
	$('#enable-wg').addClass('hidden');
	$('#enable-disable').removeClass('hidden');
	$('#enable-alert').addClass('hidden');
	pcwrt.apply_changes(r.apply);
    }, 'application/json');
});

$('#enable-wg').on('click', function(e) {
    e.preventDefault();
    $('#enable-disable').addClass('hidden');
    $('#enable-alert').removeClass('hidden');
    $('#wg-settings').slideDown();
});

$('#disable-wg').on('click', function(e) {
    e.preventDefault();
    var $form = $(this).parents('form');
    disable_wg($form);
});

$('#restart-wg').on('click', function(e) {
    e.preventDefault();
    pcwrt.submit_form($('#restart-server'), {}, function(r) {
 	pcwrt.show_message(msgs.restart_wg_title, msgs.restart_wg_message);
    });
});

$('#wg-conns').on('click', '.list-remove', function(e) {
    e.preventDefault();
    $('#wg-conns').data('deleteConfig', $(this).parents('tr').index());
    pcwrt.confirm_action(window.msgs.delete_wg_conn_title,
	window.msgs.delete_wg_conn_confirm+' "' + $(this).parent().text().trim() + '"?',
	function() {
	    var idx = $('#wg-conns').data('deleteConfig');
	    $('#wg-conns tr:eq('+idx+')').remove();
	    $('#wg-conns').data('uncommitted', true);
	}
    );
});

function display_conn_edit(row, connname) {
    $('#conn-modal')
    .find('.modal-title').text(window.msgs.edit_wg_conn_title).end()
    .find('.form-group').removeClass('has-error').end()
    .find('.form-control-error').remove().end()
    .find('input:not([type=radio],[type=checkbox])').val('').end()
    .find('input[name=connname]').val(connname).end()
    .find('input[name=svrhost]').val(row.data('serverhost')).end()
    .find('input[name=svrport]').val(row.data('serverport')).end()
    .find('input[name=presharedkey]').val(row.data('presharedkey')).end()
    .find('input[name=svrpubkey]').val(row.data('serverpubkey')).end()
    .find('input[name=cliprivkey]').val(row.data('privatekey')).end()
    .find('input[name=clipubkey]').val(row.data('publickey')).end()
    .find('input[name=cliip]').val(row.data('ip')).end()
    .find('input[name=cliport]').val(row.data('port')).end()
    .find('input[name=clidns]').val(row.data('dns')).end()
    .find('input[name=oldconnname]').val(row.data('oldconnname')).end()
    .modal('show');
}

$('#wg-conns').on('click', '.list-edit', function(e) {
    e.preventDefault();

    var row = $(this).parent().parent();
    if (!row.data('privatekey')) {
	pcwrt.fetch_data($('#get-connparms').attr('action'), { cfg: row.data('oldconnname') }, function(r) {
	    row.data('serverhost', r.serverhost);
	    row.data('serverport', r.serverport);
	    row.data('serverpubkey', r.serverpubkey);
	    row.data('presharedkey', r.presharedkey);
	    row.data('privatekey', r.privatekey);
	    row.data('publickey', r.publickey);
	    row.data('ip', r.ip);
	    row.data('port', r.port);
	    row.data('dns', r.dns);
	    display_conn_edit(row, r.name);
	});
	return;
    }

    display_conn_edit(row, $(this).parent().text().trim());
});

$('#wg-conns').on('click', 'span.glyphicon.logs', function(e) {
    e.preventDefault();
    pcwrt.fetch_data($('#get-clientlog').attr('action'), {}, function(d) {
	$('#logs-modal')
	.find('#client-logs').html(pcwrt.is_empty(d) ? window.msgs.logs_empty : d)
	.end()
	.modal('show');
    });
});

$('#wg-conns').on('click', 'span.glyphicon.control', function(e) {
    e.preventDefault();

    if ($('#wg-conns').data('uncommitted')) {
	pcwrt.show_message(msgs.uncommitted_title, msgs.uncommitted_changes);
	return;
    }

    var $el = $(this);
    if ($el.hasClass('glyphicon-play')) {
	var $form = $('#connect-wg');
	$('[name=action]', $form).val('start');
	$('[name=cfg]', $form).val($el.parents('td:first').text().trim());
	pcwrt.submit_form($form, $form.serialize(), function(r) {
	    $el.parents('td:first').removeClass('running connected stopped');
	    if (r.state == 'running' || r.state == 'connected' || r.state == 'stopped') {
		$el.parents('td:first').addClass(r.state).parent().siblings().find('td:first').removeClass('running connected stopped').find('span.logs').hide();
		$el.parents('tr:first').siblings().find('span.glyphicon.control').removeClass('glyphicon-stop').addClass('glyphicon-play');
		$el.removeClass('glyphicon-play').addClass('glyphicon-stop').attr('title', 'Stop').parents('td:first').find('span.logs').show();
	    }
	}, null, false, window.msgs.start_wgconf + ' "'+$('[name=cfg]', $form).val()+'"');
    }
    else {
	var $form = $('#connect-wg');
	$('[name=action]', $form).val('stop');
	$('[name=cfg]', $form).val($el.parents('td:first').text().trim());
	pcwrt.submit_form($form, $form.serialize(), function(r) {
	    $el.parents('td:first').removeClass('running connected').addClass('stopped');
	    $el.removeClass('glyphicon-stop').addClass('glyphicon-play').attr('title', 'Start');
	}, null, false, window.msgs.stop_wgconf + ' "' +$('[name=cfg]', $form).val()+ '"');
    }
});

$(function() {
    $.each(fv.client.enabled_network, function(i, nw) {
	var f1 = $('[name=network]:first').parent().parent();
	if (i > 0) {
	    var f2 = f1.clone();
	    f1.parent().append(f2);
	    f1 = f2;
	}
	var $c = $('label', f1).contents();
	$c[$c.length - 1].nodeValue = nw.text;
	$('input', f1).prop('value', nw.name);
	$('input', f1).prop('checked', nw.enabled ? true : false);
    });

    if (fv.client.conns) {
	fv.client.conns.sort(function(a, b) {return a.name.toUpperCase() > b.name.toUpperCase()?1:-1;});
	$.each(fv.client.conns, function(i, conn) {
	    var $row = $('<tr><td><span class="glyphicon glyphicon-play pull-right control" title="Start"></span>'
		    + '<span class="pull-right list-remove" title="Remove">&nbsp;</span>'
		    + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>'
		    + '<span class="glyphicon glyphicon-list-alt pull-right logs" title="View log" style="display:none"></span>'
		    + conn.name +'</td><td class="text-center">'
		    + '<input type="checkbox" name="autostart"></td></tr>');
	    if (conn.autostart == '1') {
		$row.find('[name=autostart]').prop('checked', true);
	    }

	    if (conn.state == 'connected' || conn.state == 'running' || conn.state == 'stopped') {
		$('#connect-wg [name=cfg]').val(conn.name);
		$row.find('td:first').addClass(conn.state).find('span.logs').show();
		if (conn.state != 'stopped') {
		    $row.find('.glyphicon.control').removeClass('glyphicon-play').addClass('glyphicon-stop').attr('title', 'Stop');
		}
	    }

	    $row.data('oldconnname', conn.name);
	    $('#wg-conns tr:last').before($row);
	});
    }

    pcwrt.populate_forms(fv.server);
    fv.server.peers.sort(function(a, b) {return a.name.toUpperCase() > b.name.toUpperCase()?1:-1;});
    $.each(fv.server.peers, function(i, peer) {
	var row = $('<tr><td><span class="pull-right list-remove" title="Delete peer">&nbsp;</span>'
		  + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>'
		  + '<span class="pull-right glyphicon glyphicon-download-alt control" title="Download WireGuard peer config"></span>'
		  + (peer.qr ? '<span class="pull-right glyphicon glyphicon-qrcode control" title="Download QR code"></span>' : '')
		  + peer.name + '</td><td>'+(peer.vpnout ? window.msgs.vpn : window.msgs.isp)
		  + '</td><td class="text-center"><input type="checkbox" name="guest"'
		  + (peer.guest ? ' checked' : '') + '></td></tr>');
	$('#peers tr:last').before(row);
	row.data('peername', peer.name);
    });

    if (fv.server.enabled == '0') {
    	$('#enable-disable').addClass('alert-danger').removeClass('alert-success');
	$('#wg-status').text(window.msgs.disabled);
	$('#enable-wg').removeClass('hidden');
    }
    else {
    	$('#enable-disable').removeClass('alert-danger').addClass('alert-success');
	$('#wg-status').text(window.msgs.enabled);
	$('#disable-wg').removeClass('hidden');
	$('#restart-wg').removeClass('hidden');
	$('#wg-settings').slideDown();
    }

    window.setInterval(function() {
	var $form = $('#connect-wg');
	var cfg = $('[name=cfg]', $form).val();
	if (pcwrt.is_empty(cfg)) { return; }
	pcwrt.fetch_data($form.data('state_url'), {cfg: cfg}, function(d) {
	    var $el = null;
	    $('#wg-conns tr:gt(0)').find('td:first').removeClass('running connected stopped').each(function() {
		$(this).find('span.logs').hide();
		if ($(this).text().trim() == d.cfg) {
		    $el = $(this);
		}
	    });
	    
	    if ($el) {
		$el.addClass(d.state).find('span.logs').show();
	    }
	});
    }, 10000);
});
