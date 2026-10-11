import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final landscape = selection.template.orientation == PageOrientation.landscape;
    final width = landscape ? tileWidth * 1.3 : tileWidth;
    // Groups flow side by side when there is room, one under the other
    // on narrow screens.
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: Gaps.xl,
        runSpacing: Gaps.md,
        children: [
          for (final (category, entries) in sections)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gaps.xs, left: Gaps.xs),
                    child: SectionLabel(category.label),
                  ),
                  Wrap(
                    spacing: Gaps.xxs,
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
      ),
    );
  }

  Widget _tile(TemplateEntry entry, double width) {
    final template = selection.templateFor(entry);
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
        borderRadius: BorderRadius.circular(Radii.control),
        child: Padding(
          padding: const EdgeInsets.all(Gaps.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: width + 6,
                height: height + 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: scheme.outline.withValues(alpha: 0.6)),
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                ),
                child: Icon(Icons.add_photo_alternate_outlined, color: scheme.primary),
              ),
              const SizedBox(height: Gaps.xs),
              SizedBox(
                width: width + 10,
                child: Text(
                  'Import…',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable template miniature with its name; a check badge marks
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
        borderRadius: BorderRadius.circular(Radii.control),
        child: Padding(
          padding: const EdgeInsets.all(Gaps.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: Motion.fast,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(
                        color: selected ? scheme.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.xs - 2),
                        border: Border.all(color: scheme.outlineVariant),
                        boxShadow: Shadows.low(theme.brightness),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.xs - 2),
                        child: TemplatePreview(template: template, width: width),
                      ),
                    ),
                  ),
                  if (selected)
                    Positioned(right: -2, top: -2, child: _CheckBadge(color: scheme.primary)),
                ],
              ),
              const SizedBox(height: Gaps.xs),
              SizedBox(
                width: width + 10,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Offset _center(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  return box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero));
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
      ),
      child: Icon(Icons.check_rounded, size: 12, color: Theme.of(context).colorScheme.onPrimary),
    );
  }
}
