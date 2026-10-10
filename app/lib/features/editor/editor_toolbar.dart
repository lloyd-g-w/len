import 'package:flutter/material.dart';

import '../../domain/stroke.dart';
import '../../ink/tool_settings.dart';
import '../../ui/adaptive_popover.dart';
import '../../ui/floating_panel.dart';
import 'pen/eraser_options_panel.dart';
import 'pen/eraser_strip.dart';
import 'pen/pen_icons.dart';
import 'pen/pen_options_panel.dart';
import 'pen/preset_strip.dart';

/// The floating tool palette: pen / highlighter / eraser (tap the active
/// one again for its options), the active tool's quick presets, and palm
/// rejection.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key, required this.tools, required this.onStylusOnlyChanged});

  final ToolSettings tools;
  final ValueChanged<bool> onStylusOnlyChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final erasing = tools.tool == EditorTool.eraser;
        return FloatingPanel(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToolButton(
                  tools: tools,
                  tool: EditorTool.pen,
                  icon: penIcon(tools.penType),
                  label: 'Pen (P)',
                  inkColor: tools.configOf(tools.penType).current.color,
                  options: (_) => PenOptionsPanel(tools: tools, ink: null),
                ),
                _ToolButton(
                  tools: tools,
                  tool: EditorTool.highlighter,
                  icon: penIcon(InkTool.highlighter),
                  label: 'Highlighter (H)',
                  inkColor: tools.configOf(InkTool.highlighter).current.color,
                  options: (_) => PenOptionsPanel(tools: tools, ink: InkTool.highlighter),
                ),
                _ToolButton(
                  tools: tools,
                  tool: EditorTool.eraser,
                  icon: Icons.auto_fix_normal_rounded,
                  label: 'Eraser (E)',
                  options: (_) => EraserOptionsPanel(tools: tools),
                ),
                const _Divider(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: erasing
                      ? EraserStrip(key: const ValueKey('eraser'), tools: tools)
                      : PresetStrip(key: ValueKey(tools.activeInk), tools: tools),
                ),
                if (!erasing)
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: 'Colour & width',
                      onPressed: () => openPresetEditor(
                        context,
                        tools,
                        tools.activeInk,
                        tools.activeConfig.selected,
                      ),
                      icon: const _RainbowIcon(),
                    ),
                  ),
                const _Divider(),
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
/// inks in dark mode). Tapping the already active tool opens its options.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tools,
    required this.tool,
    required this.icon,
    required this.label,
    required this.options,
    this.inkColor,
  });

  final ToolSettings tools;
  final EditorTool tool;
  final IconData icon;
  final String label;
  final int? inkColor;
  final WidgetBuilder options;

  @override
  Widget build(BuildContext context) {
    final selected = tools.tool == tool;
    final color = inkColor;
    void openOptions() => showAdaptivePopover<void>(context: context, builder: options);
    return GestureDetector(
      onLongPress: openOptions,
      onSecondaryTap: openOptions,
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

/// A small colour-wheel glyph for the colour picker button.
class _RainbowIcon extends StatelessWidget {
  const _RainbowIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0xFFFF5252),
            Color(0xFFFFD740),
            Color(0xFF69F0AE),
            Color(0xFF40C4FF),
            Color(0xFF7C4DFF),
            Color(0xFFFF4081),
            Color(0xFFFF5252),
          ],
        ),
      ),
      padding: const EdgeInsets.all(5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainer,
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
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
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
