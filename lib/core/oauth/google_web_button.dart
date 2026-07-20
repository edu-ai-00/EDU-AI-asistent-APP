// Resolves to the GIS-rendered button on web, a no-op elsewhere. The web
// implementation imports google_sign_in_web (web-only), so it must never be
// imported directly on native — the conditional export guards that.
export 'google_web_button_stub.dart'
    if (dart.library.html) 'google_web_button_web.dart';
