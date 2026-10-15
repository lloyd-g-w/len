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
import 'text/rich_text_controller.dart';
import 'text/text_style_menus.dart';

/// Formatting controls for the text box being edited: font, size, bold,
/// italic, underline, strikethrough, colour, highlight, headings, lists,
/// alignment, delete and done. Character formats apply to the selection
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
        builder: (context, _) =>
            Row(mainAxisSize: MainAxisSize.min, children: row(_groups(context))),
      ),
    );
    // Delete in a trailing ⋯ (REDESIGN §2.6): out of the way of ✓.
    final more = MenuIconButton<bool>(
      tooltip: 'More',
      icon: const Icon(Symbols.more_horiz_sharp, size: Glyphs.bar),
      items: () => const [
        MenuRow(
          value: true,
          icon: Symbols.delete_sharp,
          label: 'Delete text box',
          destructive: true,
        ),
      ],
      onSelected: (_) => onDelete(),
    );
    final done = IconButton(
      tooltip: 'Done (Esc)',
      onPressed: onDone,
      icon: const Icon(Symbols.check_sharp, size: Glyphs.bar),
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

  /// The controls in three groups: font and size; character formats;
  /// paragraph.
  List<List<Widget>> _groups(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = controller;
    final style = c.currentStyle;
    final para = c.currentPara;
    final box = c.box;
    final font = style.font ?? box.font;
    Widget toggle(String label, IconData icon, bool on, VoidCallback onPressed) => IconButton(
      tooltip: label,
      isSelected: on,
      onPressed: onPressed,
      style: IconButton.styleFrom(backgroundColor: on ? Surfaces.pressed(scheme) : null),
      icon: Icon(icon, size: Glyphs.bar),
    );
    final nextAlign = TextAlignment.values[(box.align.index + 1) % TextAlignment.values.length];
    final size = c.currentSize;
    return [
      [
        FontMenuButton(
          font: font,
          compact: MediaQuery.sizeOf(context).width < dockBelowWidth,
          onSelected: (f) {
            c.setFont(f);
            if (c.isEmpty) onBoxChanged(c.box);
            refocus();
          },
        ),
        IconButton(
          tooltip: 'Smaller',
          onPressed: () => _setSize(step(size, -1)),
          icon: const Icon(Symbols.text_decrease_sharp, size: Glyphs.bar),
        ),
        SizedBox(
          width: 28,
          child: Text(
            size.round().toString(),
            key: const ValueKey('text-size'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        IconButton(
          tooltip: 'Larger',
          onPressed: () => _setSize(step(size, 1)),
          icon: const Icon(Symbols.text_increase_sharp, size: Glyphs.bar),
        ),
      ],
      [
        toggle('Bold (${modifierLabel()}+B)', Symbols.format_bold_sharp, style.bold, c.toggleBold),
        toggle(
          'Italic (${modifierLabel()}+I)',
          Symbols.format_italic_sharp,
          style.italic,
          c.toggleItalic,
        ),
        toggle(
          'Underline (${modifierLabel()}+U)',
          Symbols.format_underlined_sharp,
          style.underline,
          c.toggleUnderline,
        ),
        toggle(
          'Strikethrough (${modifierLabel()}+Shift+X)',
          Symbols.format_strikethrough_sharp,
          style.strike,
          c.toggleStrike,
        ),
        Builder(
          builder: (context) => IconButton(
            tooltip: 'Colour',
            onPressed: () async {
              final colour = await pickColour(
                context,
                title: 'Text colour',
                initial: style.color ?? box.color,
                tools: tools,
                live: c.setColor,
                anchor: _barAnchor(context),
              );
              if (colour != null) {
                c.setColor(colour);
                if (c.isEmpty) onBoxChanged(c.box);
              }
              refocus();
            },
            icon: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Color(style.color ?? box.color),
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outline),
              ),
            ),
          ),
        ),
        HighlightMenuButton(
          highlight: style.highlight,
          onSelected: (h) {
            c.setHighlight(h);
            refocus();
          },
        ),
      ],
      [
        ParagraphMenuButton(
          heading: para.heading,
          list: para.list,
          onSelected: (choice) {
            switch (choice) {
              case HeadingChoice(:final level):
                c.setHeading(level);
              case ListChoice(:final kind):
                c.toggleList(kind);
            }
            refocus();
          },
        ),
        IconButton(
          tooltip: 'Align ${nextAlign.name}',
          onPressed: () => _box(box.copyWith(align: nextAlign)),
          icon: Icon(switch (box.align) {
            TextAlignment.left => Symbols.format_align_left_sharp,
            TextAlignment.center => Symbols.format_align_center_sharp,
            TextAlignment.right => Symbols.format_align_right_sharp,
          }, size: Glyphs.bar),
        ),
      ],
    ];
  }

  /// The button at [context] widened to the bar's height, so a popover
  /// drops its 4 dp off the bar rather than off the button inside it.
  static Rect? _barAnchor(BuildContext context) {
    RenderBox? panel;
    context.visitAncestorElements((e) {
      if (e.widget is! FloatingPanel) return true;
      panel = e.findRenderObject() as RenderBox?;
      return false;
    });
    final button = context.findRenderObject() as RenderBox?;
    if (panel == null || button == null) return null;
    final b = button.localToGlobal(Offset.zero) & button.size;
    final p = panel!.localToGlobal(Offset.zero) & panel!.size;
    return Rect.fromLTRB(b.left, p.top, b.right, p.bottom);
  }

  void _setSize(double size) {
    controller.setSize(size);
    if (controller.isEmpty) onBoxChanged(controller.box);
  }
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
