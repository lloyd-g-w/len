import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_picker/color_choices.dart';
import '../pen/ink_paper.dart';

/// The width of a popover holding [ColorChoices] on touch (a row of seven
/// 48-dp swatches): the text options and the colour slot editors.
const double toolOptionsTouchWidth = colorChoicesTouchWidth;

/// Opens the options of [tool] — the small submenu every tool shares —
/// anchored to [anchor] (the tool's button) on tablets and desktops, 320 dp
/// wide ([toolOptionsTouchWidth] for text on touch, whose colours are
/// here), a sheet on phones. Edits apply live; an outside tap (the tool
/// button too) or Esc closes it. Colours and sizes are not options: the
/// quick slots in the strip have their own small editors
/// (`slot_editors.dart`, `laser_slots.dart`).
///
/// A colour newly given to text becomes a recent colour when it closes
/// (not while the custom picker is dragged).
Future<void> showToolOptions(
  BuildContext anchor, {
  required ToolSettings tools,
  required EditorTool tool,
  required WidgetBuilder body,
}) async {
  final text = tool == EditorTool.text;
  final before = tools.textStyle.color;
  await showAdaptivePopover<void>(
    context: anchor,
    width: text && Targets.touchFirst ? toolOptionsTouchWidth : popoverWidth,
    // Ink previews show the paper being written on.
    builder: InkPaper.carry(anchor, (context) => ToolOptionsPopover(tool: tool, body: body)),
  );
  final after = tools.textStyle.color;
  if (text && after != before) tools.addRecentColor(after);
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
