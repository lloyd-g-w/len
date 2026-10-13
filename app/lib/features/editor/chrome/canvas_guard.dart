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
class ChromeMenuAnchor extends StatefulWidget {
  const ChromeMenuAnchor({super.key, required this.menuChildren, required this.builder});

  final List<Widget> menuChildren;
  final MenuAnchorChildBuilder builder;

  @override
  State<ChromeMenuAnchor> createState() => _ChromeMenuAnchorState();
}

class _ChromeMenuAnchorState extends State<ChromeMenuAnchor> {
  final MenuController _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final guard = CanvasGuardScope.maybeOf(context);
    return MenuEdgeMargin(
      child: MenuAnchor(
        controller: _controller,
        reservedPadding: menuReservedPadding(context),
        consumeOutsideTap: true,
        onOpen: () => guard?.opened(_controller),
        onClose: () => guard?.closed(_controller),
        menuChildren: widget.menuChildren,
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
