import 'package:flutter/material.dart';

import '../document/undo_target.dart';
import 'bar_button.dart';

/// Undo and redo, enabled as the [target]'s history allows.
class UndoRedoButtons extends StatelessWidget {
  const UndoRedoButtons({super.key, required this.target});

  final UndoTarget target;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: target,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BarButton(
            tooltip: 'Undo (Ctrl+Z)',
            onPressed: target.canUndo ? target.undo : null,
            icon: Icons.undo_rounded,
          ),
          BarButton(
            tooltip: 'Redo (Ctrl+Shift+Z)',
            onPressed: target.canRedo ? target.redo : null,
            icon: Icons.redo_rounded,
          ),
        ],
      ),
    );
  }
}
