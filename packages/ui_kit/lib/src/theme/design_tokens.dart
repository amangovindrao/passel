import 'package:flutter/material.dart';

/// Four-point spacing scale.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 64;
}

/// Paasel corner-radius scale.
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

/// Flat, two-level elevation system.
abstract final class AppShadows {
  static const level1 = <BoxShadow>[
    BoxShadow(color: Color(0x120B0B0D), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const level2 = <BoxShadow>[
    BoxShadow(color: Color(0x1A0B0B0D), blurRadius: 16, offset: Offset(0, 6)),
  ];
}

/// Shared motion durations and curves.
abstract final class AppMotion {
  static const status = Duration(milliseconds: 225);
  static const button = Duration(milliseconds: 100);
  static const pulse = Duration(milliseconds: 1800);
  static const easeOut = Curves.easeOutCubic;
}
