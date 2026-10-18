import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app_services.dart';
import '../../../../domain/text/text_data.dart';
import '../../../../ink/fonts/text_fonts.dart';
import '../../../../ui/app_theme.dart';
import '../../../../ui/group_header.dart';
import '../../../../ui/menus.dart';
import '../../../fonts/font_import.dart';

/// The font menu's choices: the bundled fonts, the user's (each shown in
/// itself), a missing current font, and "Import font…" (with an app).
List<PopupMenuEntry<String>> _fontItems(BuildContext context, TextFont? current) {
  final user = TextFonts.library;
  final missing = current != null && current.isUser && TextFonts.userFont(current) == null;
  return [
    for (final f in TextFont.bundled)
      MenuRow(value: f.name, label: f.label, labelStyle: fontSample(f), checked: f == current),
    if (user.isNotEmpty || missing) const PopupMenuDivider(),
    for (final u in user)
      MenuRow(
        value: u.id,
        label: u.name,
        labelStyle: TextFonts.isShown(u.font) ? fontSample(u.font) : null,
        caption: TextFonts.isShown(u.font) ? null : 'Not on this device yet',
        checked: u.font == current,
      ),
    if (missing)
      MenuRow(value: current.name, label: 'Missing font', caption: 'Shown in Sans', checked: true),
    if (AppScope.maybeRead(context) != null) ...[
      const PopupMenuDivider(),
      const MenuRow(value: _import, icon: Symbols.upload_file_sharp, label: 'Import font…'),
    ],
  ];
}

const _import = 'import';

/// Runs a choice of the font menu: a font, or importing one (then chosen).
Future<void> _choose(BuildContext context, String value, ValueChanged<TextFont> onSelected) async {
  if (value != _import) return onSelected(TextFont.parse(value));
  final font = await FontImport.pick(context);
  if (font != null) onSelected(font.font);
}

/// [font] as the font menu shows it: in itself while it is shown, else in
/// the default style (a missing user font).
TextStyle? _labelStyle(TextFont? font) =>
    font == null || !TextFonts.isShown(font) ? null : fontSample(font);

/// A sample of [font] for menus.
TextStyle fontSample(TextFont font, {double size = 15}) =>
    TextStyle(fontFamily: TextFonts.familyOf(font), fontSize: size, height: 1.2);

/// Picks a font for text: the bundled ones and the user's, each shown in
/// itself, and "Import font…". A user font that is missing (removed, or
/// not on this device yet) is named in the default style, in grey.
class FontMenuButton extends StatelessWidget {
  const FontMenuButton({
    super.key,
    required this.font,
    required this.onSelected,
    this.compact = false,
  });

  final TextFont? font;
  final ValueChanged<TextFont> onSelected;

  /// Shows "Aa" in the font instead of its name (phones, where the bar
  /// needs the room for the controls after it).
  final bool compact;

  /// A sample of [font] for menus.
  static TextStyle sample(TextFont font, {double size = 15}) => fontSample(font, size: size);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: TextFonts.changes,
    builder: (context, _, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final current = font;
    final label = current == null ? 'Mixed' : TextFonts.labelOf(current);
    final shown = current == null || TextFonts.isShown(current);
    final style =
        _labelStyle(current) ??
        (shown ? null : TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
    return MenuButton<String>(
      key: const ValueKey('font-menu'),
      tooltip: shown ? 'Font' : 'Font: $label, shown in Sans',
      onSelected: (v) => unawaited(_choose(context, v, onSelected)),
      // Each font in itself.
      items: () => _fontItems(context, current),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: Gaps.sm + 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (compact)
              Text('Aa', semanticsLabel: label, style: style)
            else
              SizedBox(
                width: 92,
                child: Text(label, overflow: TextOverflow.ellipsis, style: style),
              ),
            const Icon(Symbols.expand_more_sharp, size: Glyphs.bar),
          ],
        ),
      ),
    );
  }
}

/// "Font … Sans ⌄" as a row of an options popover, like its other rows:
/// the label, then the font's name (in itself) and a chevron flush with
/// the end edge; the whole row opens the font menu.
class FontMenuRow extends StatelessWidget {
  const FontMenuRow({super.key, required this.font, required this.onSelected});

  final TextFont? font;
  final ValueChanged<TextFont> onSelected;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: TextFonts.changes,
    builder: (context, _, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final current = font;
    return MenuButton<String>(
      key: const ValueKey('font-menu'),
      tooltip: 'Font',
      onSelected: (v) => unawaited(_choose(context, v, onSelected)),
      items: () => _fontItems(context, current),
      child: SizedBox(
        height: Targets.menuRowHeight(context),
        child: Row(
          children: [
            Expanded(child: Text('Font', style: theme.textTheme.labelLarge)),
            // (A long user font name ends in an ellipsis.)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                current == null ? 'Mixed' : TextFonts.labelOf(current),
                overflow: TextOverflow.ellipsis,
                style: _labelStyle(current) ?? theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: Gaps.xs),
            EndChevron(
              child: Icon(
                Symbols.expand_more_sharp,
                size: Glyphs.bar,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
