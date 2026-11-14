import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tools/selection_menu.dart';
import 'area_capture.dart';

/// The selection menu's "Copy as image": the selection's bounding box,
/// background and all, as a picture on the clipboard ([AreaCapture]).
SelectionExtraAction copyAsImageAction(BuildContext context, AreaCapture capture) =>
    SelectionExtraAction(
      copyAsImageLabel,
      Symbols.screenshot_region_rounded,
      (_) => capture.copySelection(context),
    );

/// The selection menu entry's name.
const String copyAsImageLabel = 'Copy as image';
