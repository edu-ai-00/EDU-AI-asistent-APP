import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:eduai/routing/app_router.dart';

/// BR-PCAKUU: https://app.edu-ai.eu/pin/242424 opened the browser on a phone
/// that had the app installed.
///
/// A web link reaches the app only when four files agree, and before the fix
/// none of them existed: the Android manifest has to claim the URL with an
/// `autoVerify` intent filter, the iOS entitlements have to name the domain,
/// and the domain itself has to vouch for the app in
/// `/.well-known/assetlinks.json` (Android) and
/// `/.well-known/apple-app-site-association` (iOS). Miss any one and the OS
/// quietly falls back to the browser — nothing fails, which is why the set is
/// pinned here rather than left to a phone check.
///
/// Not covered: the OS actually verifying the domain. That needs the files
/// live on app.edu-ai.eu and a store build carrying the new manifest and
/// entitlement — a device check after the release.
void main() {
  const host = 'app.edu-ai.eu';
  const packageName = 'com.eduai.eduaiapp';
  const appleAppId = '24ZTV92G3K.com.eduai.eduaiapp';
  // Play App Signing key (Play Console → App integrity → App signing). Play
  // re-signs every store build with it, so this — not the upload key — is the
  // certificate a phone with the app from Google Play presents.
  const playSigningSha256 =
      '4E:A1:B1:D9:72:8C:A9:AF:8F:CF:2E:58:72:AF:00:BD:B8:6E:00:5B:02:BB:00:1C:EF:25:CE:28:90:45:6A:3C';

  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final entitlements = File('ios/Runner/Runner.entitlements').readAsStringSync();
  final assetLinks = jsonDecode(
    File('web/.well-known/assetlinks.json').readAsStringSync(),
  ) as List<dynamic>;
  final appleAssociation = jsonDecode(
    File('web/.well-known/apple-app-site-association').readAsStringSync(),
  ) as Map<String, dynamic>;

  /// The body of the manifest's `autoVerify` intent filter.
  String verifiedFilter() {
    final match = RegExp(
      r'<intent-filter android:autoVerify="true">([\s\S]*?)</intent-filter>',
    ).firstMatch(manifest);
    expect(
      match,
      isNotNull,
      reason: 'AndroidManifest.xml has no autoVerify intent filter',
    );
    return match!.group(1)!;
  }

  /// Path prefixes the Android filter claims, e.g. `/pin/`.
  Set<String> androidPrefixes() => RegExp(r'android:pathPrefix="([^"]+)"')
      .allMatches(verifiedFilter())
      .map((m) => m.group(1)!)
      .toSet();

  /// The `applinks` entry for this app.
  Map<String, dynamic> appleDetails() {
    final details = (appleAssociation['applinks']
        as Map<String, dynamic>)['details'] as List<dynamic>;
    return details.cast<Map<String, dynamic>>().singleWhere(
          (d) => (d['appIDs'] as List<dynamic>).contains(appleAppId),
        );
  }

  /// Path prefixes the Apple association claims — `/pin/*` read as `/pin/`.
  Set<String> applePrefixes() => (appleDetails()['components'] as List<dynamic>)
      .map((c) => (c as Map<String, dynamic>)['/'] as String)
      .map((path) {
    expect(path, endsWith('/*'), reason: '$path is not a prefix pattern');
    return path.substring(0, path.length - 1);
  }).toSet();

  test('Android claims /pin links on the prod host and asks to verify', () {
    final filter = verifiedFilter();
    expect(filter, contains('android.intent.action.VIEW'));
    expect(filter, contains('android.intent.category.BROWSABLE'));
    expect(filter, contains('android.intent.category.DEFAULT'));
    expect(filter, contains('android:scheme="https"'));
    expect(filter, contains('android:host="$host"'));
    expect(androidPrefixes(), contains('/pin/'));
  });

  test('iOS names the domain in its associated domains', () {
    expect(entitlements, contains('com.apple.developer.associated-domains'));
    expect(entitlements, contains('<string>applinks:$host</string>'));
  });

  test('both platforms claim the same paths', () {
    // A path claimed on one platform only is a link that opens the app on
    // half the phones and the browser on the rest.
    expect(applePrefixes(), androidPrefixes());
  });

  test('assetlinks.json vouches for the Android app', () {
    final statement = assetLinks.cast<Map<String, dynamic>>().singleWhere(
          (s) => (s['target'] as Map<String, dynamic>)['namespace'] ==
              'android_app',
        );
    expect(
      statement['relation'],
      contains('delegate_permission/common.handle_all_urls'),
    );
    final target = statement['target'] as Map<String, dynamic>;
    expect(target['package_name'], packageName);
    final fingerprints =
        (target['sha256_cert_fingerprints'] as List<dynamic>).cast<String>();
    // Without it only sideloaded upload-key builds verify; every install
    // from Google Play keeps opening the browser.
    expect(fingerprints, contains(playSigningSha256));
    for (final fingerprint in fingerprints) {
      // Upper-case colon-separated SHA-256, the only shape Android accepts.
      expect(fingerprint, matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));
    }
  });

  test('nginx serves the proof files as JSON, never the SPA shell', () {
    // apple-app-site-association has no extension, so without default_type
    // nginx labels it octet-stream; without `=404` a missing file comes back
    // as index.html — what prod served before the fix, for both files.
    final nginxConf = File('nginx.conf').readAsStringSync();
    final start = nginxConf.indexOf('location ^~ /.well-known/');
    expect(start, isNot(-1), reason: 'nginx.conf has no /.well-known/ block');
    final block = nginxConf.substring(start, nginxConf.indexOf('}', start));
    expect(block, contains('default_type application/json'));
    expect(block, contains('try_files \$uri =404'));
  });

  testWidgets('every claimed path is one the app routes', (tester) async {
    // Claiming a path the router does not know would open the app on its
    // "Stránka nenalezena" page instead of the web page the link meant.
    final router = buildAppRouter();
    addTearDown(router.dispose);
    for (final prefix in androidPrefixes()) {
      final path = '${prefix}242424';
      final matches = router.configuration.findMatch(Uri.parse(path));
      expect(matches.isError, isFalse, reason: '$path does not route');
      final route = (matches.matches.last as RouteMatch).route;
      expect(route.path, startsWith(prefix));
    }
  });
}
