import 'package:flutter/foundation.dart';

/// Which platform and form factor the app is running on — sent with work-time
/// heartbeats so the admin "Čas práce" tab can show web/Android/iOS and
/// phone/tablet/PC next to each session (BR-Y2TJ74).
@immutable
class DeviceKind {
  /// `web`, `android`, `ios`, `macos`, `windows` or `linux`.
  final String platform;

  /// `mobile`, `tablet` or `desktop`; null when the screen size is unknown.
  final String? type;

  const DeviceKind({required this.platform, this.type});

  /// Shortest screen side, in logical pixels, from which a phone OS device
  /// counts as a tablet — Android's `sw600dp` cut-off.
  static const double tabletMinShortestSide = 600;

  /// The device this app is running on.
  static DeviceKind current() => classify(
        isWeb: kIsWeb,
        os: defaultTargetPlatform,
        shortestSide: _shortestSide(),
      );

  /// [os] is the operating system even on web: the web engine derives it from
  /// the browser, and reports an iPad (whose Safari poses as a Mac) as iOS.
  @visibleForTesting
  static DeviceKind classify({
    required bool isWeb,
    required TargetPlatform os,
    required double shortestSide,
  }) {
    final platform = isWeb ? 'web' : os.name.toLowerCase();
    final handheld = os == TargetPlatform.android || os == TargetPlatform.iOS;

    final String? type;
    if (!handheld) {
      type = 'desktop';
    } else if (shortestSide <= 0) {
      type = null;
    } else if (shortestSide < tabletMinShortestSide) {
      type = 'mobile';
    } else {
      type = 'tablet';
    }

    return DeviceKind(platform: platform, type: type);
  }

  static double _shortestSide() {
    final view = PlatformDispatcher.instance.implicitView;
    if (view == null) return 0;
    if (kIsWeb) {
      // The browser viewport. Phone and tablet browsers run full-screen, and
      // the web engine's Display reports CSS pixels, not physical ones.
      return (view.physicalSize / view.devicePixelRatio).shortestSide;
    }
    // The physical screen, so a tablet in split-screen is still a tablet.
    final display = view.display;
    return (display.size / display.devicePixelRatio).shortestSide;
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceKind && other.platform == platform && other.type == type;

  @override
  int get hashCode => Object.hash(platform, type);

  @override
  String toString() => 'DeviceKind($platform, $type)';
}
