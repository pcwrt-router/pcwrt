function display_disabled() {
    $('#vpn-status').text(msgs.disabled)
    .parent().removeClass('alert-success').addClass('alert-danger');
    $('#enable-vpn').removeClass('hidden');
    $('#disable-vpn').addClass('hidden');
    $('#restart-vpn').addClass('hidden');
    $('#vpn-settings').slideUp();
}

function disable_vpn($form) {
    pcwrt.submit_form($form, JSON.stringify({enabled: '0'}), function(r) {
	display_disabled();
	pcwrt.apply_changes(r.apply);
    });
}

$('#users .btn').on('click', function(e) {
    e.preventDefault();
    $('#user-dialog .form-group').removeClass('has-error').find('p.form-control-error').remove();
    $('#user-dialog').modal('show');
    $('#username').val('').data('rowname', null).focus();
    $('#password').val('');
    $('[name=vpnout]:first').prop('checked', true);
});

$('#user-dialog .btn-success').on('click', function(e) {
    e.preventDefault();
    $('#user-dialog .form-group').removeClass('has-error').find('p.form-control-error').remove();

    if (!/^[a-zA-Z0-9._\-\\\$@%#&]+$/.test($('#username').val())) {
	$('#username').after('<p class="form-control-error">'+window.msgs.enter_valid_user_name+'</p>').parent().addClass('has-error');
	return;
    }
    
    var row = null;
    var err = null;
    $('#users tr:gt(0)').each(function() {
	if (!$(this).is(':last-child')) {
	    if ($(this).data('username') == $('#username').data('rowname')) {
		row = $(this);
	    }

	    if ($(this).data('username') == $('#username').val() && 
		$(this).data('username') != $('#username').data('rowname')) {
		err = 'duplicate';
	    }
	}
    });

    if (err == 'duplicate') {
	$('#username').after('<p class="form-control-error">'+window.msgs.user_name_exists+'</p>').parent().addClass('has-error');
	return;
    }

    if (!row) {
	if (/^\s*$/.test($('#password').val())) {
	    $('#password').after('<p class="form-control-error">'+window.msgs.enter_password+'</p>').parent().addClass('has-error');
	    return;
	}

	row = $('<tr><td><span class="pull-right list-remove" title="Delete">&nbsp;</span>'
 	    + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>'+$('#username').val()+'</td><td>'
  	    + ($('[name=vpnout]:checked').val() == '1' ? window.msgs.vpn : window.msgs.isp)
   	    + '</td><td class="text-center"><input type="checkbox" name="guest"></td></tr>');
	$('#users tr:last').before(row);
    }
    else {
	$('td:eq(0)', row).html('<span class="pull-right list-remove" title="Delete">&nbsp;</span>'
	    + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>'+$('#username').val());
	$('td:eq(1)', row).text($('[name=vpnout]:checked').val() == '1' ? window.msgs.vpn : window.msgs.isp);
    }

    row.data('username', $('#username').val().trim());
    if (!/^\**$/.test($('#password').val())) {
	row.data('password', $('#password').val());
    }

    $('#user-dialog').modal('hide');
});

$('#users').on('click', '.list-remove', function(e) {
    e.preventDefault();
    $('#users').data('deleteUser', $(this).parents('tr').index());
    pcwrt.confirm_action(window.msgs.delete_user_title,
	window.msgs.delete_user_confirm+' "' + $(this).parent().text().trim() + '"?',
	function() {
	    var idx = $('#users').data('deleteUser');
	    $('#users tr:eq('+idx+')').remove();
	}
    );
});

$('#users').on('click', '.list-edit', function(e) {
    e.preventDefault();
    var rowname = $(this).parent().text().trim();
    $('#user-dialog .form-group').removeClass('has-error').find('p.form-control-error').remove();
    $('#username').val(rowname).data('rowname', rowname);
    $('#password').val('*******************');
    if ($(this).parent().next().text() == window.msgs.vpn) {
 	$('[name=vpnout]:eq(1)').prop('checked', true);
    }
    else {
  	$('[name=vpnout]:eq(0)').prop('checked', true);
    }
    $('#user-dialog').modal('show');
});

$('#vpn-init button[type="submit"]').on('click', function (e) {
    e.preventDefault();
    var $form = $(this).parents('form');
    pcwrt.submit_form($form, {}, function(r) {
	$('#init-alert').addClass('hidden').next().hide();
	$('#prog-alert').removeClass('hidden');
    });
});

$('#reinit-vpn').on('click', function(e) {
    e.preventDefault();
    pcwrt.confirm_action(window.msgs.reinit_vpn_title, window.msgs.reinit_vpn_confirm, function() {
	pcwrt.submit_form($('#vpn-init'), {}, function(r) {
	    $('#main-form').hide();
	    $('#prog-alert').removeClass('hidden');
	});
    });
});

$('#enable-vpn').on('click', function(e) {
    e.preventDefault();
    $('#enable-disable').addClass('hidden');
    $('#enable-alert').removeClass('hidden');
    $('#vpn-settings').slideDown();
});

$('#disable-vpn').on('click', function(e) {
    e.preventDefault();
    var $form = $(this).parents('form');
    disable_vpn($form);
});

$('#restart-vpn').on('click', function(e) {
    e.preventDefault();
    pcwrt.submit_form($('#restart-server'), {}, function(r) {
	pcwrt.show_message(msgs.restart_vpn_title, msgs.restart_vpn_message);
    });
});

$('#vpn-update button[type="submit"]').on('click', function (e) {
    e.preventDefault();

    var data = {
	port: $('#port').val(),
	extaddr: $('#extaddr').val(),
	ipaddr: $('#ipaddr').val(),
	netmask: $('#netmask').val(),
	scramble: $('#scramble').prop('checked') ? '1' : '0',
	scrampass: $('#scrampass').val(),
	users: []
    };

    $('#users tr:gt(0)').each(function() {
	if ($(this).is(':last-child')) {
	    return false;
	}

	data.users.push({
	    oldname: $(this).data('oldname'),
	    name: $(this).data('username'),
	    password: $(this).data('password'),
	    guest: $('[name=guest]', $(this)).prop('checked'),
	    vpnout: $('td:eq(1)', $(this)).text() == window.msgs.vpn
	});
    });

    var $form = $(this).parents('form');
    pcwrt.submit_form($form, JSON.stringify(data), function(r) {
	$('#users tr').each(function() {
	    if ($(this).is(':last-child')) {
		return false;
	    }

	    $(this).data('oldname', $(this).data('username'));
	});

	$('#vpn-status').text(msgs.enabled)
	.parent().removeClass('alert-danger').addClass('alert-success');
	$('#disable-vpn').removeClass('hidden');
	$('#restart-vpn').removeClass('hidden');
	$('#enable-vpn').addClass('hidden');
	$('#enable-disable').removeClass('hidden');
	$('#enable-alert').addClass('hidden');
	pcwrt.apply_changes(r.apply);
    }, 'application/json');
});

$('#add-vpn-config').on('click', function(e) {
    e.preventDefault();

    $('#new-cfg-msg').show();
    $('#update-cfg-msg').hide();

    $('#client-modal')
    .find('.modal-title').text(window.msgs.add_vpn_title).end()
    .find('.form-group').removeClass('has-error').end()
    .find('.form-control-error').remove().end()
    .find('input').val('').end()
    .modal('show');
});

$('#vpn-configs').on('click', '.list-remove', function(e) {
    e.preventDefault();
    $('#vpn-configs').data('deleteConfig', $(this).parents('tr').index());
    pcwrt.confirm_action(window.msgs.delete_vpn_config_title,
	window.msgs.delete_vpn_config_confirm+' "' + $(this).parent().text().trim() + '"?',
	function() {
	    var idx = $('#vpn-configs').data('deleteConfig');
	    var cfg = $('#vpn-configs tr:eq('+idx+') td:first').text().trim();
	    if (cfg == $('#connect-vpn [name=cfg]').val()) {
		$('#connect-vpn [name=cfg]').val('');
	    }
	    $('#vpn-configs tr:eq('+idx+')').remove();
	}
    );
});

$('#vpn-configs').on('click', '.list-edit', function(e) {
    e.preventDefault();

    var oldname = $(this).parent().parent().data('oldname');
    pcwrt.fetch_data($('#client-modal').data('cfgurl') + '?cfg='+escape(oldname), '', function(d) {
	$('#client-modal input[name=cfguser]').val(d.cfguser);
	$('#client-modal input[name=cfgpass]').val(d.cfgpass);
    });

    $('#update-cfg-msg a').attr('href', $('#update-cfg-msg a').data('url') + '?cfg=' + escape(oldname));
    $('#new-cfg-msg').hide();
    $('#update-cfg-msg').show();

    $('#client-modal')
    .find('.modal-title').text(window.msgs.edit_vpn_title).end()
    .find('.form-group').removeClass('has-error').end()
    .find('.form-control-error').remove().end()
    .find('input').val('').end()
    .find('input[name=cfgname]').val($(this).parent().text().trim()).end()
    .find('input[name=oldname]').val(oldname).end()
    .modal('show');
});

$('#vpn-configs').on('click', 'span.glyphicon.logs', function(e) {
    e.preventDefault();
    pcwrt.fetch_data($('#get-clientlog').attr('action'), {}, function(d) {
	$('#logs-modal')
	.find('#client-logs').html(d)
	.end()
	.modal('show');
    });
});

$('#vpn-configs').on('click', 'span.glyphicon.control', function(e) {
    e.preventDefault();

    if ($('#vpn-configs').data('uncommitted')) {
	pcwrt.show_message(msgs.uncommitted_title, msgs.uncommitted_changes);
	return;
    }

    var $el = $(this);
    if ($el.hasClass('glyphicon-play')) {
	var $form = $('#connect-vpn');
	$('[name=action]', $form).val('start');
	$('[name=cfg]', $form).val($el.parents('td:first').text().trim());
	pcwrt.submit_form($form, $form.serialize(), function(r) {
	    $el.parents('td:first').removeClass('running connected stopped');
	    if (r.state == 'running' || r.state == 'connected' || r.state == 'stopped') {
		$el.parents('td:first').addClass(r.state).parent().siblings().find('td:first').removeClass('running connected stopped').find('span.logs').hide();
		$el.parents('tr:first').siblings().find('span.glyphicon.control').removeClass('glyphicon-stop').addClass('glyphicon-play');
		$el.removeClass('glyphicon-play').addClass('glyphicon-stop').attr('title', 'Stop').parents('td:first').find('span.logs').show();
	    }
	}, null, false, window.msgs.start_vpnconf + ' "'+$('[name=cfg]', $form).val()+'"');
    }
    else {
	var $form = $('#connect-vpn');
	$('[name=action]', $form).val('stop');
	$('[name=cfg]', $form).val($el.parents('td:first').text().trim());
	pcwrt.submit_form($form, $form.serialize(), function(r) {
	    $el.parents('td:first').removeClass('running connected').addClass('stopped');
	    $el.removeClass('glyphicon-stop').addClass('glyphicon-play').attr('title', 'Start');
	}, null, false, window.msgs.stop_vpnconf + ' "' +$('[name=cfg]', $form).val()+ '"');
    }
});

$('#vpn-configs').on('click', 'input', function(e) {
    if ($(this).prop('checked')) {
	$(this).parent().parent().siblings().find('input[type=checkbox]').prop('checked', false);
    }
});

$('#client-modal .btn-file :file').on('fileselect', function(e, numFiles, label) {
    $('#client-modal [name=ovpn-name]').val(label);
});

$('#cert-modal .btn-file:first :file').on('fileselect', function(e, numFiles, label) {
    $('#cert-modal [name=cacert-name]').val(label);
});

$('#cert-modal .btn-file:eq(1) :file').on('fileselect', function(e, numFiles, label) {
    $('#cert-modal [name=clicert-name]').val(label);
});

$('#cert-modal .btn-file:eq(2) :file').on('fileselect', function(e, numFiles, label) {
    $('#cert-modal [name=clikey-name]').val(label);
});

$('#cert-modal .btn-file:eq(3) :file').on('fileselect', function(e, numFiles, label) {
    $('#cert-modal [name=tlscert-name]').val(label);
});

function update_vpn_configs() {
    var row;
    $('#vpn-configs tr:gt(0)').each(function() {
	if ($(this).is(':last-child')) {
	    return false;
	}

	if ($('#client-modal input[name=oldname]').val() == $(this).data('oldname')) {
	    row = $(this);
	    return false;
	}
    });

    if (row) {
	$('td:first', row).html('<span class="glyphicon glyphicon-play pull-right control" title="Start"></span>'
	    + '<span class="pull-right list-remove" title="Remove">&nbsp;</span>'
	    + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>'
	    + '<span class="glyphicon glyphicon-list-alt pull-right logs" title="View log" style="display:none"></span>'
	    + $('#cfgname').val().trim());
    }
    else {
	row = $('<tr><td><span class="glyphicon glyphicon-play pull-right control" title="Start"></span>'
	    + '<span class="pull-right list-remove" title="Remove">&nbsp;</span>'
	    + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>'
	    + '<span class="glyphicon glyphicon-list-alt pull-right logs" title="View log" style="display:none"></span>'
	    + $('#cfgname').val().trim()+'</td><td class="text-center">'
	    + '<input type="checkbox" name="autostart"></td></tr>');
	$('#vpn-configs tr:last').before(row);
    }
    row.data('oldname', $('#cfgname').val().trim());

    $('#vpn-configs').data('uncommitted', true);
}

$('#client-modal form').ajaxForm({
    beforeSubmit: function(formData, jqForm, options) {
	$('#client-modal .form-control-error')
	.parent().removeClass('has-error')
	.end().remove();

	var ok = true;
	var cfgname = jqForm[0].cfgname.value.trim();
	if (!cfgname) {
	    $('#client-modal form .form-group:first')
	    .addClass('has-error')
	    .append('<p class="form-control-error">'+window.msgs.empty_config+'</p>');
	    ok = false;
	}
	else {
	    $('#vpn-configs tr:gt(0)').each(function() {
		if ($(this).is(':last-child')) {
		    return false;
		}

		if ($('td:first', $(this)).text().trim() == cfgname && jqForm[0].oldname.value != $(this).data('oldname')) {
		    $('#client-modal form .form-group:first')
		    .addClass('has-error')
		    .append('<p class="form-control-error">'+window.msgs.duplicate_config+'</p>');
		    ok = false;
		    return false;
		}
	    });
	}

	return ok;
    },
    complete: function(xhr) {
	var r = xhr.responseJSON;
	if (r.status == 'success') {
	    update_vpn_configs();
	    $('#client-modal').modal('hide');
	}
	else if (r.status == 'error') {
	    if (r.message) {
		for (name in r.message) {
		    var input = $('#client-modal input[name="'+name+'"]:visible');
		    if (input.parent().hasClass('input-group')) {
			input = input.parent();
		    }
		    input.parent()
		    .addClass('has-error')
		    .append('<p class="form-control-error">'+r.message[name]+'</p>');
		}

		if (r.message.ovpnfile) {
		    $('#client-modal .form-group:eq(1)')
		    .addClass('has-error')
		    .append('<p class="form-control-error">'+r.message.ovpnfile+'</p>');
		}
	    }
	    else if (r.need_certs) {
		$('#cert-modal .form-group').hide();
		$.each(r.need_certs, function(i, v) {
		    $('#'+v+'-group').show();
		});
		$('#cert-modal')
		.find('.form-group').removeClass('has-error').end()
		.find('.form-control-error').remove().end()
		.find('input').val('').end()
		.find('input[name=cfgname]').val($('#cfgname').val().trim()).end()
		.modal('show');
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

$('#cert-modal form').ajaxForm({
    beforeSubmit: function(formData, jqForm, options) {
	$('#cert-modal .form-control-error')
	.parent().removeClass('has-error')
	.end().remove();

	var ok = true;
	$('#cert-modal .form-group').each(function() {
	    if ($(this).is(':visible') && !$(this).find('input[type=file]').val()) {
		var msg = msgs['select_' + $(this).attr('id').replace('-group', '') + '_file'];
		$(this).addClass('had-error')
		.append('<p class="form-control-error">'+msg+'</p>');
		ok = false;
	    }
	});
	return ok;
    },
    complete: function(xhr) {
	var r = xhr.responseJSON;
	if (r.status == 'success') {
	    update_vpn_configs();
	    $('#cert-modal').modal('hide');
	    $('#client-modal').modal('hide');
	}
	else if (r.status == 'error') {
	    if (r.message.cacert) {
		$('#cert-modal .form-group:eq(0)')
		.addClass('has-error')
		.append('<p class="form-control-error">'+r.message.cacert+'</p>');
	    }

	    if (r.message.clicert) {
		$('#cert-modal .form-group:eq(1)')
		.addClass('has-error')
		.append('<p class="form-control-error">'+r.message.clicert+'</p>');
	    }

	    if (r.message.clikey) {
		$('#cert-modal .form-group:eq(2)')
		.addClass('has-error')
		.append('<p class="form-control-error">'+r.message.clikey+'</p>');
	    }

	    if (r.message.tlscert) {
		$('#cert-modal .form-group:eq(3)')
		.addClass('has-error')
		.append('<p class="form-control-error">'+r.message.tlscert+'</p>');
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

$('#vpn-clients button[type="submit"]').on('click', function(e) {
    e.preventDefault();

    var $form = $(this).parents('form');
    var data = $form.serializeArray();
    var autostart = null;
    $('#vpn-configs tr:gt(0)').each(function() {
	if ($(this).is(':last-child')) {
	    return false;
	}

	if (!autostart && $('td:eq(1) [name=autostart]', $(this)).prop('checked')) {
	    autostart = $('td:first', $(this)).text().trim();
	}

	data.push({
	    name: 'cfgname',
	    value: $('td:first', $(this)).text().trim()
	});
    });

    $.each(data, function(i, v) {
	if (v.name == 'autostart') {
	    v.value = autostart;
	    return false;
	}
    });

    pcwrt.submit_form($form, data, function(r) {
	$('#vpn-configs').data('uncommitted', null);
	pcwrt.apply_changes(r.apply);
    });
});

function toggle_scramble() {
    if ($('#scramble').prop('checked')) {
	$('#scrampass').parent().slideDown();
    }
    else {
	$('#scrampass').parent().slideUp();
    }
}

$('#scramble').on('click', function() { toggle_scramble(); });

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

    if (fv.client.clients) {
	fv.client.clients.sort(function(a, b) { return a.name.toUpperCase() > b.name.toUpperCase() ? 1 : -1 });
	$.each(fv.client.clients, function(i, client) {
	    var $row = $('<tr><td><span class="glyphicon glyphicon-play pull-right control" title="Start"></span>'
		    + '<span class="pull-right list-remove" title="Remove">&nbsp;</span>'
		    + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>'
		    + '<span class="glyphicon glyphicon-list-alt pull-right logs" title="View log" style="display:none"></span>'
		    + client.name +'</td><td class="text-center">'
		    + '<input type="checkbox" name="autostart"></td></tr>');
	    if (client.name == fv.client.autostart) {
		$row.find('[name=autostart]').prop('checked', true);
	    }

	    if (client.state == 'connected' || client.state == 'running' || client.state == 'stopped') {
		$('#connect-vpn [name=cfg]').val(client.name);
		$row.find('td:first').addClass(client.state).find('span.logs').show();
		if (client.state != 'stopped') {
		    $row.find('.glyphicon.control').removeClass('glyphicon-play').addClass('glyphicon-stop').attr('title', 'Stop');
		}
	    }

	    $row.data('oldname', client.name);
	    $('#vpn-configs tr:last').before($row);
	});
    }

    pcwrt.populate_forms(fv.server);
    toggle_scramble();

    if (fv.server.users) {
	fv.server.users.sort(function(a, b) {return a.name.toUpperCase() > b.name.toUpperCase()?1:-1;});
	$.each(fv.server.users, function(i, v) {
	    var row = $('<tr><td><span class="pull-right list-remove" title="Delete">&nbsp;</span>'
   		    + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>'+v.name+'</td><td>'
      		    + (v.vpnout ? window.msgs.vpn : window.msgs.isp)
	 	    + '</td><td class="text-center"><input type="checkbox" name="guest"'+(v.guest ? ' checked' : '')+'></td></tr>');
	    $('#users tr:last').before(row);
	    row.data('username', v.name).data('oldname', v.name);
	});
    }

    if (fv.server.enabled == '0') {
    	$('#enable-disable').addClass('alert-danger').removeClass('alert-success');
	$('#vpn-status').text(window.msgs.disabled);
	$('#enable-vpn').removeClass('hidden');
    }
    else {
    	$('#enable-disable').removeClass('alert-danger').addClass('alert-success');
	$('#vpn-status').text(window.msgs.enabled);
	$('#disable-vpn').removeClass('hidden');
	$('#restart-vpn').removeClass('hidden');
	$('#vpn-settings').slideDown();
    }

    window.setInterval(function() {
	var $form = $('#connect-vpn')
	var cfg = $('[name=cfg]', $form).val();
	if (pcwrt.is_empty(cfg)) { return; }
	pcwrt.fetch_data($form.data('state_url'), {cfg: cfg}, function(d) {
	    var $el = null;
	    $('#vpn-configs tr:gt(0)').find('td:first').removeClass('running connected stopped').each(function() {
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
