import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/preferences.dart';
import '../../../ui/app_switch.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/group_header.dart';
import '../../../ui/menus.dart';
import '../canvas/canvas_shortcuts.dart';
import '../document/document_layout.dart';
import '../document/page_fit.dart';
import '../document/page_overview.dart';
import '../tabs/open_notebooks.dart';
import '../tabs/tab_switcher.dart';
import 'bar_button.dart';
import 'canvas_guard.dart';
import 'editor_menu_actions.dart';

part 'editor_more_menu_rows.dart';

/// The top bar's "⋯" menu (REDESIGN §2.3): search, export and print; the page
/// (paged) or the background (canvas); view options; split view; drawing
/// with a finger; settings. Phones ([compact]) add audio and the open
/// notebooks at the top, and open Page and View in place of the menu
/// (a drill-in with a back row) instead of beside it. Shortcut hints show
/// only where a keyboard is likely (not on touch-first devices).
class EditorMoreMenu extends StatefulWidget {
  const EditorMoreMenu({
    super.key,
    required this.actions,
    this.compact = false,
    this.tabs,
    this.compactItems = const [],
    this.split,
  });

  final EditorMenuActions actions;

  /// Phones: [compactItems] and [tabs] on top, submenus drill in.
  final bool compact;

  /// Open notebooks to offer a switcher for (phones, where there are no
  /// tabs).
  final OpenNotebooks? tabs;

  /// Entries of features the phone bar has no room for (audio).
  final List<Widget> compactItems;

  /// The split view submenu (wide panes).
  final Widget? split;

  @override
  State<EditorMoreMenu> createState() => _EditorMoreMenuState();
}

/// A submenu shown in place of the menu on phones.
typedef _Drill = ({IconData icon, String label, List<Widget> children});

class _EditorMoreMenuState extends State<EditorMoreMenu> {
  /// The submenu drilled into (phones), null for the menu itself.
  String? _drilled;

  EditorMenuActions get actions => widget.actions;
  bool get compact => widget.compact;

