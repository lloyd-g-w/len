import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Whether [showDialogOrSheet] shows a centred dialog in [context]: wide
/// enough for the tablet / desktop layout and at least [minHeight] tall.
bool prefersDialog(BuildContext context, {double minHeight = 520}) {
  final size = MediaQuery.sizeOf(context);
  return size.width >= Breakpoints.medium && size.height >= minHeight;
}

/// Shows [builder]'s content as a centred dialog on tablets and desktops
/// (at most [maxWidth] × [maxHeight]) and as a bottom sheet with a drag
/// handle on phones (and short windows). The builder learns which one it
/// is in (`wide`: the dialog), so it can pad its top (sheets have the drag
/// handle above) and lay out side by side.
///
/// [sheetHeightFactor] makes the sheet that tall (a fraction of the
/// screen) rather than as tall as its content.
Future<T?> showDialogOrSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, bool wide) builder,
  double maxWidth = 560,
  double maxHeight = double.infinity,
  double minHeight = 520,
  double? sheetHeightFactor,
  bool sheetDragHandle = true,
  double sheetMaxWidth = 720,
}) {
  if (prefersDialog(context, minHeight: minHeight)) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(Gaps.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: builder(context, true),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: sheetDragHandle,
    constraints: BoxConstraints(maxWidth: sheetMaxWidth),
    builder: (context) => sheetHeightFactor == null
        ? builder(context, false)
        : FractionallySizedBox(heightFactor: sheetHeightFactor, child: builder(context, false)),
  );
}
