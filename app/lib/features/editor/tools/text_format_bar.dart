import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/text/text_data.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../../../ui/menus.dart';
import '../../../ui/scroll_fade.dart';
import '../../settings/keyboard_shortcuts.dart' show modifierLabel;
import 'colour_sheet.dart';
import 'text/paragraph_spacing_menus.dart';
import 'text/rich_text_controller.dart';
import 'text/table_menus.dart';
import 'text/text_style_menus.dart';

part 'text_format_bar_groups.dart';

/// Formatting controls for the text box being edited: font, size, bold,
/// italic, underline, strikethrough, colour, highlight, headings, lists,
/// alignment, paragraph spacing, delete and done. Character formats apply to the selection
/// (or to what is typed next). Placed above [anchor] (the box's screen
/// bounds), or below it when there is no room; scrolls when too wide.
class TextFormatBar extends StatelessWidget {
  const TextFormatBar({
    super.key,
    required this.anchor,
    required this.controller,
    required this.tools,
    required this.onBoxChanged,
    required this.onDelete,
    required this.onDone,
    required this.refocus,
    this.dockedKey,
  });

  /// Keys the bar while it is docked (phones), so the editor can keep the
  /// box clear of it.
  final GlobalKey? dockedKey;

  final Rect anchor;
  final RichTextController controller;
  final ToolSettings tools;

  /// The box defaults changed (remembered for new boxes).
  final ValueChanged<TextData> onBoxChanged;
  final VoidCallback onDelete;
  final VoidCallback onDone;

  /// Gives the text field its focus back (after a menu or sheet).
  final VoidCallback refocus;

  static const List<double> sizes = [12, 16, 20, 24, 32, 40, 56, 72, 96];

  /// The ⋯ menu's "Insert table…", "Table…" and "Paragraph spacing"
  /// (phones; the last two open the menus the tablet's buttons show).
  static const Object _insertTable = #insertTable, _table = #table, _spacing = #spacing;

  /// Narrower screens (phones) dock the bar at the bottom.
  static const double dockBelowWidth = 600;

  /// The next preset size after [s] in [direction].
  static double step(double s, int direction) {
    final next = direction > 0
        ? sizes.firstWhere((v) => v > s + 0.01, orElse: () => s * 1.25)
        : sizes.lastWhere((v) => v < s - 0.01, orElse: () => s / 1.25);
    return next.clamp(TextData.minFontSize, TextData.maxFontSize).toDouble();
  }

  void _box(TextData box) {
    controller.setBox(box);
    onBoxChanged(box);
  }

  @override
  Widget build(BuildContext context) {
    // Phones: docked full width at the bottom (above the keyboard, which
    // the editor makes room for), where a thumb reaches it and it never
    // covers the box being typed in.
    final docked = MediaQuery.sizeOf(context).width < dockBelowWidth;
    // A fade one button wide, so a cut always shows a faded control (a
    // hint that the row scrolls), wherever it falls.
    Widget scrolling(List<Widget> Function(List<List<Widget>>) row) => ScrollFade(
      extent: Targets.barHit(context),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: row(_groups(context, docked: docked)),
        ),
      ),
    );
    // Delete in a trailing ⋯ (REDESIGN §2.6): out of the way of ✓. On
    // phones, whose rows have no room left, tables and paragraph spacing
    // too: a row each, opening the menu the tablet's button shows, so ⋯
    // stays short and its rows whole at large text (UX_AUDIT R26-17, R26-31).
    // (The box's spacing: in a table cell [controller] is the cell's.)
    final box = controller.boxController;
    final more = Builder(
      builder: (anchor) => MenuIconButton<Object>(
        tooltip: 'More',
        icon: const Icon(Symbols.more_horiz_rounded, size: Glyphs.bar),
        items: () => [
          if (docked) ...[
            box.inTable
                ? const MenuRow<Object>(value: _table, icon: Symbols.table_rounded, label: 'Table…')
                : const MenuRow<Object>(
                    value: _insertTable,
                    icon: Symbols.table_rounded,
                    label: 'Insert table…',
                  ),
            MenuRow<Object>(
              value: _spacing,
              icon: Symbols.format_line_spacing_rounded,
              label: 'Paragraph spacing',
              caption: box.box.spacing.label,
            ),
            const PopupMenuDivider(),
          ],
          const MenuRow<Object>(
            value: true,
            icon: Symbols.delete_rounded,
            label: 'Delete text box',
            destructive: true,
          ),
        ],
        onSelected: (choice) async {
          if (choice == _insertTable) {
            await insertTableFromPicker(context, box, refocus);
          } else if (choice == _table) {
            final command = await showMenuBelow(anchor, items: tableMenuItems(box));
            command?.run(box);
            refocus();
          } else if (choice == _spacing) {
            final spacing = await showMenuBelow(
              anchor,
              items: paragraphSpacingItems(box.box.spacing),
            );
            if (spacing != null) _box(controller.box.copyWith(spacing: spacing));
            refocus();
          } else {
            onDelete();
          }
        },
      ),
    );
    final done = IconButton(
      tooltip: 'Done (Esc)',
      onPressed: onDone,
      icon: const Icon(Symbols.check_rounded, size: Glyphs.bar),
    );
    // Phones: two rows, so every control shows (font, size and paragraph
    // over the character formats), with ⋯ above ✓ at the end. Elsewhere
    // one row that scrolls when the window is too narrow; ⋯ and ✓ stay.
    final bar = FloatingPanel(
      key: docked ? dockedKey : null,
      child: docked
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (row, trailing) in [
                  ((List<List<Widget>> g) => [...g[0], _divider, ...g[2]], more),
                  ((List<List<Widget>> g) => g[1], done),
                ])
                  Row(
                    children: [
                      Expanded(
                        child: Align(alignment: Alignment.centerLeft, child: scrolling(row)),
                      ),
                      trailing,
                    ],
                  ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: scrolling((g) => [...g[0], _divider, ...g[1], _divider, ...g[2]])),
                _divider,
                more,
                done,
              ],
            ),
    );
    return CustomSingleChildLayout(
      delegate: _BarLayout(anchor, MediaQuery.paddingOf(context), docked: docked),
      child: bar,
    );
  }

  /// A hairline between the groups, as tall as a glyph's plate.
  static const Widget _divider = SizedBox(
    height: Gaps.xl,
    child: VerticalDivider(width: Gaps.sm + Hairline.width),
  );
}

class _BarLayout extends SingleChildLayoutDelegate {
  _BarLayout(this.anchor, this.chrome, {this.docked = false});

  final Rect anchor;

  /// Full width at the bottom instead of beside [anchor].
  final bool docked;

  /// Screen edges covered by the editor's chrome.
  final EdgeInsets chrome;
  static const double gap = 16, margin = 8;

  double get topInset => chrome.top + margin;
  double get bottomInset => chrome.bottom + margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final loose = constraints.loosen().deflate(const EdgeInsets.all(margin));
    return docked ? loose.tighten(width: loose.maxWidth) : loose;
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    if (docked) return Offset(margin, size.height - bottomInset - child.height);
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
  bool shouldRelayout(_BarLayout old) =>
      old.anchor != anchor || old.chrome != chrome || old.docked != docked;
}
