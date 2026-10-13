import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../document/undo_target.dart';
import '../toolbar/insert_menu.dart';
import '../toolbar/tool_switcher.dart';
import '../toolbar/toolbar_metrics.dart';
import 'bar_button.dart';

/// Focus mode's only tools (REDESIGN §2.7): the active tool, which opens
/// the tool switcher (long press: its options), and undo. Hosted in a
/// `ToolbarSlot`, so it is dragged by its grip and snaps like the palette.
class ToolPuck extends StatelessWidget {
  const ToolPuck({super.key, required this.tools, required this.undo, this.insert});

  final ToolSettings tools;
  final UndoTarget undo;
  final InsertActions? insert;

  @override
  Widget build(BuildContext context) {
    return FloatingPanel(
      radius: Radii.pill,
      padding: const EdgeInsets.all(Gaps.xs),
      child: Flex(
        direction: ToolbarAxis.of(context),
        mainAxisSize: MainAxisSize.min,
        children: [
          ToolSwitcherButton(tools: tools, insert: insert),
          ToolbarAxis.gap(context, Gaps.xxs),
          ListenableBuilder(
            listenable: undo,
            builder: (context, _) => BarButton(
              tooltip: 'Undo (Ctrl+Z)',
              onPressed: undo.canUndo ? undo.undo : null,
              icon: Symbols.undo_rounded,
            ),
          ),
        ],
      ),
    );
  }
}
