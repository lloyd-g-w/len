import 'package:flutter/material.dart';

import '../../documents/export/export_flow.dart';
import 'document_layout.dart';
import 'page_overview.dart';

/// The "⋮" menu of a paged notebook: page commands, view and export.
class DocumentMenu extends StatelessWidget {
  const DocumentMenu({
    super.key,
    required this.flow,
    required this.bookmarked,
    required this.onCommand,
    required this.onOverview,
    required this.onGoTo,
    required this.onInsertPdf,
    required this.onFlow,
    required this.onExport,
  });

  final PageFlow flow;

  /// Whether the current page is bookmarked.
  final bool bookmarked;
  final ValueChanged<PageCommand> onCommand;
  final VoidCallback onOverview;
  final VoidCallback onGoTo;
  final VoidCallback onInsertPdf;
  final ValueChanged<PageFlow> onFlow;
  final ValueChanged<ExportKind> onExport;

  @override
  Widget build(BuildContext context) {
    MenuItemButton item(IconData icon, String label, VoidCallback onPressed) =>
        MenuItemButton(leadingIcon: Icon(icon), onPressed: onPressed, child: Text(label));
    return MenuAnchor(
      menuChildren: [
        item(Icons.grid_view_rounded, 'All pages', onOverview),
        item(Icons.numbers_rounded, 'Go to page…', onGoTo),
        const Divider(),
        item(
          bookmarked ? Icons.bookmark_remove_rounded : Icons.bookmark_add_outlined,
          bookmarked ? 'Remove bookmark' : 'Bookmark page',
          () => onCommand(PageCommand.bookmark),
        ),
        for (final c in const [
          PageCommand.template,
          PageCommand.insertBefore,
          PageCommand.duplicate,
          PageCommand.delete,
        ])
          item(c.icon, c == PageCommand.duplicate ? 'Duplicate page' : c.label, () => onCommand(c)),
        item(Icons.picture_as_pdf_outlined, 'Insert PDF pages…', onInsertPdf),
        const Divider(),
        SubmenuButton(
          leadingIcon: const Icon(Icons.view_agenda_outlined),
          menuChildren: [
            for (final (f, label) in const [
              (PageFlow.continuous, 'Continuous scrolling'),
              (PageFlow.single, 'One page at a time'),
            ])
              MenuItemButton(
                leadingIcon: Icon(f == flow ? Icons.radio_button_checked : Icons.radio_button_off),
                onPressed: () => onFlow(f),
                child: Text(label),
              ),
          ],
          child: const Text('Page layout'),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.ios_share_rounded),
          menuChildren: [
            for (final kind in ExportKind.values)
              MenuItemButton(onPressed: () => onExport(kind), child: Text(kind.label)),
          ],
          child: const Text('Export'),
        ),
      ],
      builder: (context, menu, _) => IconButton(
        tooltip: 'Page options',
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        icon: const Icon(Icons.more_vert_rounded),
      ),
    );
  }
}
