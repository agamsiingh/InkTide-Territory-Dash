import 'dart:ui';

/// Colors as ARGB ints plus helpers that avoid version-specific Color APIs.
class Palette {
  static const int sky = 0xFF7FD3F7;
  static const int skyDeep = 0xFF3AA8E8;
  static const int floor = 0xFFF2FBF8;
  static const int floorAlt = 0xFFE5F5F0;
  static const int wall = 0xFFFFFFFF;
  static const int navy = 0xFF1B2559;
  static const int ink = 0xFF16204A;
  static const int yellow = 0xFFFFC928;
  static const int pink = 0xFFFF4FA3;
  static const int cyan = 0xFF2EB7FF;
  static const int green = 0xFF5DD62C;
  static const int greenDark = 0xFF2E9A0E;
  static const int purple = 0xFF6C4BFF;
  static const int white = 0xFFFFFFFF;
  static const int gold = 0xFFFFE14D;
  static const int orange = 0xFFFF9F1C;
}

Color col(int argb) => Color(argb);

/// [argb] with its alpha replaced by [opacity] (0..1).
Color fade(int argb, double opacity) {
  final a = (opacity.clamp(0.0, 1.0) * 255).round();
  return Color((argb & 0x00FFFFFF) | (a << 24));
}

/// Linear mix of two ARGB ints.
int mix(int a, int b, double t) {
  int ch(int shift) {
    final ca = (a >> shift) & 0xFF, cb = (b >> shift) & 0xFF;
    return (ca + (cb - ca) * t).round().clamp(0, 255);
  }

  return (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}
