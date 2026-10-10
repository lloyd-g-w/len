import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';

/// A tool toggle. Inking tools show their current colour as a small bar
/// under the icon (recolouring the icon itself would be illegible for dark
/// inks in dark mode). Tapping the already active tool opens its options
/// (as do long-press and right-click), if it has any.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.tools,
    required this.tool,
    required this.icon,
    required this.label,
    this.options,
    this.inkColor,
  });

  final ToolSettings tools;
  final EditorTool tool;
  final IconData icon;
  final String label;
  final int? inkColor;
  final WidgetBuilder? options;

  @override
  Widget build(BuildContext context) {
    final selected = tools.tool == tool;
    final color = inkColor;
    final options = this.options;
    void openOptions() {
      if (options != null) showAdaptivePopover<void>(context: context, builder: options);
    }

    return GestureDetector(
      onLongPress: options == null ? null : openOptions,
      onSecondaryTap: options == null ? null : openOptions,
      child: IconButton(
        tooltip: label,
        isSelected: selected,
        onPressed: () => selected ? openOptions() : tools.tool = tool,
        style: IconButton.styleFrom(
          backgroundColor: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
        ),
        icon: SizedBox.square(
          dimension: 24,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Icon(icon, size: 19),
              if (color != null)
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: 14,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Color(color),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
