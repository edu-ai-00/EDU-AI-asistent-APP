import 'package:flutter/foundation.dart';

/// Firebase project settings, baked in at build time with `--dart-define`
/// (see `build_android.sh` / `build_ios.sh`). The app ships no
/// `google-services.json` or `GoogleService-Info.plist`: these values are the
/// whole Firebase configuration.
///
/// Missing values are not an error — a build without them (web, desktop, a
/// local run) simply has no push, and the feed carries everything (spec §0
/// "Works without push credentials").
class PushConfig {
  final String apiKey;
  final String projectId;
  final String messagingSenderId;
  final String androidAppId;
  final String iosAppId;
  final String iosBundleId;

  const PushConfig({
    this.apiKey = '',
    this.projectId = '',
    this.messagingSenderId = '',
    this.androidAppId = '',
    this.iosAppId = '',
    this.iosBundleId = '',
  });

  /// The values this build was compiled with.
  static const PushConfig fromEnvironment = PushConfig(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    androidAppId: String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
    iosAppId: String.fromEnvironment('FIREBASE_IOS_APP_ID'),
    iosBundleId: String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
  );

  /// The Firebase app id for [platform] (`android` / `ios`), or empty.
  String appIdFor(String platform) => switch (platform) {
        'android' => androidAppId,
        'ios' => iosAppId,
        _ => '',
      };

  /// Whether push can be initialised on [platform].
  bool isCompleteFor(String? platform) {
    if (platform == null) return false;
    return apiKey.isNotEmpty &&
        projectId.isNotEmpty &&
        messagingSenderId.isNotEmpty &&
        appIdFor(platform).isNotEmpty;
  }
}

/// The push platform this build runs on — `android` or `ios` — or null where
/// push is not offered (web, macOS, Windows, Linux). Values match
/// `push_devices.platform` on the server.
///
/// Parameters exist for tests; production calls take the defaults.
String? pushPlatformName({bool? isWeb, TargetPlatform? platform}) {
  if (isWeb ?? kIsWeb) return null;
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => null,
  };
}
