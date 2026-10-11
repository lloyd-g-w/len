import 'package:flutter/widgets.dart';

/// Remembers which part of the screen opened each route (dialog, sheet,
/// popup menu, page), so that part can close what it opened — and only
/// that. E.g. a split view pane whose notebook was deleted on another
/// device closes its own dialogs, not those opened from the other pane.
///
/// Registered with the app's navigator; the parts set [current] when used
/// (pointer down, keyboard focus).
class RouteOwners extends NavigatorObserver {
  /// The part of the screen in use: routes pushed now belong to it.
  Object? current;

  final Map<Route<dynamic>, Object> _owners = {};

  /// Whether routes are being tracked (registered with a navigator).
  bool get tracking => navigator != null;

  /// The routes [owner] opened that are still open, oldest first.
  List<Route<dynamic>> routesOf(Object owner) => [
    for (final MapEntry(:key, :value) in _owners.entries)
      if (identical(value, owner)) key,
  ];

  /// Closes the routes [owner] opened, newest first, leaving everything
  /// else (also routes above them) where it is.
  void closeRoutesOf(Object owner) {
    for (final route in routesOf(owner).reversed) {
      if (route.isActive) route.navigator?.removeRoute(route);
    }
  }

  /// [owner] is gone: nothing more is pushed in its name.
  void forget(Object owner) {
    if (identical(current, owner)) current = null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final owner = current;
    if (owner != null) _owners[route] = owner;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _owners.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _owners.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final owner = _owners.remove(oldRoute);
    if (owner != null && newRoute != null) _owners[newRoute] = owner;
  }
}
