function display_disabled() {
    $('#ipsec-status').text(msgs.disabled)
    .parent().removeClass('alert-success').addClass('alert-danger');
    $('#enable-ipsec').removeClass('hidden');
    $('#disable-ipsec').addClass('hidden');
    $('#restart-ipsec').addClass('hidden');
    $('#ipsec-settings').slideUp();
}

function disable_ipsec($form) {
    pcwrt.submit_form($form, JSON.stringify({enabled: '0'}), function(r) {
	display_disabled();
	pcwrt.apply_changes(r.apply);
    });
}

function toggle_ipsec_auth_type() {
    if ($('#auth-modal [name=ipsec_type]:checked').val() == 'ikev2') {
	$('#ikev2-auth-conf').show();
	$('#ikev1-auth-conf').hide();
	if ($("#auth-modal [name=cert_type]:checked").val() == 'p12') {
	    $('#p12-certs').show();
	    $('#pem-certs').hide();
	}
	else {
	    $('#p12-certs').hide();
	    $('#pem-certs').show();
	}
    }
    else {
	$('#ikev1-auth-conf').show();
	$('#ikev2-auth-conf').hide();
    }
}

$("#auth-modal [name=ipsec_type]").on('click', function(e) {
    toggle_ipsec_auth_type();
});

function showAddAuthModal() {
    $('#auth-modal')
    .find('.modal-title').text(window.msgs.add_ipsec_auth_title).end()
    .find('.form-group').removeClass('has-error').end()
    .find('.form-control-error').remove().end()
    .find('input:not([type=radio],[type=checkbox])').val('').end()
    .modal('show');
    toggle_ipsec_auth_type();
}

function update_auth_config_select() {
    var configs = [];
    configs.push({
	value: "",
	text: window.msgs.select_auth_config
    });

    $('#auth-configs tr:gt(0)').each(function() {
	if ($(this).is(':last-child')) {
	    return false;
	}

	configs.push({
	    value: $('td', this).text().trim(),
	    text: $('td', this).text().trim()
	});
    });
    $('#authconfig').updatecombo(configs);
}

function is_equivalent_name(name1, name2) {
    if (name1 == null || name2 == null) { return false; }

    name1 = name1.replace(/[^0-9-a-zA-Z.]/g, '-');
    name2 = name2.replace(/[^0-9-a-zA-Z.]/g, '-');
    return name1 == name2;
}

$("#user-dialog [name=ipsec_type]").on('click', function(e) {
    if ($(this).val() == 'ikev1') {
	$('#password').parent().show();
    }
    else {
	$('#password').parent().hide();
    }
});

$('#gen-passwd').on('click', function(e) {
    e.preventDefault();
    $('#password').val(random_string('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz', 12));
});

$('#ipsec-init button[type="submit"]').on('click', function (e) {
    e.preventDefault();
    var $form = $(this).parents('form');
    pcwrt.submit_form($form, {}, function(r) {
	$('#init-alert').addClass('hidden').next().hide();
	$('#prog-alert').removeClass('hidden');
    });
});

$('#reinit-ipsec').on('click', function(e) {
    e.preventDefault();
    pcwrt.confirm_action(window.msgs.reinit_ipsec_title, window.msgs.reinit_ipsec_confirm, function() {
	pcwrt.submit_form($('#ipsec-init'), {}, function(r) {
	    $('#main-form').hide();
	    $('#prog-alert').removeClass('hidden');
	});
    });
});

$("[name=cert_type]").on('click', function(e) {
    toggle_ipsec_auth_type();
});

$('#ipsec-conns').on('click', 'input', function(e) {
    if ($(this).prop('checked')) {
	$(this).parent().parent().siblings().find('input[type=checkbox]').prop('checked', false);
    }
});

$('#users .btn').on('click', function(e) {
    e.preventDefault();
    $('#user-dialog .form-group').removeClass('has-error').find('p.form-control-error').remove();
    $('#user-dialog [name=ipsec_type][value=ikev2]').prop('checked', true);
    $('#password').val('').parent().hide();
    $('#user-dialog').data('rowidx', null).modal('show');
    $('#username').val('').focus();
    $('[name=vpnout]:first').prop('checked', true);
});

