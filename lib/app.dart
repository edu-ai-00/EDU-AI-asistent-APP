import 'package:flutter/material.dart';
import 'core/strings/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'core/util/drag_scroll_behavior.dart';
import 'main.dart' show routeObserver;
import 'routing/root_navigator.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    ThemeManager.notifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeManager.notifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      scrollBehavior: const DragScrollBehavior(),
      navigatorObservers: [routeObserver],
      builder: (context, child) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: child,
          ),
        );
      },
      home: const AuthWrapper(),
    );
  }
}
