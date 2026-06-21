import 'package:flutter/material.dart';

/// Centralized color tokens.
///
/// Keeping every color in one place (instead of scattered hex literals
/// across dozens of widgets) makes the palette easy to audit, keeps usage
/// consistent, and means a future re-theme only touches this file.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF0077FF);
  static const Color primaryDark = Color(0xFF0066FF);
  static const Color primaryLight = Color(0xFF00A8FF);
  static const Color accentTeal = Color(0xFF0099CC);

  // Surfaces
  static const Color background = Color(0xFFF2FAFF);
  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFF7FCFF);
  static const Color border = Color(0xFFDCEEFA);
  static const Color borderStrong = Color(0xFFD7EAF5);
  static const Color chipBg = Color(0xFFE7F7FF);
  static const Color chipBorder = Color(0xFFC6EDFF);

  // Text
  static const Color textPrimary = Color(0xFF063B63);
  static const Color textHeading = Color(0xFF102033);
  static const Color textBody = Color(0xFF5C7188);
  static const Color textMuted = Color(0xFF6B8198);
  static const Color textSubtle = Color(0xFF7C8FA3);
  static const Color textSecondary = Color(0xFF50677E);

  // Status
  static const Color success = Color(0xFF00A96B);
  static const Color successStrong = Color(0xFF00C875);
  static const Color warning = Color(0xFFF0A400);
  static const Color danger = Color(0xFFE63946);
  static const Color dangerStrong = Color(0xFFD90429);
  static const Color idle = Color(0xFFB8C7D6);
  static const Color info = Color(0xFF0077B6);

  // Shadow
  static const Color shadow = Color(0xFF0069AA);

  // Gradients
  static const LinearGradient activeMode = LinearGradient(
    colors: [primaryLight, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient brandMark = LinearGradient(
    colors: [primaryLight, primary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
