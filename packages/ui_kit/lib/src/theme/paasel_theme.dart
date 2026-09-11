import 'package:flutter/material.dart';
import 'package:ui_kit/src/theme/app_theme.dart';

/// Backwards-compatible access to the Paasel application themes.
abstract final class PaaselTheme {
  static ThemeData get light => AppTheme.light();
  static ThemeData get dark => AppTheme.dark();
}
