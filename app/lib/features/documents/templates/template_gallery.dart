import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/paper.dart';
import '../../../domain/templates/user_template.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/context_menu_keys.dart';
import '../../../ui/roving_focus.dart';
import '../../../ui/section_label.dart';
import '../template_preview.dart';
import 'template_catalog.dart';

/// Template sections (see [templateSections]) as live miniatures in the
/// selected colour and size, under small headings. "My templates" ends
/// with an import tile; its templates have a menu (rename, delete).
class TemplateGallery extends StatelessWidget {
  const TemplateGallery({
    super.key,
    required this.sections,
    required this.selection,
    required this.onSelect,
    this.tileWidth = 84,
    this.onImport,
    this.onTemplateMenu,
  });

  final List<(TemplateCategory, List<TemplateEntry>)> sections;
  final TemplateSelection selection;
  final ValueChanged<TemplateEntry> onSelect;

  /// Width of a portrait miniature; landscape tiles are wider.
  final double tileWidth;

  /// Imports a template (the tile is hidden when null).
  final VoidCallback? onImport;

  /// Opens the menu of one of the user's templates at a global position.
  final void Function(UserTemplate template, Offset position)? onTemplateMenu;

  /// Space a tile takes beyond its miniature's width (padding, selection
  /// rule), and the gap between tiles.
  static const double _tileChrome = 2 * TemplateTile.inset, _spacing = Gaps.xxs;

  /// The miniature width that fills [available] with whole columns of
  /// tiles: the column count whose tiles come closest to [preferred], fewer
  /// where a name's longest word ([minLabel] wide) would not fit.
  static double fillWidth(double available, double preferred, {double minLabel = 0}) {
    if (!available.isFinite) return preferred;
    double widthFor(int columns) => (available - (columns - 1) * _spacing) / columns - _tileChrome;
    var columns = math.max(
      1,
      ((available + _spacing) / (preferred + _tileChrome + _spacing)).round(),
    );
    while (columns > 1 && widthFor(columns) + TemplateTile.labelOverhang < minLabel) {
      columns--;
    }
    return math.max(widthFor(columns), preferred * 0.75);
  }

