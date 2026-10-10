import 'package:flutter/material.dart';

import '../../domain/stroke.dart';
import '../../ink/tool_settings.dart';
import '../../ui/floating_panel.dart';
import 'pen/eraser_options_panel.dart';
import 'pen/eraser_strip.dart';
import 'pen/pen_icons.dart';
import 'pen/pen_options_panel.dart';
import 'pen/preset_strip.dart';
import 'tools/shape_options_panel.dart';
import 'tools/text_options_panel.dart';
import 'tools/tool_button.dart';
import 'tools/tool_icons.dart';

/// The floating tool palette: pen / highlighter / eraser / lasso / shapes /
/// text / laser (tap the active one again for its options), the active
/// tool's quick presets, and palm rejection.
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
        final inking = tools.tool.usesPresets;
        return FloatingPanel(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ToolButton(
                  tools: tools,
                  tool: EditorTool.pen,
                  icon: penIcon(tools.penType),
                  label: 'Pen (P)',
                  inkColor: tools.configOf(tools.penType).current.color,
                  options: (_) => PenOptionsPanel(tools: tools, ink: null),
                ),
                ToolButton(
                  tools: tools,
                  tool: EditorTool.highlighter,
                  icon: penIcon(InkTool.highlighter),
                  label: 'Highlighter (H)',
                  inkColor: tools.configOf(InkTool.highlighter).current.color,
                  options: (_) => PenOptionsPanel(tools: tools, ink: InkTool.highlighter),
                ),
                ToolButton(
                  tools: tools,
                  tool: EditorTool.eraser,
                  icon: Icons.auto_fix_normal_rounded,
                  label: 'Eraser (E)',
                  options: (_) => EraserOptionsPanel(tools: tools),
                ),
                ToolButton(
                  tools: tools,
                  tool: EditorTool.lasso,
                  icon: lassoIcon,
                  label: 'Lasso (L)',
                ),
                ToolButton(
                  tools: tools,
                  tool: EditorTool.shape,
                  glyph: ShapeGlyph(tools.shape),
                  label: 'Shapes (S)',
                  inkColor: tools.configOf(tools.penType).current.color,
                  options: (_) => ShapeOptionsPanel(tools: tools),
                ),
                ToolButton(
                  tools: tools,
                  tool: EditorTool.text,
                  icon: textIcon,
                  label: 'Text (T)',
                  inkColor: tools.textStyle.color,
                  options: (_) => TextOptionsPanel(tools: tools),
                ),
                ToolButton(
                  tools: tools,
                  tool: EditorTool.laser,
                  icon: laserIcon,
                  label: 'Laser pointer (K)',
                  inkColor: 0xFFFF2D2D,
                ),
                if (erasing || inking) const _Divider(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: erasing
                      ? EraserStrip(key: const ValueKey('eraser'), tools: tools)
                      : inking
                      ? PresetStrip(key: ValueKey(tools.activeInk), tools: tools)
                      : const SizedBox.shrink(),
                ),
                if (inking)
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
