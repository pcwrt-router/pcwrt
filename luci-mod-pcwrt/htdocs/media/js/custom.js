(function($) {
Date.prototype.stdTimezoneOffset = function() {
    var jan = new Date(this.getFullYear(), 0, 1);
    var jul = new Date(this.getFullYear(), 6, 1);
    return Math.max(jan.getTimezoneOffset(), jul.getTimezoneOffset());
}

Date.prototype.hasDst = function() {
    var jan = new Date(this.getFullYear(), 0, 1);
    var jul = new Date(this.getFullYear(), 6, 1);
    return jan.getTimezoneOffset() != jul.getTimezoneOffset();
}

Date.prototype.dst = function() {
    return this.getTimezoneOffset() < this.stdTimezoneOffset();
}

$(document).on('change', '.btn-file :file', function() {
    var input = $(this),
    numFiles = input.get(0).files ? input.get(0).files.length : 1,
    label = input.val().replace(/\\/g, '/').replace(/.*\//, '');
    input.trigger('fileselect', [numFiles, label]);
});

$.fn.startRotate = function(clockwise) {
    return this.each(function() {
	function rotateForEver($elem, rotator) {
	    if (rotator === void(0)) {
		rotator = $({deg: 0});
	    } else {
		rotator.get(0).deg = 0;
	    }

	    return rotator.animate(
		{deg: 360},
		{
		    duration: 2500,
		    easing: 'linear',
		    step: function(now) {
			if (!clockwise) {
			    now = -now;
			}
			$elem.css({transform: 'rotate(' + now + 'deg)'});
		    },
		    complete: function(){
			if (!$elem.data('_stop_rotation_')) {
			    rotateForEver($elem, rotator);
			}
		    },
		}
	    );
	}
			
	$(this).data('_stop_rotation_', null);
	rotateForEver($(this));
    });
};

$.fn.stopRotate = function() {
    return this.each(function() {
	$(this).data('_stop_rotation_', true);
    });
}

$.fn.makecombo = function() {
  this.each(function() {
    if ($(this).data('makecombo')) {
	return;
    }

    var $sel = $(this);
    var editable = $(this).data('editable');

    var $input = $('<input type="text">');
    $input.attr("class", $(this).attr("class"));
    $input.attr("name", $(this).attr("name"));
    if ($(this).attr("id")) {
	$input.attr("id", $(this).attr("id"));
	$(this).attr("id", $(this).attr("id") + "-no-longer-used");
    }

    if (editable == true) {
	$input.attr('tabindex', $(this).attr('tabindex'));
	$(this).prop('disabled', true);
    }
    else {
	$input.attr("tabindex", "-1");
	$input.prop("disabled", true);
	$input.addClass("combo-facade");
    }

    var $grpbtn = $('<div class="input-group-btn">');
    $grpbtn.append('<button type="button" class="btn btn-default dropdown-toggle" data-toggle="dropdown"><span class="caret"></span></button>');

    var $ul = $('<ul class="dropdown-menu pull-right">');
    for (var i = 0; i < $(this).children().length; i++) {
	var e = $($(this).children()[i]);
	if (e.is('option')) {
	    if (!e.prop('disabled')) {
		var $li = $('<li><a href="#">'+e.text()+'</a></li>');
		$li.data('idx', i);
		$ul.append($li);
	    }
	}
	else if (e.is('optgroup')) {
    	    $ul.append('<li class="divider"></li>');
	}
    }
    $grpbtn.append($ul);
		
    var $grp = $('<div class="control-group input-group combo-group">');
    $grp.append($input);
    $grp.append($grpbtn);

    $(this).after($grp);
    $(this).data('idx', -1);
    if ($(this).val()) {
	$input.val($(this).val());
    }
    else {
	$input.val($('option:first', $(this)).attr('value'));
    }

    // hookup events
    var events = jQuery._data(this, "events");
    if (events) $.each(events, function(i, event) {
        $.each(event, function(j, h) {
    	    $input.on(i, h.handler);
	});
    });

    $ul.on('click', 'li a', function(e) {
	e.preventDefault();
    });

    $ul.on('click', 'li[class!=divider]', function() {
	var c = $(this).parent().parent().prev();
	var d = c.parent().prev();
	var v = c.val(); 
	d.val(d.children(':eq('+$(this).data('idx')+')').attr('value'));
	c.val(d.val());
	$(this).parent().prev().trigger('focus');
	if (d.data('idx') != $(this).data('idx')) {
	    if (typeof($input.change) == 'function') $input.trigger('change');
	    c.trigger('selection.change', [$(this).index(), d.val(), d.children(':eq('+$(this).index()+')').text()]);
	    $sel.trigger('selection.change', [$(this).index(), d.val(), d.children(':eq('+$(this).index()+')').text()]);
	}
    });

    $ul
    .on('keydown', function(event) {
	var len = $('a', $(this)).length;
	var selected = 0;
	if (typeof($(this).data('selected')) != 'undefined') {
	    selected = $(this).data('selected');
	}

	if (event.which == 38 || event.which == 40) {
	    event.preventDefault();
	    selected = event.which == 38 ?
		(selected - 1) % len :
		(selected + 1) % len;
	    $(this)
	    .data('selected', selected)
	    .find('a:eq('+selected+')')
	    .trigger('focus');
	}
	else if ((event.which >= 65) && (event.which <= 90)) {
	    event.preventDefault();
	    for (var i = 1; i < len; i++) {
		var j = (selected + i) % len;
		var c = $('a:eq('+j+')', $(this)).text().charCodeAt(0);
		if (c >= 97) {
	    	    c -= 32;
		}
	
		if (c == event.which) {
		    selected = j;
		    $(this)
		    .data('selected', selected)
		    .find('a:eq('+selected+')')
		    .trigger('focus');
		    break;
		}
	    }
	}
    })
    .on('mouseover', 'li', function() {
        $(this).parent().data('selected', $(this).index());
	$('a', $(this)).trigger('focus');
    });

    $grpbtn
    .on('shown.bs.dropdown', function() {
	$ul.outerWidth($ul.parent().parent().outerWidth());
	window.setTimeout(function() { 
    	    var i = $grp.prev().children(':selected').index();
    	    $('li:eq('+i+') a', $grpbtn).trigger('focus'); 
    	    $ul.data('selected', i);
	}, 50);
    });

    $(this).data('makecombo', true);
    $(this).hide();
  });
  return this;
};

$.fn.updatecombo = function(newvalues) {
    var $el = this.first();
    if (!$el.parent().hasClass('combo-group') || !$el.parent().prev().is('select:not(visible)')) {
	return this;
    }

    var $ul = $el.next().find('ul').empty();
    $.each(newvalues, function(i, v) {
	var $li = $('<li><a href="#">'+v.text+'</a></li>');
	$li.data('idx', i);
	$ul.append($li);
    });

    var $sel = $el.parent().prev().empty();
    $.each(newvalues, function(i, v) {
	$sel.append('<option value="'+v.value+'">'+v.text+'</option>');
    });
    $sel.data('idx', -1);

    $el.val($sel.val());
    return this;
}

$.fn.makeunit = function() {
    this.each(function() {
	var $input = $(this);
	var units = $input.data('units');
	if (units == null) return;
	units = units.split(';');
	if (units.length == 0) return;

	var f = units[0].split('=');
	$input.data('unit', f[1]);

	var $grpbtn = $('<div class="input-group-btn">');
	$grpbtn.append('<button type="button" class="btn btn-default dropdown-toggle" data-toggle="dropdown">'
	+ f[0] + '&nbsp;&nbsp;<span class="caret"></span></button>');
	var $ul = $('<ul class="dropdown-menu pull-right">');
	for (var i = 0; i < units.length; i++) {
	    var u = units[i].split('=');
	    $ul.append('<li><a href="#'+u[1]+'">'+u[0]+'</a></li>');
	}
	$grpbtn.append($ul);

	var $grp = $('<div class="control-group input-group">');
	$input.after($grp);
	$grp.append($input);
	$grp.append($grpbtn);

	$('li a', $ul).on('click', function(e) {
	    e.preventDefault();
	    var unit = $(this).attr('href').substring(1);
	    $input.data('unit', unit);
	    $input.trigger('unit.change', unit);
	    $(this).parent().parent().prev().html($(this).text()+'&nbsp;&nbsp;<span class="caret"></span>');
	});
    });
    return this;
}

$.valHooks.input = {
    get: function(e) {
	if ($(e).hasClass("combo-facade")) {
	    return $(e).parent().prev().val();
	}
	else if ($(e).data('units') && $(e).data('unit')) {
	    return $(e).prop('value') + $(e).data('unit');
	}
	else if ($(e).hasClass('reveal') && $(e).is(':disabled')) {
	    var s = $(e).parent().next().find('[name='+$(e).attr('name')+']:enabled');
	    if (s.length == 0) {
		s = $(e).parent().prev().find('[name='+$(e).attr('name')+']:enabled');
	    }
	    return s.length == 0 ? $(e).prop('value') : s.prop('value');
	}
	else {
	    return $(e).prop('value');
	}
    },

    set: function(e, v) {
	if ($(e).hasClass("combo-facade")) {
	    var $sel = $(e).parent().prev();
	    var oldv = $sel.val();
	    $sel.val(v);
	    if ($sel.val() == null) {
		$sel.val(oldv);
	    }
	    $(e).prop('value', $sel.children('option:eq('+$sel.prop('selectedIndex')+')').text());
	}
	else if ($(e).data('units') && $(e).data('unit')) {
	    if (!v) {
		$(e).prop('value', '');
	    }
	    else {
		var unit = '';
		var label = '';
		var units = $(e).data('units').split(';');
		for (var i = 0; i < units.length; i++) {
		    var u = units[i].split('=');
		    if (v.substr(v.length - u[1].length) === u[1]) {
			label = u[0];
			unit = u[1];
			break;
		    }
		}
		
		$(e).prop('value', v.substr(0, v.length - unit.length));
		if (unit) {
		    $(e).data('unit', unit);
		    $(e).trigger('unit.change', unit);
		    $(e).next().find('button').html(label+'&nbsp;&nbsp;<span class="caret"></span>');
		}
	    }
	}
	else {
	    $(e).prop('value', v);
	    if ($(e).hasClass('reveal')) {
		var s = $(e).parent().next().find('[name='+$(e).attr('name')+']');
		if (s.length == 0) {
		    s = $(e).parent().prev().find('[name='+$(e).attr('name')+']');
		}

		if (s.length > 0) {
		    s.prop('value', v);
		}
	    }
	}
	return e;
    }
};

$.valHooks.checkbox = {
    get: function(e) {
	return $(e).prop('checked') ? e.value : null;
    },
    set: function(e, v) {
	$(e).prop('checked', e.value == v);
	return e;
    }
};

$.fn.init_hint = function() {
  this.each(function() {
    var label = $(this);
    label
    .mouseover(function() {
	if (label.find('span.hint').length == 0) {
	    label.append('<span class="hint" style="display:none;"></span>');
	}

	if (!label.data('hintTimer')) {
	    label.data('hintTimer', window.setTimeout(function() {
		label.find('span.hint').show();
		label.data('hintTimer', null);
	    }, 500));
	}

	if (label.data('hideTimer')) {
	    window.clearTimeout(label.data('hideTimer'));
	    label.data('hideTimer', null);
	}
    })
    .mouseout(function() {
	if (!label.data('hideTimer')) {
	    label.data('hideTimer', window.setTimeout(function() {
		label.find('span.hint').hide();
		label.data('hideTimer', null);
	    }, 500));
	}

	if (label.data('hintTimer')) {
	    window.clearTimeout(label.data('hintTimer'));
	    label.data('hintTimer', null);
	}
    })
    .popover({
	selector: 'span.hint',
	placement: 'right',
	trigger: 'manual',
	content: label.data('hint')
    })
    .on('mouseover', 'span.hint', function(e) {
	label.popover('show');
    })
    .on('mouseout', 'span.hint', function(e) {
	label.popover('hide');
    });
  });
  return this;
};

$.fn.add_required_mark = function(hint) {
  var title = hint ? hint : 'Required field';
  this.each(function() {
	$(this).before('<span class="required-mark" title="'+title+'"></span>');
  });
  return this;
};

$.fn.reveal = function() {
    this.each(function() {
	var $igrp, $igrp2;
	if ($(this).parent().hasClass('input-group')
	    && $(this).next().hasClass('glass-plus')
	    && $(this).parent().next().hasClass('input-group')) {
	    $igrp = $(this).parent();
	    $igrp2 = $igrp.next();
	}
	else {
	    $igrp = $('<div class="input-group"></div>');
	    $(this).before($igrp);
	    $igrp.append($(this));
	    $igrp.append('<span class="input-group-addon glass-plus">&nbsp;</span>');

	    var $txt = $(this).clone(true);
	    $txt.attr('type', 'text')
	    .attr('id', $(this).attr('id')+'-clone')
	    .prop('disabled', true);
	    $igrp2 = $('<div class="input-group hidden"></div>');
	    $igrp2.append($txt);
	    $igrp2.append('<span class="input-group-addon glass-minus">&nbsp;</span>')

	    $igrp.after($igrp2);
	}

	$igrp.find('.glass-plus').on('click', function() {
	    $(this).parent().addClass('hidden').next().removeClass('hidden')
	    .find('input').val($(this).prev().prop('disabled', true).val())
	    .prop('disabled', false);
	});

	$igrp2.find('.glass-minus').on('click', function() {
	    $(this).parent().addClass('hidden').prev().removeClass('hidden')
	    .find('input').val($(this).prev().prop('disabled', true).val()).prop('disabled', false);
	});
    });

    return this;
};

$.fn.addRangeSelect = function(color, cb, timeslots) {
  var $selected = this;
  var $tt = $('div.tooltip');

  $('.slider', $selected).remove();
  if (color == 'remove') {
	$tt.removeClass('top bottom fade in');
	$selected.off('click');
	$selected.data('click_hooked', null);
	return $selected;
  }

  if ($tt.length == 0) {
	$tt = $('<div class="tooltip">'
		  +'<div class="tooltip-arrow"></div>'
		  +'<div class="tooltip-inner"></div>'
		  +'</div>');
	$tt.appendTo('body');
  }

  function set_tt_value(v) {
	v = typeof(cb) == 'function' ? cb(v) : v;
	$('.tooltip-inner', $tt).text(v);
  }

  var tracker = function(elem) {
	function set_limits(el) {
		var t = 0;
		var b = el.parent().height();
		var c = el.position().top + 10;
		var h = $('.spacer', el).height();
		el.siblings().each(function() {
			var st = $(this).position().top + 10;
			if (st > (c+h) && st < b) {
				b = st - 1;
			}

			var sb = $(this).position().top + 10 + $('.spacer', $(this)).height();
			if (sb < c && sb > t) {
				t = sb + 1;
			}
		});

		el.data('top', t);
		el.data('bottom', b);
	}

	elem.on('keydown', function(e) {
		if (e.keyCode == 46) {
			var siblings = elem.siblings();
			elem.remove();
			siblings.each(function() {set_limits($(this));});
		}
	});

	elem.mousemove = function(e) {
		e.preventDefault();
		var c = elem.data('reverse') ? -1 : 1;
		var dy = c * (e.pageY - elem.data('mouseY'));
		if (elem.data('height') - dy < 0) {
			dy = elem.data('height');
		}

		if (c == 1) {
			var t = elem.data('y') + dy;
			if (t < elem.data('top') - 10) {
				t = elem.data('top') - 10;
			}
			elem.css('top', t);
			$('.spacer', elem).height(elem.data('height') + elem.data('y') - t);
		}
		else {
			var b = elem.position().top + elem.data('height') - dy + 10;
			if (b > elem.data('bottom')) {
				b = elem.data('bottom');
			}
			$('.spacer', elem).height(b - elem.position().top - 10);
		}

		set_tt_value(elem.position().top + 10 + ($tt.hasClass('bottom') ? $('.spacer', elem).height(): 0));
		$tt.css('left', (elem.outerWidth()-$tt.outerWidth())/2);
	};

	elem.mouseup = function(e) {
		elem.siblings().each(function() {set_limits($(this));});
		$(document).data('click-consumed', true);
		$(document).off({
			mousemove: elem.mousemove,
			mouseup: elem.mouseup
		});
	};

	$('.spacer', elem).on('click', function(e) {
		e.preventDefault();
		e.stopPropagation();

		$tt.removeClass('top bottom fade in');
		$('.slider', $selected).each(function() {
			if ($(this).height() > 20) {
				$(this).find('.upper,.lower').css('visibility', 'hidden');
			}
			else {
				$('.tooltip', this).appendTo('body');
				$(this).remove();
			}
		});

		$(this).siblings().css('visibility', 'visible')
		.end().parent().css('z-index', 1)
		.siblings().css('z-index', 0);

		set_limits($(this).parent());
		$(this).parent().siblings().each(function() {
			set_limits($(this));
		});
	});

	$('.upper,.lower', elem).mousedown(function(e) {
		elem.css('z-index', 1).siblings().css('z-index', 0);
		if ($(this).hasClass('upper')) {
			elem.prepend($tt);
			set_tt_value(elem.position().top + 10);
			$tt.removeClass('bottom').addClass('fade top in');
			$tt.css({
				'top': -$tt.outerHeight(),
				'left':(elem.outerWidth()-$tt.outerWidth())/2
			});
		}
		else {
			elem.append($tt);
			set_tt_value(elem.position().top + 10 + $('.spacer', elem).height());
			$tt.removeClass('top').addClass('fade bottom in');
			$tt.css({
				'top': 'auto',
				'left':(elem.outerWidth()-$tt.outerWidth())/2
			});
		}

		elem.data('mouseY', e.pageY);
		elem.data('y', elem.position().top);
		elem.data('height', $('.spacer', elem).height());
		elem.data('reverse', $(this).hasClass('lower'));
		$(document).on({
			mousemove: elem.mousemove,
			mouseup: elem.mouseup
		});
	});

	set_limits(elem);
	elem.css('z-index', 1).siblings().css('z-index', 0).each(function() {set_limits($(this));});
  };

  $selected.each(function(idx) {
	if (!$(this).data('click_hooked')) {
		$(this).on('click', function(e) {
			if ($(document).data('click-consumed')) {
				$(document).data('click-consumed', false);
				e.stopPropagation();
				return;
			}

			$tt.removeClass('top bottom fade in');
			$('.slider', $selected).each(function() {
				if ($(this).height() > 20) {
					$(this).find('.upper,.lower').css('visibility', 'hidden');
				}
				else {
					$('.tooltip', this).appendTo('body');
					$(this).remove();
				}
			});

			var $slider = $('<div class="slider">'
					+'<button class="upper"><span class="caret"></span></button>'
					+'<button class="spacer"></button>'
					+'<button class="lower"><span class="caret"></span></button>'
					+'</div>');
			$slider.css({
				top: e.pageY - $(this).offset().top - 10,
				left: '0',
				padding: '0 2px 0 2px',
				width: '100%'
			})
			.find('.spacer').css({
				'background-color': color
			});
			$(this).append($slider);

			tracker($slider);
			e.stopPropagation();
		});

		$(this).data('click_hooked', true);
	}

	if (timeslots instanceof Array) {
		var bands = timeslots[idx];
		if (bands instanceof Array) {
			for (var i = 0; i < bands.length; i++) {
				if ((!bands[i] instanceof Array) || 
					(bands[i].length != 2) || 
					(!(parseInt(bands[i][1]) > parseInt(bands[i][0])))) {
					continue;
				}

				var $slider = $('<div class="slider">'
						+'<button class="upper"><span class="caret"></span></button>'
						+'<button class="spacer"></button>'
						+'<button class="lower"><span class="caret"></span></button>'
						+'</div>');
				$slider.css({
					top: parseInt(bands[i][0]) - 10,
					left: 0,
					padding: '0 2px 0 2px',
					width: '100%'
				})
				.find('.spacer').css({
					'background-color': color
				})
				.outerHeight(parseInt(bands[i][1]) - parseInt(bands[i][0]))
				.end()
				.find('.upper,.lower').css('visibility', 'hidden');

				$(this).append($slider);
				tracker($slider);
			}
		}
	}
  });

  if (!$(document).data('dismiss-tt')) {
	$(document).on('click', function() {
		$('.tooltip').removeClass('top bottom fade in');
		$('.slider:visible').each(function() {
			if ($(this).height() > 20) {
				$(this).find('.upper,.lower').css('visibility', 'hidden');
			}
			else if ($(this).find('.upper,.lower').size() > 0) {
				/* This is real interactive slider, not the
				** ones in Calendars list, which is for display
				** only! */
				$('.tooltip', this).appendTo('body');
				$(this).remove();
			}
		});
	});
	$(document).data('dismiss-tt', true);
  }

  return this;
};
} (jQuery));

pcwrt = {
    overlayTimer: null,
    updateTimer: null,
    hideOverlayTimer: null,
    pixel2time: function(v, range) {
	if (range) {
	    v = Math.floor(v*1440/range + 0.6);
	}
	else {
	    v = Math.floor(v + 0.6);
	}
	var h = Math.floor(v/60);
	var m = v%60;
	var ap = h < 12 ? 'am' : 'pm';
	if (h >= 12) {h = h - 12;}
	if (h == 12) {ap = 'am';}
	if (h == 0) {h = 12;}

	return h + ':' + (m >= 10 ? m : '0'+m)+ ' ' + ap;
    },

    time2pixel: function(time, range) {
	if (typeof(time) != 'string' || !time) {
	    return null;
	}

	var hour = null, minute = null, ampm = null;
	time.replace(/^(\d?\d):(\d?\d) ?(am|pm)$/, function(str, p1, p2, p3) { 
		hour = parseInt(p1);
		minute = parseInt(p2);
		ampm = p3;
		return str; 
	});

	if (hour == null || isNaN(hour) || 
	    minute == null || isNaN(minute) || 
	    ampm == null) {
	    return null;
	}

	if (hour == 12) {
	    hour = 0;
	}

	if (ampm == 'pm') {
	    hour += 12;
	}

	if (range) {
	    return Math.floor((hour*60 + minute)*range/1440 + 0.6);
	}
	else {
	    return Math.floor(hour*60 + minute + 0.6);
	}
    },

    showOverlay: function(spinner) {
	if (pcwrt.hideOverlayTimer) {
	    window.clearTimeout(pcwrt.hideOverlayTimer);
	    pcwrt.hideOverlayTimer = null;
	}

	if (pcwrt.updateTimer || pcwrt.overlayTimer) {
	    return;
	}

	pcwrt.spinner = spinner;
	pcwrt.overlayTimer = window.setTimeout(function() {
	    $('#overlay')
	    .css({display: 'none', height: $(window).height()})
	    .addClass('active')
	    .fadeTo(375, 0.7);
	    spinner.addClass('active');
	    pcwrt.overlayTimer = null;
	    pcwrt.updateTimer = window.setInterval(function() {
		var t = $('strong', spinner).html();
		if (t.match(/( \.){25}$/)) {
		    $('strong', spinner).html(t.replace(/( \.){25}$/, ' .'));
		}
		else {
		    $('strong', spinner).html(t + ' .');
		}
	    }, 400);
	}, 500);
    },

    hideOverlay: function() {
	pcwrt.hideOverlayTimer = window.setTimeout(function() {
	    if (pcwrt.updateTimer) {
		window.clearInterval(pcwrt.updateTimer);
		pcwrt.updateTimer = null;
	    }

	    if (pcwrt.overlayTimer) {
		window.clearTimeout(pcwrt.overlayTimer);
		pcwrt.overlayTimer = null;
	    }

	    var txt = $('strong', pcwrt.spinner).html().replace(/( \.)*$/, ' .');

	    $(pcwrt.spinner)
	    .removeClass('active')
	    .find('strong')
	    .html(txt);

	    $('#overlay')
	    .css({height: '1px'})
	    .removeClass('active');
	}, 150);
    },

    updateOverlay: function() {
	$('#overlay').css({height: $('#overlay').hasClass('active')?$(window).height():'1px'});
    },

    fetch_data: function(url, data, cb) {
	$.ajax({
	    url: url,
	    data: data,
	    type: 'GET',
	    success: function(r) {
		if (r.status == 'success') {
		    cb(r.data);
		}
		else if (r.status == 'login') {
		    location.reload(true);
		}
		else {
		    $('#status-modal .modal-title').text(window.msgs.oops);
		    $('#status-modal .modal-body p')
		    .text('Status: '+r.status+', message: '+r.message);
		    $('#status-modal').modal('show');
		}
	    },
	    error: function(xhr, err, msg) {
		$('#status-modal .modal-title').text(window.msgs.oops);
		$('#status-modal .modal-body p').text(msg ? msg : 'Unknown error!');
		$('#status-modal').modal('show');
	    }
	});
    },

    submit_form: function($form, data, cb, contentType, omitSpinner, spinner_text, spinner_html) {
    	$('p.form-control-error', $form)
	.parent().removeClass('has-error')
	.end().remove();

	contentType = contentType ? contentType : 'application/x-www-form-urlencoded';

	if (!omitSpinner) {
	    if (spinner_text) {
		$('#spinner strong').text(spinner_text);
	    }
	    else if (spinner_html) {
		$('#spinner strong').html(spinner_html);
	    }
	    else {
		$('#spinner strong').text(msgs.apply_change);
	    }
	    pcwrt.showOverlay($('#spinner'));
	}

    	$.ajax({
	    url: $form.attr('action'),
	    type: 'POST',
	    contentType: contentType,
	    data: typeof(data) == 'function' ? data() : data,
	    success: function(r) {
		if (!omitSpinner) { pcwrt.hideOverlay(); }

	    	if (r.status == 'success') {
		    if (typeof(cb) == 'function') {
			cb(r);
		    }
		    else if (typeof(cb) == 'object' && typeof(cb.success) == 'function') {
			cb.success(r);
		    }
		}
		else if (r.status == 'error') {
		    if (typeof(cb) == 'object' && typeof(cb.error) == 'function') {
			cb.error(r);
		    }
		    else {
			for (name in r.message) {
			    var input = $(':input[name="'+name+'"]:visible', $form);
			    if (input.parent().hasClass('input-group')) {
				input = input.parent();
			    }
			    input.parent()
			    .addClass('has-error')
			    .append('<p class="form-control-error">'+r.message[name]+'</p>');
			}
		    }
		}
		else if (r.status == 'fail') {
		    $('#status-modal .modal-title').text(window.msgs.oops);
		    $('#status-modal .modal-body p').text(r.message);
		    $('#status-modal').modal('show');
		    if (typeof(cb) == 'object' && typeof(cb.fail) == 'function') {
			cb.fail(r);
		    }
		}
		else if (r.status == 'login') {
		    location.reload(true);
		}
		else {
		    $('#status-modal .modal-title').text(window.msgs.oops);
		    $('#status-modal .modal-body p')
		    .text('Status: '+r.status+', message: '+r.message);
		    $('#status-modal').modal('show');
		}
	    },
	    error: function(xhr, err, msg) {
		if (!omitSpinner) { pcwrt.hideOverlay(); }
		$('#status-modal .modal-title').text(window.msgs.oops);
		$('#status-modal .modal-body p').text(msg ? msg : 'Unknown error!');
		$('#status-modal').modal('show');
		if (typeof(cb) == 'object' && typeof(cb.fail) == 'function') {
		    cb.fail(r);
		}
	    }
	});
    },

    apply_changes: function(config, cb) {
	$('#spinner strong').text(msgs.apply_change);
	pcwrt.showOverlay($('#spinner'));
	if (Array.isArray(config)) {
	    config = config.join(' ');
	}
	$('#apply-form [name=config]').val(config);
	$form = $('#apply-form');
	$.ajax({
	    url: $form.attr('action'),
	    type: 'POST',
	    data: $form.serialize(),
	    success: function(r) {
		pcwrt.hideOverlay();
		$('#status-modal .modal-title').text(window.msgs.success);
		$('#status-modal .modal-body p').text(window.msgs.apply_success);
		$('#status-modal').modal('show');
		if (typeof(cb) == 'function') {
		    cb(r);
		}
	    },
	    error: function(xhr, err, msg) {
		pcwrt.hideOverlay();
		$('#status-modal .modal-title').text(window.msgs.oops);
		$('#status-modal .modal-body p').text('Failed: '+msg);
		$('#status-modal').modal('show');
	    }
	});
    },

    confirm_action: function(title, message, ycb, ncb) {
    	$('#confirm-modal')
	.data('confirmed', false)
	.find('.modal-title').text(title)
	.end()
	.find('.modal-body p').text(message)
	.end()
	.find('.btn-success')
	.off('click')
	.on('click', function(e) {
	    $('#confirm-modal').data('confirmed', true).modal('hide');
	})
	.end()
	.off('hidden.bs.modal')
	.on('hidden.bs.modal', function (e) {
	    if ($(this).data('confirmed')) {
		ycb();
	    }
	    else if (typeof(ncb) == 'function') {
		ncb();
	    }
	})
	.modal('show');
    },

    confirm_submit: function(e, $el, title, message, spinner_message, data, cb) {
        e.preventDefault();
	$('#confirm-modal')
	.find('.modal-title').text(title)
	.end()
	.find('.modal-body p').text(message)
	.end()
	.find('.btn-success')
	.off('click')
	.on('click', function(e2) {
	    e2.preventDefault();
	    $('#confirm-modal').modal('hide');
	    $('#spinner strong').html(spinner_message);
	    pcwrt.showOverlay($('#spinner'));
	    $.ajax({
		url: $el.data('url'),
		type: 'POST',
		data: data,
		success: function(r) {
		    cb(r);
		},
		error: function(xhr, err, msg) {
		    pcwrt.hideOverlay();
		    $('#status-modal .modal-title').text(window.msgs.oops);
		    $('#status-modal .modal-body p').text(msg ? msg : 'Unknown error!');
		    $('#status-modal').modal('show');
		}
	    });
	})
	.end()
	.modal('show');
    },

    show_message: function(title, message, dismiss_callback) {
	$('#status-modal .modal-title').text(title);
	$('#status-modal .modal-body p').text(message);
	$('#status-modal').off('hidden.bs.modal');
	if (typeof(dismiss_callback) == 'function') {
	    $('#status-modal').on('hidden.bs.modal', function() {
		dismiss_callback();
	    });
	}
	$('#status-modal').modal('show');
    },

    clear_form_errors: function($form) {
	$form
	.find('.form-group').removeClass('has-error').end()
	.find('.form-control-error').remove();
    },

    populate_forms: function(v) {
	var fv = v ? v : window.fv;
	for (k in fv) {
	    if ($('[name="'+k+'"]').attr('type') == 'radio') {
		$('[name="'+k+'"]').each(function() {
		    if ($(this).val() == fv[k]) {
			$(this).prop('checked', true);
			return false;
		    }
		});
	    }
	    else {
		$('[name="'+k+'"]').val(fv[k]);
	    }
	}
    },

    is_empty: function(v) {
	return /^\s*$/.test(v);
    },

    is_number: function(v) {
	return /^\d+/.test(v);
    },

    is_valid_macaddr: function(v) {
	return /^([0-9A-F]{2}:){5}([0-9A-F]{2})$/i.test(v);
    },

    is_valid_ipaddr: function(v) {
	return /^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/.test(v);
    },

    is_valid_hostname: function(v) {
	return v &&
	       v.length > 0 &&
	       v.length < 254 && 
	       (/^[a-zA-Z_]+$/.test(v) ||
	       (/^[a-zA-Z0-9_][a-zA-Z0-9_\-\.]*[a-zA-Z0-9]$/.test(v) &&
	        /[^0-9\.]/.test(v)));
    },

    is_valid_port: function(v) {
	return /^\d+$/.test(v) && parseInt(v) > 0 && parseInt(v) <= 65535;
    },

    is_valid_port_range: function(v) {
	if (!/^\d+-\d+$/.test(v)) {
	    return false;
	}

	ports = v.split('-');
	if (!this.is_valid_port(ports[0]) || !this.is_valid_port(ports[1]) || parseInt(ports[0]) >= parseInt(ports[1])) {
	    return false;
	}

	return true;
    },

    is_same_subnet: function(mask, ip1, ip2) {
	if (ip1 == ip2) {
	    return false;
	}

	var m = mask.split('.').map(function(v) { return parseInt(v); });
	var p1 = ip1.split('.').map(function(v) { return parseInt(v); });
	var p2 = ip2.split('.').map(function(v) { return parseInt(v); });
	return (m[0]&p1[0]) == (m[0]&p2[0]) && 
	       (m[1]&p1[1]) == (m[1]&p2[1]) &&
	       (m[2]&p1[2]) == (m[2]&p2[2]) &&
	       (m[3]&p1[3]) == (m[3]&p2[3]);
    }
};

$(window).on('resize', pcwrt.updateOverlay);

$('#reboot').on('click', function(e) {
    pcwrt.confirm_submit(e, $(this), msgs.reboot_title, msgs.reboot_message, msgs.rebooting, '', function(r) {
	$('<iframe src="'+r.reload_url+'"></iframe>').appendTo('#reloader');
    });
});

if (typeof(atob) == "undefined") {
    atob = function(s) {
       var e={},i,b=0,c,x,l=0,a,r='',w=String.fromCharCode,L=s.length;
       var A="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
       for(i=0;i<64;i++){e[A.charAt(i)]=i;}
       for(x=0;x<L;x++){
           c=e[s.charAt(x)];b=(b<<6)+c;l+=6;
           while(l>=8){((a=(b>>>(l-=8))&0xff)||(x<(L-2)))&&(r+=w(a));}
       }
       return r;
    };
};

function escapeXml(unsafe) {
    return unsafe.replace(/[<>&'"]/g, function (c) {
        switch (c) {
            case '<': return '&lt;';
            case '>': return '&gt;';
            case '&': return '&amp;';
            case '\'': return '&apos;';
            case '"': return '&quot;';
        }
    });
}

function is_ip_on_network(ip, ipaddr, netmask, exclude_router_ip) {
    if (typeof(ip) != 'string' || !ipaddr || !netmask) {
	return false;
    }

    if (exclude_router_ip && ip == ipaddr) { return false; }

    ip = ip.split('.');
    var gip = ipaddr.split('.')
    var gm = netmask.split('.')

    if (ip.length != 4 || gip.length != 4 || gm.length != 4) {
	return false;
    }

    return (ip[0] & gm[0]) == (gip[0] & gm[0]) &&
	   (ip[1] & gm[1]) == (gip[1] & gm[1]) &&
	   (ip[2] & gm[2]) == (gip[2] & gm[2]) &&
	   (ip[3] & gm[3]) == (gip[3] & gm[3]);
}

function random_string(charset, length, group_size) {
    group_size = parseInt(group_size);
    if (isNaN(group_size)) { group_size = 0; }
    var chars = charset.split('');
    var str = '';
    for (var i = 0; i < length; i++) {
	if (group_size > 0 && i > 0 && i % group_size == 0) {
	    str += '-';
	}
	str += chars[Math.floor(Math.random() * chars.length)];
    }
    return str;
}
