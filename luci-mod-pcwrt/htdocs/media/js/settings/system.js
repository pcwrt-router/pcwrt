/*
 * Copyright (C) 2023 pcwrt.com
 * Licensed to the public under the Apache License 2.0.
 */

function refresh_timezone() {
    if ($('input[value=filtered]', '#timezone-group').prop('checked')) {
	$('#zonename')
	.updatecombo(window.filtered_timezones.map(function(v) {return {text: v, value: v}}))
	.val(fv.zonename);
    }
    else {
	$('#zonename')
	.updatecombo(window.all_timezones.map(function(v) {return {text: v, value: v}}))
	.val(fv.zonename);
    }
}

function enable_ssh() {
    if ($('#enable-ssh').prop('checked')) {
	$('#enable-sshpwd').prop('disabled', false);
	$('#ssh-keys').prop('disabled', false);
    }
    else {
	$('#enable-sshpwd').prop('disabled', true);
	$('#ssh-keys').prop('disabled', true);
    }
}

$(function() {
    $('#localtime').text(fv.localtime);
    $('label.required').add_required_mark(window.msgs.required);
    $('label.control-label[data-hint]').init_hint();

    $('select').makecombo();
    pcwrt.populate_forms();

    if (fv.ntp_servers) {
	$.each(fv.ntp_servers, function(idx, svr) {
	    var $li = $('<li class="option-list"><span class="list-remove pull-right">&nbsp;</span></li>').append(svr);
	    $('#ntp-servers').append($li);
	});
    }

    enable_ssh();

    var form = $('#fetch-timezones');
    pcwrt.fetch_data(form.attr('action'), '', function(d) {
	window.all_timezones = d;
	$('[name=tz_offset]', form).val(new Date().stdTimezoneOffset());
	$('[name=dst]', form).val(new Date().hasDst());
	pcwrt.fetch_data(form.attr('action'), form.serialize(), function(d2) {
	    window.filtered_timezones = d2;
	    refresh_timezone();
	});
    });

    $('#sync-time').on('click', function(e) {
	e.preventDefault();
	$.ajax({
	    url: $(this).data('url'),
	    type: 'POST',
	    data: [{name: 'current_time', value: ~~(new Date().getTime()/1000)}],
	    success: function(r) {
		if (r.status == 'success') {
		    $('#localtime').text(r.message.current_time);
		}
	    },
	    error: function(xhr, err, msg) {
		console.log('Error: ' + msg);
	    }
	});
    });

    window.syncTimer = window.setInterval(function() {
	$.ajax({
	    url: $('#sync-time').data('url'),
	    success: function(r) {
		if (r.status == 'success') {
		    $('#localtime').text(r.message.current_time);
		}
	    }
	});
    }, 5000);

    $('input', '#timezone-group').on('click', function() {
	refresh_timezone();
    });

    $('#flash-div .btn-file :file').on('fileselect', function(e, numFiles, label) {
	$('#flash-div [name=image-name]').val(label);
    });

    $('#restore-modal .btn-file :file').on('fileselect', function(e, numFiles, label) {
	$('#restore-modal [name=archive-name]').val(label);
    });

    $('#ntp-server').next().on('click', function() {
	var $c = $(this).parent().parent();
	$c.removeClass('has-error')
	.find('.form-control-error').remove();

	var server = $(this).prev().val();
	if (!pcwrt.is_valid_hostname(server)) {
	    $c.addClass('has-error')
	    .append('<p class="form-control-error">Invalid hostname</p>');
	    return;
	}

	$('#ntp-servers li').each(function() {
	    if ($(this).text().trim().toLowerCase() == server.toLowerCase()) {
		server = null;
		return false;
	    }
	});

	if (!server) {
	    $c.addClass('has-error')
	    .append('<p class="form-control-error">NTP server already added.</p>');
	    return;
	}

	$(this).parent().prev().append('<li class="option-list"><span class="list-remove pull-right">&nbsp;</span>'+server+'</li>');
	$(this).prev().val('');
    });

    $('#ntp-servers').on('click', 'span.list-remove', function() {
	$(this).parent().remove();
    });

    $('form[name=general] button[type=submit]').on('click', function(e) {
    	e.preventDefault();
	var $form = $(this).parents('form');
	pcwrt.submit_form($form, function() {
	    var data = $form.serializeArray(); 
	    $('#ntp-servers li').each(function() {
		data.push({
		    name: 'ntp_servers',
		    value: $(this).text().trim()
		});
	    });
	    return data;
	},
	function(r) {
	    pcwrt.apply_changes(r.apply);
	});
    });

    $('#change-password-btn').on('click', function(e) {
    	e.preventDefault();
	$('#password-modal').modal('show');
    });

    $('form[name=change-password] button[type=submit]').on('click', function(e) {
    	e.preventDefault();
	var $form = $(this).parents('form');
	pcwrt.submit_form($form, $form.serialize(), function(r) {
	    $('#password-modal').modal('hide');
	    $('#status-modal .modal-title').text(window.msgs.success);
	    $('#status-modal .modal-body p').text(r.message);
	    $('#status-modal').modal('show');
	});
    });

    $('#password-modal').on('hidden.bs.modal', function(e) {
	$('.has-error', $(this)).removeClass('has-error');
	$(this).find('.form-control-error').remove();
    });

    $('#enable-ssh').on('click', function() {
	enable_ssh();
    });

    $('form[name=admin] button[type=submit]').on('click', function(e) {
	e.preventDefault();
	var $form = $(this).parents('form');
	pcwrt.submit_form($form, $form.serialize(), function(r) {
	    pcwrt.apply_changes(r.apply);
	});
    });

    $('form[name=hosts-form] button[type=submit]').on('click', function(e) {
	e.preventDefault();
	var $form = $(this).parents('form');
	pcwrt.submit_form($form, $form.serialize(), function(r) {
	    $('#status-modal .modal-title').text(window.msgs.success);
	    $('#status-modal .modal-body p').text(window.msgs.apply_success);
	    $('#status-modal').modal('show');
	});
    });

    $('#reset-settings').on('click', function(e) {
	window.clearInterval(window.syncTimer);
	pcwrt.confirm_submit(e, $(this), msgs.reset_settings_title, msgs.reset_settings_message, msgs.resetting, '', function(r) {
	    $('<iframe/>', {src: r.reload_url+'?addr='+r.addr}).appendTo('#reloader');
	});
    });

    $('#restore-backup').on('click', function(e) {
	e.preventDefault();
	$('#restore-modal')
	.find('.form-group').removeClass('has-error').end()
	.find('.form-control-error').remove().end()
	.find('.prgs').remove().end()
	.modal('show');
    });

    $('#restore-modal form').ajaxForm({
	beforeSubmit: function(formData, jqForm, options) {
	    $('#restore-modal .form-control-error')
	    .parent().removeClass('has-error')
	    .end().remove();

	    var form = jqForm[0];
	    if (!form.archive.value) {
		$('#restore-modal form .form-group:first')
		.addClass('has-error')
		.append('<p class="form-control-error">'+msgs.select_archive+'</p>');
		return false;
	    }
	    return true;
	},
	beforeSend: function() {
	},
	uploadProgress: function(e, position, total, pct) {
	    var bar = $('#restore-modal .bar');
	    var percent = $('#restore-modal .percent');
	    if (bar.length == 0) {
		bar = $('<div class="bar"></div>');
		percent = $('<div class="percent"></div>');
		var progress = $('<div class="prgs"></div>');
		progress.append(bar);
		progress.append(percent);
		$('#restore-modal .modal-body').append(progress);
	    }
	    bar.width(pct+'%');
	    percent.html(pct+'%');
	},
	success: function() {
	    $('#restore-modal .bar').width('100%');
	    $('#restore-modal .percent').html('100%');
	},
	complete: function(xhr) {
	    $('#restore-modal').modal('hide');
	    var r = xhr.responseJSON;
	    if (r.status == 'success') {
		if (r.reload_url) {
		    window.clearInterval(window.syncTimer);
		    $('#spinner strong').text(window.msgs.restoring);
		    pcwrt.showOverlay($('#spinner'));
		    $('<iframe/>', {src: r.reload_url+'?addr='+r.addr}).appendTo('#reloader');
		}
		else if (r.apply) {
		    pcwrt.apply_changes(r.apply);
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

    $('#flash-div form[name=upload]').ajaxForm({
	beforeSubmit: function(formData, jqForm, options) {
	    $('#flash-div .form-control-error')
	    .parent().removeClass('has-error')
	    .end().remove();

	    var form = jqForm[0];
	    if (!form.image.value) {
		$('#flash-div form .form-group:first')
		.addClass('has-error')
		.append('<p class="form-control-error">'+msgs.select_image+'</p>');
		return false;
	    }
	    return true;
	},
	beforeSend: function() {
	    $('#flash-div .bar').width('0%');
	    $('#flash-div .percent').html('0%');
	},
    	uploadProgress: function(e, position, total, pct) {
	    if ($('#flash-div .prgs').hasClass('hidden')) {
		$('#flash-div .prgs').removeClass('hidden');
	    }
	    $('#flash-div .bar').width(pct+'%');
	    $('#flash-div .percent').html(pct+'%');
	},
	success: function() {
	    $('#flash-div .bar').width('100%');
	    $('#flash-div .percent').html('100%');
	},
	complete: function(xhr) {
	    $('#flash-div .prgs').addClass('hidden');
	    var r = xhr.responseJSON;
	    if (r.status == 'success') {
		$('#flash-modal')
		.find('.modal-body p').addClass('hidden')
		.end().modal('show');

		$('#flash-message-'+r.code).removeClass('hidden');
		if (r.code == 'md5ok' || r.code == 'md5unchecked') {
		    $('#flash-message-ok').removeClass('hidden');
		    $('#flash-modal button[type=submit]').show();
		    $('#flash-modal input[name=keep]').val(r.keep == '1' ? '1':'0');
		    if (r.keep == '1') {
			$('#flash-message-keep').removeClass('hidden');
		    }
		    else {
			$('#flash-message-erase').removeClass('hidden');
		    }
		}
		else {
		    $('#flash-modal button[type=submit]').hide();
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

    $('#flash-modal button[type=submit]').on('click', function(e) {
	e.preventDefault();
	window.clearInterval(window.syncTimer);
	var $form = $(this).parents('form');
	$('#spinner strong').html(window.msgs.updating.join("<br><br>"));
	pcwrt.showOverlay($('#spinner'));
	pcwrt.submit_form($form, $form.serialize(), function(r) {
	    $('<iframe/>', {src: r.reload_url+'?addr='+r.addr}).appendTo('#reloader');
	}, null, true);
    });
});
