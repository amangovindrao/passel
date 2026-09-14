import 'package:flutter/material.dart';

/// Paasel's canonical color palette.
abstract final class AppColors {
  static const ink = Color(0xFF0B0B0D);
  static const paper = Color(0xFFFCFCFB);
  static const gold = Color(0xFFD4AF37);
  static const graphite = Color(0xFF1C1C1F);
  static const cloud = Color(0xFFF3F2EF);
  static const ash = Color(0xFF8B8B8F);
  static const success = Color(0xFF2FA84F);
  static const warning = Color(0xFFE8A33D);
  static const danger = Color(0xFFE5484D);
  static const mist = Color(0xFFE2E2EA);

  // Soft pastel & pinkie customer theme accents
  static const softPink = Color(0xFFFDE8EE);
  static const blush = Color(0xFFFFF2F5);
  static const deepBlush = Color(0xFFE85D88);
  static const lavender = Color(0xFFF5EEFD);
  static const deepLavender = Color(0xFF8B5CF6);
  static const peach = Color(0xFFFFF4EC);
  static const warmPeach = Color(0xFFF97316);
  static const mint = Color(0xFFE6F7ED);
  static const glassBorder = Color(0x33FFFFFF);
  static const glassSurface = Color(0xD9FFFFFF);
  static const glassCardDark = Color(0xCC1C1C1F);

  // Neutral-first theme tokens — sand & slate for classic, blush & peach for pinkie
  static const sand = Color(0xFFF5F0EB);
  static const slate = Color(0xFF64748B);

  // --- Centralized Theme Helpers ---

  /// Primary accent (CTA backgrounds, active indicators).
  static Color primaryFor({required bool isPinkie}) =>
      isPinkie ? deepBlush : gold;

  /// Light accent (chip backgrounds, tints).
  static Color accentFor({required bool isPinkie}) =>
      isPinkie ? softPink : sand;

  /// Glass card border for light mode.
  static Color glassBorderFor({required bool isPinkie}) =>
      isPinkie
          ? softPink.withValues(alpha: 0.6)
          : Colors.black.withValues(alpha: 0.07);

  /// Glass card shadow color for light mode.
  static Color glassShadowFor({required bool isPinkie, int elevation = 1}) =>
      isPinkie
          ? deepBlush.withValues(alpha: elevation == 1 ? 0.04 : 0.08)
          : Colors.black.withValues(alpha: elevation == 1 ? 0.04 : 0.08);

  /// InkWell splash/highlight for glass cards.
  static Color splashFor({required bool isPinkie}) =>
      isPinkie
          ? softPink.withValues(alpha: 0.3)
          : Colors.black.withValues(alpha: 0.06);

  static Color highlightFor({required bool isPinkie}) =>
      isPinkie
          ? blush.withValues(alpha: 0.2)
          : Colors.black.withValues(alpha: 0.04);
}
