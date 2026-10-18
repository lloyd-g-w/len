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
    return UndoStateBuilder(
      target: target,
      builder: (context) => Row(
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

/// Builds with [target]'s state, again only when [UndoTarget.canUndo] or
/// [UndoTarget.canRedo] changes: the target notifies on every edit of the
/// surface (each stroke), which the buttons need not rebuild for.
class UndoStateBuilder extends StatefulWidget {
  const UndoStateBuilder({super.key, required this.target, required this.builder});

  final UndoTarget target;
  final WidgetBuilder builder;

  @override
  State<UndoStateBuilder> createState() => _UndoStateBuilderState();
}

class _UndoStateBuilderState extends State<UndoStateBuilder> {
  late (bool, bool) _state = _read();

  (bool, bool) _read() => (widget.target.canUndo, widget.target.canRedo);

  @override
  void initState() {
    super.initState();
    widget.target.addListener(_onChange);
  }

  @override
  void didUpdateWidget(UndoStateBuilder old) {
    super.didUpdateWidget(old);
    if (old.target == widget.target) return;
    old.target.removeListener(_onChange);
    widget.target.addListener(_onChange);
    _state = _read();
  }

  @override
  void dispose() {
    widget.target.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final state = _read();
    if (state != _state) setState(() => _state = state);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
