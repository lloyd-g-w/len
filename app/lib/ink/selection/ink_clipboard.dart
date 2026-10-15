import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';

/// The in-app clipboard for strokes and elements. It outlives editors, so
/// content can be pasted onto other pages and into other notebooks.
/// [mirror] hears every copy at once (still within the user's gesture),
/// e.g. to put a picture of it on the system clipboard for other apps.
class InkClipboard extends ChangeNotifier {
  InkClipboard({this.mirror});

  final void Function(List<Stroke> strokes, List<SurfaceElement> elements)? mirror;

  List<Stroke> _strokes = const [];
  List<SurfaceElement> _elements = const [];
  Rect _bounds = Rect.zero;

  List<Stroke> get strokes => _strokes;
  List<SurfaceElement> get elements => _elements;

  /// World bounds of the copied content where it was copied.
  Rect get bounds => _bounds;

  bool get isEmpty => _strokes.isEmpty && _elements.isEmpty;

  void put(List<Stroke> strokes, List<SurfaceElement> elements, Rect bounds) {
    _strokes = List.unmodifiable(strokes);
    _elements = List.unmodifiable(elements);
    _bounds = bounds;
    mirror?.call(_strokes, _elements);
    notifyListeners();
  }
}
