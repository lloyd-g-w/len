import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import '../../../domain/text/text_data.dart';
import '../../../ink/selection/selection_controller.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_dot.dart';
import '../../../ui/even_grid.dart';
import '../pen/option_controls.dart';
import 'colour_sheet.dart';
import 'text/text_style_menus.dart';
import 'text_format_bar.dart';

/// Opens the style panel of a lasso selection: the colour of its ink and
/// text, then font and size of the selected text boxes, pen type and width
/// of the selected ink.
Future<void> showSelectionStyle(
  BuildContext context, {
  required SelectionController selection,
  required ToolSettings tools,
}) => showAdaptivePopover<void>(
  context: context,
  builder: (_) => SelectionStylePanel(selection: selection, tools: tools),
);

/// See [showSelectionStyle]. Every change is one undoable edit.
class SelectionStylePanel extends StatefulWidget {
  const SelectionStylePanel({super.key, required this.selection, required this.tools});

  final SelectionController selection;
  final ToolSettings tools;

  @override
  State<SelectionStylePanel> createState() => _SelectionStylePanelState();
}

class _SelectionStylePanelState extends State<SelectionStylePanel> {
  /// The width shown while the slider is dragged (committed on release).
  double? _dragWidth;

  SelectionController get _sel => widget.selection;

  List<TextData> get _texts => [
    for (final e in _sel.elements)
      if (e.knownType == ElementType.text) TextData.fromJson(e.data),
  ];

  /// The value all of [values] share, else null.
  static T? _common<T>(Iterable<T> values) {
    final set = values.toSet();
    return set.length == 1 ? set.single : null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _sel,
      builder: (context, _) {
        final texts = _texts;
        final strokes = _sel.strokes;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._colourSection(context),
            const SizedBox(height: Gaps.md),
            if (texts.isNotEmpty) ..._textSection(context, texts),
            if (texts.isNotEmpty && strokes.isNotEmpty) const SizedBox(height: Gaps.md),
            if (strokes.isNotEmpty) ..._inkSection(context, strokes),
          ],
        );
      },
    );
  }

  /// The colour all strokes and text boxes share, else null.
  int? _commonColour() => _common([
    for (final s in _sel.strokes) s.color | 0xFF000000,
    for (final e in _sel.elements)
      if (e.knownType == ElementType.text) TextData.fromJson(e.data).color | 0xFF000000,
  ]);

  /// The pen's quick colours, then the saved favourites; at most two rows.
  List<int> _swatches() {
    final tools = widget.tools;
    return {
      for (final c in tools.configOf(InkTool.ballpoint).colors) c | 0xFF000000,
      ...tools.favorites.map((c) => c | 0xFF000000),
    }.take(_maxSwatches).toList();
  }

  static const int _maxSwatches = 13;

  List<Widget> _colourSection(BuildContext context) {
    final current = _commonColour();
    return [
      const OptionHeader('Colour'),
      EvenGrid(
        itemExtent: 32,
        touchTargets: true,
        children: [
          for (final c in _swatches())
            ColorDot(color: c, selected: c == current, onTap: () => _sel.recolor(c)),
          Builder(
            builder: (anchor) => IconButton(
              tooltip: 'More colours',
              padding: EdgeInsets.zero,
              icon: const Icon(Symbols.add_rounded, size: Glyphs.bar),
              onPressed: () async {
                final colour = await pickColour(
                  anchor,
                  title: 'Recolour selection',
                  initial: current ?? _sel.strokes.firstOrNull?.color ?? 0xFF000000,
                  tools: widget.tools,
                );
                if (colour != null) _sel.recolor(colour);
              },
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _textSection(BuildContext context, List<TextData> texts) {
    final label = Theme.of(context).textTheme.labelLarge;
    final font = _common(texts.map((t) => t.font));
    final size = _common(texts.map((t) => t.fontSize.round()));
    void step(int direction) =>
        _sel.restyleText((t) => t.withFontSize(TextFormatBar.step(t.fontSize, direction)));
    return [
      OptionHeader(texts.length == 1 ? 'Text box' : '${texts.length} text boxes'),
      Row(
        children: [
          Expanded(child: Text('Font', style: label)),
          FontMenuButton(font: font, onSelected: (f) => _sel.restyleText((t) => t.withFont(f))),
        ],
      ),
      Row(
        children: [
          Expanded(child: Text('Size', style: label)),
          IconButton(
            tooltip: 'Smaller',
            onPressed: () => step(-1),
            icon: const Icon(Symbols.text_decrease_rounded, size: Glyphs.bar),
          ),
          SizedBox(
            width: 40,
            child: Text(size?.toString() ?? '–', textAlign: TextAlign.center, style: label),
          ),
          IconButton(
            tooltip: 'Larger',
            onPressed: () => step(1),
            icon: const Icon(Symbols.text_increase_rounded, size: Glyphs.bar),
          ),
        ],
      ),
    ];
  }

  List<Widget> _inkSection(BuildContext context, List<Stroke> strokes) {
    final tool = _common(strokes.map((s) => s.tool.isHighlighter));
    final highlighter = tool ?? false;
    final defaults = highlighter ? PenDefaults.highlighter : PenDefaults.pen;
    final width = _dragWidth ?? _common(strokes.map((s) => s.width)) ?? strokes.first.width;
    final tools = widget.tools;
    return [
      OptionHeader(strokes.length == 1 ? 'Ink' : '${strokes.length} strokes'),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Pen'), icon: Icon(Symbols.edit_rounded)),
          ButtonSegment(
            value: true,
            label: Text('Highlighter'),
            icon: Icon(Symbols.border_color_rounded),
          ),
        ],
        selected: {?tool},
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        onSelectionChanged: (s) {
          if (s.isEmpty) return;
          final ink = s.single ? InkTool.highlighter : InkTool.ballpoint;
          _sel.restyleInk(
            tool: ink,
            // Highlighters are much wider than pens: take the tool's width.
            width: tools.configOf(ink).width,
            styleFor: (t, w) => tools.configOf(t).styleFor(t, w),
          );
        },
      ),
      const SizedBox(height: Gaps.sm),
      Row(
        children: [
          Expanded(child: Text('Width', style: Theme.of(context).textTheme.labelLarge)),
          Text(width.toStringAsFixed(1), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      Slider(
        value: defaults.clampWidth(width),
        min: defaults.minWidth,
        max: defaults.maxWidth,
        onChanged: (w) => setState(() => _dragWidth = w),
        onChangeEnd: (w) {
          _sel.restyleInk(width: w);
          setState(() => _dragWidth = null);
        },
      ),
    ];
  }
}
