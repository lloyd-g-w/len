import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/color_picker/pick_color.dart';

/// [pickColor] with the editor's recent colours; the colour picked becomes
/// a recent colour.
Future<int?> pickColour(
  BuildContext context, {
  required String title,
  required int initial,
  required ToolSettings tools,
  ValueChanged<int>? live,
  Rect? anchor,
}) async {
  final picked = await pickColor(
    context,
    title: title,
    initial: initial,
    recent: tools.recentColors,
    live: live,
    anchor: anchor,
  );
  if (picked case final colour?) tools.addRecentColor(colour);
  return picked;
}
