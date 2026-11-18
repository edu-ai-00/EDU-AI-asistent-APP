import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'lesson_image_backend.dart';

LessonImageBackend? createLessonImageBackend() => WebLessonImageBackend();

/// Web: downloads lesson pictures with the browser's `fetch` and keeps them in
/// Cache Storage, so a course opened online still has its pictures offline
/// (BR-7XZXZD).
///
/// The web build used to have no backend at all and loaded every lesson
/// picture through the API image proxy, which the browser's HTTP cache kept
/// for an hour at most — and only for pictures actually shown. Lessons the
/// student had not opened before going offline had none.
///
/// Cache Storage, unlike the HTTP cache, keeps a response for as long as the
/// site's data is kept, whatever its headers say. It exists only in a secure
/// context (https, localhost); where it is missing or blocked — some private
/// windows — pictures still load, they just are not kept.
class WebLessonImageBackend implements LessonImageBackend {
  WebLessonImageBackend({Future<Uint8List> Function(String source)? download})
      : _download = download ?? _fetchBytes;

  static const String _cacheName = 'lesson-images-v1';

  final Future<Uint8List> Function(String source) _download;
  Future<web.Cache?>? _cache;

  Future<web.Cache?> get _store => _cache ??= () async {
        if (!web.window.isSecureContext) return null;
        try {
          return await web.window.caches.open(_cacheName).toDart;
        } catch (_) {
          return null;
        }
      }();

  @override
  Future<Uint8List> fetch(
    String url, {
    LessonImageProgress? onProgress,
    bool background = false,
  }) async {
    Object? error;
    StackTrace? stack;
    for (final source in webLessonImageSources(url, background: background)) {
      try {
        return await _download(source);
      } catch (e, st) {
        error = e;
        stack = st;
      }
    }
    Error.throwWithStackTrace(error!, stack!);
  }

  @override
  Future<Uint8List?> read(String url) async {
    final kept = await _match(url);
    if (kept == null) return null;
    final bytes = (await kept.arrayBuffer().toDart).toDart.asUint8List();
    return bytes.isEmpty ? null : bytes;
  }

  @override
  Future<bool> contains(String url) async => await _match(url) != null;

  @override
  Future<void> write(String url, Uint8List bytes) async {
    final store = await _store;
    if (store == null) return;
    await store.put(url.toJS, web.Response(bytes.toJS)).toDart;
  }

  Future<web.Response?> _match(String url) async {
    final store = await _store;
    if (store == null) return null;
    return store.match(url.toJS).toDart;
  }

  static Future<Uint8List> _fetchBytes(String source) async {
    final response = await web.window.fetch(source.toJS).toDart;
    if (!response.ok) {
      throw LessonImageDownloadException('HTTP ${response.status}', source);
    }
    // A Wi-Fi login page answers every URL with 200 and its own HTML. Taking
    // that for the picture would overwrite the good copy kept in the cache.
    final type = response.headers.get('content-type') ?? '';
    if (type.toLowerCase().startsWith('text/html')) {
      throw LessonImageDownloadException('Not an image (text/html)', source);
    }
    final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
    if (bytes.isEmpty) {
      throw LessonImageDownloadException('Empty image', source);
    }
    return bytes;
  }
}

/// A lesson picture the server answered, but not with a picture.
class LessonImageDownloadException implements Exception {
  final String message;
  final String url;

  const LessonImageDownloadException(this.message, this.url);

  @override
  String toString() => 'LessonImageDownloadException: $message ($url)';
}
