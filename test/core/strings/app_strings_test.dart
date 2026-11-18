import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/strings/locale_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// A missing key never throws — `_t` quietly falls back to another language —
/// so a forgotten translation is invisible at runtime. These tests are the
/// only thing standing between "we added a string" and "Slovak users read it
/// in Czech".
void main() {
  final tables = AppStrings.translationTables;

  // Restore the default so a locale set here cannot leak into other tests.
  tearDown(() => LocaleManager.notifier.value = AppLocale.cs);

  group('translation tables', () {
    test('cover every supported locale', () {
      expect(tables.keys.toSet(), AppLocale.values.toSet());
    });

    test('hold identical key sets', () {
      final reference = tables[AppLocale.cs]!.keys.toSet();

      for (final entry in tables.entries) {
        final keys = entry.value.keys.toSet();

        expect(
          keys.difference(reference),
          isEmpty,
          reason: '${entry.key.code} has keys Czech does not',
        );
        expect(
          reference.difference(keys),
          isEmpty,
          reason: '${entry.key.code} is missing keys Czech has',
        );
      }
    });

    test('have no blank values', () {
      for (final entry in tables.entries) {
        for (final pair in entry.value.entries) {
          expect(
            pair.value.trim(),
            isNotEmpty,
            reason: '${entry.key.code}/${pair.key} is blank',
          );
        }
      }
    });
  });

  group('lookup', () {
    test('resolves each locale to its own table', () {
      for (final locale in AppLocale.values) {
        LocaleManager.notifier.value = locale;

        expect(AppStrings.profileLanguage, tables[locale]!['profileLanguage']);
      }
    });

    test('interpolated strings differ per locale', () {
      LocaleManager.notifier.value = AppLocale.cs;
      expect(AppStrings.lessonTitle(2, 'Buňka'), 'Lekce 2: Buňka');

      LocaleManager.notifier.value = AppLocale.sk;
      expect(AppStrings.lessonTitle(2, 'Bunka'), 'Lekcia 2: Bunka');

      LocaleManager.notifier.value = AppLocale.en;
      expect(AppStrings.lessonTitle(2, 'Cell'), 'Lesson 2: Cell');
    });
  });

  // The guest is promised saved progress, not "full access" (BR-FZE5NZ) — the
  // account is free, so a paywall-shaped prompt was the wrong pitch. The
  // sentence is drawn twice, in the e-mail banner and in the sidebar's
  // register card, so both keys are pinned and the card keeps its own break.
  group('guest prompt', () {
    test('offers saved progress in Czech', () {
      expect(
        tables[AppLocale.cs]!['bannerGuestMessage'],
        'Postup se uloží až po přihlášení.',
      );
      expect(
        tables[AppLocale.cs]!['shellGuestCtaTitle'],
        'Postup se uloží\naž po přihlášení.',
      );
    });

    test('drops the old full-access pitch in every locale', () {
      const keys = ['bannerGuestMessage', 'shellGuestCtaTitle'];

      for (final entry in tables.entries) {
        for (final key in keys) {
          expect(
            entry.value[key]!.toLowerCase(),
            isNot(anyOf(
              contains('přístup'),
              contains('prístup'),
              contains('full access'),
            )),
            reason: '${entry.key.code}/$key still sells access',
          );
        }
      }
    });
  });

  // The app speaks to pupils informally (tykání), but the shared-device dialog
  // and its error snackbar addressed them formally — "budete odhlášeni",
  // "Chcete se odhlásit", "Zkuste to" (BR-WHE88W). English has no T–V split,
  // so only the Czech and Slovak texts are checked.
  group('shared-device dialog', () {
    const keys = ['sharedDeviceDialogMessage', 'sharedDeviceConvertError'];

    // Formal second-person plural forms: verbs and the plural participles
    // that go with "vy". Matched as whole words, case-insensitively.
    final formal = {
      AppLocale.cs: RegExp(
        r'(?<!\p{L})(budete|chcete|zkuste|přihlášeni|odhlášeni)(?!\p{L})',
        caseSensitive: false,
        unicode: true,
      ),
      AppLocale.sk: RegExp(
        r'(?<!\p{L})(budete|chcete|skúste|prihlásení|odhlásení)(?!\p{L})',
        caseSensitive: false,
        unicode: true,
      ),
    };

    test('addresses the pupil informally in Czech and Slovak', () {
      for (final entry in formal.entries) {
        for (final key in keys) {
          final text = tables[entry.key]![key]!;
          expect(
            entry.value.hasMatch(text),
            isFalse,
            reason: '${entry.key.code}/$key still uses vykání: "$text"',
          );
        }
      }
    });

    test('pins the Czech wording', () {
      expect(
        tables[AppLocale.cs]!['sharedDeviceDialogMessage'],
        'Toto zařízení je označené jako sdílené — po 15 minutách nečinnosti '
        'tě automaticky odhlásíme. Chceš se odhlásit hned, nebo zařízení '
        'označit jako své? Pak už tě odhlašovat nebudeme.',
      );
      expect(
        tables[AppLocale.cs]!['sharedDeviceConvertError'],
        'Zařízení se nepodařilo označit jako vlastní. Zkus to prosím znovu.',
      );
    });
  });

  // The first nav item read "Prehled" in Czech — the háček was missing, while
  // the page heading and the rest of the app say "Přehled" (BR-VRUMPN).
  group('nav labels', () {
    test('spell the dashboard item per locale', () {
      expect(tables[AppLocale.cs]!['navPrehled'], 'Přehled');
      expect(tables[AppLocale.sk]!['navPrehled'], 'Prehľad');
      expect(tables[AppLocale.en]!['navPrehled'], 'Overview');
    });
  });

  group('AppLocale', () {
    test('exposes a distinct code and short label per locale', () {
      expect(
        AppLocale.values.map((l) => l.code).toSet().length,
        AppLocale.values.length,
      );
      expect(
        AppLocale.values.map((l) => l.shortLabel).toSet().length,
        AppLocale.values.length,
      );
    });

    test('fromCode falls back to Czech for unknown or null input', () {
      expect(AppLocale.fromCode('sk'), AppLocale.sk);
      expect(AppLocale.fromCode('de'), AppLocale.cs);
      expect(AppLocale.fromCode(null), AppLocale.cs);
    });
  });
}
