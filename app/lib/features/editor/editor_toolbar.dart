import 'package:flutter/material.dart';

import '../../domain/stroke.dart';
import '../../ink/tool_settings.dart';
import '../../ui/app_theme.dart';
import '../../ui/color_dot.dart';
import '../../ui/floating_panel.dart';

/// The floating tool palette: tools, colours, width and palm rejection.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key, required this.tools, required this.onStylusOnlyChanged});

  final ToolSettings tools;
  final ValueChanged<bool> onStylusOnlyChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final palette = tools.activeInk == InkTool.highlighter ? Palette.highlighter : Palette.pen;
        return FloatingPanel(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToolButton(
                  tools: tools,
                  tool: EditorTool.pen,
                  icon: Icons.edit_rounded,
                  label: 'Pen (P)',
                ),
                _ToolButton(
                  tools: tools,
                  tool: EditorTool.highlighter,
                  icon: Icons.border_color_rounded,
                  label: 'Highlighter (H)',
                ),
                _ToolButton(
                  tools: tools,
                  tool: EditorTool.eraser,
                  icon: Icons.auto_fix_normal_rounded,
                  label: 'Eraser (E)',
                ),
                const _Divider(),
                for (final color in palette)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ColorDot(
                      color: color,
                      size: 30,
                      selected: tools.tool != EditorTool.eraser && tools.activeStyle.color == color,
                      onTap: () => tools.setColor(color),
                    ),
                  ),
                const _Divider(),
                _WidthButton(tools: tools),
                _PalmRejectionButton(
                  enabled: tools.stylusOnly ?? false,
                  onChanged: onStylusOnlyChanged,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A tool toggle. Inking tools show their current colour as a small bar
/// under the icon (recolouring the icon itself would be illegible for dark
/// inks in dark mode).
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tools,
    required this.tool,
    required this.icon,
    required this.label,
  });

  final ToolSettings tools;
  final EditorTool tool;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final selected = tools.tool == tool;
    final inkColor = tool.inkTool == null ? null : Color(tools.styleOf(tool.inkTool!).color);
    return IconButton(
      tooltip: label,
      isSelected: selected,
      onPressed: () => tools.tool = tool,
      style: IconButton.styleFrom(
        backgroundColor: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
      ),
      icon: SizedBox.square(
        dimension: 24,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Icon(icon, size: 19),
            if (inkColor != null)
              Positioned(
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 3,
                  decoration: BoxDecoration(
                    color: inkColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

/// Shows the current width as a dot; opens a slider.
class _WidthButton extends StatelessWidget {
  const _WidthButton({required this.tools});

  final ToolSettings tools;

  static const _ranges = {
    InkTool.pen: (min: 0.5, max: 16.0),
    InkTool.highlighter: (min: 6.0, max: 48.0),
  };

  @override
  Widget build(BuildContext context) {
    final style = tools.activeStyle;
    final range = _ranges[tools.activeInk]!;
    final t = ((style.width - range.min) / (range.max - range.min)).clamp(0.0, 1.0);
    return MenuAnchor(
      menuChildren: [
        SizedBox(
          width: 240,
          child: ListenableBuilder(
            listenable: tools,
            builder: (context, _) => Slider(
              value: tools.activeStyle.width.clamp(range.min, range.max),
              min: range.min,
              max: range.max,
              label: tools.activeStyle.width.toStringAsFixed(1),
              divisions: ((range.max - range.min) * 2).round(),
              onChanged: tools.setWidth,
            ),
          ),
        ),
      ],
      builder: (context, menu, _) => IconButton(
        tooltip: 'Width',
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        icon: SizedBox.square(
          dimension: 24,
          child: Center(
            child: Container(
              width: 4 + 16 * t,
              height: 4 + 16 * t,
              decoration: BoxDecoration(color: Color(style.color), shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

class _PalmRejectionButton extends StatelessWidget {
  const _PalmRejectionButton({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: enabled
          ? 'Stylus only: fingers pan & zoom (tap to let fingers draw)'
          : 'Fingers draw (tap for stylus only)',
      isSelected: enabled,
      onPressed: () => onChanged(!enabled),
      icon: const Icon(Icons.touch_app_outlined),
      selectedIcon: const Icon(Icons.do_not_touch_outlined),
    );
  }
}
