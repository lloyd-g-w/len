import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import '../../../domain/text/text_data.dart';
import '../../../ink/selection/selection_controller.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_picker/color_choices.dart';
import '../../../ui/color_picker/color_swatches.dart';
import '../../../ui/group_header.dart';
import '../../../ui/roving_focus.dart';
import '../pen/ink_slots.dart';
import '../pen/option_controls.dart';
import '../pen/size_scale.dart';
import 'selection_fill.dart';
import 'text/text_style_menus.dart';
import 'text_format_bar.dart';

/// Opens the style panel of a lasso selection: the colour of its ink and
/// text, then font and size of the selected text boxes, pen type and width
/// of the selected ink, and the fill of the selected closed shapes.
Future<void> showSelectionStyle(
  BuildContext context, {
  required SelectionController selection,
  required ToolSettings tools,
}) => showAdaptivePopover<void>(
  context: context,
  width: colorChoicesPopoverWidth(),
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
            if (strokes.any((s) => s.isClosed)) ...[
              const SizedBox(height: Gaps.md),
              SelectionFill(selection: _sel, recent: widget.tools.recentColors),
            ],
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

  /// A custom colour not yet applied: the custom picker reports every
  /// drag step, and each recolour is an undoable edit, so a custom colour
  /// is applied once it has rested for [_settle] (or the panel closes).
  int? _pending;
  Timer? _settleTimer;
  static const _settle = Duration(milliseconds: 400);

  @override
  void dispose() {
    _settleTimer?.cancel();
    if (_pending != null) {
      // After the tree is unlocked: recolouring notifies listeners.
      scheduleMicrotask(_commit);
    }
    super.dispose();
  }

  void _recolor(int colour, {required bool preset}) {
    _settleTimer?.cancel();
    if (preset) {
      _pending = null;
      _sel.recolor(colour);
      return;
    }
    setState(() => _pending = colour);
    _settleTimer = Timer(_settle, _commit);
  }

  void _commit() {
    final colour = _pending;
    if (colour == null) return;
    _pending = null;
    _sel.recolor(colour);
    widget.tools.addRecentColor(colour);
  }

  List<Widget> _colourSection(BuildContext context) {
    final recent = widget.tools.recentColors;
    return [
      const OptionHeader('Style'),
      const SizedBox(height: Gaps.sm),
      ColorChoices(
        color: _pending ?? _commonColour() ?? _sel.strokes.firstOrNull?.color ?? 0xFF000000,
        recent: recent,
        onChanged: (c) => _recolor(
          c,
          preset: ColorSwatches.palette.contains(c) || recent.any((r) => r | 0xFF000000 == c),
        ),
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
      FontMenuRow(font: font, onSelected: (f) => _sel.restyleText((t) => t.withFont(f))),
      Row(
        children: [
          Expanded(child: Text('Size', style: label)),
          IconButton(
            tooltip: 'Smaller',
            onPressed: () => step(-1),
            icon: const Icon(Symbols.text_decrease_sharp, size: Glyphs.bar),
          ),
          SizedBox(
            width: 40,
            child: Text(size?.toString() ?? '–', textAlign: TextAlign.center, style: label),
          ),
          IconButton(
            tooltip: 'Larger',
            onPressed: () => step(1),
            icon: const Icon(Symbols.text_increase_sharp, size: Glyphs.bar),
          ),
        ],
      ),
    ];
  }

  List<Widget> _inkSection(BuildContext context, List<Stroke> strokes) {
    final tool = _common(strokes.map((s) => s.tool.isHighlighter));
    final highlighter = tool ?? false;
    final scale = SizeScale(highlighter ? PenDefaults.highlighter : PenDefaults.pen);
    final width = _dragWidth ?? _common(strokes.map((s) => s.width)) ?? strokes.first.width;
    final tools = widget.tools;
    return [
      OptionHeader(strokes.length == 1 ? 'Ink' : '${strokes.length} strokes'),
      RovingSegments(
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Pen'), icon: Icon(Symbols.edit_sharp)),
            ButtonSegment(
              value: true,
              label: Text('Highlighter'),
              icon: Icon(Symbols.border_color_sharp),
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
              styleFor: tools.styleFor,
            );
          },
        ),
      ),
      const SizedBox(height: Gaps.sm),
      GroupHeader('Size', value: formatWidth(width)),
      // The pen popover's log scale: fine pens get as much travel as broad.
      Semantics(
        label: 'Size',
        child: Slider(
          value: scale.toSlider(width),
          semanticFormatterCallback: (t) => formatWidth(scale.toWidth(t)),
          onChanged: (t) => setState(() => _dragWidth = scale.toWidth(t)),
          onChangeEnd: (t) {
            _sel.restyleInk(width: scale.toWidth(t));
            setState(() => _dragWidth = null);
          },
        ),
      ),
    ];
  }
}
