import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/text/text_data.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../../../ui/menus.dart';
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
  });

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
    // The formatting controls scroll when the screen is too narrow;
    // delete and done always stay visible.
    final bar = FloatingPanel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => _row(context),
              ),
            ),
          ),
          const SizedBox(height: 24, child: VerticalDivider(width: 9)),
          // Delete in a trailing ⋯ (REDESIGN §2.6): out of the way of ✓.
          MenuIconButton<bool>(
            tooltip: 'More',
            icon: const Icon(Symbols.more_horiz_rounded, size: Glyphs.bar),
            items: () => const [
              MenuRow(
                value: true,
                icon: Symbols.delete_rounded,
                label: 'Delete text box',
                destructive: true,
              ),
            ],
            onSelected: (_) => onDelete(),
          ),
          IconButton(
            tooltip: 'Done (Esc)',
            onPressed: onDone,
            icon: const Icon(Symbols.check_rounded, size: Glyphs.bar),
          ),
        ],
      ),
    );
    return CustomSingleChildLayout(
      delegate: _BarLayout(
        anchor,
        MediaQuery.paddingOf(context),
        // Phones: docked full width at the bottom (above the keyboard,
        // which the editor makes room for), where a thumb reaches it and
        // it never covers the box being typed in.
        docked: MediaQuery.sizeOf(context).width < dockBelowWidth,
      ),
      child: bar,
    );
  }

  Widget _row(BuildContext context) {
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
    Widget divider() => const SizedBox(height: 24, child: VerticalDivider(width: 9));
    final nextAlign = TextAlignment.values[(box.align.index + 1) % TextAlignment.values.length];
    final size = c.currentSize;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FontMenuButton(
          font: font,
          onSelected: (f) {
            c.setFont(f);
            if (c.isEmpty) onBoxChanged(c.box);
            refocus();
          },
        ),
        IconButton(
          tooltip: 'Smaller',
          onPressed: () => _setSize(step(size, -1)),
          icon: const Icon(Symbols.text_decrease_rounded, size: Glyphs.bar),
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
          icon: const Icon(Symbols.text_increase_rounded, size: Glyphs.bar),
        ),
        divider(),
        toggle('Bold (Ctrl+B)', Symbols.format_bold_rounded, style.bold, c.toggleBold),
        toggle('Italic (Ctrl+I)', Symbols.format_italic_rounded, style.italic, c.toggleItalic),
        toggle(
          'Underline (Ctrl+U)',
          Symbols.format_underlined_rounded,
          style.underline,
          c.toggleUnderline,
        ),
        toggle(
          'Strikethrough (Ctrl+Shift+X)',
          Symbols.format_strikethrough_rounded,
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
        divider(),
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
            TextAlignment.left => Symbols.format_align_left_rounded,
            TextAlignment.center => Symbols.format_align_center_rounded,
            TextAlignment.right => Symbols.format_align_right_rounded,
          }, size: 20),
        ),
      ],
    );
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
