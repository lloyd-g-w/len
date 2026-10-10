import 'dart:async';

import 'package:flutter/widgets.dart';

/// Keeps the canvas from reacting while a chrome menu is open.
///
/// Menus close on a tap outside them, but the canvas reads raw pointer
/// events, so without this the tap that closes a menu would also draw a
/// dot. Menus report [opened] / [closed]; the editor makes the canvas
/// ignore pointers while [blocking].
class CanvasGuard extends ChangeNotifier {
  int _open = 0;
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

  void opened() {
    _open++;
    if (_open == 1) notifyListeners();
  }

  /// Forgets all open menus (e.g. after the chrome was rebuilt).
  void reset() {
    if (_open == 0) return;
    _open = 0;
    scheduleMicrotask(_notify);
  }

  void closed() {
    if (_open == 0) return;
    _open--;
    // Menus may close while the tree is being torn down; notify later.
    if (_open == 0) scheduleMicrotask(_notify);
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
