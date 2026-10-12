import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_picker/color_picker.dart';
import '../pen/option_controls.dart';

/// Asks for a colour (opaque ARGB) with the full picker and the recent
/// colours; null if dismissed. [live] previews every change as it is
/// made (for edits that are only committed later, like text formatting).
Future<int?> pickColour(
  BuildContext context, {
  required String title,
  required int initial,
  required ToolSettings tools,
  ValueChanged<int>? live,
}) => showAdaptivePopover<int>(
  context: context,
  builder: (_) => _ColourSheet(title: title, initial: initial, tools: tools, live: live),
);

class _ColourSheet extends StatefulWidget {
  const _ColourSheet({required this.title, required this.initial, required this.tools, this.live});

  final String title;
  final int initial;
  final ToolSettings tools;
  final ValueChanged<int>? live;

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
          OptionHeader(
            widget.title,
            trailing: FilledButton(
              onPressed: () => Navigator.of(context).pop(_colour),
              child: const Text('Apply'),
            ),
          ),
          const SizedBox(height: Gaps.sm),
          ColorPicker(
            color: _colour,
            showOpacity: false,
            recent: widget.tools.recentColors,
            onChanged: (c) {
              setState(() => _colour = c | 0xFF000000);
              widget.live?.call(_colour);
            },
          ),
        ],
      ),
    );
  }
}
