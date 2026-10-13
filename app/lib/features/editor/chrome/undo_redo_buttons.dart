import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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
            icon: Symbols.undo_sharp,
          ),
          BarButton(
            tooltip: 'Redo (Ctrl+Shift+Z)',
            onPressed: target.canRedo ? target.redo : null,
            icon: Symbols.redo_sharp,
          ),
        ],
      ),
    );
  }
}
