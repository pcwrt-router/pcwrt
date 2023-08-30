/*
 * Copyright (C) 2023 pcwrt.com
 * Licensed to the public under the Apache License 2.0.
 *
 * jQuery Cookie Plugin v1.4.1
 * https://github.com/carhartl/jquery-cookie
 *
 * Copyright 2006, 2014 Klaus Hartl
 * Released under the MIT license
 */
(function (factory) {
	if (typeof define === 'function' && define.amd) {
		// AMD (Register as an anonymous module)
		define(['jquery'], factory);
	} else if (typeof exports === 'object') {
		// Node/CommonJS
		module.exports = factory(require('jquery'));
	} else {
		// Browser globals
		factory(jQuery);
	}
}(function ($) {

	var pluses = /\+/g;

	function encode(s) {
		return config.raw ? s : encodeURIComponent(s);
	}

	function decode(s) {
		return config.raw ? s : decodeURIComponent(s);
	}

	function stringifyCookieValue(value) {
		return encode(config.json ? JSON.stringify(value) : String(value));
	}

	function parseCookieValue(s) {
		if (s.indexOf('"') === 0) {
			// This is a quoted cookie as according to RFC2068, unescape...
			s = s.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, '\\');
		}

		try {
			// Replace server-side written pluses with spaces.
			// If we can't decode the cookie, ignore it, it's unusable.
			// If we can't parse the cookie, ignore it, it's unusable.
			s = decodeURIComponent(s.replace(pluses, ' '));
			return config.json ? JSON.parse(s) : s;
		} catch(e) {}
	}

	function read(s, converter) {
		var value = config.raw ? s : parseCookieValue(s);
		return $.isFunction(converter) ? converter(value) : value;
	}

	var config = $.cookie = function (key, value, options) {

		// Write

		if (arguments.length > 1 && !$.isFunction(value)) {
			options = $.extend({}, config.defaults, options);

			if (typeof options.expires === 'number') {
				var days = options.expires, t = options.expires = new Date();
				t.setMilliseconds(t.getMilliseconds() + days * 864e+5);
			}

			return (document.cookie = [
				encode(key), '=', stringifyCookieValue(value),
				options.expires ? '; expires=' + options.expires.toUTCString() : '', // use expires attribute, max-age is not supported by IE
				options.path    ? '; path=' + options.path : '',
				options.domain  ? '; domain=' + options.domain : '',
				options.secure  ? '; secure' : ''
			].join(''));
		}

		// Read

		var result = key ? undefined : {},
			// To prevent the for loop in the first place assign an empty array
			// in case there are no cookies at all. Also prevents odd result when
			// calling $.cookie().
			cookies = document.cookie ? document.cookie.split('; ') : [],
			i = 0,
			l = cookies.length;

		for (; i < l; i++) {
			var parts = cookies[i].split('='),
				name = decode(parts.shift()),
				cookie = parts.join('=');

			if (key === name) {
				// If second argument (value) is a function it's a converter...
				result = read(cookie, value);
				break;
			}

			// Prevent storing a cookie that we couldn't decode.
			if (!key && (cookie = read(cookie)) !== undefined) {
				result[name] = cookie;
			}
		}

		return result;
	};

	config.defaults = {};

	$.removeCookie = function (key, options) {
		// Must not alter options, thus extending a fresh object...
		$.cookie(key, '', $.extend({}, options, { expires: -1 }));
		return !$.cookie(key);
	};

}));
(function ($) {
  'use strict'
  /*
  * Convert a raw string to a hex string
  */
  function str2hex (input) {
    var hexTab = '0123456789abcdef'
    var output = ''
    var x
    var i
    for (i = 0; i < input.length; i += 1) {
      x = input.charCodeAt(i)
      output += hexTab.charAt((x >>> 4) & 0x0f) + hexTab.charAt(x & 0x0f)
    }
    return output
  }

  function hex2str(input) {
    var hex = input.toString();//force conversion
    var str = '';
    for (var i = 0; i < hex.length; i += 2)
        str += String.fromCharCode(parseInt(hex.substr(i, 2), 16));
    return str;
  }

  function randomhex(length) {
    var chars = '0123456789abcdef'.split('');
    
    if (! length) {
        length = Math.floor(Math.random() * chars.length);
    }
    
    var str = '';
    for (var i = 0; i < length; i++) {
        str += chars[Math.floor(Math.random() * chars.length)];
    }
    return str;
  }

  function strxor(s1, s2, length) {
    var str = ''
    var i = 0, j = 0;
    while ((j + 1)*length <= s2.length) {
	for (i = 0; i < length; i++) {
	    str += String.fromCharCode(s1.charCodeAt(i) ^ s2.charCodeAt(j*length + i));
	}
	j++;
    }
    return str;
  }

  function encrypt(s) {
    if (s.length > 47) {
	s = s.substr(0, 47);
    }

    var input = String.fromCharCode(s.length) + s;
    if (input.length < 48) {
	input += hex2str(randomhex(2*(48 - input.length)));
    }

    var iv = randomhex(32);
    input = strxor(hex2str(iv), input, 16);
    return iv + str2hex(input);
  }

  function decrypt(s) {
    if (s.length != 128) {
	return s;
    }

    var secret = strxor(hex2str(s.substr(0, 32)), hex2str(s.substr(32, 96)), 16);
    return secret.substr(1, secret.charCodeAt(0));
  }

  $.encrypt = encrypt
  $.decrypt = decrypt
})(this)

$('#lost-password').on('click', function(e) {
    e.preventDefault();
    e.stopPropagation();
    $('#password-modal').modal('show');
});

$('#password-modal .btn-success').on('click', function(e) {
    e.preventDefault();
    var $form = $(this).parents('form');
    pcwrt.submit_form($form, $form.serialize(), {
	success: function(r) {
	    $('#password-modal').modal('hide');
	    pcwrt.show_message(r.title ? r.title : window.msgs.success, r.message);
	},
	fail: function() {
	    $('#password-modal').modal('hide');
	}
    });
});

$(function() {
    if ($.cookie("token") != null && $.cookie("token").length > 0) {
	$('input[name=password]').val(decrypt($.cookie("token")));
	$('[name=remember_me]').prop('checked', true);
    }
    else {
	$('[name=remember_me]').prop('checked', false);
    }
    $('input[name=password]').trigger('focus');
    $('form:first').on('submit', function(e) {
	if ($('[name=remember_me]').prop('checked')) {
	    $('[name=token]').val(encrypt($('[name=password]').val()));
	}
	else {
	    $('[name=token]').val(null);
	}
    });
});