  @override
  Widget build(BuildContext context) {
    final landscape = selection.template.orientation == PageOrientation.landscape;
    final minLabel = [
      for (final (_, entries) in sections)
        for (final entry in entries) TemplateTile.wordWidth(context, entry.name),
    ].fold(0.0, math.max);
    // Every section shares one column grid that fills the width, so no
    // gutter is left at the end of the rows. The tiles hang out by their
    // inset on both sides, so the miniatures line up with the headings
    // and the content's edges.
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth + 2 * TemplateTile.inset;
        final preferred = landscape ? tileWidth * 1.3 : tileWidth;
        final width = fillWidth(available, preferred, minLabel: minLabel);
        // One Tab stop, at the chosen template; the arrows move across
        // the sections.
        return RovingGroup.grid(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, (category, entries)) in sections.indexed)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : Gaps.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: Gaps.xs),
                        child: SectionLabel(category.label),
                      ),
                      OverflowBox(
                        fit: OverflowBoxFit.deferToChild,
                        minWidth: available,
                        maxWidth: available,
                        child: Wrap(
                          spacing: _spacing,
                          runSpacing: Gaps.xs,
                          children: [
                            for (final entry in entries) _tile(entry, width),
                            if (category == TemplateCategory.mine && onImport != null)
                              _ImportTile(width: width, height: width * 1.414, onTap: onImport!),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(TemplateEntry entry, double width) {
    final template = selection.tileTemplate(entry);
    final user = entry is MyTemplate ? entry.template : null;
    final tileWidth = user == null ? width : width * (user.width / user.height) / (1 / 1.414);
    return TemplateTile(
      key: ValueKey(switch (entry) {
        BuiltInTemplate(:final style) => 'template-${style.name}',
        MyTemplate(:final template) => 'my-template-${template.id}',
      }),
      template: template,
      label: entry.name,
      width: user == null ? width : tileWidth.clamp(width * 0.7, width * 1.6),
      selected: selection.isSelected(entry),
      onTap: () => onSelect(entry),
      onMenu: user == null || onTemplateMenu == null
          ? null
          : (position) => onTemplateMenu!(user, position),
    );
  }
}

/// "Import…": adds an image or PDF page to My templates.
class _ImportTile extends StatelessWidget {
  const _ImportTile({required this.width, required this.height, required this.onTap});

  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: 'Import template',
      child: InkWell(
        key: const ValueKey('import-template'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.xs),
        child: Padding(
          padding: const EdgeInsets.all(Gaps.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A secondary button the size of a page: a Pencil edge, an Ink
              // glyph.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TemplateTile.ruleRoom,
                  vertical: TemplateTile.pageRoom,
                ),
                child: Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: scheme.outline),
                  ),
                  child: Icon(Symbols.add_photo_alternate_sharp, color: scheme.onSurface),
                ),
              ),
              const SizedBox(height: Gaps.xs),
              Container(
                width: width + 2 * TemplateTile.ruleRoom,
                padding: const EdgeInsets.only(left: TemplateTile.ruleRoom),
                child: Text(
                  'Import…',
                  maxLines: 2,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable template miniature with its name; the margin rule marks
/// the selection.
class TemplateTile extends StatelessWidget {
  const TemplateTile({
    super.key,
    required this.template,
    required this.label,
    required this.width,
    required this.selected,
    required this.onTap,
    this.onMenu,
  });

  final PageTemplate template;
  final String label;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  /// Opens the tile's menu at a global position (long press, right click).
  final ValueChanged<Offset>? onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final menu = onMenu;
    // In the gallery, Tab enters at the chosen template.
    return RovingItem(
      stop: selected,
      child: ContextMenuKeys(
        label: 'Template options',
        onMenu: menu == null ? null : () => menu(_center(context)),
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: InkWell(
            onTap: onTap,
            onLongPress: onMenu == null ? null : () => onMenu!(_center(context)),
            onSecondaryTapUp: onMenu == null ? null : (d) => onMenu!(d.globalPosition),
            borderRadius: BorderRadius.circular(Radii.xs),
            child: Padding(
              padding: const EdgeInsets.all(Gaps.xs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The selected template carries the margin rule along its
                  // left edge and a bold Ink name (DESIGN §0, as the sidebar
                  // marks its current row); no ring, no badge.
                  Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ruleRoom,
                          vertical: pageRoom,
                        ),
                        // A page: square corners, a hairline edge on the sheet
                        // and the contact shadow.
                        child: DecoratedBox(
                          position: DecorationPosition.foreground,
                          decoration: BoxDecoration(
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(boxShadow: Shadows.low(theme.brightness)),
                            child: TemplatePreview(template: template, width: width),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: pageRoom,
                        bottom: pageRoom,
                        child: AnimatedContainer(
                          duration: Motion.fast,
                          width: Hairline.rule,
                          color: selected ? scheme.primary : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gaps.xs),
                  SizedBox(
                    // The name may run into the gap after the miniature, and
                    // the tile grows rather than break a word (large text).
                    width: math.max(width + labelOverhang, wordWidth(context, label)) + ruleRoom,
                    child: Padding(
                      padding: const EdgeInsets.only(left: ruleRoom),
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _labelStyle(context, selected: selected),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Room on each side of the miniature: the margin rule and its gap (on
  /// the 4-dp grid, UX_AUDIT R8-35).
  static const double ruleRoom = Gaps.xs;

  /// Room above and below the miniature, for its contact shadow.
  static const double pageRoom = Gaps.xxs;

  /// How far the miniature sits inside the tile: its padding and the room
  /// for the margin rule. The gallery hangs tiles out by this much so the
  /// miniatures align with the content's left edge (the rule sits in the
  /// margin, like the sidebar's).
  static const double inset = Gaps.xs + ruleRoom;

  /// How far a name may run past its miniature (into the tile's padding).
  static const double labelOverhang = ruleRoom;

  static TextStyle? _labelStyle(BuildContext context, {required bool selected}) {
    final theme = Theme.of(context);
    return theme.textTheme.bodySmall?.copyWith(
      color: selected ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    );
  }

  /// The width of the longest word of [label] as a selected (bold) tile
  /// shows it: the narrowest label box that never breaks a word.
  static double wordWidth(BuildContext context, String label) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    var widest = 0.0;
    for (final word in label.split(' ')) {
      painter
        ..text = TextSpan(text: word, style: _labelStyle(context, selected: true))
        ..layout();
      widest = math.max(widest, painter.width.ceilToDouble());
    }
    painter.dispose();
    return widest;
  }
}

Offset _center(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  return box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero));
}
