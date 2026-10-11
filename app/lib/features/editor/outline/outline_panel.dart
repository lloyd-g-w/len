import 'package:flutter/material.dart';

import '../../../domain/outline/outline_tree.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/menus.dart';
import '../../../ui/section_label.dart';
import '../editor_session.dart';
import '../pdf/pdf_outline_sheet.dart';
import 'notebook_outline.dart';

/// Shows the notebook's outline: the user's own entries and, with PDF
/// pages, the PDFs' bookmarks. Picking an entry goes to its page.
Future<void> showOutline(BuildContext context, EditorSession session) async {
  final doc = session.doc!;
  final outline = NotebookOutline(
    repository: session.services.outline,
    notebookId: session.notebook.id,
    doc: doc,
    sync: session.services.sync,
  );
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (context, scroll) => OutlinePanel(
          outline: outline,
          session: session,
          scroll: scroll,
          onPage: (page) {
            Navigator.of(context).pop();
            doc.scrollToPage(page);
          },
        ),
      ),
    );
  } finally {
    outline.dispose();
  }
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
  });

  final NotebookOutline outline;
  final EditorSession session;
  final ValueChanged<int> onPage;
  final ScrollController? scroll;

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
        return ListView(
          controller: widget.scroll,
          padding: const EdgeInsets.only(bottom: Gaps.xl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.lg, Gaps.sm),
              child: Row(
                children: [
                  Expanded(child: Text('Outline', style: theme.textTheme.titleLarge)),
                  FilledButton.tonalIcon(
                    onPressed: () => _outline.addCurrentPage(context),
                    icon: const Icon(Icons.add_rounded),
                    label: Text('Add page ${current + 1}'),
                  ),
                ],
              ),
            ),
            if (hasPdf) _label('This notebook'),
            if (_outline.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gaps.xl, vertical: Gaps.md),
                child: Text(
                  'Add pages to build a table of contents. Entries can be nested.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final row in _outline.tree.rows(collapsed: _collapsed)) _row(row, current),
            if (hasPdf) ...[
              _label('PDF'),
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

  Widget _row(OutlineTreeRow row, int current) {
    final theme = Theme.of(context);
    final page = row.page;
    final entry = row.entry;
    final collapsed = _collapsed.contains(entry.id);
    final tree = _outline.tree;
    return ListTile(
      key: ValueKey('user-outline-${entry.id}'),
      selected: page == current,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      contentPadding: EdgeInsetsDirectional.only(start: Gaps.sm + row.depth * 24.0, end: Gaps.xs),
      minLeadingWidth: 48,
      horizontalTitleGap: Gaps.xs,
      leading: row.hasChildren
          ? IconButton(
              tooltip: collapsed ? 'Expand' : 'Collapse',
              icon: Icon(collapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded),
              onPressed: () => setState(
                () => collapsed ? _collapsed.remove(entry.id) : _collapsed.add(entry.id),
              ),
            )
          : const SizedBox(width: 48),
      title: Text(
        entry.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: (row.depth == 0 ? theme.textTheme.bodyLarge : theme.textTheme.bodyMedium)?.copyWith(
          color: page == current ? theme.colorScheme.primary : null,
          fontWeight: page == current ? FontWeight.w600 : null,
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
          PopupMenuButton<_EntryAction>(
            tooltip: 'Entry options',
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            onSelected: (a) => switch (a) {
              _EntryAction.rename => _outline.rename(context, entry),
              _EntryAction.indent => _outline.indent(entry),
              _EntryAction.outdent => _outline.outdent(entry),
              _EntryAction.repoint => _outline.moveToCurrentPage(entry),
              _EntryAction.delete => _outline.delete(context, entry),
            },
            itemBuilder: (_) => [
              const MenuRow(
                value: _EntryAction.rename,
                icon: Icons.edit_outlined,
                label: 'Rename…',
              ),
              MenuRow(
                value: _EntryAction.indent,
                icon: Icons.format_indent_increase_rounded,
                label: 'Nest under previous',
                enabled: tree.indentTarget(entry) != null,
              ),
              MenuRow(
                value: _EntryAction.outdent,
                icon: Icons.format_indent_decrease_rounded,
                label: 'Move out a level',
                enabled: tree.isNested(entry),
              ),
              MenuRow(
                value: _EntryAction.repoint,
                icon: Icons.my_location_rounded,
                label: 'Link to page ${current + 1}',
                enabled: page != current,
              ),
              const PopupMenuDivider(),
              const MenuRow(
                value: _EntryAction.delete,
                icon: Icons.delete_outline_rounded,
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