$('#users').on('click', '.list-edit', function(e) {
    e.preventDefault();
    var row = $(this).parents('tr:first');
    $('#user-dialog [name=ipsec_type][value='+row.data('type')+']').prop('checked', true);
    $('#password').val(row.data('password'));
    $('#user-dialog .form-group').removeClass('has-error').find('p.form-control-error').remove();
    $('#user-dialog').data('rowidx', row.index()).modal('show');
    if (row.data('type') == 'ikev1') {
 	$('#password').parent().show();
    }
    else {
  	$('#password').parent().hide();
    }
    if ($(this).parent().next().text() == window.msgs.vpn) {
   	$('[name=vpnout]:eq(1)').prop('checked', true);
    }
    else {
    	$('[name=vpnout]:eq(0)').prop('checked', true);
    }
    $('#username').val($('td:first', row).text().trim()).focus();
});

$('#user-dialog .btn-success').on('click', function(e) {
    e.preventDefault();
    $('#user-dialog .form-group').removeClass('has-error').find('p.form-control-error').remove();

    var err = '';
    if (!/^[a-zA-Z0-9._\-\\\$@%#&]+$/.test($('#username').val())) {
	$('#username').after('<p class="form-control-error">'+window.msgs.enter_valid_user_name+'</p>').parent().addClass('has-error');
	err += ' username';
    }

    if ($('#user-dialog [name=ipsec_type]:checked').val() == 'ikev1' && pcwrt.is_empty($('#password').val())) {
	$('#password').after('<p class="form-control-error">'+window.msgs.enter_password+'</p>').parent().addClass('has-error');
	err += ' password';
    }
    
    if (err) { return; }

    err = null;
    var rowidx = $('#user-dialog').data('rowidx');
    $('#users tr:gt(0)').each(function() {
	if (!$(this).is(':last-child')) {
	    if ($(this).index() != rowidx && is_equivalent_name($('td', $(this)).text().trim(), $('#username').val())) {
		err = 'duplicate';
	    }
	}
    });

    if (err == 'duplicate') {
	$('#username').after('<p class="form-control-error">'+window.msgs.user_name_exists+'</p>').parent().addClass('has-error');
	return;
    }

    var ipsec_type = $('#user-dialog [name=ipsec_type]:checked').val();
    var row = '<tr><td><span class="pull-right list-remove" title="Delete user">&nbsp;</span>'
	    + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>';
    if (ipsec_type == 'ikev2') {
	row += '<span class="pull-right glyphicon glyphicon-download-alt control" title="Download user certificate"></span>';
    }
    row += $('#username').val().trim()+'</td><td>'
	+ ($('[name=vpnout]:checked').val() == '1' ? window.msgs.vpn : window.msgs.isp)
	+ '</td><td class="text-center"><input type="checkbox" name="guest"></td></tr>';

    var $row;
    if (rowidx != null) {
	$row = $('#users tr:eq('+rowidx+')');
	var guest = $('[name=guest]', $row).prop('checked');
	$row.replaceWith(row);
	$row = $('#users tr:eq('+rowidx+')');
	$('[name=guest]', $row).prop('checked', guest);
    }
    else {
	$row = $(row)
	$('#users tr:last').before($row);
    }

    $row.data('type', ipsec_type);
    $row.data('username', $('#username').val().trim());
    if (ipsec_type == 'ikev1') { $row.data('password', $('#password').val()); } else { $row.data('password', null); }
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

$('#users').on('click', '.glyphicon-download-alt', function(e) {
    e.preventDefault();
    var username = $(this).parent().parent().data('username');
    if (username) {
	$('#download-cert [name=user]').val(username);
	var data = $('#download-cert').serializeArray();
	data.push({
	    name: 'status',
	    value: true
	});

	pcwrt.submit_form($('#download-cert'), data, function(r) {
	    if (r.cert_status == 'ready') {
		$('#p12-password')
    		.find('.form-group').removeClass('has-error').end()
		.find('.form-control-error').remove().end()
		.find('#p12password').val('').end()
		.modal('show');
	    }
	    else if (r.cert_status == 'in_progress') {
		pcwrt.show_message(msgs.user_cert_in_progress_title, msgs.user_cert_in_progress);
	    }
	    else {
		pcwrt.show_message(msgs.user_cert_missing_title, msgs.user_cert_missing);
	    }
	});
    }
    else {
	pcwrt.show_message(msgs.user_not_saved_title, msgs.user_not_saved);
    }
});

$('#p12-password .btn-success').on('click', function(e) {
    e.preventDefault();

    $('#p12-password')
    .find('.form-group').removeClass('has-error').end()
    .find('.form-control-error').remove().end()

    if (!/^[a-zA-Z0-9._\-\\\$@%#&]*$/.test($('#p12password').val())) {
	$('#p12password').after('<p class="form-control-error">'+window.msgs.enter_valid_password+'</p>').parent().addClass('has-error');
	return;
    }

    $('#download-cert [name=password]').val($('#p12password').val());
    $('#p12-password').modal('hide');
    window.location.href = $('#download-cert').attr('action') + '?' + $('#download-cert').serialize();
});

$('#create-auth-config,#add-ipsec-auth').on('click', function(e) {
    e.preventDefault();
    showAddAuthModal();
});

$('#download-rootca').on('click', function(e) {
    e.preventDefault();
    window.location.href = $('#download-cacert').attr('action');
});

$('#add-ipsec-conn').on('click', function(e) {
    e.preventDefault();
    $('#conn-modal')
    .find('.modal-title').text(window.msgs.add_ipsec_conn_title).end()
    .find('.form-group').removeClass('has-error').end()
    .find('.form-control-error').remove().end()
    .find('input:not([type=radio],[type=checkbox])').val('').end()
    .modal('show');
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
    else {
	$('#ipsec-conns tr:gt(0)').each(function() {
	    if ($(this).is(':last-child')) {
		return false;
	    }

	    if ($('#oldconnname').val() != $(this).data('oldconnname') &&
		is_equivalent_name($(this).data('oldconnname'), $('#connname').val().trim())) {
		$('#conn-modal .form-group:first')
		.addClass('has-error')
		.append('<p class="form-control-error">'+window.msgs.duplicate_conn+'</p>');
		valid = false;
		return false;
	    }
	});
    }

    if (!pcwrt.is_valid_hostname($('#connhost').val()) && !pcwrt.is_valid_ipaddr($('#connhost').val())) {
	$('#conn-modal .form-group:eq(1)')
	.addClass('has-error')
	.append('<p class="form-control-error">'+window.msgs.empty_host_name+'</p>');
	valid = false;
    }

    if (pcwrt.is_empty($('#authconfig').val())) {
	$('#conn-modal .form-group:eq(2)')
	.addClass('has-error')
	.append('<p class="form-control-error">'+window.msgs.empty_auth_config+'</p>');
	valid = false;
    }

    if (valid) {
	update_ipsec_conn();
	$('#conn-modal').modal('hide');
    }
});

$('#auth-configs').on('click', '.list-remove', function(e) {
    e.preventDefault();

    var used = false;
    var authconfig = $(this).parent().text().trim();
    $('#ipsec-conns tr:gt(0)').each(function() {
	if ($(this).is(':last-child')) {
	    return false;
	}

	if ($(this).data('authconfig') == authconfig) {
	    used = $('td:first', $(this)).text().trim();
	    pcwrt.show_message(
		window.msgs.delete_auth_config_cannot_title,
		window.msgs.delete_auth_config_cannot + " '" + authconfig + "', "
		+ window.msgs.delete_auth_config_used + " '" + used + "'."
	    );
	    return false;
	}
    });

    if (used) {
	return;
    }

    $('#auth-configs').data('deleteConfig', $(this).parents('tr').index());
    pcwrt.confirm_action(window.msgs.delete_auth_config_title,
	window.msgs.delete_auth_config_confirm+' "' + authconfig + '"?',
	function() {
	    var idx = $('#auth-configs').data('deleteConfig');
	    $('#auth-configs tr:eq('+idx+')').remove();
	    update_auth_config_select();
	    $('#auth-configs').data('uncommitted', true);
	}
    );
});

$('#auth-configs').on('click', '.list-edit', function(e) {
    e.preventDefault();

    $('#auth-modal')
    .find('.modal-title').text(window.msgs.edit_ipsec_auth_title).end()
    .find('.form-group').removeClass('has-error').end()
    .find('.form-control-error').remove().end()
    .find('input:not([type=radio],[type=checkbox])').val('').end();

    var row = $(this).parent().parent();
        var ipsec_type = row.data('ipsec_type');
    if (ipsec_type == 'ikev1') {
	$('#auth-modal')
	.find('[name=ipsec_type][value=ikev1]').prop('checked', true).end()
	.find('input[name=username]').val(row.data('cfguser')).end()
	.find('input[name=password]').val(row.data('cfgpass')).end()
	.find('input[name=psk]').val(row.data('psk'));
    }
    else {
	$('#auth-modal')
	.find('[name=ipsec_type][value=ikev2]').prop('checked', true).end()
	.find('[name=cert_type][value=pem]').prop('checked', true).end()
	.find('input[name=cfguser]').val(row.data('cfguser')).end()
	.find('input[name=cfgpass]').val(row.data('cfgpass'));

	if (row.data('cadn')) {
	    $('#auth-modal').find('[name=cacert-name]').val(row.data('cadn'));
	}

	if (row.data('clidn')) {
	    $('#auth-modal').find('[name=clicert-name]').val(row.data('clidn'));
	}
    }

    $('#auth-modal')
    .find('input[name=cfgname]').val($(this).parent().text().trim()).end()
    .find('input[name=oldname]').val(row.data('oldname')).end()
    .modal('show');

    toggle_ipsec_auth_type();
});

$('#auth-modal .btn-file:first :file').on('fileselect', function(e, numFiles, label) {
    $('#auth-modal [name=p12-name]').val(label);
});

$('#auth-modal .btn-file:eq(1) :file').on('fileselect', function(e, numFiles, label) {
    $('#auth-modal [name=cacert-name]').val(label);
});

$('#auth-modal .btn-file:eq(2) :file').on('fileselect', function(e, numFiles, label) {
    $('#auth-modal [name=clicert-name]').val(label);
});

$('#auth-modal .btn-file:eq(3) :file').on('fileselect', function(e, numFiles, label) {
    $('#auth-modal [name=clikey-name]').val(label);
});

function update_ipsec_auth(response) {
    var row;
    $('#auth-configs tr:gt(0)').each(function() {
	if ($(this).is(':last-child')) {
	    return false;
	}

	if ($('#auth-modal input[name=oldname]').val() == $(this).data('oldname')) {
	    row = $(this);
	    return false;
	}
    });

    if (row) {
	$('td', row).html('<span class="pull-right list-remove" title="Remove">&nbsp;</span>'
	    + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>'
	    + $('#cfgname').val().trim());
    }
    else {
	row = $('<tr><td><span class="pull-right list-remove" title="Remove">&nbsp;</span>'
	    + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>'
	    + $('#cfgname').val().trim()+'</td></tr>');
	$('#auth-configs tr:last').before(row);
    }

    var oldname = row.data('oldname');
    var newname =  $('#cfgname').val().trim();
    $('#ipsec-conns tr:gt(0)').each(function() {
	if ($(this).is(':last-child')) {
	    return false;
	}

	if ($(this).data('authconfig') == oldname) {
	    $(this).data('authconfig', newname);
	}
    });

    var ipsec_type = $('#auth-modal [name=ipsec_type]:checked').val();
    row.data('oldname', newname);
    row.data('ipsec_type', ipsec_type);
    if (ipsec_type == 'ikev1') {
	row.data('psk', $('#ikev1-psk').val().trim());
	row.data('cfguser', $('#ikev1-user').val().trim());
	row.data('cfgpass', $('#ikev1-pass').val().trim());
    }
    else {
	row.data('cfguser', $('#cfguser').val().trim());
	row.data('cfgpass', $('#cfgpass').val().trim());
    }

    if (response) {
	row.data('cadn', response.cadn);
	row.data('clidn', response.clidn);
    }

    update_auth_config_select();

    $('#auth-configs').data('uncommitted', true);
}

function update_ipsec_conn() {
    var row;
    $('#ipsec-conns tr:gt(0)').each(function() {
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
	$('#ipsec-conns tr:last').before(row);
    }
    row.data('oldconnname', $('#connname').val().trim());
    row.data('connhost', $('#connhost').val().trim());
    row.data('authconfig', $('#authconfig').val().trim());

    $('#ipsec-conns').data('uncommitted', true);
}

function validate_ikev1_auth() {
    var valid = true
    if (pcwrt.is_empty($('#ikev1-psk').val())) {
	$('#ikev1-psk').after('<p class="form-control-error">'+window.msgs.enter_psk+'</p>').parent().addClass('has-error');
	valid = false;
    }

    if (!/^[a-zA-Z0-9._\-\\\$@%#&]+$/.test($('#ikev1-user').val())) {
	$('#ikev1-user').after('<p class="form-control-error">'+window.msgs.enter_valid_user_name+'</p>').parent().addClass('has-error');
	valid = false;
    }

    if (pcwrt.is_empty($('#ikev1-pass').val())) {
	$('#ikev1-pass').after('<p class="form-control-error">'+window.msgs.enter_password+'</p>').parent().addClass('has-error');
	valid = false;
    }

    return valid;
}

$('#auth-modal form').ajaxForm({
    beforeSubmit: function(formData, jqForm, options) {
	$('#auth-modal .form-control-error')
	.parent().removeClass('has-error')
	.end().remove();

	var cfgname = jqForm[0].cfgname.value.trim();
	if (!cfgname) {
	    $('#auth-modal form .form-group:first')
	    .addClass('has-error')
	    .append('<p class="form-control-error">'+window.msgs.empty_config+'</p>');
	    return false;
	}

	var ipsec_type = $('#auth-modal [name=ipsec_type]:checked').val();
	if (ipsec_type == 'ikev1') {
	    if (validate_ikev1_auth()) {
		update_ipsec_auth();
		$('#auth-modal').modal('hide');
	    }
	    return false;
	}

	var ok = true;
	$('#auth-configs tr:gt(0)').each(function() {
	    if ($(this).is(':last-child')) {
		return false;
	    }

	    if (jqForm[0].oldname.value != $(this).data('oldname') &&
		is_equivalent_name($('td:first', $(this)).text().trim(), cfgname)) {
		$('#auth-modal form .form-group:first')
		.addClass('has-error')
		.append('<p class="form-control-error">'+window.msgs.duplicate_config+'</p>');
		ok = false;
		return false;
	    }
	});

	return ok;
    },
    complete: function(xhr) {
	var r = xhr.responseJSON;
	if (r.status == 'success') {
	    update_ipsec_auth(r);
	    $('#auth-modal').modal('hide');
	    if ($('#conn-modal').is(':visible')) {
		$('#conn-modal .form-control-error')
		.parent().removeClass('has-error')
		.end().remove();
		$('#authconfig').val($('#cfgname').val().trim());
	    }
	}
	else if (r.status == 'error') {
	    if (r.message) {
		for (name in r.message) {
		    var input = $('#auth-modal input[name="'+name+'"]:visible');
		    if (input.parent().hasClass('input-group')) {
			input = input.parent();
		    }
		    input.parent()
		    .addClass('has-error')
		    .append('<p class="form-control-error">'+r.message[name]+'</p>');
		}

		if (r.message.p12file) {
		    $('#p12-group')
		    .addClass('has-error')
		    .append('<p class="form-control-error">'+r.message.p12file+'</p>');
		}

		if (r.message.cacertfile) {
		    $('#cacert-group')
		    .addClass('has-error')
		    .append('<p class="form-control-error">'+r.message.cacertfile+'</p>');
		}

		if (r.message.clicertfile) {
		    $('#clicert-group')
		    .addClass('has-error')
		    .append('<p class="form-control-error">'+r.message.clicertfile+'</p>');
		}

		if (r.message.clikeyfile) {
		    $('#clikey-group')
		    .addClass('has-error')
		    .append('<p class="form-control-error">'+r.message.clikeyfile+'</p>');
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

$('#ipsec-clients button[type="submit"]').on('click', function(e) {
    e.preventDefault();

    var data = {
	networks: [],
	configs: [],
	conns: []
    };

    $('#ipsec-clients [name=network]').each(function() {
	if ($(this).prop('checked')) {
	    data.networks.push($(this).val());
	}
    });

    $('#auth-configs tr:gt(0)').each(function() {
	if ($(this).is(':last-child')) {
	    return false;
	}

	data.configs.push({
	    name: $(this).data('oldname'),
	    type: $(this).data('ipsec_type'),
	    psk: $(this).data('psk'),
	    cfguser: $(this).data('cfguser'),
	    cfgpass: $(this).data('cfgpass')
	});
    });

    $('#ipsec-conns tr:gt(0)').each(function() {
	if ($(this).is(':last-child')) {
	    return false;
	}

	data.conns.push({
	    name: $(this).data('oldconnname'),
	    host: $(this).data('connhost'),
	    authconfig: $(this).data('authconfig'),
	    autostart: $(this).find('[name=autostart]').prop('checked')
	});
    });

    var $form = $(this).parents('form');
    pcwrt.submit_form($form, JSON.stringify(data), function(r) {
	$('#auth-configs').data('uncommitted', null);
	$('#ipsec-conns').data('uncommitted', null);
	pcwrt.apply_changes(r.apply);
    }, 'application/json');
});

$('#ipsec-update button[type="submit"]').on('click', function(e) {
    e.preventDefault();

    var data = {
	extaddr: $('#extaddr').val(),
	ipaddr: $('#ipaddr').val(),
	netmask: $('#netmask').val(),
	users: []
    };

    $('#users tr:gt(0)').each(function() {
	if ($(this).is(':last-child')) {
	    return false;
	}

	data.users.push({
	    type: $(this).data('type'),
	    name: $('td:first', $(this)).text().trim(),
	    password: $(this).data('password'),
	    create: $(this).data('username') == null,
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

	    $(this).data('username', $('td:first', $(this)).text().trim());
	});

	$('#ipsec-status').text(msgs.enabled)
	.parent().removeClass('alert-danger').addClass('alert-success');
	$('#disable-ipsec').removeClass('hidden');
	$('#restart-ipsec').removeClass('hidden');
	$('#enable-ipsec').addClass('hidden');
	$('#enable-disable').removeClass('hidden');
	$('#enable-alert').addClass('hidden');
	pcwrt.apply_changes(r.apply);
    }, 'application/json');
});

$('#enable-ipsec').on('click', function(e) {
    e.preventDefault();
    $('#enable-disable').addClass('hidden');
    $('#enable-alert').removeClass('hidden');
    $('#ipsec-settings').slideDown();
});

$('#disable-ipsec').on('click', function(e) {
    e.preventDefault();
    var $form = $(this).parents('form');
    disable_ipsec($form);
});

$('#restart-ipsec').on('click', function(e) {
    e.preventDefault();
    pcwrt.submit_form($('#restart-server'), {}, function(r) {
	pcwrt.show_message(msgs.restart_ipsec_title, msgs.restart_ipsec_message);
    });
});

$('#ipsec-conns').on('click', '.list-remove', function(e) {
    e.preventDefault();
    $('#ipsec-conns').data('deleteConfig', $(this).parents('tr').index());
    pcwrt.confirm_action(window.msgs.delete_ipsec_conn_title,
	window.msgs.delete_ipsec_conn_confirm+' "' + $(this).parent().text().trim() + '"?',
	function() {
	    var idx = $('#ipsec-conns').data('deleteConfig');
	    var cfg = $('#ipsec-conns tr:eq('+idx+') td:first').text().trim();
	    if (cfg == $('#connect-ipsec [name=cfg]').val()) {
		$('#connect-ipsec [name=cfg]').val('');
	    }
	    $('#ipsec-conns tr:eq('+idx+')').remove();
	    $('#ipsec-conns').data('uncommitted', true);
	}
    );
});

$('#ipsec-conns').on('click', '.list-edit', function(e) {
    e.preventDefault();

    var row = $(this).parent().parent();
    $('#conn-modal')
    .find('.modal-title').text(window.msgs.edit_ipsec_conn_title).end()
    .find('.form-group').removeClass('has-error').end()
    .find('.form-control-error').remove().end()
    .find('input:not([type=radio],[type=checkbox])').val('').end()
    .find('input[name=connname]').val($(this).parent().text().trim()).end()
    .find('input[name=connhost]').val(row.data('connhost')).end()
    .find('input[name=oldconnname]').val(row.data('oldconnname')).end()
    .find('#authconfig').val(row.data('authconfig')).end()
    .modal('show');
});

$('#ipsec-conns').on('click', 'span.glyphicon.logs', function(e) {
    e.preventDefault();
    pcwrt.fetch_data($('#get-clientlog').attr('action'), {}, function(d) {
	$('#logs-modal')
	.find('#client-logs').html(d)
	.end()
	.modal('show');
    });
});

$('#ipsec-conns').on('click', 'span.glyphicon.control', function(e) {
    e.preventDefault();

    if ($('#auth-configs').data('uncommitted') || $('#ipsec-conns').data('uncommitted')) {
	pcwrt.show_message(msgs.uncommitted_title, msgs.uncommitted_changes);
	return;
    }

    var $el = $(this);
    if ($el.hasClass('glyphicon-play')) {
	var $form = $('#connect-ipsec');
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
	var $form = $('#connect-ipsec');
	$('[name=action]', $form).val('stop');
	$('[name=cfg]', $form).val($el.parents('td:first').text().trim());
	pcwrt.submit_form($form, $form.serialize(), function(r) {
	    $el.parents('td:first').removeClass('running connected').addClass('stopped');
	    $el.removeClass('glyphicon-stop').addClass('glyphicon-play').attr('title', 'Start');
	}, null, false, window.msgs.stop_vpnconf + ' "' +$('[name=cfg]', $form).val()+ '"');
    }
});

$(function() {
    var f1 = $('[name=network]:first').parent().parent();
    $.each(fv.client.enabled_network, function(i, nw) {
	if (i > 0) {
	    var f2 = f1.clone();
	    f1.after(f2);
	    f1 = f2;
	}
	var $c = $('label', f1).contents();
	$c[$c.length - 1].nodeValue = nw.text;
	$('input', f1).prop('value', nw.name);
	$('input', f1).prop('checked', nw.enabled ? true : false);
    });

    if (fv.client.configs) {
	fv.client.configs.sort(function(a, b) {return a.name.toUpperCase() > b.name.toUpperCase()?1:-1;});
	$.each(fv.client.configs, function(i, cfg) {
	    var $row = $('<tr><td><span class="pull-right list-remove" title="Remove">&nbsp;</span>'
		    + '<span class="pull-right list-edit" title="Edit">&nbsp;</span>'
		    + cfg.name +'</td></tr>');
	    $row.data('oldname', cfg.name);
	    $row.data('ipsec_type', cfg.type);
	    $row.data('psk', cfg.psk);
	    $row.data('cfguser', cfg.username);
	    $row.data('cfgpass', cfg.password);
	    $row.data('cadn', cfg.cadn);
	    $row.data('clidn', cfg.clidn);
	    $('#auth-configs tr:last').before($row);
	});
    }

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
		$('#connect-ipsec [name=cfg]').val(conn.name);
		$row.find('td:first').addClass(conn.state).find('span.logs').show();
		if (conn.state != 'stopped') {
		    $row.find('.glyphicon.control').removeClass('glyphicon-play').addClass('glyphicon-stop').attr('title', 'Stop');
		}
	    }

	    $row.data('oldconnname', conn.name);
	    $row.data('connhost', conn.host);
	    $row.data('authconfig', conn.authconfig);
	    $('#ipsec-conns tr:last').before($row);
	});
    }

    pcwrt.populate_forms(fv.server);
    fv.server.users.sort(function(a, b) {return a.name.toUpperCase() > b.name.toUpperCase()?1:-1;});
    $.each(fv.server.users, function(i, v) {
	var row = '<tr><td><span class="pull-right list-remove" title="Delete user">&nbsp;</span>'
		+ '<span class="pull-right list-edit" title="Edit">&nbsp;</span>';
	if (v.type == 'ikev2') {
	    row += '<span class="pull-right glyphicon glyphicon-download-alt control" title="Download user certificate"></span>';
	}
 	row += v.name + '</td><td>'+(v.vpnout ? window.msgs.vpn : window.msgs.isp)
  	    +'</td><td class="text-center"><input type="checkbox" name="guest"'
	    + (v.guest ? ' checked' : '') + '></td></tr>';
	row = $(row)
	$('#users tr:last').before(row);
	row.data('username', v.name);
	row.data('type', v.type);
	if (v.type == 'ikev1') { row.data('password', v.password); }
    });

    if (fv.server.enabled == '0') {
    	$('#enable-disable').addClass('alert-danger').removeClass('alert-success');
	$('#ipsec-status').text(window.msgs.disabled);
	$('#enable-ipsec').removeClass('hidden');
    }
    else {
    	$('#enable-disable').removeClass('alert-danger').addClass('alert-success');
	$('#ipsec-status').text(window.msgs.enabled);
	$('#disable-ipsec').removeClass('hidden');
	$('#restart-ipsec').removeClass('hidden');
	$('#ipsec-settings').slideDown();
    }

    $('#authconfig').makecombo();
    update_auth_config_select();

    window.setInterval(function() {
	var $form = $('#connect-ipsec');
	var cfg = $('[name=cfg]', $form).val();
	if (pcwrt.is_empty(cfg)) { return; }
	pcwrt.fetch_data($form.data('state_url'), { cfg: cfg }, function(d) {
	    var $el = null;
	    $('#ipsec-conns tr:gt(0)').find('td:first').removeClass('running connected stopped').each(function() {
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
