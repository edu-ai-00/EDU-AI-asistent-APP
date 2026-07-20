import 'package:flutter/material.dart';
import '../core/strings/locale_manager.dart';
import 'legal/legal_page.dart';

/// Thin wrapper around [LegalPage] for in-app navigation
/// (Profile → Podmínky). Public web route `/terms` uses
/// [LegalPage] directly via [buildAppRouter].
class TermsPage extends StatelessWidget {
  final VoidCallback? onBack;

  const TermsPage({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return LegalPage(
      slug: 'terms',
      locale: LocaleManager.current.code,
      inAppMode: true,
    );
  }
}
