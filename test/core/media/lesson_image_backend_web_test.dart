// BR-7XZXZD — offline, the web app showed broken-image boxes in a downloaded
// course: the web build had no LessonImageCache backend, so nothing kept the
// pictures. WebLessonImageBackend keeps them in the browser's Cache Storage.
//
//   flutter test --platform chrome test/core/media/lesson_image_backend_web_test.dart
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/media/lesson_image_backend_web.dart';
import 'package:eduai/core/media/lesson_image_cache.dart';
import 'package:eduai/core/utils/image_url.dart';

void main() {
  final unique = DateTime.now().microsecondsSinceEpoch;
  final url = 'https://pub-x.r2.dev/assets/web-$unique.png';

  test('keeps pictures in Cache Storage and reads them back', () async {
    final backend = WebLessonImageBackend();

    expect(await backend.contains(url), isFalse);
    expect(await backend.read(url), isNull);

    await backend.write(url, Uint8List.fromList([1, 2, 3]));

    expect(await backend.contains(url), isTrue);
    expect(await WebLessonImageBackend().read(url), [1, 2, 3],
        reason: 'a fresh backend — a reloaded page — still has it');
  });

  test('falls back to the API proxy when the direct download fails', () async {
    final tried = <String>[];
    final backend = WebLessonImageBackend(download: (source) async {
      tried.add(source);
      if (source == url) throw StateError('CORS');
      return Uint8List.fromList([7]);
    });

    expect(await backend.fetch(url), [7]);
    expect(tried, [url, proxyImageUrl(url)]);
  });

  test('a background download never goes through the proxy', () async {
    final tried = <String>[];
    final backend = WebLessonImageBackend(download: (source) async {
      tried.add(source);
      throw StateError('CORS');
    });

    await expectLater(backend.fetch(url, background: true), throwsStateError);
    expect(tried, [url]);
  });

  test('offline, the cache serves what was downloaded online', () async {
    var online = true;
    final offlineUrl = 'https://pub-x.r2.dev/assets/offline-$unique.png';
    final cache = LessonImageCache(
      backend: WebLessonImageBackend(download: (source) async {
        if (!online) throw StateError('Failed to fetch');
        return Uint8List.fromList([4, 2]);
      }),
    )..setConnectivityForTesting(isOnline: () async => true);

    await cache.prefetch([offlineUrl]);
    online = false;

    expect(await cache.load(offlineUrl), [4, 2]);
  });
}