  @override
  Widget build(BuildContext context) {
    final a = actions;
    final tabs = widget.tabs;
    final submenus = <_Drill>[if (a.isPaged) _pageMenu(), _viewMenu()];
    final drilled = submenus.where((d) => d.label == _drilled).firstOrNull;
    final top = [
      ...widget.compactItems,
      if (tabs != null)
        _item(
          Symbols.filter_none_sharp,
          'Open notebooks (${tabs.length})',
          () => showTabSwitcher(context, tabs),
        ),
    ];
    return ChromeMenuAnchor(
      menuChildren: drilled != null
          ? [_back(drilled), const Divider(), ...drilled.children]
          : [
              if (top.isNotEmpty) ...[...top, const Divider()],
              _item(
                Symbols.search_sharp,
                'Search in notebook',
                a.onSearch,
                shortcut: const SingleActivator(LogicalKeyboardKey.keyF, control: true),
              ),
              if (a.onExport case final onExport?)
                _item(
                  Symbols.ios_share_sharp,
                  'Export…',
                  onExport,
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyE, control: true),
                ),
              if (a.onPrint case final onPrint?)
                _item(
                  Symbols.print_sharp,
                  'Print…',
                  onPrint,
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyP, control: true),
                ),
              if (a.onVersionHistory case final onVersionHistory?)
                _item(Symbols.history_sharp, 'Version history…', onVersionHistory),
              const Divider(),
              if (a.isPaged)
                _submenu(_pageMenu())
              else
                _item(Symbols.wallpaper_sharp, 'Background…', a.onBackground),
              _submenu(_viewMenu()),
              ?widget.split,
              const Divider(),
              // Writing with a finger on a phone is writing in the zoom
              // window (GoodNotes' answer): one tap, not three.
              if (compact) _zoomWindow(),
              // Automatic (null) draws with a finger until a stylus is seen; with
              // a mouse the switch shows once a stylus was.
              if (a.stylusOnly != null || Targets.touchFirst)
                MenuItemButton(
                  leadingIcon: const Icon(Symbols.draw_sharp),
                  trailingIcon: _MenuSwitch(value: !(a.stylusOnly ?? false)),
                  onPressed: () => a.onStylusOnly(!(a.stylusOnly ?? false)),
                  child: const Text('Draw with finger'),
                ),
              _item(Symbols.settings_sharp, 'Settings', a.onSettings),
            ],
      builder: (context, menu, _) => BarButton(
        tooltip: 'More options',
        icon: Symbols.more_horiz_sharp,
        onPressed: () {
          if (menu.isOpen) return menu.close();
          // Always opens at the top, not in the submenu last drilled into.
          if (_drilled != null) setState(() => _drilled = null);
          menu.open();
        },
      ),
    );
  }

  /// The page menu: the overview tile's too ([PageCommand.menu]).
  _Drill _pageMenu() => (
    icon: Symbols.description_sharp,
    label: 'Page',
    children: [
      for (final c in PageCommand.menuFor(pdf: actions.pdfPage)) ...[
        if (c.destructive) const Divider(),
        _command(c),
      ],
    ],
  );

  Widget _zoomWindow() => _switch(
    Symbols.pageview_sharp,
    'Zoom window',
    actions.zoomWindow,
    actions.onZoomWindow,
    shortcut: const SingleActivator(LogicalKeyboardKey.keyM),
  );

  _Drill _viewMenu() {
    final a = actions;
    return (
      icon: Symbols.visibility_sharp,
      label: 'View',
      children: [
        // The zoom choices are the menu's one group; the rest switch.
        if (a.isPaged) ...[
          for (final (fit, keys) in const [
            (PageFit.page, SingleActivator(LogicalKeyboardKey.digit1, shift: true)),
            (PageFit.width, SingleActivator(LogicalKeyboardKey.digit2, shift: true)),
            (PageFit.auto, SingleActivator(LogicalKeyboardKey.digit0)),
          ])
            _radio(a.fit == fit, fit.label, () => a.onFit?.call(fit), shortcut: keys),
          const Divider(),
          _switch(
            Symbols.auto_stories_sharp,
            'One page at a time',
            a.flow == PageFlow.single,
            switch (a.onFlow) {
              final onFlow? => () => onFlow(
                a.flow == PageFlow.single ? PageFlow.continuous : PageFlow.single,
              ),
              null => null,
            },
          ),
        ],
        _switch(
          Symbols.toolbar_sharp,
          'Floating toolbar',
          a.placement == ToolbarPlacement.floating,
          () => a.onPlacement(
            a.placement == ToolbarPlacement.floating
                ? ToolbarPlacement.docked
                : ToolbarPlacement.floating,
          ),
        ),
        // Phones have it on top, by Draw with finger (R20-2).
        if (!compact) _zoomWindow(),
        if (a.minimap case final minimap?)
          _switch(Symbols.map_sharp, 'Minimap', minimap, a.onMinimap, shortcut: minimapShortcut),
        if (a.onPointerTags != null)
          _switch(Symbols.badge_sharp, 'Name tags', a.pointerTags, a.onPointerTags),
        _item(
          Symbols.fullscreen_sharp,
          'Focus mode',
          a.onFocusMode,
          // As text: Flutter labels F-keys as characters when compiled to
          // JavaScript (their 64-bit key ids lose the plane bits in 32-bit
          // bitwise operations), so F11 showed as a missing glyph on the web;
          // a CharacterActivator only takes one character.
          shortcutLabel: 'F11',
        ),
      ],
    );
  }

  /// A submenu: beside the menu where there is room, in its place on
  /// phones (where a cascade would cover its parent).
  Widget _submenu(_Drill d) => compact
      ? MenuItemButton(
          leadingIcon: Icon(d.icon),
          trailingIcon: const MenuChevron(),
          closeOnActivate: false,
          onPressed: () => setState(() => _drilled = d.label),
          child: Text(d.label),
        )
      : SubmenuButton(leadingIcon: Icon(d.icon), menuChildren: d.children, child: Text(d.label));

  /// The drilled-in submenu's title row; goes back to the menu.
  Widget _back(_Drill d) => MenuItemButton(
    leadingIcon: const Icon(Symbols.chevron_left_sharp),
    closeOnActivate: false,
    onPressed: () => setState(() => _drilled = null),
    child: Text(d.label),
  );
}
