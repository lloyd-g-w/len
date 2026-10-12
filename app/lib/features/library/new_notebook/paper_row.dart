import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/paper.dart';
import '../../../ui/app_theme.dart';
import '../../documents/templates/template_catalog.dart';
import '../../documents/templates/template_gallery.dart';

/// The new-notebook sheet's paper choice: the recently used papers as
/// miniatures (the selection first when it is not one of them, e.g. a
/// planner from the full chooser), then "All templates…".
class PaperRow extends StatelessWidget {
  const PaperRow({
    super.key,
    required this.selection,
    required this.styles,
    required this.onSelect,
    required this.onAll,
  });

  final TemplateSelection selection;

  /// The recent papers ([recentPapers]).
  final List<PaperStyle> styles;
  final ValueChanged<TemplateEntry> onSelect;

  /// Opens the full template chooser.
  final VoidCallback onAll;

  /// What a tile adds around its miniature (padding and selection ring).
  static const double _tileChrome = 2 * (Gaps.xs + 5);

  @override
  Widget build(BuildContext context) {
    final current = selection.template;
    final entries = [for (final s in styles) BuiltInTemplate(s)];
    final listed = entries.any(selection.isSelected);
    final landscape = current.orientation == PageOrientation.landscape;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Every tile fits when it can; on phones the row scrolls.
        final fit = constraints.maxWidth / (entries.length + 1) - _tileChrome;
        final portrait = fit.clamp(44.0, 64.0);
        return _row(current, entries, listed, landscape ? portrait * 1.3 : portrait);
      },
    );
  }

  Widget _row(PageTemplate current, List<BuiltInTemplate> entries, bool listed, double width) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Tiles scroll out to the sheet's edge rather than being cut at the inset.
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!listed)
            TemplateTile(
              key: const ValueKey('paper-current'),
              template: current,
              label: current.paper.label,
              width: width,
              selected: true,
              onTap: onAll,
            ),
          for (final entry in entries.take(listed ? entries.length : entries.length - 1))
            TemplateTile(
              key: ValueKey('paper-${entry.style.name}'),
              template: selection.tileTemplate(entry),
              label: entry.name,
              width: width,
              selected: selection.isSelected(entry),
              onTap: () => onSelect(entry),
            ),
          _AllTemplatesTile(
            width: width,
            height: width * current.size.height / current.size.width,
            onTap: onAll,
          ),
        ],
      ),
    );
  }
}

/// "All templates…": a tile the size of a miniature.
class _AllTemplatesTile extends StatelessWidget {
  const _AllTemplatesTile({required this.width, required this.height, required this.onTap});

  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: 'All templates',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('all-templates'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.all(Gaps.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                // The miniature's selection ring (3 + 2) around the page.
                margin: const EdgeInsets.all(5),
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(
                  Symbols.grid_view_rounded,
                  size: Glyphs.bar,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Gaps.xs),
              SizedBox(
                width: width + 10,
                child: Text(
                  'All templates…',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
