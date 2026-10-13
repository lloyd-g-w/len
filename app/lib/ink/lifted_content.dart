import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Draws content lifted out of a surface, in the surface's coordinates.
typedef LiftedPaint = void Function(Canvas canvas);

/// What owners hiding items on a surface draw in their place, in that
/// surface's coordinates: a selection its (moving) items, a text editor its
/// box as typed. The owner's own view draws them itself; other views of the
/// surface (split view) paint them from here ([paint]) instead of showing a
/// hole. Notifies when lifted content appears, changes or goes. Owned by
/// `SurfaceModel`, which exposes it through its own methods.
class LiftedContent extends ChangeNotifier {
  final Map<Object, LiftedPaint> _paints = {};

  /// Whose lifted content changed last (see [ForeignLiftedChanges]).
  Object? get lastOwner => _lastOwner;
  Object? _lastOwner;

  /// Sets (or with null, removes) what [owner] draws in place of the items
  /// it hides.
  void set(Object owner, LiftedPaint? paint) {
    if (paint == null) {
      if (_paints.remove(owner) == null) return;
    } else {
      final had = _paints.containsKey(owner);
      _paints[owner] = paint;
      if (had) return; // Same owner, same paint: changes come by [changed].
    }
    _notify(owner);
  }

  /// [owner]'s lifted content changed (it moved, was retyped).
  void changed(Object owner) {
    if (_paints.containsKey(owner)) _notify(owner);
  }

  void _notify(Object owner) {
    _lastOwner = owner;
    notifyListeners();
  }

  /// Whether owners other than [except] have lifted content.
  bool hasExcept(Set<Object?> except) => _paints.keys.any((o) => !except.contains(o));

  /// Paints the lifted content of owners other than [except].
  void paint(Canvas canvas, {Set<Object?> except = const {}}) {
    for (final MapEntry(key: owner, value: paint) in _paints.entries) {
      if (!except.contains(owner)) paint(canvas);
    }
  }
}

/// [source] (lifted content changing), heard only when the change came
/// from an owner outside [self] (whose [owner] is asked at the time): a
/// view's own selection dragging never repaints that view's ink.
class ForeignLiftedChanges implements Listenable {
  ForeignLiftedChanges(this.source, this.owner, this.self);

  final Listenable source;
  final Object? Function() owner;
  final Set<Object?> self;
  final Map<VoidCallback, VoidCallback> _wrapped = {};

  @override
  void addListener(VoidCallback listener) {
    void wrapped() {
      if (!self.contains(owner())) listener();
    }

    _wrapped[listener] = wrapped;
    source.addListener(wrapped);
  }

  @override
  void removeListener(VoidCallback listener) {
    final wrapped = _wrapped.remove(listener);
    if (wrapped != null) source.removeListener(wrapped);
  }
}
