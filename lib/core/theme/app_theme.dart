/// Barrel export + ThemeData for the app.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'theme_config.dart';

export 'app_colors.dart';
export 'app_text_styles.dart';
export 'app_decorations.dart';
export 'theme_config.dart';

/// Provides the app-wide [ThemeData].
abstract final class AppTheme {
  static ThemeData get light => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          surface: AppColors.background,
        ),
        scaffoldBackgroundColor: AppColors.background,
        textTheme: GoogleFonts.getTextTheme(ThemeManager.typography.headingFont),
      );
}
