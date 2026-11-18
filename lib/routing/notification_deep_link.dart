import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/core_providers.dart';
import '../core/providers/navigation_providers.dart';
import '../core/services/course_enroll_service.dart';
import '../core/util/markdown_link_handler.dart';
import '../core/util/shell_route.dart';
import '../core/util/silent_log.dart';
import '../data/repositories/user_course_repository.dart';
import '../pages/notification_settings_page.dart';
import '../pages/practice_page.dart';
import '../pages/prehled_page.dart';
import 'tab_routes.dart';

/// Where an unknown or broken notification link leads (NOTIF-4 D): the
/// dashboard, never an error page or a blank screen.
const String kNotificationFallbackLink = '/dash';

/// What a notification's `deep_link` opens.
enum NotificationLinkKind {
  /// One of the main tabs ([NotificationLinkTarget.tabIndex]).
  tab,

  /// A course by its join code/PIN ([NotificationLinkTarget.courseCode]).
  course,

  /// The practice (FSRS review) session.
  practice,

  /// The dashboard's "Dej si kvíz" challenge.
  quiz,

  /// Doplňky — the mini games.
  games,

  /// "Můj účet".
  profile,

  /// The notification settings page.
  notificationSettings,
}

/// The resolved target of a notification link.
class NotificationLinkTarget {
  final NotificationLinkKind kind;
  final int? tabIndex;
  final String? courseCode;

  const NotificationLinkTarget._(this.kind, {this.tabIndex, this.courseCode});

  const NotificationLinkTarget.tab(int index)
      : this._(NotificationLinkKind.tab, tabIndex: index);

  const NotificationLinkTarget.course(String code)
      : this._(NotificationLinkKind.course, courseCode: code);

  const NotificationLinkTarget.of(NotificationLinkKind kind) : this._(kind);

  /// The fallback.
  static const dashboard = NotificationLinkTarget.tab(0);

  @override
  bool operator ==(Object other) =>
      other is NotificationLinkTarget &&
      other.kind == kind &&
      other.tabIndex == tabIndex &&
      other.courseCode == courseCode;

  @override
  int get hashCode => Object.hash(kind, tabIndex, courseCode);

  @override
  String toString() => 'NotificationLinkTarget(${kind.name}'
      '${tabIndex == null ? '' : ', tab $tabIndex'}'
      '${courseCode == null ? '' : ', $courseCode'})';
}

/// Decide what [link] opens, without opening it.
///
/// Accepts the paths the server's notification types use (spec §8): the tab
/// URLs (`/dash`, `/news`, `/courses`, `/library`, `/chat`), `/course/{code}`
/// (and its `/pin/{code}` alias), `/practice`, `/quiz`, `/games`, `/profile`
/// and `/settings/notifications` — relative, or absolute on the app's own
/// host. Everything else, including a missing link, resolves to
/// [NotificationLinkTarget.dashboard]. Never throws.
NotificationLinkTarget resolveNotificationLink(String? link) {
  final trimmed = link?.trim() ?? '';
  if (trimmed.isEmpty) return NotificationLinkTarget.dashboard;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return NotificationLinkTarget.dashboard;
  if (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') {
    return NotificationLinkTarget.dashboard;
  }
  if (uri.hasAuthority && !isOwnAppUri(uri)) {
    return NotificationLinkTarget.dashboard;
  }

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return NotificationLinkTarget.dashboard;
  final first = segments.first.toLowerCase();

  if (segments.length == 1) {
    final tab = mainTabIndexForPath('/$first');
    if (tab != null) return NotificationLinkTarget.tab(tab);
    return switch (first) {
      'practice' => const NotificationLinkTarget.of(NotificationLinkKind.practice),
      'quiz' => const NotificationLinkTarget.of(NotificationLinkKind.quiz),
      // `/tools` is Doplňky's own URL since BR-N6B622; `/games` is the
      // notification catalogue's name for it.
      'games' || 'tools' =>
        const NotificationLinkTarget.of(NotificationLinkKind.games),
      'profile' => const NotificationLinkTarget.of(NotificationLinkKind.profile),
      _ => NotificationLinkTarget.dashboard,
    };
  }

  if (segments.length == 2) {
    if (first == 'course' || first == 'pin') {
      final code = segments[1].trim();
      return code.isEmpty
          ? NotificationLinkTarget.dashboard
          : NotificationLinkTarget.course(code);
    }
    if (first == 'settings' && segments[1].toLowerCase() == 'notifications') {
      return const NotificationLinkTarget.of(
        NotificationLinkKind.notificationSettings,
      );
    }
  }

  return NotificationLinkTarget.dashboard;
}

