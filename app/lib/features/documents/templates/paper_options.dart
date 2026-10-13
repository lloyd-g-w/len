import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_dot.dart';
import '../../../ui/color_picker/custom_color_swatch.dart';
import '../../../ui/color_picker/pick_color.dart';
import '../template_preview.dart';
import 'page_setup.dart';
import 'paper_option_rows.dart';
import 'paper_swatch.dart';

/// The "Paper" section of the template picker: an actual-size preview
/// (unless the picker shows a page preview already), the paper and pattern
/// colours, the pattern's spacing (a slider; the templates cover the usual
/// spacings), line weight or dot size, and the margin line and header area — only
/// what the selected template uses.
class PaperOptions extends StatelessWidget {
  const PaperOptions({
    super.key,
    required this.template,
    required this.onChanged,
    this.canvas = false,
    this.swatch = true,
  });

  final PageTemplate template;

  /// Shows the actual-size [PaperSwatch] (one preview per picker).
  final bool swatch;
  final ValueChanged<PageTemplate> onChanged;

  /// Options for a canvas background (no header or margin).
  final bool canvas;

  /// Pattern colours offered besides "Auto" (the paper's own).
  static const List<int> patternColors = [
    0xFF9AA8BC, // slate
    0xFF8FB3E8, // blue
    0xFF93CBA7, // green
    0xFFE8A3A3, // red
    0xFF4A4F57, // graphite
  ];

  Paper get _paper => template.paper;
  PaperLook get _look => _paper.look;
  PaperStyle get _style => _paper.style;

  void _setLook(PaperLook look) => onChanged(template.copyWith(paper: _paper.withLook(look)));

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final image = style == PaperStyle.image;
    final pattern = !image && style != PaperStyle.blank;
    final kind = style.pitchKind;
    final extras = [
      if (style.hasMargin && !canvas)
        PaperExtraChip(
          key: const ValueKey('paper-margin'),
          label: 'Margin line',
          selected: _look.margin,
          onSelected: (v) => _setLook(_look.copyWith(margin: v)),
        ),
      if (style.hasHeader && !canvas)
        PaperExtraChip(
          key: const ValueKey('paper-header'),
          label: 'Header',
          selected: _look.header,
          onSelected: (v) => _setLook(_look.copyWith(header: v)),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: PickerLabel(canvas ? 'Background' : 'Paper')),
            if (!_look.isStandard)
              Padding(
                padding: const EdgeInsets.only(bottom: Gaps.sm),
                child: TextButton(
                  onPressed: () => _setLook(PaperLook.standard),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Reset'),
                ),
              ),
          ],
        ),
        // Planners are page layouts: a corner at actual size would show
        // just a crop of the heading, so they get the whole page.
        if (!image && swatch && style.isPlanner) ...[
          PagePreview(template: template),
          const SizedBox(height: Gaps.md),
        ] else if (!image && swatch) ...[
          PaperSwatch(template: template, canvas: canvas),
          const SizedBox(height: Gaps.sm),
        ],
        PaperOptionRow(label: 'Colour', child: _paperColors(context)),
        if (pattern) ...[
          PaperOptionRow(label: 'Pattern', child: _patternColors(context)),
          PaperSliderRow(
            label: 'Opacity',
            value: _look.patternOpacity,
            min: PaperLook.minOpacity,
            max: 1,
            display: (v) => '${(v * 100).round()}%',
            onChanged: (v) => _setLook(_look.copyWith(patternOpacity: (v * 20).round() / 20)),
          ),
        ],
        if (kind != null) ..._spacing(kind),
        if (pattern && style.hasLines)
          PaperSliderRow(
            label: 'Lines',
            value: _look.lineWeight,
            min: PaperLook.minScale,
            max: PaperLook.maxScale,
            display: _times,
            onChanged: (v) => _setLook(_look.copyWith(lineWeight: (v * 4).round() / 4)),
          ),
        if (style.hasDots)
          PaperSliderRow(
            label: 'Dots',
            value: _look.dotSize,
            min: PaperLook.minScale,
            max: PaperLook.maxScale,
            display: _times,
            onChanged: (v) => _setLook(_look.copyWith(dotSize: (v * 4).round() / 4)),
          ),
        if (extras.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Gaps.xs),
            child: Wrap(spacing: Gaps.sm, runSpacing: Gaps.xs, children: extras),
          ),
      ],
    );
  }

  static String _times(double v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}×';

  List<Widget> _spacing(PitchKind kind) {
    final mm = _paper.pitch / PaperLook.unitsPerMm;
    return [
      PaperSliderRow(
        key: const ValueKey('spacing-slider'),
        label: 'Spacing',
        value: mm,
        min: kind.min,
        max: kind.max,
        display: (v) => '${v.toStringAsFixed(1)} mm',
        onChanged: (v) => _setLook(_look.copyWith(spacing: (v * 10).round() / 10)),
      ),
    ];
  }

  Widget _paperColors(BuildContext context) {
    final color = template.color;
    return SwatchWrap(
      children: [
        for (final c in PaperColor.presets)
          ColorDot(
            key: ValueKey('paper-${c.name}'),
            color: c.paper.toARGB32(),
            size: 28,
            tooltip: c.label,
            selected: color == c,
            onTap: () => onChanged(template.copyWith(color: c)),
          ),
        CustomColorSwatch(
          key: const ValueKey('paper-custom'),
          color: color.isCustom ? color.paper.toARGB32() : null,
          // Live, like every colour popover: the preview follows the picker.
          onTap: (context) => pickCustomColor(
            context,
            title: 'Paper colour',
            initial: color.paper.toARGB32(),
            live: (c) => onChanged(template.copyWith(color: PaperColor.custom(c))),
          ),
        ),
      ],
    );
  }

  Widget _patternColors(BuildContext context) {
    final current = _look.patternColor;
    final auto = template.color.pattern.toARGB32() | 0xFF000000;
    return SwatchWrap(
      children: [
        ColorDot(
          key: const ValueKey('pattern-auto'),
          color: auto,
          size: 28,
          tooltip: 'Auto (matches the paper)',
          selected: current == null,
          onTap: () => _setLook(_look.copyWith(clearPatternColor: true)),
        ),
        for (final c in patternColors)
          ColorDot(
            key: ValueKey('pattern-$c'),
            color: c,
            size: 28,
            selected: current == c,
            onTap: () => _setLook(_look.copyWith(patternColor: c)),
          ),
        CustomColorSwatch(
          key: const ValueKey('pattern-custom'),
          color: current != null && !patternColors.contains(current) ? current : null,
          onTap: (context) => pickCustomColor(
            context,
            title: 'Pattern colour',
            initial: current ?? auto,
            live: (c) => _setLook(_look.copyWith(patternColor: c)),
          ),
        ),
      ],
    );
  }
}
