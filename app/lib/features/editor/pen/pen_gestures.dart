import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import 'option_controls.dart';

/// The pen's gestures, at the end of its Feel section, under a rule and
/// after "Reset feel" (they are global switches, not part of the pen's
/// feel): hold to snap, which also applies to the highlighter. This is
/// their only home; the Shapes popover points here.
class PenGestures extends StatelessWidget {
  const PenGestures({super.key, required this.tools});

  final ToolSettings tools;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OptionRule(),
          OptionSwitch(
            label: 'Hold to snap',
            subtitle: 'Hold the pen still at the end of a stroke for a clean line or shape',
            value: tools.holdToStraighten,
            onChanged: (v) => tools.holdToStraighten = v,
          ),
        ],
      ),
    );
  }
}
