import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/menus.dart';

/// Keeps the canvas from reacting while a chrome menu is open.
///
/// Menus close on a tap outside them, but the canvas reads raw pointer
/// events, so without this the tap that closes a menu would also draw a
/// dot. Menus report [opened] / [closed]; the editor makes the canvas
/// ignore pointers while [blocking].
///
/// Menus opened with a tap leave keyboard focus on the canvas, where
/// Escape would never reach them: [closeMenus] closes those that
/// registered their controller ([ChromeMenuAnchor]).
class CanvasGuard extends ChangeNotifier {
  int _open = 0;
  final Set<MenuController> _menus = {};
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool get blocking => _open > 0;

  void opened([MenuController? menu]) {
    if (menu != null) _menus.add(menu);
    _open++;
    if (_open == 1) notifyListeners();
  }

  bool? _compact;

  /// The chrome laid out [compact] (the phone's bar) or not: the top bar
  /// swaps its menus when switching between compact and wide layouts, and
  /// one disposed while open never reports closing, so the guard [reset]s
  /// then.
  void laidOut({required bool compact}) {
    if (_compact != null && _compact != compact) reset();
    _compact = compact;
  }

  /// Forgets all open menus (e.g. after the chrome was rebuilt).
  void reset() {
    _menus.clear();
    if (_open == 0) return;
    _open = 0;
    scheduleMicrotask(_notify);
  }

  void closed([MenuController? menu]) {
    if (menu != null) _menus.remove(menu);
    if (_open == 0) return;
    _open--;
    // Menus may close while the tree is being torn down; notify later.
    if (_open == 0) scheduleMicrotask(_notify);
  }

  /// Closes the open chrome menus; false if there were none.
  bool closeMenus() {
    if (_menus.isEmpty) return false;
    for (final menu in [..._menus]) {
      menu.close();
    }
    return true;
  }
}

/// A [MenuAnchor] for the editor chrome: the canvas ignores the tap that
/// closes it, and Escape closes it (see [CanvasGuard.closeMenus]).
///
/// Opened from the keyboard (Enter or Space on its button), focus moves to
/// the menu's first item, and closing the menu gives it back to the button.
class ChromeMenuAnchor extends StatefulWidget {
  const ChromeMenuAnchor({super.key, required this.menuChildren, required this.builder});

  final List<Widget> menuChildren;
  final MenuAnchorChildBuilder builder;

  @override
  State<ChromeMenuAnchor> createState() => _ChromeMenuAnchorState();
}

class _ChromeMenuAnchorState extends State<ChromeMenuAnchor> {
  final MenuController _controller = MenuController();

  /// Marks the first menu item, to find the menu's focus scope.
  final GlobalKey _first = GlobalKey();

  /// The button that had keyboard focus when the menu opened.
  FocusNode? _opener;

  void _opened(CanvasGuard? guard) {
    guard?.opened(_controller);
    final focus = FocusManager.instance;
    final node = focus.primaryFocus;
    final keyboard = focus.highlightMode == FocusHighlightMode.traditional;
    _opener = keyboard && node?.context != null && _owns(node!.context!) ? node : null;
    if (_opener == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _first.currentContext;
      if (context == null || !_controller.isOpen) return;
      final scope = FocusScope.of(context);
      final policy = FocusTraversalGroup.maybeOf(context) ?? ReadingOrderTraversalPolicy();
      policy.findFirstFocus(scope, ignoreCurrentFocus: true)?.requestFocus();
    });
  }

  void _closed(CanvasGuard? guard) {
    guard?.closed(_controller);
    final opener = _opener;
    _opener = null;
    // Focus goes back to the button, unless the item chosen took it on
    // (a dialog opened by the item claims it after this).
    if (opener != null && opener.context?.mounted == true) opener.requestFocus();
  }

  /// Whether [context] is this anchor's button (or inside it).
  bool _owns(BuildContext context) {
    var owns = false;
    context.visitAncestorElements((e) {
      owns = e == this.context;
      return !owns;
    });
    return owns;
  }

  @override
  Widget build(BuildContext context) {
    final guard = CanvasGuardScope.maybeOf(context);
    final children = widget.menuChildren;
    return MenuEdgeMargin(
      child: MenuAnchor(
        controller: _controller,
        reservedPadding: menuReservedPadding(context),
        consumeOutsideTap: true,
        onOpen: () => _opened(guard),
        onClose: () => _closed(guard),
        menuChildren: [
          if (children.isNotEmpty) KeyedSubtree(key: _first, child: children.first),
          ...children.skip(1),
        ],
        builder: widget.builder,
      ),
    );
  }
}

/// Provides a [CanvasGuard] to the chrome's menus.
class CanvasGuardScope extends InheritedWidget {
  const CanvasGuardScope({super.key, required this.guard, required super.child});

  final CanvasGuard guard;

  static CanvasGuard? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CanvasGuardScope>()?.guard;

  @override
  bool updateShouldNotify(CanvasGuardScope old) => old.guard != guard;
}
