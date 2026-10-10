import 'dart:math' as math;

import '../../domain/stroke.dart';

/// A colour + width pair offered as a one-tap preset in the toolbar.
typedef PresetSeed = ({int color, double width});

/// Everything intrinsic to a pen type: how its outline is shaped and
/// textured, and the defaults offered for its user-adjustable settings.
///
/// Render constants here must stay stable — strokes only store the
/// adjustable parameters ([StrokeStyle]), the rest comes from the profile.
class PenProfile {
  const PenProfile._({
    required this.tool,
    required this.label,
    this.easing = _identity,
    this.nibVariation = 0,
    this.textured = false,
    this.flatCaps = false,
    this.taperFactor = 0,
    required this.opacity,
    required this.thinning,
    required this.streamline,
    this.taper = false,
    required this.minWidth,
    required this.maxWidth,
    required this.presets,
  });

  final InkTool tool;

  /// Human-readable name.
  final String label;

  /// Maps the effective pressure-derived size factor (0..1) to the radius.
  final double Function(double) easing;

  /// Fountain pens: how much narrower (fraction of the width) a line drawn
  /// along the nib is than one drawn across it (0 = no effect). Requires
  /// linear [easing].
  final double nibVariation;

  /// Pencil: graphite grain texture.
  final bool textured;

  /// Highlighter: square chisel ends instead of round caps.
  final bool flatCaps;

  /// Taper length as a multiple of the stroke width, when tapering is on.
  final double taperFactor;

  // Defaults of the user-adjustable settings.
  final double opacity;
  final double thinning;
  final double streamline;
  final bool taper;

  /// Width slider range in world units.
  final double minWidth;
  final double maxWidth;

  /// The three default toolbar presets.
  final List<PresetSeed> presets;

  /// The nib angle of the fountain pen (radians, y pointing down): a broad
  /// nib held at 45°, so right-upward hairlines are thin and downstrokes
  /// broad.
  static const double nibAngle = -math.pi / 4;

  static double _identity(double t) => t;
  static double _easeInQuad(double t) => t * t;

  static PenProfile of(InkTool tool) => _profiles[tool] ?? _profiles[InkTool.pen]!;

  static final Map<InkTool, PenProfile> _profiles = {for (final p in _all) p.tool: p};

  static const List<PenProfile> _all = [
    PenProfile._(
      tool: InkTool.pen,
      label: 'Pen',
      opacity: 1,
      thinning: 0.6,
      streamline: 0.35,
      minWidth: 0.5,
      maxWidth: 16,
      presets: [
        (color: 0xFF1F2937, width: 3),
        (color: 0xFF1C7ED6, width: 3),
        (color: 0xFFE03131, width: 3),
      ],
    ),
    PenProfile._(
      tool: InkTool.ballpoint,
      label: 'Ballpoint',
      opacity: 1,
      thinning: 0.25,
      streamline: 0.4,
      taperFactor: 2,
      minWidth: 0.5,
      maxWidth: 12,
      presets: [
        (color: 0xFF1F2937, width: 2),
        (color: 0xFF1C4ED8, width: 2),
        (color: 0xFFE03131, width: 2),
      ],
    ),
    PenProfile._(
      tool: InkTool.fountain,
      label: 'Fountain',
      nibVariation: 0.6,
      opacity: 1,
      thinning: 0.65,
      streamline: 0.45,
      taper: true,
      taperFactor: 2.5,
      minWidth: 1,
      maxWidth: 20,
      presets: [
        (color: 0xFF111827, width: 4.5),
        (color: 0xFF1E3A8A, width: 4.5),
        (color: 0xFF7F1D1D, width: 4.5),
      ],
    ),
    PenProfile._(
      tool: InkTool.brush,
      label: 'Brush',
      easing: _easeInQuad,
      opacity: 1,
      thinning: 0.85,
      streamline: 0.5,
      taper: true,
      taperFactor: 6,
      minWidth: 2,
      maxWidth: 48,
      presets: [
        (color: 0xFF111827, width: 10),
        (color: 0xFF2F9E44, width: 10),
        (color: 0xFF7048E8, width: 10),
      ],
    ),
    PenProfile._(
      tool: InkTool.pencil,
      label: 'Pencil',
      textured: true,
      opacity: 0.85,
      thinning: 0.4,
      streamline: 0.35,
      taper: true,
      taperFactor: 1.5,
      minWidth: 0.5,
      maxWidth: 14,
      presets: [
        (color: 0xFF374151, width: 2.5),
        (color: 0xFF1C7ED6, width: 2.5),
        (color: 0xFFE8590C, width: 2.5),
      ],
    ),
    PenProfile._(
      tool: InkTool.marker,
      label: 'Marker',
      opacity: 1,
      thinning: 0,
      streamline: 0.5,
      taperFactor: 1,
      minWidth: 2,
      maxWidth: 32,
      presets: [
        (color: 0xFF1F2937, width: 7),
        (color: 0xFFE03131, width: 7),
        (color: 0xFF1C7ED6, width: 7),
      ],
    ),
    PenProfile._(
      tool: InkTool.highlighter,
      label: 'Highlighter',
      flatCaps: true,
      opacity: 0.35,
      thinning: 0,
      streamline: 0.5,
      taperFactor: 0,
      minWidth: 6,
      maxWidth: 48,
      presets: [
        (color: 0xFFFACC15, width: 18),
        (color: 0xFF69DB7C, width: 18),
        (color: 0xFFF783AC, width: 18),
      ],
    ),
  ];
}
