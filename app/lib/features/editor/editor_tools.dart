import 'package:flutter/material.dart';

import '../../domain/stroke.dart';
import '../../ink/tool_settings.dart';
import '../../ui/adaptive_popover.dart';
import 'pen/eraser_icon.dart';
import 'pen/eraser_options_panel.dart';
import 'pen/eraser_strip.dart';
import 'pen/highlighter_options_panel.dart';
import 'pen/ink_strip.dart';
import 'pen/pen_options_panel.dart';
import 'tools/shape_options_panel.dart';
import 'tools/text_options_panel.dart';
import 'tools/tool_icons.dart';

/// One tool of the editor toolbar: its button, and the quick controls and
/// settings popover it brings along while active.
///
/// The toolbar is built from [editorTools], so further tools slot in by
/// adding an [EditorTool] value and a descriptor there.
class ToolDescriptor {
  const ToolDescriptor({
    required this.tool,
    required this.icon,
    required this.label,
    String? shortLabel,
    this.shortcut,
    this.inkColor,
    this.strip,
    this.stripWidth,
    this.compactStrip,
    this.compactStripWidth,
    this.options,
  }) : shortLabel = shortLabel ?? label;

  final EditorTool tool;

  /// The button's glyph (an [Icon] or a widget sized by [IconTheme]).
  final Widget icon;

  /// Name shown in the tooltip (with the [shortcut], if any).
  final String label;

  /// A short name for labels under the icon (e.g. "Laser").
  final String shortLabel;

  /// Single-key keyboard shortcut, e.g. `P`.
  final String? shortcut;

  /// The colour shown under the icon (inking tools).
  final int? Function()? inkColor;

  /// Quick controls shown in the toolbar while the tool is active.
  final WidgetBuilder? strip;

  /// The [strip]'s width in logical pixels, used to decide whether the
  /// toolbar fits on one row (it wraps to two otherwise).
  final double Function()? stripWidth;

  /// A narrower [strip] for the compact (phone) toolbar, if it has one
  /// (e.g. without the "+" buttons), and its width.
  final WidgetBuilder? compactStrip;
  final double Function()? compactStripWidth;

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

/// The toolbar's tools, in display order (Select PDF text only in notebooks
/// with imported PDF pages).
List<ToolDescriptor> editorTools(ToolSettings tools) => [
  ToolDescriptor(
    tool: EditorTool.pen,
    icon: const Icon(Icons.edit_rounded),
    label: 'Pen',
    shortcut: 'P',
    inkColor: () => tools.configOf(InkTool.ballpoint).color,
    strip: (_) => InkStrip(tools: tools, ink: InkTool.ballpoint),
    stripWidth: () => InkStrip.widthFor(tools.configOf(InkTool.ballpoint)),
    compactStrip: (_) => InkStrip(tools: tools, ink: InkTool.ballpoint, showAdd: false),
    compactStripWidth: () => InkStrip.widthFor(tools.configOf(InkTool.ballpoint), showAdd: false),
    options: (_) => PenOptionsPanel(tools: tools),
  ),
  ToolDescriptor(
    tool: EditorTool.highlighter,
    icon: const Icon(Icons.border_color_rounded),
    label: 'Highlighter',
    shortcut: 'H',
    inkColor: () => tools.configOf(InkTool.highlighter).color,
    strip: (_) => InkStrip(tools: tools, ink: InkTool.highlighter),
    stripWidth: () => InkStrip.widthFor(tools.configOf(InkTool.highlighter)),
    compactStrip: (_) => InkStrip(tools: tools, ink: InkTool.highlighter, showAdd: false),
    compactStripWidth: () => InkStrip.widthFor(tools.configOf(InkTool.highlighter), showAdd: false),
    options: (_) => HighlighterOptionsPanel(tools: tools),
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
  const ToolDescriptor(
    tool: EditorTool.lasso,
    icon: Icon(lassoIcon),
    label: 'Lasso',
    shortcut: 'L',
  ),
  ToolDescriptor(
    tool: EditorTool.shape,
    icon: ShapeGlyph(tools.shape, size: 20),
    label: 'Shapes',
    shortcut: 'S',
    // Shapes are drawn with the pen's quick colour and width.
    inkColor: () => tools.configOf(InkTool.ballpoint).color,
    strip: (_) => InkStrip(tools: tools, ink: InkTool.ballpoint),
    stripWidth: () => InkStrip.widthFor(tools.configOf(InkTool.ballpoint)),
    compactStrip: (_) => InkStrip(tools: tools, ink: InkTool.ballpoint, showAdd: false),
    compactStripWidth: () => InkStrip.widthFor(tools.configOf(InkTool.ballpoint), showAdd: false),
    options: (_) => ShapeOptionsPanel(tools: tools),
  ),
  ToolDescriptor(
    tool: EditorTool.text,
    icon: const Icon(textIcon),
    label: 'Text',
    shortcut: 'T',
    inkColor: () => tools.textStyle.color,
    options: (_) => TextOptionsPanel(tools: tools),
  ),
  ToolDescriptor(
    tool: EditorTool.laser,
    icon: const Icon(laserIcon),
    label: 'Laser pointer',
    shortLabel: 'Laser',
    shortcut: 'K',
    inkColor: () => 0xFFFF2D2D,
  ),
  if (tools.selectTextAvailable)
    const ToolDescriptor(
      tool: EditorTool.selectText,
      icon: Icon(selectTextIcon),
      label: 'Select PDF text',
      shortLabel: 'Select',
      shortcut: 'X',
    ),
];
