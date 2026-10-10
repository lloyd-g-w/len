import 'package:flutter/foundation.dart';

import '../domain/stroke.dart';

/// The tools selectable in the editor toolbar.
enum EditorTool {
  pen(InkTool.pen),
  highlighter(InkTool.highlighter),
  eraser(null);

  const EditorTool(this.inkTool);

  /// The ink this tool lays down, or null for non-inking tools.
  final InkTool? inkTool;
}

/// Per-tool style: colour (ARGB) and nominal width in world units.
class ToolStyle {
  const ToolStyle({required this.color, required this.width});

  final int color;
  final double width;

  ToolStyle copyWith({int? color, double? width}) =>
      ToolStyle(color: color ?? this.color, width: width ?? this.width);
}

/// Current tool selection and input preferences for the editor.
class ToolSettings extends ChangeNotifier {
  ToolSettings({this._stylusOnly});

  EditorTool _tool = EditorTool.pen;
  final Map<InkTool, ToolStyle> _styles = {
    InkTool.pen: const ToolStyle(color: 0xFF1F2937, width: 3),
    InkTool.highlighter: const ToolStyle(color: 0xFFFACC15, width: 18),
  };
  bool? _stylusOnly;

  /// Eraser radius in screen pixels (independent of zoom).
  double eraserRadius = 12;

  EditorTool get tool => _tool;
  set tool(EditorTool value) {
    if (value == _tool) return;
    _tool = value;
    notifyListeners();
  }

  /// Colour and width used for [tool] ink.
  ToolStyle styleOf(InkTool tool) => _styles[tool]!;

  /// The ink tool the colour/width controls currently edit.
  InkTool get activeInk => _tool.inkTool ?? InkTool.pen;

  ToolStyle get activeStyle => styleOf(activeInk);

  void setColor(int color) {
    _styles[activeInk] = activeStyle.copyWith(color: color);
    if (_tool == EditorTool.eraser) _tool = EditorTool.pen;
    notifyListeners();
  }

  void setWidth(double width) {
    _styles[activeInk] = activeStyle.copyWith(width: width);
    notifyListeners();
  }

  /// Palm rejection: only the stylus draws; fingers navigate. `null` means
  /// undecided — it turns on automatically when a stylus is first used.
  bool? get stylusOnly => _stylusOnly;
  set stylusOnly(bool? value) {
    if (value == _stylusOnly) return;
    _stylusOnly = value;
    notifyListeners();
  }
}
