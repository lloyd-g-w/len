import 'package:flutter/foundation.dart';

/// The edited box's own history (its editor keeps it): what the editor's
/// undo and redo act on while a box is edited.
abstract interface class BoxHistory implements Listenable {
  bool get canUndo;
  bool get canRedo;

  /// Steps back; false when there is nothing to undo.
  bool undo();

  /// Steps forward; false when there is nothing to redo.
  bool redo();
}
