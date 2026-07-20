import 'package:flutter/material.dart';
import '../core/strings/locale_manager.dart';
import 'legal/legal_page.dart';

/// Thin wrapper around [LegalPage] for in-app navigation
/// (Profile → Soukromí). Public web route `/privacy` uses
/// [LegalPage] directly via [buildAppRouter].
class PrivacyPage extends StatelessWidget {
  final VoidCallback? onBack;

  const PrivacyPage({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return LegalPage(
      slug: 'privacy',
      locale: LocaleManager.current.code,
      inAppMode: true,
    );
  }
}
