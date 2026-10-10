import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'color_hex.dart';
import 'color_swatches.dart';
import 'gradient_slider.dart';
import 'hsv_square.dart';

/// A full colour picker: saturation/value square, hue and opacity sliders,
/// hex input, a preset palette and the user's favourite colours.
///
/// Reports every change through [onChanged] as ARGB (alpha = opacity).
/// Favourites are owned by the caller ([favorites], [onAddFavorite],
/// [onRemoveFavorite]); without [onAddFavorite] that row is hidden.
class ColorPicker extends StatefulWidget {
  const ColorPicker({
    super.key,
    required this.color,
    required this.onChanged,
    this.favorites = const [],
    this.onAddFavorite,
    this.onRemoveFavorite,
    this.showOpacity = true,
  });

  final int color;
  final ValueChanged<int> onChanged;
  final List<int> favorites;
  final ValueChanged<int>? onAddFavorite;
  final ValueChanged<int>? onRemoveFavorite;
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
    if (widget.color != _argb) _setHsv(HSVColor.fromColor(Color(widget.color)), notify: false);
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

  /// Applies an opaque swatch, keeping the current opacity.
  void _pickSwatch(int rgb) {
    final alpha = widget.showOpacity ? (_hsv.alpha * 255).round() : 0xFF;
    _setHsv(HSVColor.fromColor(Color((alpha << 24) | (rgb & 0xFFFFFF))));
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
          thumbColor: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
          onChanged: (t) => _setHsv(_hsv.withHue(t * 360)),
        ),
        if (widget.showOpacity) ...[
          const SizedBox(height: Gaps.sm),
          GradientSlider(
            label: 'Opacity',
            value: _hsv.alpha,
            colors: [opaque.withValues(alpha: 0), opaque],
            thumbColor: _hsv.toColor(),
            checkerboard: true,
            onChanged: (t) => _setHsv(_hsv.withAlpha(t)),
          ),
        ],
        const SizedBox(height: Gaps.md),
        _HexRow(controller: _hex, color: _hsv.toColor(), alpha: _hsv.alpha, onChanged: _onHex),
        const SizedBox(height: Gaps.md),
        _SwatchGrid(
          colors: ColorSwatches.palette,
          selected: _argb | 0xFF000000,
          onTap: _pickSwatch,
        ),
        if (widget.onAddFavorite != null) ...[
          const SizedBox(height: Gaps.md),
          _FavoritesRow(
            favorites: widget.favorites,
            selected: _argb,
            onTap: (c) => _setHsv(HSVColor.fromColor(Color(c))),
            onAdd: () => widget.onAddFavorite!(_argb),
            onRemove: widget.onRemoveFavorite,
          ),
        ],
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
  final double alpha;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(Radii.control - 4),
            border: Border.all(color: scheme.outlineVariant),
          ),
        ),
        const SizedBox(width: Gaps.sm),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            maxLength: 9,
            decoration: const InputDecoration(
              prefixText: '# ',
              counterText: '',
              isDense: true,
              hintText: 'RRGGBB',
            ),
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
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
    );
  }
}

class _SwatchGrid extends StatelessWidget {
  const _SwatchGrid({required this.colors, required this.selected, required this.onTap});

  final List<int> colors;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in colors) Swatch(color: c, selected: c == selected, onTap: () => onTap(c)),
      ],
    );
  }
}

class _FavoritesRow extends StatelessWidget {
  const _FavoritesRow({
    required this.favorites,
    required this.selected,
    required this.onTap,
    required this.onAdd,
    required this.onRemove,
  });

  final List<int> favorites;
  final int selected;
  final ValueChanged<int> onTap;
  final VoidCallback onAdd;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Favourites', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: Gaps.xs),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in favorites)
              Swatch(
                color: c,
                selected: c == selected,
                onTap: () => onTap(c),
                onLongPress: onRemove == null ? null : () => onRemove!(c),
                tooltip: 'Long-press to remove',
              ),
            Tooltip(
              message: 'Add current colour to favourites',
              child: InkResponse(
                onTap: onAdd,
                radius: 18,
                child: Container(
                  width: Swatch.size,
                  height: Swatch.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.outline),
                  ),
                  child: Icon(Icons.add_rounded, size: 18, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
