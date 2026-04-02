// === Privacy & Anti-Tracking ===
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
user_pref("privacy.trackingprotection.cryptomining.enabled", true);
user_pref("privacy.trackingprotection.fingerprinting.enabled", true);
user_pref("privacy.resistFingerprinting", true);
user_pref("privacy.firstparty.isolate", true);
user_pref("network.cookie.cookieBehavior", 1); // Block third-party cookies
user_pref("network.cookie.lifetimePolicy", 2); // Session-only cookies

// === Disable Telemetry ===
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("browser.ping-centre.telemetry", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);

// === Disable Dangerous Features ===
user_pref("dom.disable_open_during_load", true);       // Block popups
// WebAssembly kept enabled — required by YouTube video player and many modern sites.
// Trade-off: WASM is a primary exploit payload vector, but disabling it breaks YouTube.
// To disable for maximum security (at the cost of video compatibility):
// user_pref("javascript.options.wasm", false);
user_pref("media.peerconnection.enabled", false);       // Disable WebRTC (prevents IP leak)
user_pref("media.navigator.enabled", false);            // Disable media device enumeration
user_pref("geo.enabled", false);                        // Disable geolocation
user_pref("dom.battery.enabled", false);                // Disable battery API
user_pref("dom.event.clipboardevents.enabled", false);  // Disable clipboard event detection
user_pref("dom.allow_cut_copy", false);                 // Disable cut/copy from scripts

// === Network Hardening ===
user_pref("network.prefetch-next", false);              // Disable link prefetching
user_pref("network.dns.disablePrefetch", true);         // Disable DNS prefetching
user_pref("network.predictor.enabled", false);          // Disable speculative connections
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("network.IDN_show_punycode", true);           // Show punycode (anti-phishing)

// === DNS-over-HTTPS (M7 fix) ===
// Use Cloudflare's malware-blocking resolver to filter known-bad domains at DNS level.
// Mode 3 = DoH only (no fallback to plaintext DNS). Prevents DNS-based C2/exfiltration.
user_pref("network.trr.mode", 3);
user_pref("network.trr.uri", "https://security.cloudflare-dns.com/dns-query");
user_pref("network.trr.custom_uri", "https://security.cloudflare-dns.com/dns-query");

// === HTTPS & Certificate Hardening ===
user_pref("dom.security.https_only_mode", true);        // HTTPS-only mode
user_pref("security.mixed_content.block_active_content", true);
user_pref("security.mixed_content.block_display_content", true);
user_pref("security.ssl.require_safe_negotiation", true);
user_pref("security.OCSP.enabled", 1);
user_pref("security.OCSP.require", true);

// === Safe Browsing — DISABLED for OPSEC (L5 fix) ===
// Safe Browsing sends URL prefix hashes to Google, which leaks the URLs being
// investigated. For malware analysis this is an OPSEC risk — threat actors
// monitor for URL scanning. uBlock Origin with URLhaus provides equivalent
// malware URL blocking without phoning home.
user_pref("browser.safebrowsing.malware.enabled", false);
user_pref("browser.safebrowsing.phishing.enabled", false);
user_pref("browser.safebrowsing.downloads.enabled", false);
user_pref("browser.safebrowsing.downloads.remote.enabled", false);
user_pref("browser.safebrowsing.downloads.remote.url", "");

// === Disable Risky Integrations ===
user_pref("browser.download.manager.addToRecentDocs", false);
user_pref("pdfjs.disabled", true);                      // Disable built-in PDF viewer
user_pref("plugin.state.flash", 0);                     // Disable Flash
user_pref("media.gmp-gmpopenh264.enabled", false);      // Disable OpenH264 codec plugin
user_pref("media.gmp-gmpopenh264.autoupdate", false);
user_pref("media.gmp-manager.url", "");                  // Prevent GMP plugin downloads

// === Graphics (software rendering for containers) ===
user_pref("layers.acceleration.disabled", true);
user_pref("gfx.xrender.enabled", false);
user_pref("gfx.webrender.all", false);
user_pref("gfx.webrender.enabled", false);

// === UI Hardening ===
user_pref("browser.urlbar.trimURLs", false);            // Show full URLs
user_pref("browser.urlbar.speculativeConnect.enabled", false);
user_pref("browser.search.suggest.enabled", false);     // No search suggestions
user_pref("browser.formfill.enable", false);            // No form autofill
user_pref("signon.rememberSignons", false);             // Never save passwords
user_pref("signon.autofillForms", false);
user_pref("browser.cache.disk.enable", false);          // No disk cache
user_pref("browser.cache.memory.capacity", 65536);      // Limited memory cache
