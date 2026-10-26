import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/paper.dart';
import '../../../ui/app_theme.dart';
import '../../documents/templates/template_catalog.dart';
import '../../documents/templates/template_gallery.dart';

/// The new-notebook sheet's paper choice: the recently used papers as
/// miniatures (the selection first when it is not one of them, e.g. a
/// planner from the full chooser), then "More…" (all templates).
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

  /// What a tile adds around its miniature (padding and selection rule).
  static const double _tileChrome = 2 * TemplateTile.inset;

  @override
  Widget build(BuildContext context) {
    final current = selection.template;
    final entries = [for (final s in styles) BuiltInTemplate(s)];
    final listed = entries.any(selection.isSelected);
    final landscape = current.orientation == PageOrientation.landscape;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Every tile fits when it can; on phones the row scrolls. The
        // tiles hang out by their inset so the miniatures align with the
        // heading (as in the gallery).
        final available = constraints.maxWidth + _tileChrome;
        final fit = available / (entries.length + 1) - _tileChrome;
        final portrait = fit.clamp(48.0, 64.0);
        return OverflowBox(
          fit: OverflowBoxFit.deferToChild,
          minWidth: available,
          maxWidth: available,
          child: _row(current, entries, listed, landscape ? portrait * 1.3 : portrait),
        );
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

/// "More…" (all templates): a tile the size of a miniature.
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                // Where a template tile has its page (and margin rule).
                margin: const EdgeInsets.symmetric(
                  horizontal: TemplateTile.ruleRoom,
                  vertical: TemplateTile.pageRoom,
                ),
                width: width,
                height: height,
                // An outline like the library's New tile, not a grey plate.
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: scheme.outline),
                ),
                child: Icon(Symbols.grid_view_rounded, size: Glyphs.bar, color: scheme.onSurface),
              ),
              const SizedBox(height: Gaps.xs),
              Padding(
                padding: const EdgeInsets.only(left: TemplateTile.ruleRoom),
                // One short name on every width: "All templates…" broke
                // or swapped names on narrow tiles with large text.
                child: Text('More…', maxLines: 1, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
