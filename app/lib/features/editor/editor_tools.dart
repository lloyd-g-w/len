import 'package:flutter/material.dart';

import '../../domain/stroke.dart';
import '../../ink/tool_settings.dart';
import '../../ui/adaptive_popover.dart';
import 'pen/eraser_icon.dart';
import 'pen/eraser_options_panel.dart';
import 'pen/eraser_strip.dart';
import 'pen/ink_strip.dart';
import 'pen/pen_options_panel.dart';

/// One tool of the editor toolbar: its button, and the quick controls and
/// settings popover it brings along while active.
///
/// The toolbar is built from [editorTools], so further tools (lasso,
/// shapes, text, laser, …) slot in by adding a descriptor there.
class ToolDescriptor {
  const ToolDescriptor({
    required this.tool,
    required this.icon,
    required this.label,
    this.shortcut,
    this.inkColor,
    this.strip,
    this.stripWidth,
    this.options,
  });

  final EditorTool tool;

  /// The button's glyph (an [Icon] or a widget sized by [IconTheme]).
  final Widget icon;

  /// Name shown in the tooltip (with the [shortcut], if any).
  final String label;

  /// Single-key keyboard shortcut, e.g. `P`.
  final String? shortcut;

  /// The colour shown under the icon (inking tools).
  final int? Function()? inkColor;

  /// Quick controls shown in the toolbar while the tool is active.
  final WidgetBuilder? strip;

  /// The [strip]'s width in logical pixels, used to decide whether the
  /// toolbar fits on one row (it wraps to two otherwise).
  final double Function()? stripWidth;

  /// Content of the settings popover (tap the active tool, long-press it,
  /// or use the settings button).
  final WidgetBuilder? options;

  String get tooltip => shortcut == null ? label : '$label ($shortcut)';

  /// Opens the settings popover, anchored to [anchor].
  void openOptions(BuildContext anchor) {
    final builder = options;
    if (builder != null) showAdaptivePopover<void>(context: anchor, builder: builder);
  }
}

/// The toolbar's tools, in display order.
List<ToolDescriptor> editorTools(ToolSettings tools) => [
  ToolDescriptor(
    tool: EditorTool.pen,
    icon: const Icon(Icons.edit_rounded),
    label: 'Pen',
    shortcut: 'P',
    inkColor: () => tools.configOf(InkTool.ballpoint).color,
    strip: (_) => InkStrip(tools: tools, ink: InkTool.ballpoint),
    stripWidth: () => InkStrip.widthFor(tools.configOf(InkTool.ballpoint)),
    options: (_) => PenOptionsPanel(tools: tools, ink: InkTool.ballpoint),
  ),
  ToolDescriptor(
    tool: EditorTool.highlighter,
    icon: const Icon(Icons.border_color_rounded),
    label: 'Highlighter',
    shortcut: 'H',
    inkColor: () => tools.configOf(InkTool.highlighter).color,
    strip: (_) => InkStrip(tools: tools, ink: InkTool.highlighter),
    stripWidth: () => InkStrip.widthFor(tools.configOf(InkTool.highlighter)),
    options: (_) => PenOptionsPanel(tools: tools, ink: InkTool.highlighter),
  ),
  ToolDescriptor(
    tool: EditorTool.eraser,
    icon: const EraserIcon(),
    label: 'Eraser',
    shortcut: 'E',
    strip: (_) => EraserStrip(tools: tools),
    stripWidth: () => EraserStrip.width,
    options: (_) => EraserOptionsPanel(tools: tools),
  ),
];
