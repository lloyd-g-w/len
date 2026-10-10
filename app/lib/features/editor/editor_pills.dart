import 'package:flutter/material.dart';

import '../../ui/floating_panel.dart';
import 'document/undo_target.dart';

/// Back button and the notebook title (tap to rename).
class TitlePill extends StatelessWidget {
  const TitlePill({super.key, required this.title, required this.onBack, required this.onRename});

  final String title;
  final VoidCallback onBack;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    return FloatingPanel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Tooltip(
                message: 'Rename',
                child: TextButton(
                  onPressed: onRename,
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Undo / redo buttons, plus any [trailing] actions (e.g. a page menu).
class UndoRedoPill extends StatelessWidget {
  const UndoRedoPill({super.key, required this.target, this.trailing});

  final UndoTarget target;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return FloatingPanel(
      child: ListenableBuilder(
        listenable: target,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Undo (Ctrl+Z)',
              onPressed: target.canUndo ? target.undo : null,
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: 'Redo (Ctrl+Shift+Z)',
              onPressed: target.canRedo ? target.redo : null,
              icon: const Icon(Icons.redo_rounded),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
