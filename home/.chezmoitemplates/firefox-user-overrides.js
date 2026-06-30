user_pref("security.OCSP.require", false); // too much breakage
user_pref("browser.safebrowsing.downloads.remote.enabled", true);

/* override recipe: keep some cookies + site data on exit ***/
// user_pref("network.cookie.lifetimePolicy", 2); // 2801 [default 2 in user.js 94+]
// user_pref("privacy.clearOnShutdown.cookies", false); // 2811 [default false in user.js 94+]
// user_pref("privacy.cpd.cookies", false); // 2812 Ctrl-Shift-Del [default false in user.js 94+]

// user_pref("privacy.clearOnShutdown.offlineApps", false); // 2811 [default false in user.js 95+]
// user_pref("privacy.cpd.offlineApps", false); // 2812 Ctrl-Shift-Del [default false in user.js 95+]

/* override recipe: enable session restore ***/
user_pref("browser.startup.page", 3); // 0102
// user_pref("browser.privatebrowsing.autostart", false); // 0110 required if you had it set as true
// user_pref("browser.sessionstore.privacy_level", 0); // 1003 optional to restore cookies/formdata
user_pref("privacy.clearOnShutdown_v2.historyFormDataAndDownloads", false); // 2811 FF128-135
user_pref("privacy.clearOnShutdown_v2.browsingHistoryAndDownloads", false); // 2812 FF136+

/* override recipe: don't drop out of macOS native fullscreen on Esc ***/
user_pref("browser.fullscreen.exit_on_escape", false);
