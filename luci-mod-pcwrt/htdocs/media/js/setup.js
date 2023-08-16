function refresh_timezone() {
    var tz = fv.zonename;
    if (!tz) {
	try {
	    tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
	}
	catch (e) {}
    }
    
    if ($('input[value=filtered]', '#timezone-group').prop('checked')) {
	$('#zonename')
	.updatecombo(window.filtered_timezones.map(function(v) {return {text: v, value: v}}))
	.val(tz);
    }
    else {
	$('#zonename')
	.updatecombo(window.all_timezones.map(function(v) {return {text: v, value: v}}))
	.val(tz);
    }
}

function encryption_change($e) {
    var v = $e.val();
    var $tab = $e.parents('.tab-pane:first');
    if (v == 'none') {
	$('.key-div', $tab).slideUp();
	$('.cipher-div', $tab).slideUp();
    }
    else {
	$('.cipher-div', $tab).slideDown();
	$('.key-div', $tab).slideDown();
    }
}

function checkPassword() {
    var err = '';
    $('#password1,#password2').parent().removeClass('has-error');
    if (/^\s*$/.test($('#password1').val())) {
    	err = window.msgs.enter_password;
    	$('#password1').parent().addClass('has-error');
    }
    else if (/^\s*$/.test($('#password2').val())) {
    	err = window.msgs.confirm_password;
    	$('#password2').parent().addClass('has-error');
    }
    else if ($('#password1').val() != $('#password2').val()) {
    	err = window.msgs.password_not_match;
    	$('#password1,#password2').parent().addClass('has-error');
    }
    return err;
}

function checkWifi_tab($li) {
    var err = '';
    var $tab = $('#wifi-panel .tab-pane:eq('+$li.index()+')');

    if ($tab.data('disabled')) { return null; }

    $('[name=ssid],[name=key]', $tab).parent().removeClass('has-error');

    if (/^\s*$/.test($('[name=ssid]', $tab).val())) {
	err = window.msgs.enter_ssid;
	$('[name=ssid]', $tab).parent().addClass('has-error');
    }
    else if ($('[name=encryption]', $tab).val() != 'none') {
	var key = $('[name=key]', $tab).val();
	if (key.length < 8 || key.length > 64 || (key.length == 64 && !/^[0-9A-Fa-f]{64}$/.test(key))) {
	    err = window.msgs.enc_key_invalid;
	    $('[name=key]', $tab).parent().addClass('has-error');
	}
    }
    return err;
}

function checkWifi() {
    var err = '';
    var $a;
    $('#wifi-panel .nav-tabs li').each(function() {
	$a = $('a', $(this));
	err = checkWifi_tab($(this));
	if (err) {
	    $a.tab('show');
	    return false;
	}
    });

    return err;
}

function add_options(e, opts) {
    $.each(opts, function(idx, opt) {
	e.append($('<option/>').attr('value', opt.value).text(opt.text));
    });
}

var panels = ['pwd', 'tz', 'wifi'];
var np = 0;

function displayPanel(p) {
    p = p.replace(/set-(.*)-btn/, '$1');
    var a = $('#top-buttons').data('active');
    var err = '';
    if (a == 'pwd') {
	err = checkPassword();
	if (err) {
	    p = 'pwd';
	}
    }
    else if (a == 'wifi') {
	err = checkWifi();
	if (err) {
	    p = 'wifi';
	}
    }

    if (err) {
	$('#error-msg').text(err).parent().removeClass('hidden');
    }
    else {
	$('#error-msg').text('').parent().addClass('hidden');
    }
    _displayPanel(p);
}

function _displayPanel(p) {
    $('#top-buttons button').removeClass('btn-primary').addClass('btn-default');
    $('#set-'+p+'-btn').removeClass('btn-default').addClass('btn-primary');
    $('.setup-panel').addClass('hidden');
    $('#'+p+'-panel').removeClass('hidden');
    $('#action-panel button').addClass('hidden');
    if (p == 'pwd') {
	$('#next-btn').removeClass('hidden');
    }
    else if (p == 'tz') {
	$('#next-btn').removeClass('hidden');
	$('#back-btn').removeClass('hidden');
    }
    else if (p == 'wifi') {
	$('#back-btn').removeClass('hidden');
	$('#finish-btn').removeClass('hidden');
    }
    $('#top-buttons').data('active', p);
    for (var i = 0; i < panels.length; i++) {
	if (panels[i] == p) {
	    np = i;
	    break;
	}
    }
}

