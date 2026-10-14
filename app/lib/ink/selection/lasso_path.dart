import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The lasso being drawn (world coordinates), shown by the selection layer:
/// a freehand loop, or a rectangle's four corners.
class LassoPath extends ChangeNotifier {
  final List<Offset> _points = [];

  List<Offset> get points => _points;
  bool get isEmpty => _points.isEmpty;

  void begin(Offset world) {
    _points
      ..clear()
      ..add(world);
    notifyListeners();
  }

  void add(Offset world) {
    _points.add(world);
    notifyListeners();
  }

  /// Makes the path the rectangle with corners [from] and [to].
  void rectangle(Offset from, Offset to) {
    _points
      ..clear()
      ..addAll([from, Offset(to.dx, from.dy), to, Offset(from.dx, to.dy)]);
    notifyListeners();
  }

  void clear() {
    if (_points.isEmpty) return;
    _points.clear();
    notifyListeners();
  }
}
