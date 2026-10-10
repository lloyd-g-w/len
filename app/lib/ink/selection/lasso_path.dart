import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The lasso being drawn (world coordinates), shown by the selection layer.
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

  void clear() {
    if (_points.isEmpty) return;
    _points.clear();
    notifyListeners();
  }
}
