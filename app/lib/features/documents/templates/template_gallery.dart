import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/paper.dart';
import '../../../domain/templates/user_template.dart';
import '../../../ui/app_theme.dart';
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
  /// ring, label overhang), and the gap between tiles.
  static const double _tileChrome = 2 * Gaps.xs + 10, _spacing = Gaps.xxs;

  /// The miniature width that fills [available] with whole columns of
  /// tiles: the column count whose tiles come closest to [preferred].
  static double fillWidth(double available, double preferred) {
    if (!available.isFinite) return preferred;
    final columns = math.max(
      1,
      ((available + _spacing) / (preferred + _tileChrome + _spacing)).round(),
    );
    final width = (available - (columns - 1) * _spacing) / columns - _tileChrome;
    return math.max(width, preferred * 0.75);
  }

  @override
  Widget build(BuildContext context) {
    final landscape = selection.template.orientation == PageOrientation.landscape;
    // Every section shares one column grid that fills the width, so no
    // gutter is left at the end of the rows.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = fillWidth(constraints.maxWidth, landscape ? tileWidth * 1.3 : tileWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, (category, entries)) in sections.indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : Gaps.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gaps.xs, left: Gaps.xs),
                      child: SectionLabel(category.label),
                    ),
                    Wrap(
                      spacing: _spacing,
                      runSpacing: Gaps.xs,
                      children: [
                        for (final entry in entries) _tile(entry, width),
                        if (category == TemplateCategory.mine && onImport != null)
                          _ImportTile(width: width, height: width * 1.414, onTap: onImport!),
                      ],
                    ),
                  ],
                ),
              ),
          ],
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
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
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
                width: width + 10,
                padding: const EdgeInsets.only(left: 5),
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
    return Semantics(
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
                    padding: const EdgeInsets.symmetric(horizontal: _ruleRoom, vertical: 3),
                    // A page: square corners, a hairline edge on the sheet
                    // and the contact shadow.
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant)),
                      child: DecoratedBox(
                        decoration: BoxDecoration(boxShadow: Shadows.low(theme.brightness)),
                        child: TemplatePreview(template: template, width: width),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 3,
                    bottom: 3,
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
                width: width + 2 * _ruleRoom,
                child: Padding(
                  padding: const EdgeInsets.only(left: _ruleRoom),
                  child: Text(
                    label,
                    maxLines: 2,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Room on each side of the miniature: the margin rule and its gap.
  static const double _ruleRoom = 5;
}

Offset _center(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  return box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero));
}
