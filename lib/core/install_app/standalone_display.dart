// Whether the web app runs from the home screen rather than in a browser tab.
// The web implementation needs package:web, so it must never be imported
// directly on native — the conditional export guards that.
export 'standalone_display_stub.dart'
    if (dart.library.js_interop) 'standalone_display_web.dart';
