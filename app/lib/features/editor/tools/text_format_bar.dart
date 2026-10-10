import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/text_data.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/floating_panel.dart';
import 'colour_sheet.dart';

/// Formatting controls for the text box being edited: size, bold,
/// italic, alignment, colour, delete and done. Placed above [anchor] (the
/// box's screen bounds), or below it when there is no room.
class TextFormatBar extends StatelessWidget {
  const TextFormatBar({
    super.key,
    required this.anchor,
    required this.data,
    required this.tools,
    required this.onChanged,
    required this.onDelete,
    required this.onDone,
  });

  final Rect anchor;
  final TextData data;
  final ToolSettings tools;
  final ValueChanged<TextData> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onDone;

  static const List<double> sizes = [12, 16, 20, 24, 32, 40, 56, 72, 96];

  double _step(int direction) {
    final s = data.fontSize;
    final next = direction > 0
        ? sizes.firstWhere((v) => v > s + 0.01, orElse: () => s * 1.25)
        : sizes.lastWhere((v) => v < s - 0.01, orElse: () => s / 1.25);
    return next.clamp(TextData.minFontSize, TextData.maxFontSize);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget toggle(String label, IconData icon, bool on, VoidCallback onPressed) => IconButton(
      tooltip: label,
      isSelected: on,
      onPressed: onPressed,
      style: IconButton.styleFrom(backgroundColor: on ? scheme.secondaryContainer : null),
      icon: Icon(icon, size: 20),
    );
    final nextAlign = TextAlignment.values[(data.align.index + 1) % TextAlignment.values.length];
    final bar = FloatingPanel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Smaller',
            onPressed: () => onChanged(data.copyWith(fontSize: _step(-1))),
            icon: const Icon(Icons.text_decrease_rounded, size: 20),
          ),
          SizedBox(
            width: 28,
            child: Text(
              data.fontSize.round().toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          IconButton(
            tooltip: 'Larger',
            onPressed: () => onChanged(data.copyWith(fontSize: _step(1))),
            icon: const Icon(Icons.text_increase_rounded, size: 20),
          ),
          toggle(
            'Bold',
            Icons.format_bold_rounded,
            data.bold,
            () => onChanged(data.copyWith(bold: !data.bold)),
          ),
          toggle(
            'Italic',
            Icons.format_italic_rounded,
            data.italic,
            () => onChanged(data.copyWith(italic: !data.italic)),
          ),
          IconButton(
            tooltip: 'Align ${nextAlign.name}',
            onPressed: () => onChanged(data.copyWith(align: nextAlign)),
            icon: Icon(switch (data.align) {
              TextAlignment.left => Icons.format_align_left_rounded,
              TextAlignment.center => Icons.format_align_center_rounded,
              TextAlignment.right => Icons.format_align_right_rounded,
            }, size: 20),
          ),
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Colour',
              onPressed: () async {
                final colour = await pickColour(
                  context,
                  title: 'Text colour',
                  initial: data.color,
                  tools: tools,
                  live: (c) => onChanged(data.copyWith(color: c)),
                );
                if (colour != null) onChanged(data.copyWith(color: colour));
              },
              icon: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Color(data.color),
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.outline),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Delete text box',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
          ),
          IconButton(
            tooltip: 'Done (Esc)',
            onPressed: onDone,
            icon: const Icon(Icons.check_rounded, size: 20),
          ),
        ],
      ),
    );
    return CustomSingleChildLayout(
      delegate: _BarLayout(anchor, MediaQuery.paddingOf(context)),
      child: bar,
    );
  }
}

class _BarLayout extends SingleChildLayoutDelegate {
  _BarLayout(this.anchor, this.chrome);

  final Rect anchor;

  /// Screen edges covered by the editor's chrome.
  final EdgeInsets chrome;
  static const double gap = 16, margin = 8;

  double get topInset => chrome.top + margin;
  double get bottomInset => chrome.bottom + margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().deflate(const EdgeInsets.all(margin));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final double x = (anchor.left).clamp(
      margin,
      math.max(margin, size.width - child.width - margin),
    );
    var y = anchor.top - gap - child.height;
    if (y < topInset) y = anchor.bottom + gap;
    if (y + child.height > size.height - bottomInset) y = topInset;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_BarLayout old) => old.anchor != anchor || old.chrome != chrome;
}
