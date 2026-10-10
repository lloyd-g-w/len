import '../../domain/stroke.dart';

/// Defaults and ranges of the inks offered in the toolbar: the pen
/// (ballpoint rendering) and the highlighter.
class PenDefaults {
  const PenDefaults._({
    required this.tool,
    required this.label,
    required this.opacity,
    required this.thinning,
    required this.streamline,
    this.taperFactor = 0,
    required this.minWidth,
    required this.maxWidth,
    required this.dotScale,
    required this.colors,
    required this.widths,
  });

  /// The ink tool new strokes are drawn with.
  final InkTool tool;

  /// Human-readable name.
  final String label;

  // Defaults of the user-adjustable settings.
  final double opacity;
  final double thinning;
  final double streamline;

  /// Taper length as a multiple of the stroke width, when tapering is on.
  final double taperFactor;

  /// Width range in world units.
  final double minWidth;
  final double maxWidth;

  /// Width slot dots are `3 + width × dotScale` logical pixels wide: the
  /// real width, scaled so the sizes are easy to tell apart.
  final double dotScale;

  /// The default quick colours (opaque ARGB) and widths.
  final List<int> colors;
  final List<double> widths;

  /// The pen.
  static const PenDefaults pen = PenDefaults._(
    tool: InkTool.ballpoint,
    label: 'Pen',
    opacity: 1,
    thinning: 0.25,
    streamline: 0.4,
    taperFactor: 2,
    minWidth: 0.5,
    maxWidth: 12,
    dotScale: 2.4,
    colors: [0xFF1A2233, 0xFF1C4ED8, 0xFFDC2626],
    widths: [1.5, 2.5, 4],
  );

  /// The highlighter.
  static const PenDefaults highlighter = PenDefaults._(
    tool: InkTool.highlighter,
    label: 'Highlighter',
    opacity: 0.35,
    thinning: 0,
    streamline: 0.5,
    minWidth: 4,
    maxWidth: 48,
    dotScale: 0.6,
    colors: [0xFFFACC15, 0xFF4ADE80, 0xFFF472B6],
    widths: [10, 16, 24],
  );

  /// The defaults for [tool]: the highlighter's, or else the pen's.
  static PenDefaults of(InkTool tool) => tool.isHighlighter ? highlighter : pen;

  /// Clamps [width] to this ink's range.
  double clampWidth(double width) => width.clamp(minWidth, maxWidth).toDouble();
}
