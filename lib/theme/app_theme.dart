import 'package:flutter/material.dart';

import 'app_colors.dart';

/// App-wide ThemeData plus a handful of decoration/text-style builders that
/// were previously re-created (as brand-new objects) on every single
/// widget build. Reusing static const/cached instances avoids unnecessary
/// allocations during rebuilds.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Roboto',
    );
  }

  static BoxDecoration cardDecoration(double radius) {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.border),
      boxShadow: [
        BoxShadow(
          color: AppColors.shadow.withValues(alpha: 0.10),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  static BoxDecoration lightBoxDecoration(double radius) {
    return BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.border),
    );
  }

  static BoxDecoration pillDecoration() {
    return BoxDecoration(
      color: AppColors.chipBg,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: AppColors.chipBorder),
    );
  }

  static const TextStyle panelTitle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w900,
    fontSize: 19,
  );

  static const TextStyle pillText = TextStyle(
    color: AppColors.info,
    fontWeight: FontWeight.w900,
    fontSize: 12,
  );

  static const TextStyle label = TextStyle(
    color: AppColors.textMuted,
    fontWeight: FontWeight.w900,
  );
}
