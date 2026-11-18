import 'package:eduai/features/dashboard/dashboard_banner_link.dart';
import 'package:eduai/models/chat_models.dart';
import 'package:eduai/models/dashboard_banner.dart';
import 'package:flutter_test/flutter_test.dart';

/// BR-SAWX2U: the dashboard's banners moved from `DashboardTiers` and
/// `_buildJpzSection` into admin-managed rows.
///
/// The XP band is applied on the device, so these are the rules that decide
/// which banner the learner actually sees.
void main() {
  DashboardBanner banner({int? minXp, int? maxXp, String? link}) {
    return DashboardBanner(
      id: 1,
      title: 'Uvažuješ o přijímačkách?',
      body: 'Projdi si úvod',
      minXp: minXp,
      maxXp: maxXp,
      link: link,
    );
  }

  group('XP band', () {
    test('both bounds are inclusive, so neighbouring bands do not gap', () {
      final intro = banner(minXp: 0, maxXp: 30);
      final next = banner(minXp: 31, maxXp: 150);

      expect(intro.appliesTo(0), isTrue);
      expect(intro.appliesTo(30), isTrue);
      expect(intro.appliesTo(31), isFalse);

      expect(next.appliesTo(30), isFalse);
      expect(next.appliesTo(31), isTrue);
      expect(next.appliesTo(150), isTrue);
      expect(next.appliesTo(151), isFalse);
    });

    test('an open end means no limit on that side', () {
      expect(banner(maxXp: 100).appliesTo(0), isTrue);
      expect(banner(maxXp: 100).appliesTo(101), isFalse);
      expect(banner(minXp: 101).appliesTo(100), isFalse);
      expect(banner(minXp: 101).appliesTo(1000000), isTrue);
    });

    test('a banner with no band shows at any XP', () {
      expect(banner().appliesTo(0), isTrue);
      expect(banner().appliesTo(99999), isTrue);
    });

    test('a zero lower bound is a bound, not a missing one', () {
      // `0` is falsy in a lot of languages; the band must still read as set.
      expect(banner(minXp: 0, maxXp: 0).appliesTo(0), isTrue);
      expect(banner(minXp: 0, maxXp: 0).appliesTo(1), isFalse);
    });
  });

  group('JSON', () {
    test('a row survives the cache round-trip', () {
      final original = DashboardBanner.fromJson({
        'id': 7,
        'key': 'system.jpz_cermatik',
        'badge': 'PŘIJÍMAČKY',
        'title': 'Uvažuješ o přijímačkách?',
        'body': 'Zeptej se Cermatíka na cokoli\nkolem přijímaček',
        'accent': 'primary',
        'illustration': 'news',
        'link': '/chat/cermatik',
        'min_xp': 101,
        'max_xp': null,
      });

      final restored = DashboardBanner.fromJson(original.toJson());

      expect(restored.id, 7);
      expect(restored.key, 'system.jpz_cermatik');
      expect(restored.badge, 'PŘIJÍMAČKY');
      expect(restored.body, contains('\n'));
      expect(restored.link, '/chat/cermatik');
      expect(restored.minXp, 101);
      expect(restored.maxXp, isNull);
    });

    test('a row missing the optional fields still parses', () {
      final parsed = DashboardBanner.fromJson({
        'id': 2,
        'title': 'Nadpis',
        'body': 'Text',
      });

      expect(parsed.badge, isNull);
      expect(parsed.link, isNull);
      expect(parsed.accent, 'primary');
      expect(parsed.appliesTo(0), isTrue);
    });
  });

  group('link', () {
    test('a local course link carries its field course id', () {
      final link = DashboardBannerLink.parse('/field-course/EDU_JPZ_INTRO');

      expect(link.kind, DashboardBannerLinkKind.fieldCourse);
      expect(link.fieldCourseId, 'EDU_JPZ_INTRO');
    });

    test('a mentor link resolves to the persona', () {
      final link = DashboardBannerLink.parse('/chat/cermatik');

      expect(link.kind, DashboardBannerLinkKind.chatPersona);
      expect(link.persona, ChatPersona.cermatik);
    });

    test('no link means the banner does not react to a tap', () {
      expect(DashboardBannerLink.parse(null).kind,
          DashboardBannerLinkKind.none);
      expect(DashboardBannerLink.parse('   ').kind,
          DashboardBannerLinkKind.none);
    });

    test('everything else is left to the notification resolver', () {
      for (final link in [
        '/library',
        '/practice',
        '/quiz',
        '/course/123456',
        '/chat',
        // Unknown mentor: `/chat` is a real tab, so the tap still lands.
        '/chat/nobody',
        'https://example.com/elsewhere',
        'nonsense',
      ]) {
        expect(
          DashboardBannerLink.parse(link).kind,
          DashboardBannerLinkKind.notification,
          reason: '$link should go to the notification resolver',
        );
      }
    });
  });
}
