import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Safari's own flag for a page launched from the home screen; older iOS
/// versions set it where the `display-mode` media query does not match.
extension on web.Navigator {
  @JS('standalone')
  external bool? get iosStandalone;
}

/// True when the web app was opened from the home screen (an installed PWA),
/// not in a browser tab.
bool isStandaloneDisplay() {
  try {
    return web.window.matchMedia('(display-mode: standalone)').matches ||
        (web.window.navigator.iosStandalone ?? false);
  } catch (_) {
    return false;
  }
}
