import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'color_hex.dart';
import 'gradient_slider.dart';
import 'hsv_square.dart';

/// The custom colour picker: saturation/value square, hue and opacity
/// sliders and hex input (the "Custom" part of [ColorChoices], which lists
/// the swatches).
///
/// Reports every change through [onChanged] as ARGB (alpha = opacity).
class ColorPicker extends StatefulWidget {
  const ColorPicker({
    super.key,
    required this.color,
    required this.onChanged,
    this.showOpacity = true,
  });

  /// The colour shown (ARGB).
  final int color;

  /// Called with the new ARGB colour on every change.
  final ValueChanged<int> onChanged;

  /// Whether the opacity slider is shown (otherwise colours are opaque).
  final bool showOpacity;

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  // Kept as HSV so hue survives fully desaturated / black colours.
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.color));
  late final TextEditingController _hex = TextEditingController(text: ColorHex.rgb(widget.color));

  int get _argb => _hsv.toColor().toARGB32();

  @override
  void didUpdateWidget(ColorPicker old) {
    super.didUpdateWidget(old);
    final color = widget.color;
    if (color & 0xFFFFFF != _argb & 0xFFFFFF) {
      // A different colour from outside: start over from it.
      _hsv = HSVColor.fromColor(Color(color));
      _hex.text = ColorHex.rgb(color);
    } else if (color >>> 24 != _argb >>> 24) {
      // Only the opacity differs (e.g. the owner clamped it): keep the hue,
      // which RGB alone loses for greys and black.
      _hsv = _hsv.withAlpha(((color >>> 24) & 0xFF) / 255);
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor hsv, {bool notify = true, bool syncHex = true}) {
    setState(() => _hsv = hsv);
    if (syncHex) _hex.text = ColorHex.rgb(_argb);
    if (notify) widget.onChanged(_argb);
  }

  void _onHex(String text) {
    final parsed = ColorHex.parse(text, alpha: (_hsv.alpha * 255).round());
    if (parsed != null) _setHsv(HSVColor.fromColor(Color(parsed)), syncHex: false);
  }

  @override
  Widget build(BuildContext context) {
    final opaque = _hsv.withAlpha(1).toColor();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HsvSquare(hsv: _hsv, onChanged: _setHsv),
        const SizedBox(height: Gaps.md),
        GradientSlider(
          label: 'Hue',
          value: _hsv.hue / 360,
          colors: GradientSlider.hues,
          onChanged: (t) => _setHsv(_hsv.withHue(t * 360)),
        ),
        if (widget.showOpacity) ...[
          const SizedBox(height: Gaps.sm),
          GradientSlider(
            label: 'Opacity',
            value: _hsv.alpha,
            colors: [opaque.withValues(alpha: 0), opaque],
            checkerboard: true,
            onChanged: (t) => _setHsv(_hsv.withAlpha(t)),
          ),
        ],
        const SizedBox(height: Gaps.md),
        _HexRow(
          controller: _hex,
          color: _hsv.toColor(),
          alpha: widget.showOpacity ? _hsv.alpha : null,
          onChanged: _onHex,
        ),
      ],
    );
  }
}

class _HexRow extends StatelessWidget {
  const _HexRow({
    required this.controller,
    required this.color,
    required this.alpha,
    required this.onChanged,
  });

  final TextEditingController controller;
  final Color color;

  /// Shown as a percentage; null hides it (opaque-only pickers).
  final double? alpha;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontFeatures: AppTheme.tabularFigures);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(Radii.xs),
            border: Border.all(color: scheme.outlineVariant),
          ),
        ),
        const SizedBox(width: Gaps.sm),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            maxLength: 9,
            // The UI face with tabular figures, the "#" in the same face.
            decoration: InputDecoration(
              prefixText: '#',
              prefixStyle: text.copyWith(color: scheme.onSurfaceVariant),
              counterText: '',
              isDense: true,
              hintText: 'RRGGBB',
            ),
            style: text,
          ),
        ),
        if (alpha case final alpha?) ...[
          const SizedBox(width: Gaps.sm),
          SizedBox(
            width: 52,
            child: Text(
              '${(alpha * 100).round()}%',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ],
    );
  }
}
