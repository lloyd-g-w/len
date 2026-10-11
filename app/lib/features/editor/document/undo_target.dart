import 'package:flutter/foundation.dart';

import '../../../ink/surface_model.dart';

/// What the editor's undo/redo buttons and shortcuts act on: a single
/// surface (infinite canvas) or a whole paged notebook.
abstract interface class UndoTarget implements Listenable {
  bool get canUndo;
  bool get canRedo;
  void undo();
  void redo();
}

/// Undo for a single surface.
class SurfaceUndo implements UndoTarget {
  SurfaceUndo(this.model);

  final SurfaceModel model;

  /// Called after every undo and redo.
  VoidCallback? onStep;

  @override
  bool get canUndo => model.history.canUndo;

  @override
  bool get canRedo => model.history.canRedo;

  @override
  void undo() {
    model.undo();
    onStep?.call();
  }

  @override
  void redo() {
    model.redo();
    onStep?.call();
  }

  @override
  void addListener(VoidCallback listener) => model.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => model.removeListener(listener);
}
