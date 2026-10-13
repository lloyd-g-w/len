import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// A plain name for a colour, for screen readers: "dark blue", "light
/// grey", "orange". Hue, lightness and saturation pick from a few basic
/// names, so custom colours get one too.
String colorName(int argb) {
  final color = Color(argb | 0xFF000000);
  final hsl = HSLColor.fromColor(color);
  final l = hsl.lightness, h = hsl.hue;
  // Chroma rather than HSL saturation, which calls dark slates blue.
  final channels = [color.r, color.g, color.b];
  final chroma = channels.reduce(math.max) - channels.reduce(math.min);
  if (l < 0.08) return 'black';
  if (l > 0.95) return 'white';
  String tone(String name) => l < 0.35
      ? 'dark $name'
      : l > 0.72
      ? 'light $name'
      : name;
  if (chroma < 0.12) return tone('grey');
  final base = switch (h) {
    < 12 || >= 345 => 'red',
    < 40 => 'orange',
    < 70 => 'yellow',
    < 95 => 'lime',
    < 165 => 'green',
    < 195 => 'teal',
    < 250 => 'blue',
    < 290 => 'purple',
    _ => 'pink',
  };
  // Dark oranges and reds read as brown; light reds as pink.
  if ((base == 'orange' || base == 'yellow') && l < 0.42) return 'brown';
  if (base == 'red' && l > 0.72) return 'pink';
  return tone(base);
}
