import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paasel's complete Sora, Inter, and JetBrains Mono type scale.
abstract final class AppTypography {
  static TextStyle get displayLarge => GoogleFonts.sora(
    fontSize: 52,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
    height: 1.08,
  );
  static TextStyle get displayMedium => GoogleFonts.sora(
    fontSize: 40,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.8,
    height: 1.12,
  );
  static TextStyle get headline => GoogleFonts.sora(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.2,
  );
  static TextStyle get title => GoogleFonts.sora(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
  );
  static TextStyle get body => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.5,
  );
  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.5,
  );
  static TextStyle get bodyStrong => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.5,
  );
  static TextStyle get label => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.35,
  );
  static TextStyle get caption => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    height: 1.35,
  );
  static TextStyle get data => GoogleFonts.jetBrainsMono(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
    height: 1.4,
  );
  static TextStyle get price => GoogleFonts.jetBrainsMono(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.5,
    height: 1.25,
  );
  static TextStyle get priceLarge => GoogleFonts.jetBrainsMono(
    fontSize: 36,
    fontWeight: FontWeight.w500,
    letterSpacing: -1,
    height: 1.15,
  );
  static TextStyle get otp => GoogleFonts.jetBrainsMono(
    fontSize: 28,
    fontWeight: FontWeight.w500,
    letterSpacing: 4,
    height: 1.2,
  );

  static TextTheme textTheme(Color color) => TextTheme(
    displayLarge: displayLarge.copyWith(color: color),
    displayMedium: displayMedium.copyWith(color: color),
    headlineLarge: headline.copyWith(color: color),
    headlineMedium: headline.copyWith(fontSize: 26, color: color),
    headlineSmall: headline.copyWith(fontSize: 24, color: color),
    titleLarge: title.copyWith(color: color),
    titleMedium: bodyStrong.copyWith(color: color),
    titleSmall: label.copyWith(color: color),
    bodyLarge: body.copyWith(color: color),
    bodyMedium: body.copyWith(fontSize: 14, color: color),
    bodySmall: caption.copyWith(color: color),
    labelLarge: label.copyWith(color: color),
    labelMedium: caption.copyWith(color: color),
    labelSmall: caption.copyWith(fontSize: 11, color: color),
  );
}
