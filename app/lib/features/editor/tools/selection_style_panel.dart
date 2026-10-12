import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import '../../../domain/text/text_data.dart';
import '../../../ink/selection/selection_controller.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../pen/option_controls.dart';
import 'text/text_style_menus.dart';
import 'text_format_bar.dart';

/// Opens the style panel of a lasso selection: font and size of the
/// selected text boxes, pen type and width of the selected ink.
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
            if (texts.isNotEmpty) ..._textSection(context, texts),
            if (texts.isNotEmpty && strokes.isNotEmpty) const SizedBox(height: Gaps.md),
            if (strokes.isNotEmpty) ..._inkSection(context, strokes),
          ],
        );
      },
    );
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
            icon: const Icon(Icons.text_decrease_rounded, size: 20),
          ),
          SizedBox(
            width: 40,
            child: Text(size?.toString() ?? '–', textAlign: TextAlign.center, style: label),
          ),
          IconButton(
            tooltip: 'Larger',
            onPressed: () => step(1),
            icon: const Icon(Icons.text_increase_rounded, size: 20),
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
          ButtonSegment(value: false, label: Text('Pen'), icon: Icon(Icons.edit_rounded)),
          ButtonSegment(
            value: true,
            label: Text('Highlighter'),
            icon: Icon(Icons.border_color_rounded),
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
      const SizedBox(height: Gaps.sm),
      Row(
        children: [
          Expanded(child: Text('Width', style: Theme.of(context).textTheme.labelLarge)),
          Text(width.toStringAsFixed(1), style: Theme.of(context).textTheme.labelMedium),
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
