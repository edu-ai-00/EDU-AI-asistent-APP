import '../../models/chat_models.dart';

/// What a dashboard banner's link opens (BR-SAWX2U).
///
/// The banner vocabulary is the notification one plus the two targets only
/// the dashboard has ever needed: the course already synced to this device
/// and a chat with one mentor. Everything else is handed to
/// `openNotificationLink`, which already covers the tabs, `/practice`,
/// `/quiz`, `/games`, `/profile` and `/course/{code}` — and lands on the
/// dashboard for anything it cannot read.
enum DashboardBannerLinkKind {
  /// A course on the device, by its `field_course_id` (e.g. EDU_JPZ_INTRO).
  fieldCourse,

  /// A fresh chat with one of the mentors.
  chatPersona,

  /// Handled by the notification link resolver.
  notification,

  /// No link: the banner does not react to a tap.
  none,
}

/// A banner link, resolved without opening it.
class DashboardBannerLink {
  final DashboardBannerLinkKind kind;

  /// Set for [DashboardBannerLinkKind.fieldCourse].
  final String? fieldCourseId;

  /// Set for [DashboardBannerLinkKind.chatPersona].
  final ChatPersona? persona;

  const DashboardBannerLink._(this.kind, {this.fieldCourseId, this.persona});

  static const none = DashboardBannerLink._(DashboardBannerLinkKind.none);

  static const notification =
      DashboardBannerLink._(DashboardBannerLinkKind.notification);

  /// Decide what [link] opens. Never throws.
  ///
  /// An unparseable `/field-course/` or `/chat/` link falls through to the
  /// notification resolver rather than to nothing, so the tap still lands
  /// somewhere sensible.
  factory DashboardBannerLink.parse(String? link) {
    final trimmed = link?.trim() ?? '';
    if (trimmed.isEmpty) return none;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return notification;

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length != 2) return notification;

    final first = segments.first.toLowerCase();
    final second = segments[1].trim();
    if (second.isEmpty) return notification;

    if (first == 'field-course') {
      return DashboardBannerLink._(
        DashboardBannerLinkKind.fieldCourse,
        fieldCourseId: second,
      );
    }

    if (first == 'chat') {
      final wanted = second.toLowerCase();
      for (final persona in ChatPersona.values) {
        if (persona.id == wanted) {
          return DashboardBannerLink._(
            DashboardBannerLinkKind.chatPersona,
            persona: persona,
          );
        }
      }
      // An unknown mentor is not worth a dead tap: `/chat` is a real tab.
      return notification;
    }

    return notification;
  }
}
