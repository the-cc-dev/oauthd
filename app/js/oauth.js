OAuth = null;

(function() {
	var config = {
		oauthd_url = 'http://oauth.io/auth'
	}
	OAuth = {
		initialize: function(public_key) {
			config.key = public_key
		},
		popup: function(provider, callback) {
			var url = config.oauthd_url + '/' + provider + "?k=" + config.key;

			// create popup
			var wnd_settings = {
				width: Math.floor(window.outerWidth * 0.8)
				height: Math.floor(window.outerHeight * 0.5)
			};
			if (wnd_settings.height < 350)
				wnd_settings.height = 350;
			if (wnd_settings.width < 800)
				wnd_settings.width = 800;
			wnd_settings.left = window.screenX + (window.outerWidth - wnd_settings.width) / 2
			wnd_settings.top = window.screenY + (window.outerHeight - wnd_settings.height) / 8
			var wnd_options = "width=" + wnd_settings.width + ",height=" + wnd_settings.height;
			wnd_options += ",toolbar=0,scrollbars=1,status=1,resizable=1,location=1,menuBar=0";
			wnd_options += ",left=" + wnd_settings.left + ",top=" + wnd_settings.top
			var wnd = window.open(url, "Authorization", wnd_options);
			if (wnd)
				wnd.focus();
		},
		redirect: function(provider, url) {
			var url = config.oauthd_url + '/' + provider + "?k=" + config.key + "&redirect_uri=" + url;
			document.location.href = url;
		}
	};
})();