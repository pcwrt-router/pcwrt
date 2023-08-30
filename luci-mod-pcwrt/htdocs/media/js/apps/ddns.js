/*
 * Copyright (C) 2023 pcwrt.com
 * Licensed to the public under the Apache License 2.0.
 */

function change_service_provider() {
    var sp = $('#servicesel').val();
    $('.service-option').each(function() {
	if (this.id == sp.replace(/\./g, '_')) {
	    $(this).slideDown();
	}
	else {
	    $(this).slideUp();
	}
    });
}

$(function() {
    $('label.required').add_required_mark(window.msgs.required);
    $('label.control-label[data-hint]').init_hint();
    $('input[data-units]').makeunit();
    $('select').makecombo();
    $('input[type=password].reveal').reveal();

    pcwrt.populate_forms();
    change_service_provider();

    $('#servicesel').on('change', function() {
	change_service_provider();
    });

    $('button[type="submit"]').on('click', function (e) {
	e.preventDefault();
	var $form = $(this).parents('form');
	pcwrt.submit_form($form, $form.serialize(), function(r) {
	    pcwrt.apply_changes(r.apply);
	});
    });
});