$('#wifi-panel').on('click', '.disable-wifi', function(e) {
    if ($(this).text() == window.msgs.disable) {
	$(this).parent().siblings().hide();
	$(this).text(window.msgs.enable);
	$(this).parent().next().show().next().show();
	$(this).parent().parent().data('disabled', true);
    }
    else {
	$(this).parent().siblings().show();
	$(this).text(window.msgs.disable);
	$(this).parent().next().hide().next().hide();
	$(this).parent().parent().data('disabled', false);
    }
});

$('#back-btn').click(function(e) {
    e.preventDefault();
    if (np == 0) {
	return;
    }

    if (panels[np] == 'wifi') {
	var idx = $('#wifi-panel .tab-pane:visible').index();
	if (idx == 1) {
	    $('#error-msg').text('').parent().addClass('hidden');
	    $('[name=ssid],[name=key]', $('#wifi-panel .tab-pane:eq(1)')).parent().removeClass('has-error');
	    $('#wifi-panel .nav-tabs>li:first a').tab('show');
	    return;
	}
    }

    np--;
    displayPanel(panels[np]);
});

$('#next-btn').click(function(e) {
    e.preventDefault();
    if (np == (panels.length - 1)) {
	return;
    }

    if (panels[np] == 'wifi') {
	var idx = $('#wifi-panel .tab-pane:visible').index();
	if (idx == 0) {
	    var err = checkWifi_tab($('#wifi-panel .nav-tabs li:first'));
	    if (err) {
		$('#error-msg').text(err).parent().removeClass('hidden');
		return;
	    }

	    $('#error-msg').text('').parent().addClass('hidden');
	    if ($('#wifi-panel .nav-tabs>li').length > 1) {
		$('#wifi-panel .nav-tabs>li:eq(1) a').tab('show');
		return;
	    }
	}
    }

    np++;
    displayPanel(panels[np]);
});

$('#top-buttons button').click(function(e) {
    e.preventDefault();
    displayPanel($(this).attr('id'));
});

$('#finish-btn').click(function(e) {
    e.preventDefault();
    var p = '';
    var err = checkPassword();
    if (err) {
	p = 'pwd';
    }
    else {
	err = checkWifi();
	if (err) {
	    p = 'wifi';
	}
    }

    if (err) {
	$('#error-msg').text(err).parent().removeClass('hidden');
	_displayPanel(p);
	return;
    }

    $('#error-msg').text('').parent().addClass('hidden');
    $(this).parents('form').submit();
});

$('input', '#timezone-group').click(function(e) {
    refresh_timezone();
});

$(function() {
    for (var i = 1; i < fv.devices.length; i++) {
	var p = $('#wifi-panel .nav-tabs>li:first').clone();
	p.removeClass('active');
	$('#wifi-panel .nav-tabs').append(p);

	var w = $('#wifi-panel .tab-content>div:first').clone();
	w.removeClass('in active');
	$('#wifi-panel .tab-content').append(w);
    }

    if (fv.devices.length > 1) {
	$('#wifi-panel .nav-tabs').show();
    }

    $.each(fv.devices, function(idx, d) {
	var $tab = $('#wifi-panel')
	.find('.nav-tabs>li:eq('+idx+') a')
	.attr('href', '#'+d.band.replace(/[^0-9a-zA-Z]/g, '-'))
	.attr('aria-controls', d.band)
	.text(d.band)
	.end()
	.find('.tab-pane:eq('+idx+')')
	.attr('id', d.band.replace(/[^0-9a-zA-Z]/g, '-'));

	$tab.data('name', d['.name']);
	add_options($('[name=encryption]', $tab), d.encryptions);
	add_options($('[name=cipher]', $tab), d.ciphers);
	$('[name=ssid]', $tab).val(d.ssid);
	$('[name=encryption]', $tab).val(d.encryption);
	$('[name=cipher]', $tab).val(d.cipher);
	encryption_change($('[name=encryption]', $tab));
    });

    $('[name=encryption]').change(function() {
	encryption_change($(this));
    });

    $('select').makecombo();
    $('input[type=password].reveal').reveal();

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

    _displayPanel('pwd');

    $('#setup-form').submit(function(e) {
	e.preventDefault();

	var devs = [];
	$('#wifi-panel .tab-pane').each(function() {
	    var dev = {};
	    dev['.name'] = $(this).data('name');
	    if ($(this).data('disabled')) {
		dev.disabled = true;
	    }
	    else {
		dev.ssid = $('[name=ssid]', $(this)).val();
		dev.encryption = $('[name=encryption]', $(this)).val();
		dev.cipher = $('[name=cipher]', $(this)).val();
		dev.key = $('[name=key]', $(this)).val();
	    }
	    devs.push(dev);
	});

	$('[name=devices]', this).val(JSON.stringify(devs));

	this.submit();
    });
});
