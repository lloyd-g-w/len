import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/preferences.dart';
import '../../../ui/app_switch.dart';
import '../../../ui/app_theme.dart';
import '../document/document_layout.dart';
import '../document/page_fit.dart';
import '../document/page_overview.dart';
import '../tabs/open_notebooks.dart';
import '../tabs/tab_switcher.dart';
import 'bar_button.dart';
import 'canvas_guard.dart';
import 'editor_menu_actions.dart';

/// The top bar's "⋯" menu (REDESIGN §2.3): search and export; the page
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
              const Divider(),
              if (a.isPaged)
                _submenu(_pageMenu())
              else
                _item(Symbols.wallpaper_sharp, 'Background…', a.onBackground),
              _submenu(_viewMenu()),
              ?widget.split,
              const Divider(),
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

  _Drill _pageMenu() {
    final a = actions;
    return (
      icon: Symbols.description_sharp,
      label: 'Page',
      children: [
        _command(PageCommand.duplicate, 'Duplicate page'),
        _item(
          a.bookmarked ? Symbols.bookmark_remove_sharp : Symbols.bookmark_add_sharp,
          a.bookmarked ? 'Remove bookmark' : 'Bookmark page',
          a.onToggleBookmark,
        ),
        _command(PageCommand.template, 'Change template…'),
        _command(PageCommand.saveAsTemplate, 'Save as template…'),
        const Divider(),
        _command(PageCommand.delete, 'Delete page', destructive: true),
      ],
    );
  }

  _Drill _viewMenu() {
    final a = actions;
    return (
      icon: Symbols.visibility_sharp,
      label: 'View',
      children: [
        if (a.isPaged) ...[
          _radio(
            a.flow == PageFlow.continuous,
            'Scroll pages',
            () => a.onFlow?.call(PageFlow.continuous),
          ),
          _radio(
            a.flow == PageFlow.single,
            'One page at a time',
            () => a.onFlow?.call(PageFlow.single),
          ),
          const Divider(),
          for (final (fit, keys) in const [
            (PageFit.page, SingleActivator(LogicalKeyboardKey.digit1, shift: true)),
            (PageFit.width, SingleActivator(LogicalKeyboardKey.digit2, shift: true)),
            (PageFit.auto, SingleActivator(LogicalKeyboardKey.digit0)),
          ])
            _radio(a.fit == fit, fit.label, () => a.onFit?.call(fit), shortcut: keys),
          const Divider(),
        ],
        _radio(
          a.placement == ToolbarPlacement.docked,
          'Toolbar docked',
          () => a.onPlacement(ToolbarPlacement.docked),
        ),
        _radio(
          a.placement == ToolbarPlacement.floating,
          'Toolbar floating',
          () => a.onPlacement(ToolbarPlacement.floating),
        ),
        const Divider(),
        _item(
          Symbols.fullscreen_sharp,
          'Focus mode',
          a.onFocusMode,
          shortcut: const SingleActivator(LogicalKeyboardKey.f11),
        ),
      ],
    );
  }

  Widget _command(PageCommand c, String label, {bool destructive = false}) {
    final run = actions.onPageCommand;
    return _item(c.icon, label, run == null ? null : () => run(c), destructive: destructive);
  }

  /// A menu row; [shortcut] hints only where a keyboard is likely.
  Widget _item(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    SingleActivator? shortcut,
    bool destructive = false,
  }) => Builder(
    builder: (context) {
      final error = Theme.of(context).colorScheme.error;
      return MenuItemButton(
        style: destructive
            ? MenuItemButton.styleFrom(foregroundColor: error, iconColor: error)
            : null,
        leadingIcon: Icon(icon),
        shortcut: Targets.touchFirst ? null : shortcut,
        onPressed: onPressed,
        child: Text(label),
      );
    },
  );

  /// A choice in a group: checked in the accent, like a checked menu row.
  Widget _radio(bool selected, String label, VoidCallback onPressed, {SingleActivator? shortcut}) =>
      Builder(
        builder: (context) => MenuItemButton(
          leadingIcon: Icon(
            selected ? Symbols.radio_button_checked_sharp : Symbols.radio_button_unchecked_sharp,
            fill: selected ? 1 : 0,
            color: selected ? Theme.of(context).colorScheme.primary : null,
          ),
          shortcut: Targets.touchFirst ? null : shortcut,
          onPressed: onPressed,
          child: Text(label),
        ),
      );

  /// A submenu: beside the menu where there is room, in its place on
  /// phones (where a cascade would cover its parent).
  Widget _submenu(_Drill d) => compact
      ? MenuItemButton(
          leadingIcon: Icon(d.icon),
          trailingIcon: const Icon(Symbols.chevron_right_sharp),
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

/// A switch shown in a menu row; the row itself toggles it.
class _MenuSwitch extends StatelessWidget {
  const _MenuSwitch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeFocus(
      child: AppSwitch(value: value, onChanged: (_) {}, padded: false),
    ),
  );
}