/// Open [link] from a notification: a feed row tapped in Novinky, or a push
/// tapped in the system tray ([fromPush]).
///
/// Must be called with a context below `MainScreen` (or `MainScreen`'s own):
/// Doplňky and the profile are opened through [pendingShellIntentProvider],
/// which only `MainScreen` drains. Whatever goes wrong — an unknown path, a
/// course code that no longer resolves, an exception — ends on the dashboard.
Future<void> openNotificationLink(
  BuildContext context,
  WidgetRef ref,
  String? link, {
  bool fromPush = false,
}) async {
  final target = resolveNotificationLink(link);
  try {
    if (fromPush) {
      // A push can be tapped from anywhere — mid-lesson, say. Leaving that
      // page on top would bury the target underneath it.
      Navigator.maybeOf(context)?.popUntil((route) => route.isFirst);
    }
    final opened = await _open(context, ref, target, fromPush: fromPush);
    if (!opened && context.mounted) {
      goToMainTab(context, ref, NotificationLinkTarget.dashboard.tabIndex!);
    }
  } catch (e, st) {
    silentLog('notification_link', e, st);
    if (context.mounted) {
      goToMainTab(context, ref, NotificationLinkTarget.dashboard.tabIndex!);
    }
  }
}

/// Carry [target] out. False when it could not be, so the caller falls back.
Future<bool> _open(
  BuildContext context,
  WidgetRef ref,
  NotificationLinkTarget target, {
  required bool fromPush,
}) async {
  switch (target.kind) {
    case NotificationLinkKind.tab:
      goToMainTab(context, ref, target.tabIndex!);
      return true;

    case NotificationLinkKind.course:
      // From the tray there is no tab context, so point the shell at Kurzy the
      // way the `/course/:code` URL does (BR-48B7DY); from the feed, Back
      // should return to Novinky.
      final outcome = await openCourseByCode(
        context,
        ref,
        target.courseCode!,
        selectCoursesTab: fromPush,
      );
      // The two login cases run a flow of their own (forced logout, the
      // guest-upgrade dialog) that the fallback must not cut across.
      return outcome.isSuccess ||
          outcome.error == EnrollErrorKind.loginRequired ||
          outcome.error == EnrollErrorKind.loginRequiredForCourse;

    case NotificationLinkKind.practice:
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PracticePage()),
      );
      return true;

    case NotificationLinkKind.quiz:
      final courses = PrehledPage.globalQuizCourses(await _userCourses(ref));
      // Nothing to ask (no course with questions yet): the dashboard is where
      // the challenge appears once there is.
      if (courses.isEmpty || !context.mounted) return false;
      await PrehledPage.startGlobalQuiz(context, ref, courses);
      return true;

    case NotificationLinkKind.games:
      ref.read(pendingShellIntentProvider.notifier).state =
          ShellIntent.openDoplnky;
      return true;

    case NotificationLinkKind.profile:
      ref.read(pendingShellIntentProvider.notifier).state =
          ShellIntent.openProfile;
      return true;

    case NotificationLinkKind.notificationSettings:
      Navigator.of(context).push(
        shellPageRoute(
          context,
          builder: (_) => const NotificationSettingsPage(),
        ),
      );
      return true;
  }
}

Future<List<UserCourse>> _userCourses(WidgetRef ref) async {
  final user = await ref.read(appDatabaseProvider).getActiveUser();
  if (user == null) return const [];
  return ref.read(userCourseRepositoryProvider).getUserCourses(user.id);
}
