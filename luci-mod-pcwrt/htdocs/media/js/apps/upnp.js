function display_disabled() {
    $('#upnp-status').text(msgs.disabled)
    .parent().removeClass('alert-success').addClass('alert-danger');
    $('#enable-upnp').removeClass('hidden');
    $('#disable-upnp').addClass('hidden');
    $('#upnp-settings').slideUp();
}

function disable_upnp($form) {
    pcwrt.submit_form($form, {disabled: '1'}, function(r) {
	display_disabled();
	pcwrt.apply_changes(r.apply);
    });
}

$(function() {
    pcwrt.populate_forms();

    $.each(fv.enabled_network, function(i, nw) {
	var f1 = $('[name=network]:first').parent().parent();
	if (i > 0) {
	    var f2 = f1.clone();
	    f1.parent().append(f2);
	    f1 = f2;
	}
	var $c = $('label', f1).contents();
	$c[$c.length - 1].nodeValue = nw.text;
	$('input', f1).prop('value', nw.name);
	$('input', f1).prop('checked', nw.enabled);
    });

    if (fv.disabled == '1') {
    	$('#enable-disable').addClass('alert-danger').removeClass('alert-success');
	$('#upnp-status').text(window.msgs.disabled);
	$('#enable-upnp').removeClass('hidden');
    }
    else {
    	$('#enable-disable').removeClass('alert-danger').addClass('alert-success');
	$('#upnp-status').text(window.msgs.enabled);
	$('#disable-upnp').removeClass('hidden');
	$('#upnp-settings').slideDown();
    }

    $('#enable-upnp').on('click', function(e) {
	e.preventDefault();
	$('#enable-disable').addClass('hidden');
	$('#enable-alert').removeClass('hidden');
	$('#upnp-settings').slideDown();
    });

    $('#disable-upnp').on('click', function(e) {
	e.preventDefault();
	var $form = $(this).parents('form');
	disable_upnp($form);
    });

    $('#upnp-update button[type="submit"]').on('click', function (e) {
	e.preventDefault();

	var enable = false;
	$('[name=network]').each(function(i, e) {
	    if ($(e).prop('checked')) {
		enable = true;
		return false;
	    }
	});

	var $form = $(this).parents('form');
	if (!enable) {
	    pcwrt.confirm_action('Disable UPnP?', 'You have not selected an internal network to enable UPnP, do you want to disable UPnP instead?', function() {
		$('#enable-disable').removeClass('hidden');
		$('#enable-alert').addClass('hidden');
		if (fv.disabled == '1') {
		    display_disabled();
		}
		else {
		    disable_upnp($form);
		}
	    });
	}
	else {
	    pcwrt.submit_form($form, $form.serialize(), function(r) {
		$('#upnp-status').text(msgs.enabled)
		.parent().removeClass('alert-danger').addClass('alert-success');
		$('#disable-upnp').removeClass('hidden');
		$('#enable-upnp').addClass('hidden');
		$('#enable-disable').removeClass('hidden');
		$('#enable-alert').addClass('hidden');
		pcwrt.apply_changes(r.apply);
	    });
	}
    });
});
