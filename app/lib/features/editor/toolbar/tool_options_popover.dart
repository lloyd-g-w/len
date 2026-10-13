import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_picker/color_choices.dart';
import '../pen/ink_paper.dart';

/// The tool options popover's width on touch (fits [ColorChoices]).
const double toolOptionsTouchWidth = colorChoicesTouchWidth;

/// Opens the options of [tool] — the one popover every tool shares — at
/// [anchor] (the tool's button, or an eraser or laser slot): anchored on
/// tablets and desktops (320 dp wide, or [toolOptionsTouchWidth] on touch
/// so a row of seven 48-dp swatches fits), a sheet on phones. Edits apply
/// live; an outside tap or Esc closes it. The pen's and highlighter's
/// quick slots open their own small editors instead (`slot_editors.dart`).
///
/// Colours newly put into the ink's quick slots, or newly given to text or
/// the laser, become recent colours when it closes (not while the custom
/// picker is dragged).
Future<void> showToolOptions(
  BuildContext anchor, {
  required ToolSettings tools,
  required EditorTool tool,
  required WidgetBuilder body,
}) async {
  final ink = tool == EditorTool.highlighter ? InkTool.highlighter : InkTool.ballpoint;
  List<int> colours() => switch (tool) {
    EditorTool.text => [tools.textStyle.color],
    EditorTool.laser => [tools.laser.color],
    _ when tool.usesInk => tools.configOf(ink).colors,
    _ => const [],
  };
  final before = colours();
  await showAdaptivePopover<void>(
    context: anchor,
    width: Targets.touchFirst ? toolOptionsTouchWidth : popoverWidth,
    // Ink previews show the paper being written on.
    builder: InkPaper.carry(anchor, (context) => ToolOptionsPopover(tool: tool, body: body)),
  );
  for (final c in colours().reversed) {
    if (!before.contains(c)) tools.addRecentColor(c);
  }
}

/// The tool options popover's content: the active tool's section (its
/// title row first, then its controls), from the tool's descriptor.
class ToolOptionsPopover extends StatelessWidget {
  const ToolOptionsPopover({super.key, required this.tool, required this.body});

  final EditorTool tool;
  final WidgetBuilder body;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: ValueKey('tool-options-${tool.name}'),
    child: Builder(builder: body),
  );
}
