import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../settings/keyboard_shortcuts.dart' show modifierLabel;
import '../document/undo_target.dart';
import 'bar_button.dart';

/// Undo and redo, enabled as the [target]'s history allows.
class UndoRedoButtons extends StatelessWidget {
  const UndoRedoButtons({super.key, required this.target, this.redoOnlyWhenAvailable = false});

  final UndoTarget target;

  /// Phones: redo shows only while there is something to redo (it appears
  /// after an undo), giving the title its room the rest of the time.
  final bool redoOnlyWhenAvailable;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: target,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BarButton(
            tooltip: 'Undo (${modifierLabel()}+Z)',
            onPressed: target.canUndo ? target.undo : null,
            icon: Symbols.undo_sharp,
          ),
          if (target.canRedo || !redoOnlyWhenAvailable)
            BarButton(
              tooltip: 'Redo (${modifierLabel()}+Shift+Z)',
              onPressed: target.canRedo ? target.redo : null,
              icon: Symbols.redo_sharp,
            ),
        ],
      ),
    );
  }
}
