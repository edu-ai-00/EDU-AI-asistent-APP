import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/oauth/oauth_clients.dart';
import 'core/strings/app_strings.dart';
import 'core/strings/locale_manager.dart';
import 'core/theme/app_theme.dart';
import 'core/util/drag_scroll_behavior.dart';
import 'routing/app_router.dart';

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  late final _router = buildAppRouter(
    navigatorKey: ref.read(oauthNavigatorKeyProvider),
  );

  @override
  void initState() {
    super.initState();
    ThemeManager.notifier.addListener(_onThemeChanged);
    LocaleManager.notifier.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    ThemeManager.notifier.removeListener(_onThemeChanged);
    LocaleManager.notifier.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  void _onLocaleChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final locale = LocaleManager.current;
    return MaterialApp.router(
      // Keying MaterialApp by locale forces Flutter to throw away the entire
      // element tree when the user switches language, so static
      // `AppStrings.x` getters are re-invoked.
      key: ValueKey('app-locale-${locale.code}'),
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: locale.toFlutterLocale(),
      scrollBehavior: const DragScrollBehavior(),
      routerConfig: _router,
      builder: (context, child) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: child,
          ),
        );
      },
    );
  }
}
