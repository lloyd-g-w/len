import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';

/// Opens the options of [tool] — the one popover every tool shares — at
/// [anchor] (the tool's button or one of its quick slots): anchored and
/// 320 dp wide on tablets and desktops, a sheet on phones. Edits apply
/// live; an outside tap or Esc closes it.
///
/// Colours newly put into the ink's quick slots become recent colours when
/// it closes (not while the custom picker is dragged).
Future<void> showToolOptions(
  BuildContext anchor, {
  required ToolSettings tools,
  required EditorTool tool,
  required WidgetBuilder body,
}) async {
  final ink = tool == EditorTool.highlighter ? InkTool.highlighter : InkTool.ballpoint;
  final before = tools.configOf(ink).colors;
  await showAdaptivePopover<void>(
    context: anchor,
    builder: (context) => ToolOptionsPopover(tool: tool, body: body),
  );
  if (!tool.usesInk) return;
  for (final c in tools.configOf(ink).colors.reversed) {
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
