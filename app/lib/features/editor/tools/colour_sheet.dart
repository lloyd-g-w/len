import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_picker/color_picker.dart';
import '../pen/option_controls.dart';

/// Asks for a colour (opaque ARGB) with the full picker and the recent
/// colours, in a popover (a sheet on phones). Like every popover it has no
/// buttons: [live] sees each change as it is made (previews), and closing
/// it returns the last colour picked; null if none was.
Future<int?> pickColour(
  BuildContext context, {
  required String title,
  required int initial,
  required ToolSettings tools,
  ValueChanged<int>? live,
}) async {
  int? picked;
  await showAdaptivePopover<void>(
    context: context,
    builder: (_) => _ColourSheet(
      title: title,
      initial: initial,
      tools: tools,
      onChanged: (c) {
        picked = c;
        live?.call(c);
      },
    ),
  );
  if (picked case final colour?) tools.addRecentColor(colour);
  return picked;
}

class _ColourSheet extends StatefulWidget {
  const _ColourSheet({
    required this.title,
    required this.initial,
    required this.tools,
    required this.onChanged,
  });

  final String title;
  final int initial;
  final ToolSettings tools;
  final ValueChanged<int> onChanged;

  @override
  State<_ColourSheet> createState() => _ColourSheetState();
}

class _ColourSheetState extends State<_ColourSheet> {
  late int _colour = widget.initial | 0xFF000000;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.tools,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OptionHeader(widget.title),
          const SizedBox(height: Gaps.md),
          ColorPicker(
            color: _colour,
            showOpacity: false,
            recent: widget.tools.recentColors,
            onChanged: (c) {
              setState(() => _colour = c | 0xFF000000);
              widget.onChanged(_colour);
            },
          ),
        ],
      ),
    );
  }
}
