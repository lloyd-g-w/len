import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/stroke.dart';
import '../../ink/tool_settings.dart';
import '../../ui/app_theme.dart';
import 'pen/eraser_icon.dart';
import 'pen/eraser_options_panel.dart';
import 'pen/eraser_strip.dart';
import 'pen/highlighter_options_panel.dart';
import 'pen/ink_options.dart';
import 'pen/ink_slots.dart';
import 'pen/ink_strip.dart';
import 'pen/pen_options_panel.dart';
import 'toolbar/tool_options_popover.dart';
import 'tools/laser_options_panel.dart';
import 'tools/laser_strip.dart';
import 'tools/lasso_options_panel.dart';
import 'tools/shape_options_panel.dart';
import 'tools/shape_strip.dart';
import 'tools/text_options_panel.dart';
import 'tools/tool_icons.dart';

/// Builds a tool's quick controls; [openOptions] opens the tool's options
/// anchored to the slot that asks.
typedef StripBuilder = Widget Function(BuildContext context, SlotEdit openOptions);

/// One tool of the editor toolbar: its button, the quick controls it shows
/// while active and its section of the tool options popover.
///
/// The toolbar is built from [editorTools] (in a fixed order), so further
/// tools slot in by adding an [EditorTool] value and a descriptor there.
class ToolDescriptor {
  const ToolDescriptor({
    required this.settings,
    required this.tool,
    required this.icon,
    required this.label,
    String? shortLabel,
    this.shortcut,
    this.inkColor,
    this.strip,
    this.stripWidth,
    required this.options,
  }) : shortLabel = shortLabel ?? label;

  /// The tool settings the descriptor reads and edits.
  final ToolSettings settings;
  final EditorTool tool;

  /// The button's glyph (an [Icon] or a widget sized by [IconTheme]).
  final Widget icon;

  /// Name shown in the tooltip (with the [shortcut], if any).
  final String label;

  /// A short name for the phone tool switcher's tiles (e.g. "Laser").
  final String shortLabel;

  /// Single-key keyboard shortcut, e.g. `P`.
  final String? shortcut;

  /// The colour shown under the icon (inking tools).
  final int? Function()? inkColor;

  /// Quick controls shown in the toolbar while the tool is active.
  final StripBuilder? strip;

  /// The [strip]'s width in logical pixels, which the toolbar reserves.
  final double Function()? stripWidth;

  /// The tool's section of the options popover (tap the active tool).
  final WidgetBuilder options;

  String get tooltip => shortcut == null ? label : '$label ($shortcut)';

  /// Opens the tool options popover, anchored to [anchor].
  Future<void> openOptions(BuildContext anchor) =>
      showToolOptions(anchor, tools: settings, tool: tool, body: options);
}

/// The toolbar's tools, in display order.
List<ToolDescriptor> editorTools(ToolSettings tools) {
  final pen = ToolDescriptor(
    settings: tools,
    tool: EditorTool.pen,
    icon: const Icon(Symbols.edit_rounded),
    label: 'Pen',
    shortcut: 'P',
    inkColor: () => tools.configOf(InkTool.ballpoint).color,
    strip: (_, open) => InkStrip(tools: tools, ink: InkTool.ballpoint, onEdit: open),
    stripWidth: () => InkStrip.widthFor(tools.configOf(InkTool.ballpoint)),
    options: (_) => InkOptions(
      tools: tools,
      ink: InkTool.ballpoint,
      title: 'Pen',
      feelLabel: 'Feel',
      feel: PenOptionsPanel(tools: tools),
    ),
  );
  return [
    pen,
    ToolDescriptor(
      settings: tools,
      tool: EditorTool.highlighter,
      icon: const Icon(Symbols.border_color_rounded),
      label: 'Highlighter',
      shortcut: 'H',
      inkColor: () => tools.configOf(InkTool.highlighter).color,
      strip: (_, open) => InkStrip(tools: tools, ink: InkTool.highlighter, onEdit: open),
      stripWidth: () => InkStrip.widthFor(tools.configOf(InkTool.highlighter)),
      options: (_) => InkOptions(
        tools: tools,
        ink: InkTool.highlighter,
        title: 'Highlighter',
        feelLabel: 'Opacity and feel',
        feel: HighlighterOptionsPanel(tools: tools),
      ),
    ),
    ToolDescriptor(
      settings: tools,
      tool: EditorTool.eraser,
      icon: const EraserIcon(),
      label: 'Eraser',
      shortcut: 'E',
      strip: (_, open) => EraserStrip(tools: tools, onEdit: open),
      stripWidth: () => EraserStrip.width,
      options: (_) => EraserOptionsPanel(tools: tools),
    ),
    ToolDescriptor(
      settings: tools,
      tool: EditorTool.lasso,
      icon: const Icon(lassoIcon),
      label: 'Lasso',
      shortcut: 'L',
      options: (_) => const LassoOptionsPanel(),
    ),
    ToolDescriptor(
      settings: tools,
      tool: EditorTool.shape,
      icon: ShapeGlyph(tools.shape, size: Glyphs.bar),
      label: 'Shapes',
      shortcut: 'S',
      // Shapes are drawn with the pen's quick colour and width.
      inkColor: () => tools.configOf(InkTool.ballpoint).color,
      strip: (_, open) => ShapeStrip(tools: tools, onEdit: open, onEditInk: pen.openOptions),
      stripWidth: () => ShapeStrip.widthFor(tools),
      options: (_) => ListenableBuilder(
        listenable: tools,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShapeOptionsPanel(tools: tools),
            HoldToSnapSwitch(tools: tools),
          ],
        ),
      ),
    ),
    ToolDescriptor(
      settings: tools,
      tool: EditorTool.text,
      icon: const Icon(textIcon),
      label: 'Text',
      shortcut: 'T',
      inkColor: () => tools.textStyle.color,
      options: (_) => TextOptionsPanel(tools: tools),
    ),
    ToolDescriptor(
      settings: tools,
      tool: EditorTool.laser,
      icon: const Icon(laserIcon),
      label: 'Laser pointer',
      shortLabel: 'Laser',
      shortcut: 'K',
      inkColor: () => tools.laser.color,
      strip: (_, open) => LaserStrip(tools: tools, onEdit: open),
      stripWidth: () => LaserStrip.width,
      options: (_) => LaserOptionsPanel(tools: tools),
    ),
  ];
}
