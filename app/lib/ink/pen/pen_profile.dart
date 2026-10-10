import 'dart:math' as math;

import '../../domain/stroke.dart';

/// How each [InkTool] renders: outline easing, nib, texture and caps.
///
/// Only the ballpoint pen and the highlighter are offered in the UI (see
/// `PenDefaults`); the other tools remain here so strokes drawn with them
/// in earlier versions keep rendering as they did. Render constants here
/// must stay stable — strokes only store their adjustable parameters
/// ([StrokeStyle]), the rest comes from the profile.
class PenProfile {
  const PenProfile._({
    required this.tool,
    this.easing = _identity,
    this.nibVariation = 0,
    this.textured = false,
    this.flatCaps = false,
  });

  final InkTool tool;

  /// Maps the effective pressure-derived size factor (0..1) to the radius.
  final double Function(double) easing;

  /// Fountain pens (legacy): how much narrower (fraction of the width) a
  /// line drawn along the nib is than one drawn across it. Requires linear
  /// [easing].
  final double nibVariation;

  /// Pencil (legacy): graphite grain texture.
  final bool textured;

  /// Highlighter: square chisel ends instead of round caps.
  final bool flatCaps;

  /// The nib angle of the legacy fountain pen (radians, y pointing down).
  static const double nibAngle = -math.pi / 4;

  static double _identity(double t) => t;
  static double _easeInQuad(double t) => t * t;

  static PenProfile of(InkTool tool) => switch (tool) {
    InkTool.fountain => const PenProfile._(tool: InkTool.fountain, nibVariation: 0.6),
    InkTool.brush => const PenProfile._(tool: InkTool.brush, easing: _easeInQuad),
    InkTool.pencil => const PenProfile._(tool: InkTool.pencil, textured: true),
    InkTool.highlighter => const PenProfile._(tool: InkTool.highlighter, flatCaps: true),
    _ => PenProfile._(tool: tool),
  };
}
