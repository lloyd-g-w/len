import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../domain/text/text_data.dart';
import '../../../../ui/app_theme.dart';
import '../../../../ui/menus.dart';
import '../../../settings/keyboard_shortcuts.dart' show modifierLabel;

export 'font_menus.dart';

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
      child: c == null
          ? Icon(Symbols.block_rounded, size: Glyphs.badge, color: scheme.outline)
          : null,
    );
    return MenuIconButton<int>(
      tooltip: 'Highlight',
      // -1 = none (menus return null for "dismissed").
      onSelected: (v) => onSelected(v == -1 ? null : v),
      items: () => [
        for (final c in [...textHighlights, -1])
          MenuRow(
            value: c,
            leading: swatch(c == -1 ? null : c),
            label: c == -1 ? 'No highlight' : _names[textHighlights.indexOf(c)],
            checked: c == (highlight ?? -1),
          ),
      ],
      icon: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          const Icon(Symbols.border_color_rounded, size: Glyphs.bar),
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

/// What [ParagraphMenuButton] sets on the caret's paragraphs.
sealed class ParagraphChoice {
  const ParagraphChoice();
}

/// Body text (0) or a heading level.
class HeadingChoice extends ParagraphChoice {
  const HeadingChoice(this.level);
  final int level;
}

/// Turns a list kind on or off.
class ListChoice extends ParagraphChoice {
  const ListChoice(this.kind);
  final ListKind kind;
}

/// Lists and headings for the caret's paragraphs in one menu (REDESIGN
/// §2.6's "lists ▾"): body text, two heading levels, then bulleted,
/// numbered and checklist (each with its shortcut). Its icon shows what the
/// paragraph is.
class ParagraphMenuButton extends StatelessWidget {
  const ParagraphMenuButton({
    super.key,
    required this.heading,
    required this.list,
    required this.onSelected,
  });

  /// 0 = body text.
  final int heading;
  final ListKind list;
  final ValueChanged<ParagraphChoice> onSelected;

  static IconData iconOf(ListKind kind) => switch (kind) {
    ListKind.none => Symbols.notes_rounded,
    ListKind.bullet => Symbols.format_list_bulleted_rounded,
    ListKind.number => Symbols.format_list_numbered_rounded,
    ListKind.check => Symbols.checklist_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final current = list == ListKind.none ? null : list;
    return MenuIconButton<ParagraphChoice>(
      key: const ValueKey('paragraph-menu'),
      tooltip: 'Lists and headings',
      onSelected: onSelected,
      items: () => [
        MenuRow(value: const HeadingChoice(0), label: 'Body text', checked: heading == 0),
        MenuRow(
          value: const HeadingChoice(1),
          label: 'Heading 1',
          labelStyle: text.titleLarge,
          checked: heading == 1,
        ),
        MenuRow(
          value: const HeadingChoice(2),
          label: 'Heading 2',
          labelStyle: text.titleMedium,
          checked: heading == 2,
        ),
        const PopupMenuDivider(),
        for (final (kind, label, key) in const [
          (ListKind.bullet, 'Bulleted list', '8'),
          (ListKind.number, 'Numbered list', '7'),
          (ListKind.check, 'Checklist', '9'),
        ])
          MenuRow(
            value: ListChoice(kind),
            icon: iconOf(kind),
            label: label,
            shortcut: '${modifierLabel()}+Shift+$key',
            checked: current == kind,
          ),
      ],
      icon: Icon(
        current != null
            ? iconOf(current)
            : switch (heading) {
                1 => Symbols.title_rounded,
                2 => Symbols.text_fields_rounded,
                _ => Symbols.notes_rounded,
              },
        size: Glyphs.bar,
      ),
    );
  }
}
