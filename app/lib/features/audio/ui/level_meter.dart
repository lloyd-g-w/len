import 'package:flutter/material.dart';

/// A small four-bar input level meter (0…1).
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.level, required this.color});

  final double level;
  final Color color;

  static const int bars = 4;

  @override
  Widget build(BuildContext context) {
    final lit = (level.clamp(0, 1) * bars).ceil();
    return Semantics(
      label: 'Input level',
      value: '${(level * 100).round()}%',
      child: SizedBox(
        width: bars * 5.0,
        height: 16,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < bars; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: 3,
                height: 4.0 + i * 4,
                decoration: BoxDecoration(
                  // Square bars, like the rest of the chrome; unlit ones
                  // a faint trace of the same ink.
                  color: i < lit ? color : color.withValues(alpha: 0.2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
