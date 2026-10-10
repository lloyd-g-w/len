import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/preferences.dart';
import '../../documents/export/export_flow.dart';
import '../document/document_layout.dart';
import '../document/page_overview.dart';
import '../tabs/open_notebooks.dart';
import '../tabs/tab_switcher.dart';
import 'bar_button.dart';
import 'canvas_guard.dart';
import 'editor_menu_actions.dart';

/// The top bar's "⋯" menu: page commands, view (page layout, toolbar
/// position, focus mode), input and settings. On phones ([compact]) it
/// also holds what the top bar has no room for.
class EditorMoreMenu extends StatelessWidget {
  const EditorMoreMenu({super.key, required this.actions, this.compact = false, this.tabs});

  final EditorMenuActions actions;
  final bool compact;

  /// Open notebooks to offer a switcher for (when the bar has no room).
  final OpenNotebooks? tabs;

  @override
  Widget build(BuildContext context) {
    final a = actions;
    final tabs = this.tabs;
    return MenuAnchor(
      consumeOutsideTap: true,
      onOpen: CanvasGuardScope.maybeOf(context)?.opened,
      onClose: CanvasGuardScope.maybeOf(context)?.closed,
      menuChildren: [
        if (tabs != null)
          _item(
            Icons.filter_none_rounded,
            'Open notebooks (${tabs.length})',
            () => showTabSwitcher(context, tabs),
          ),
        if (compact && a.isPaged) ...[
          _item(Icons.grid_view_rounded, 'All pages', a.onOverview),
          _bookmarkItem(),
          if (a.onExport case final onExport?) exportSubmenu(onExport),
        ],
        if (a.isPaged) ...[
          SubmenuButton(
            leadingIcon: const Icon(Icons.description_outlined),
            menuChildren: [
              _item(Icons.numbers_rounded, 'Go to page…', a.onGoTo),
              _command(PageCommand.insertBefore, 'Insert page before'),
              _item(Icons.note_add_outlined, 'Add page with template…', a.onAddWithTemplate),
              _command(PageCommand.duplicate, 'Duplicate page'),
              _command(PageCommand.template, 'Change template…'),
              _item(Icons.picture_as_pdf_outlined, 'Insert PDF pages…', a.onInsertPdf),
              const Divider(),
              _command(PageCommand.delete, 'Delete page'),
            ],
            child: const Text('Page'),
          ),
          const Divider(),
          _radioSubmenu<PageFlow>(
            icon: Icons.view_agenda_outlined,
            label: 'Page layout',
            value: a.flow,
            options: const [
              (PageFlow.continuous, 'Continuous scrolling'),
              (PageFlow.single, 'One page at a time'),
            ],
            onSelected: a.onFlow,
          ),
        ] else ...[
          // Infinite canvas: background and navigation.
          _item(Icons.wallpaper_outlined, 'Background…', a.onBackground),
          const Divider(),
          _item(Icons.fit_screen_outlined, 'Fit content', a.onFitContent, hint: 'Shift+1'),
          _item(Icons.crop_free_rounded, 'Actual size (100%)', a.onActualSize, hint: '0'),
          _item(Icons.home_outlined, 'Back to start', a.onBackToStart, hint: 'Home'),
          _item(
            a.showMinimap ? Icons.map_rounded : Icons.map_outlined,
            a.showMinimap ? 'Hide overview' : 'Show overview',
            a.onToggleMinimap,
          ),
          const Divider(),
        ],
        _radioSubmenu<ToolbarPlacement>(
          icon: Icons.space_dashboard_outlined,
          label: 'Toolbar position',
          value: a.placement,
          options: const [
            (ToolbarPlacement.auto, 'Automatic'),
            (ToolbarPlacement.top, 'Top'),
            (ToolbarPlacement.bottom, 'Bottom'),
            (ToolbarPlacement.floating, 'Floating'),
          ],
          onSelected: a.onPlacement,
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.fullscreen_rounded),
          shortcut: const SingleActivator(LogicalKeyboardKey.f11),
          onPressed: a.onFocusMode,
          child: const Text('Focus mode'),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.draw_outlined),
          trailingIcon: Icon(
            a.stylusOnly ? Icons.toggle_on_rounded : Icons.toggle_off_outlined,
            size: 28,
          ),
          onPressed: () => a.onStylusOnly(!a.stylusOnly),
          child: const Text('Draw with stylus only'),
        ),
        _item(Icons.edit_outlined, 'Rename notebook…', a.onRename),
        _item(Icons.tune_rounded, 'Stylus & gesture settings…', a.onSettings),
      ],
      builder: (context, menu, _) => BarButton(
        tooltip: 'More options',
        icon: Icons.more_horiz_rounded,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }

  Widget _bookmarkItem() => _item(
    actions.bookmarked ? Icons.bookmark_remove_rounded : Icons.bookmark_add_outlined,
    actions.bookmarked ? 'Remove bookmark' : 'Bookmark page',
    actions.onToggleBookmark,
  );

  Widget _command(PageCommand c, String label) {
    final run = actions.onPageCommand;
    return _item(c.icon, label, run == null ? null : () => run(c));
  }

  static Widget _item(IconData icon, String label, VoidCallback? onPressed, {String? hint}) =>
      MenuItemButton(
        leadingIcon: Icon(icon),
        trailingIcon: hint == null ? null : Text(hint),
        onPressed: onPressed,
        child: Text(label),
      );

  static Widget _radioSubmenu<T>({
    required IconData icon,
    required String label,
    required T? value,
    required List<(T, String)> options,
    required ValueChanged<T>? onSelected,
  }) => SubmenuButton(
    leadingIcon: Icon(icon),
    menuChildren: [
      for (final (option, text) in options)
        MenuItemButton(
          leadingIcon: Icon(
            option == value ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
          ),
          onPressed: onSelected == null ? null : () => onSelected(option),
          child: Text(text),
        ),
    ],
    child: Text(label),
  );
}

/// "Export" submenu items (also used by the share button's menu).
Widget exportSubmenu(ValueChanged<ExportKind> onExport) => SubmenuButton(
  leadingIcon: const Icon(Icons.ios_share_rounded),
  menuChildren: [
    for (final kind in ExportKind.values)
      MenuItemButton(onPressed: () => onExport(kind), child: Text(kind.label)),
  ],
  child: const Text('Export'),
);

/// The top bar's share button: export the notebook or the page.
class ShareMenuButton extends StatelessWidget {
  const ShareMenuButton({super.key, required this.onExport});

  final ValueChanged<ExportKind> onExport;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      consumeOutsideTap: true,
      onOpen: CanvasGuardScope.maybeOf(context)?.opened,
      onClose: CanvasGuardScope.maybeOf(context)?.closed,
      menuChildren: [
        for (final (kind, icon) in const [
          (ExportKind.notebookPdf, Icons.menu_book_outlined),
          (ExportKind.pagePdf, Icons.picture_as_pdf_outlined),
          (ExportKind.pagePng, Icons.image_outlined),
        ])
          MenuItemButton(
            leadingIcon: Icon(icon),
            onPressed: () => onExport(kind),
            child: Text(kind.label),
          ),
      ],
      builder: (context, menu, _) => BarButton(
        tooltip: 'Export & share',
        icon: Icons.ios_share_rounded,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}
