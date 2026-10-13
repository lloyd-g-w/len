import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A notebook's cover at glyph size: flat colour, a darker spine band
/// (DESIGN §6.1), in the space of a [Glyphs.bar] icon. Paper, so it keeps
/// the contact shadow.
class MiniCover extends StatelessWidget {
  const MiniCover({super.key, required this.color});

  final Color color;

  /// A cover's proportions at glyph height, and its spine band (as dark
  /// as the big covers' plain spines).
  static const double _width = Glyphs.bar * 0.8;
  static const double _spine = 3;
  static const double _spineShade = 0.18;

  @override
  Widget build(BuildContext context) => Container(
    width: _width,
    height: Glyphs.bar,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(Radii.xs),
      boxShadow: Shadows.low(Theme.of(context).brightness),
    ),
    alignment: Alignment.centerLeft,
    child: Container(width: _spine, color: Color.lerp(color, Colors.black, _spineShade)),
  );
}
