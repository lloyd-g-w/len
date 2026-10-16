part of 'text_format_bar.dart';

/// The controls of [TextFormatBar]: font and size, character formats,
/// paragraph.
extension _TextFormatGroups on TextFormatBar {
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
          compact: MediaQuery.sizeOf(context).width < TextFormatBar.dockBelowWidth,
          onSelected: (f) {
            c.setFont(f);
            if (c.isEmpty) onBoxChanged(c.box);
            refocus();
          },
        ),
        IconButton(
          tooltip: 'Smaller',
          onPressed: () => _setSize(TextFormatBar.step(size, -1)),
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
          onPressed: () => _setSize(TextFormatBar.step(size, 1)),
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
          tooltip: switch (nextAlign) {
            TextAlignment.start => 'Align start',
            TextAlignment.center => 'Align centre',
            TextAlignment.end => 'Align end',
          },
          onPressed: () => _box(box.copyWith(align: nextAlign)),
          icon: Icon(_alignIcon(box.align, c.caretDirection), size: Glyphs.bar),
        ),
      ],
    ];
  }

  /// The icon of [align] in a paragraph running in [direction]: start is
  /// the right edge of right-to-left text.
  static IconData _alignIcon(TextAlignment align, TextDirection direction) {
    final rtl = direction == TextDirection.rtl;
    return switch (align) {
      TextAlignment.center => Symbols.format_align_center_sharp,
      TextAlignment.start when rtl => Symbols.format_align_right_sharp,
      TextAlignment.end when !rtl => Symbols.format_align_right_sharp,
      _ => Symbols.format_align_left_sharp,
    };
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
