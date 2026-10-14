import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import 'scan_corner_editor.dart';

/// The current page as it will be stored, large: a sheet of paper on the
/// desk. Tapping it goes back to the corners ([onTap]).
///
/// Shows [image] (falling back to the strip's small [preview] while it
/// renders) at [aspect] (width over height) until either is in.
class ScanResultView extends StatelessWidget {
  const ScanResultView({
    super.key,
    required this.image,
    required this.preview,
    required this.aspect,
    required this.onTap,
  });

  final ui.Image? image;
  final ui.Image? preview;
  final double aspect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shown = image ?? preview;
    final ratio = shown == null ? aspect : shown.width / shown.height;
    return Semantics(
      button: true,
      label: 'Cleaned-up page',
      hint: 'Shows the corners',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ScanCornerEditor.margin),
          child: Center(
            child: AspectRatio(
              aspectRatio: ratio,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Palette.paper,
                  boxShadow: Shadows.low(Theme.of(context).brightness),
                ),
                child: shown == null
                    ? null
                    : RawImage(image: shown, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
