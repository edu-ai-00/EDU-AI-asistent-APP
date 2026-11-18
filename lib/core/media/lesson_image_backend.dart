import 'dart:typed_data';

import '../utils/image_url.dart';

/// Reports download progress: bytes so far, and the total when the server
/// sent a length.
typedef LessonImageProgress = void Function(int received, int? total);

/// Where [LessonImageCache] gets picture bytes from and keeps them.
///
/// Native platforms keep them as files (`lesson_image_backend_io.dart`), the
/// web build in the browser's Cache Storage (`lesson_image_backend_web.dart`).
abstract class LessonImageBackend {
  /// Downloads [url]. Throws when the network, or the server, fails.
  ///
  /// [background] marks a download nobody is waiting to see —
  /// [LessonImageCache.prefetch]. The web backend then skips the API image
  /// proxy (see [webLessonImageSources]).
  Future<Uint8List> fetch(
    String url, {
    LessonImageProgress? onProgress,
    bool background = false,
  });

  /// The copy of [url] kept on the device, or null when there is none.
  Future<Uint8List?> read(String url);

  /// Whether a copy of [url] is kept on the device.
  Future<bool> contains(String url);

  /// Keeps [bytes] on the device as the copy of [url].
  Future<void> write(String url, Uint8List bytes);
}

/// The addresses the web build downloads the picture at [url] from, in order.
///
/// The picture's own address comes first: our R2 buckets answer CORS for the
/// app, so that normally just works (as for course covers, BR-MMAESQ). The API
/// image proxy is the second attempt, for hosts that send no CORS header. A
/// [background] download leaves the proxy out — its rate limit is a single
/// bucket shared by every web user, and prefetching a whole course through it
/// would starve the pictures people are actually looking at.
List<String> webLessonImageSources(String url, {bool background = false}) {
  final proxied = proxyImageUrl(url);
  if (background || proxied == url) return [url];
  return [url, proxied];
}
