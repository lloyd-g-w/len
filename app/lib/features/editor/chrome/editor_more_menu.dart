import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/preferences.dart';
import '../document/document_layout.dart';
import '../document/page_fit.dart';
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
  const EditorMoreMenu({
    super.key,
    required this.actions,
    this.compact = false,
    this.pagesInMenu = false,
    this.tabs,
    this.compactItems = const [],
  });

  final EditorMenuActions actions;
  final bool compact;

  /// All pages and the bookmark go in the menu even when not [compact]
  /// (top bars just wider than a phone's).
  final bool pagesInMenu;

  /// Open notebooks to offer a switcher for (when the bar has no room).
  final OpenNotebooks? tabs;

  /// Entries of features whose top bar slot has no room on phones (audio).
  final List<Widget> compactItems;

  @override
  Widget build(BuildContext context) {
    final a = actions;
    final tabs = this.tabs;
    return ChromeMenuAnchor(
      menuChildren: [
        if (tabs != null)
          _item(
            Symbols.filter_none_rounded,
            'Open notebooks (${tabs.length})',
            () => showTabSwitcher(context, tabs),
          ),
        if (compact && a.onSearch != null)
          _item(Symbols.search_rounded, 'Search in notebook', a.onSearch),
        if ((compact || pagesInMenu) && a.isPaged) ...[
          _item(Symbols.grid_view_rounded, 'All pages', a.onOverview),
          _bookmarkItem(),
        ],
        if (compact && a.isPaged)
          if (a.onExport case final onExport?) exportMenuItem(onExport),
        if (compact) ...compactItems,
        if (a.isPaged) ...[
          SubmenuButton(
            leadingIcon: const Icon(Symbols.description_rounded),
            menuChildren: [
              _item(Symbols.note_add_rounded, 'Add page with template…', a.onAddWithTemplate),
              _command(PageCommand.duplicate, 'Duplicate page'),
              _command(PageCommand.template, 'Change template…'),
              _command(PageCommand.saveAsTemplate, 'Save page as template…'),
              _item(Symbols.picture_as_pdf_rounded, 'Add pages from PDF…', a.onInsertPdf),
              _item(Symbols.playlist_add_rounded, 'Add page to outline…', a.onAddToOutline),
              const Divider(),
              _command(PageCommand.delete, 'Delete page', destructive: true),
            ],
            child: const Text('Page'),
          ),
          if (a.onOutline case final onOutline?) _item(Symbols.toc_rounded, 'Outline', onOutline),
          const Divider(),
          _radioSubmenu<PageFlow>(
            icon: Symbols.view_agenda_rounded,
            label: 'Page layout',
            value: a.flow,
            options: const [
              (PageFlow.continuous, 'Continuous scrolling'),
              (PageFlow.single, 'One page at a time'),
            ],
            onSelected: a.onFlow,
          ),
          _radioSubmenu<PageFit>(
            icon: Symbols.zoom_out_map_rounded,
            label: 'Page zoom',
            value: a.fit,
            options: [for (final f in PageFit.values) (f, f.label)],
            hints: compact
                ? const {}
                : const {PageFit.auto: '0', PageFit.page: 'Shift+1', PageFit.width: 'Shift+2'},
            onSelected: a.onFit,
          ),
        ] else ...[
          // Infinite canvas: background and navigation.
          _item(Symbols.wallpaper_rounded, 'Background…', a.onBackground),
          const Divider(),
        ],
        _radioSubmenu<ToolbarPlacement>(
          icon: Symbols.space_dashboard_rounded,
          label: 'Toolbar',
          value: a.placement,
          options: const [
            (ToolbarPlacement.docked, 'Docked'),
            (ToolbarPlacement.floating, 'Floating'),
          ],
          onSelected: a.onPlacement,
          extra: [
            const Divider(),
            MenuItemButton(
              leadingIcon: Icon(
                a.toolLabels ? Symbols.check_box_rounded : Symbols.check_box_outline_blank_rounded,
                fill: a.toolLabels ? 1 : 0,
              ),
              onPressed: a.onToolLabels == null ? null : () => a.onToolLabels!(!a.toolLabels),
              child: const Text('Show tool names'),
            ),
            if (a.onCustomiseToolbar case final onCustomise?)
              MenuItemButton(
                leadingIcon: const Icon(Symbols.tune_rounded),
                onPressed: onCustomise,
                child: const Text('Customise toolbar…'),
              ),
          ],
        ),
        MenuItemButton(
          leadingIcon: const Icon(Symbols.fullscreen_rounded),
          shortcut: compact ? null : const SingleActivator(LogicalKeyboardKey.f11),
          onPressed: a.onFocusMode,
          child: const Text('Focus mode'),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Symbols.draw_rounded),
          trailingIcon: _MenuSwitch(value: a.stylusOnly),
          onPressed: () => a.onStylusOnly(!a.stylusOnly),
          child: const Text('Draw with stylus only'),
        ),
        _item(Symbols.edit_rounded, 'Rename notebook…', a.onRename),
        _item(Symbols.tune_rounded, 'Stylus & gesture settings…', a.onSettings),
      ],
      builder: (context, menu, _) => BarButton(
        tooltip: 'More options',
        icon: Symbols.more_horiz_rounded,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }

  Widget _bookmarkItem() => _item(
    actions.bookmarked ? Symbols.bookmark_remove_rounded : Symbols.bookmark_add_rounded,
    actions.bookmarked ? 'Remove bookmark' : 'Bookmark page',
    actions.onToggleBookmark,
  );

  /// Keyboard hints only where a keyboard is likely (not on phones).
  String? hint(String keys) => compact ? null : keys;

  Widget _command(PageCommand c, String label, {bool destructive = false}) {
    final run = actions.onPageCommand;
    return _item(c.icon, label, run == null ? null : () => run(c), destructive: destructive);
  }

  static Widget _item(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    String? hint,
    bool destructive = false,
  }) => Builder(
    builder: (context) {
      final error = Theme.of(context).colorScheme.error;
      return MenuItemButton(
        style: destructive
            ? MenuItemButton.styleFrom(foregroundColor: error, iconColor: error)
            : null,
        leadingIcon: Icon(icon),
        trailingIcon: hint == null ? null : Text(hint),
        onPressed: onPressed,
        child: Text(label),
      );
    },
  );

  static Widget _radioSubmenu<T>({
    required IconData icon,
    required String label,
    required T? value,
    required List<(T, String)> options,
    required ValueChanged<T>? onSelected,
    Map<T, String> hints = const {},
    List<Widget> extra = const [],
  }) => SubmenuButton(
    leadingIcon: Icon(icon),
    menuChildren: [
      for (final (option, text) in options)
        MenuItemButton(
          leadingIcon: Icon(
            option == value
                ? Symbols.radio_button_checked_rounded
                : Symbols.radio_button_unchecked_rounded,
          ),
          trailingIcon: hints[option] == null ? null : Text(hints[option]!),
          onPressed: onSelected == null ? null : () => onSelected(option),
          child: Text(text),
        ),
      ...extra,
    ],
    child: Text(label),
  );
}

/// The "Export…" menu entry: opens the export sheet.
Widget exportMenuItem(VoidCallback onExport) => MenuItemButton(
  leadingIcon: const Icon(Symbols.ios_share_rounded),
  onPressed: onExport,
  child: const Text('Export…'),
);

/// The top bar's share button: opens the export sheet (format, pages and
/// options), so exporting takes one tap to the sheet and one to export.
class ShareMenuButton extends StatelessWidget {
  const ShareMenuButton({super.key, required this.onExport});

  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) =>
      BarButton(tooltip: 'Export & share', icon: Symbols.ios_share_rounded, onPressed: onExport);
}

/// A switch shown in a menu row; the row itself toggles it.
class _MenuSwitch extends StatelessWidget {
  const _MenuSwitch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Transform.scale(
      scale: 0.8,
      child: Switch(
        value: value,
        onChanged: (_) {},
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}
