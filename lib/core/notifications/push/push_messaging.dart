/// The OS-level answer to "may this app show notifications".
enum PushAuthorization {
  authorized,

  /// Not allowed. On Android 13+ this is also what a not-yet-asked
  /// permission looks like, and the OS may still show its prompt.
  denied,

  /// Not allowed, and the OS will not prompt again — only the system
  /// settings can change it.
  deniedPermanently,

  /// Never asked (iOS).
  notDetermined,
}

/// A push as the app cares about it: the `data` block the server sends with
/// every message (`notification_id`, `deep_link`, `type_key`) plus the text
/// shown to the user.
class PushMessage {
  final String? notificationId;
  final String? deepLink;
  final String? typeKey;
  final String? title;
  final String? body;

  const PushMessage({
    this.notificationId,
    this.deepLink,
    this.typeKey,
    this.title,
    this.body,
  });

  factory PushMessage.fromData(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) {
    String? read(String key) {
      final value = data[key];
      if (value is! String || value.trim().isEmpty) return null;
      return value.trim();
    }

    return PushMessage(
      notificationId: read('notification_id'),
      deepLink: read('deep_link'),
      typeKey: read('type_key'),
      title: title,
      body: body,
    );
  }
}

/// The messaging SDK, behind an interface so the orchestration in
/// `PushController` can be tested without Firebase and so platforms without
/// push never construct the real thing.
abstract class PushMessaging {
  /// Set the SDK up (Firebase app, background handler). Returns false when it
  /// could not be — push then stays off for this run.
  Future<bool> initialize();

  Future<PushAuthorization> authorization();

  /// Show the OS permission prompt (or, where it no longer appears, return
  /// the standing answer).
  Future<PushAuthorization> requestPermission();

  /// This device's registration token, or null when none can be had yet.
  Future<String?> getToken();

  /// Invalidate the token on this device — the next [getToken] mints a new
  /// one, so nothing addressed to the previous account reaches the next.
  Future<void> deleteToken();

  Stream<String> get onTokenRefresh;

  /// Messages that arrive while the app is in the foreground.
  Stream<PushMessage> get onForegroundMessage;

  /// Notifications tapped while the app was running in the background.
  Stream<PushMessage> get onMessageOpenedApp;

  /// The notification whose tap launched the app, once per process.
  Future<PushMessage?> getInitialMessage();
}
