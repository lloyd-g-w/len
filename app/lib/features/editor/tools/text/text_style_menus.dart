import 'package:flutter/material.dart';

import '../../../../domain/text/text_data.dart';

/// Picks one of the bundled fonts; each entry is shown in its own font.
class FontMenuButton extends StatelessWidget {
  const FontMenuButton({super.key, required this.font, required this.onSelected});

  final TextFont? font;
  final ValueChanged<TextFont> onSelected;

  static TextStyle sample(TextFont font, {double size = 15}) =>
      TextStyle(fontFamily: font.family, fontSize: size, height: 1.2);

  @override
  Widget build(BuildContext context) {
    final current = font;
    return PopupMenuButton<TextFont>(
      key: const ValueKey('font-menu'),
      tooltip: 'Font',
      initialValue: current,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final f in TextFont.values)
          CheckedPopupMenuItem(
            value: f,
            checked: f == current,
            child: Text(f.label, style: sample(f)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                current?.label ?? 'Mixed',
                overflow: TextOverflow.ellipsis,
                style: current == null ? null : sample(current),
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Highlighter colours for text (translucent, so text stays readable).
const List<int> textHighlights = [
  0x80FFEB3B, // yellow
  0x8066BB6A, // green
  0x8042A5F5, // blue
  0x80F06292, // pink
  0x80FFA726, // orange
];

/// Picks a highlight colour for text, or none.
class HighlightMenuButton extends StatelessWidget {
  const HighlightMenuButton({super.key, required this.highlight, required this.onSelected});

  final int? highlight;

  /// Null removes the highlight.
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget swatch(int? c) => Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: c == null ? null : Color(c),
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outline),
      ),
      child: c == null ? Icon(Icons.block_rounded, size: 16, color: scheme.outline) : null,
    );
    return PopupMenuButton<int>(
      tooltip: 'Highlight',
      // -1 = none (PopupMenuButton ignores null values).
      onSelected: (v) => onSelected(v == -1 ? null : v),
      itemBuilder: (_) => [
        for (final c in [...textHighlights, -1])
          PopupMenuItem(
            value: c,
            child: Row(
              children: [
                swatch(c == -1 ? null : c),
                const SizedBox(width: 12),
                Text(c == -1 ? 'No highlight' : _names[textHighlights.indexOf(c)]),
              ],
            ),
          ),
      ],
      icon: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          const Icon(Icons.border_color_outlined, size: 20),
          Container(
            width: 20,
            height: 4,
            color: highlight == null ? Colors.transparent : Color(highlight!),
          ),
        ],
      ),
    );
  }

  static const _names = ['Yellow', 'Green', 'Blue', 'Pink', 'Orange'];
}

/// Picks body text or a heading level for the caret's paragraphs.
class HeadingMenuButton extends StatelessWidget {
  const HeadingMenuButton({super.key, required this.heading, required this.onSelected});

  /// 0 = body text.
  final int heading;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PopupMenuButton<int>(
      tooltip: 'Paragraph style',
      initialValue: heading,
      onSelected: onSelected,
      itemBuilder: (_) => [
        CheckedPopupMenuItem(value: 0, checked: heading == 0, child: const Text('Body text')),
        CheckedPopupMenuItem(
          value: 1,
          checked: heading == 1,
          child: Text('Heading 1', style: text.titleLarge),
        ),
        CheckedPopupMenuItem(
          value: 2,
          checked: heading == 2,
          child: Text('Heading 2', style: text.titleMedium),
        ),
      ],
      icon: Icon(switch (heading) {
        1 => Icons.title_rounded,
        2 => Icons.text_fields_rounded,
        _ => Icons.notes_rounded,
      }, size: 20),
    );
  }
}
