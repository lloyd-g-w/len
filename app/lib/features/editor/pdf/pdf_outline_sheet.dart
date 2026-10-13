import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import 'pdf_interaction.dart';
import 'pdf_page_info.dart';

/// An outline entry placed in the notebook: its depth and the notebook
/// page it opens (null if that PDF page is no longer in the notebook).
typedef OutlineRow = ({PdfOutlineItem item, int depth, int? page, String key});

/// The rows of [outline] (of PDF [blob]) mapped onto the notebook's pages,
/// depth first, leaving out the children of entries whose key is in
/// [collapsed].
List<OutlineRow> outlineRows(
  PdfInteraction interaction,
  String blob,
  List<PdfOutlineItem> outline, {
  Set<String> collapsed = const {},
}) {
  final rows = <OutlineRow>[];
  void visit(List<PdfOutlineItem> items, int depth, String prefix) {
    for (final (i, item) in items.indexed) {
      final key = '$prefix$i';
      final target = item.page;
      rows.add((
        item: item,
        depth: depth,
        page: target == null ? null : interaction.notebookPageOf(blob, target),
        key: key,
      ));
      if (!collapsed.contains(key)) visit(item.children, depth + 1, '$key.');
    }
  }

  visit(outline, 0, '');
  return rows;
}

/// The outlines (bookmarks) of the notebook's PDFs, mapped onto its pages,
/// as a section of the editor's outline panel: one group per PDF.
class PdfOutlineSection extends StatefulWidget {
  const PdfOutlineSection({super.key, required this.interaction, required this.onPage});

  final PdfInteraction interaction;
  final ValueChanged<int> onPage;

  @override
  State<PdfOutlineSection> createState() => _PdfOutlineSectionState();
}

class _PdfOutlineSectionState extends State<PdfOutlineSection> {
  late final List<String> _blobs = widget.interaction.blobs;
  late final Future<List<List<PdfOutlineItem>>> _outlines = Future.wait([
    for (final b in _blobs) widget.interaction.info.outline(b),
  ]);
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder(
      future: _outlines,
      builder: (context, snapshot) {
        final outlines = snapshot.data;
        final children = <Widget>[];
        if (outlines == null) {
          children.add(
            const Padding(
              padding: EdgeInsets.all(Gaps.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        } else if (outlines.every((o) => o.isEmpty)) {
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.xl, vertical: Gaps.md),
              child: Text(
                _blobs.length == 1 ? 'This PDF has no outline' : 'These PDFs have no outline',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        } else {
          for (final (i, outline) in outlines.indexed) {
            if (outline.isEmpty) continue;
            if (_blobs.length > 1) children.add(_header(context, i));
            children.addAll([
              for (final row in outlineRows(
                widget.interaction,
                _blobs[i],
                outline,
                collapsed: {
                  for (final k in _collapsed)
                    if (k.startsWith('$i:')) k.substring('$i:'.length),
                },
              ))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gaps.sm),
                  child: _row(context, row, i),
                ),
            ]);
          }
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      },
    );
  }

  Widget _header(BuildContext context, int pdf) {
    final first = widget.interaction.notebookPageOf(_blobs[pdf], 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.lg, Gaps.xl, Gaps.xs),
      child: Text(
        first == null ? 'PDF ${pdf + 1}' : 'PDF ${pdf + 1} · from page ${first + 1}',
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }

  Widget _row(BuildContext context, OutlineRow row, int pdf) {
    final theme = Theme.of(context);
    final page = row.page;
    final key = '$pdf:${row.key}';
    final hasChildren = row.item.children.isNotEmpty;
    final collapsed = _collapsed.contains(key);
    return ListTile(
      key: ValueKey('outline-$key'),
      enabled: page != null,
      // Inset by Gaps.sm (below) so the highlight doesn't meet the edge.
      contentPadding: EdgeInsetsDirectional.only(start: row.depth * 24.0, end: Gaps.lg - Gaps.sm),
      minLeadingWidth: 48,
      horizontalTitleGap: Gaps.xs,
      leading: hasChildren
          ? IconButton(
              tooltip: collapsed ? 'Expand' : 'Collapse',
              icon: Icon(collapsed ? Symbols.chevron_right_sharp : Symbols.expand_more_sharp),
              onPressed: () =>
                  setState(() => collapsed ? _collapsed.remove(key) : _collapsed.add(key)),
            )
          : const SizedBox(width: 48),
      title: Text(
        row.item.title.isEmpty ? 'Untitled' : row.item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: row.depth == 0 ? theme.textTheme.labelLarge : theme.textTheme.bodyMedium,
      ),
      trailing: Text(
        page == null ? '—' : '${page + 1}',
        style: theme.textTheme.bodySmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      onTap: page == null ? null : () => widget.onPage(page),
    );
  }
}
