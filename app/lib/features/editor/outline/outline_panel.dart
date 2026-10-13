import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/outline/outline_tree.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/menus.dart';
import '../../../ui/section_label.dart';
import '../editor_session.dart';
import '../pdf/pdf_outline_sheet.dart';
import 'notebook_outline.dart';

/// The notebook's outline as the page overview's Outline filter (REDESIGN
/// §2.4): the user's own entries and, with PDF pages, the PDFs' bookmarks.
/// Picking an entry calls [onPage] with its page.
class NotebookOutlineView extends StatefulWidget {
  const NotebookOutlineView({super.key, required this.session, required this.onPage});

  final EditorSession session;
  final ValueChanged<int> onPage;

  @override
  State<NotebookOutlineView> createState() => _NotebookOutlineViewState();
}

class _NotebookOutlineViewState extends State<NotebookOutlineView> {
  late final NotebookOutline _outline = NotebookOutline(
    repository: widget.session.services.outline,
    notebookId: widget.session.notebook.id,
    doc: widget.session.doc!,
    sync: widget.session.services.sync,
  );

  @override
  void dispose() {
    _outline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OutlinePanel(
    outline: _outline,
    session: widget.session,
    onPage: widget.onPage,
    showTitle: false,
  );
}

/// Adds the current page of [session] to its outline (menu command).
Future<void> addPageToOutline(BuildContext context, EditorSession session) async {
  final outline = NotebookOutline(
    repository: session.services.outline,
    notebookId: session.notebook.id,
    doc: session.doc!,
    sync: session.services.sync,
  );
  try {
    await outline.addCurrentPage(context);
  } finally {
    outline.dispose();
  }
}

enum _EntryAction { rename, indent, outdent, repoint, delete }

/// The outline panel's content.
class OutlinePanel extends StatefulWidget {
  const OutlinePanel({
    super.key,
    required this.outline,
    required this.session,
    required this.onPage,
    this.scroll,
    this.showTitle = true,
  });

  final NotebookOutline outline;
  final EditorSession session;
  final ValueChanged<int> onPage;
  final ScrollController? scroll;

  /// Whether the "Outline" heading leads (not where the screen says so).
  final bool showTitle;

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  final Set<String> _collapsed = {};

  NotebookOutline get _outline => widget.outline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pdf = widget.session.pdf;
    final hasPdf = pdf?.hasPdf ?? false;
    return ListenableBuilder(
      listenable: _outline,
      builder: (context, _) {
        final current = _outline.doc.currentPage;
        final rows = _outline.tree.rows(collapsed: _collapsed).toList();
        // One row marks the page on screen: the deepest (last) entry for it.
        final highlighted = rows.where((r) => r.page == current).lastOrNull;
        return ListView(
          controller: widget.scroll,
          padding: const EdgeInsets.only(bottom: Gaps.xl),
          children: [
            if (widget.showTitle)
              Padding(
                padding: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.lg, Gaps.sm),
                child: Text('Outline', style: theme.textTheme.titleLarge),
              ),
            if (hasPdf) _label('This notebook'),
            if (_outline.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.md, Gaps.xl, 0),
                child: Text(
                  'Add pages to build a table of contents. Entries can be nested.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            // Adds the page on screen as an entry (not a new page).
            Padding(
              padding: EdgeInsets.fromLTRB(
                Gaps.lg,
                widget.showTitle || hasPdf ? Gaps.xs : Gaps.md,
                Gaps.lg,
                Gaps.sm,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => _outline.addCurrentPage(context),
                  icon: const Icon(Symbols.playlist_add_rounded),
                  label: Text('Add page ${current + 1} to outline'),
                ),
              ),
            ),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gaps.sm),
                child: _row(row, current, marked: row == highlighted),
              ),
            if (hasPdf) ...[
              _label('PDF outline'),
              PdfOutlineSection(interaction: pdf!, onPage: widget.onPage),
            ],
          ],
        );
      },
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.lg, Gaps.xl, Gaps.xs),
    child: SectionLabel(text),
  );

  /// An entry; [marked] if it marks [current], the page on screen.
  Widget _row(OutlineTreeRow row, int current, {required bool marked}) {
    final theme = Theme.of(context);
    final page = row.page;
    final entry = row.entry;
    final collapsed = _collapsed.contains(entry.id);
    final tree = _outline.tree;
    return ListTile(
      key: ValueKey('user-outline-${entry.id}'),
      selected: marked,
      selectedTileColor: Surfaces.pressed(theme.colorScheme),
      // Inset by Gaps.sm (below) so the highlight doesn't meet the edge.
      contentPadding: EdgeInsetsDirectional.only(start: row.depth * 24.0, end: 0),
      minLeadingWidth: 48,
      horizontalTitleGap: Gaps.xs,
      leading: row.hasChildren
          ? IconButton(
              tooltip: collapsed ? 'Expand' : 'Collapse',
              icon: Icon(collapsed ? Symbols.chevron_right_rounded : Symbols.expand_more_rounded),
              onPressed: () => setState(
                () => collapsed ? _collapsed.remove(entry.id) : _collapsed.add(entry.id),
              ),
            )
          : const SizedBox(width: 48),
      title: Text(
        entry.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: (row.depth == 0 ? theme.textTheme.labelLarge : theme.textTheme.bodyMedium)?.copyWith(
          color: marked ? theme.colorScheme.primary : null,
          fontWeight: marked ? FontWeight.w600 : null,
        ),
      ),
      subtitle: page == null ? const Text('Page deleted') : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            page == null ? '—' : '${page + 1}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          MenuIconButton<_EntryAction>(
            tooltip: 'Entry options',
            icon: const Icon(Symbols.more_horiz_rounded, size: Glyphs.bar),
            onSelected: (a) => switch (a) {
              _EntryAction.rename => _outline.rename(context, entry),
              _EntryAction.indent => _outline.indent(entry),
              _EntryAction.outdent => _outline.outdent(entry),
              _EntryAction.repoint => _outline.moveToCurrentPage(entry),
              _EntryAction.delete => _outline.delete(context, entry),
            },
            items: () => [
              const MenuRow(
                value: _EntryAction.rename,
                icon: Symbols.edit_rounded,
                label: 'Rename…',
              ),
              MenuRow(
                value: _EntryAction.indent,
                icon: Symbols.format_indent_increase_rounded,
                label: 'Nest under previous',
                enabled: tree.indentTarget(entry) != null,
              ),
              MenuRow(
                value: _EntryAction.outdent,
                icon: Symbols.format_indent_decrease_rounded,
                label: 'Move out a level',
                enabled: tree.isNested(entry),
              ),
              MenuRow(
                value: _EntryAction.repoint,
                icon: Symbols.my_location_rounded,
                label: 'Link to page ${current + 1}',
                enabled: page != current,
              ),
              const PopupMenuDivider(),
              const MenuRow(
                value: _EntryAction.delete,
                icon: Symbols.delete_rounded,
                label: 'Delete',
                destructive: true,
              ),
            ],
          ),
        ],
      ),
      onTap: page == null ? null : () => widget.onPage(page),
    );
  }
}
