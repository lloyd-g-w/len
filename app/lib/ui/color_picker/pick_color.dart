import 'package:flutter/material.dart';

import '../adaptive_popover.dart';
import '../app_theme.dart';
import 'color_choices.dart';
import 'color_picker.dart';

/// Asks for an opaque colour (ARGB) with the colour block every tool
/// popover shares ([ColorChoices]: the palette, [recent] colours, Custom),
/// in a popover anchored at [context] (a sheet on phones). Like every
/// popover it has no buttons: [live] sees each change as it is made
/// (previews), and closing it returns the last colour picked; null if none
/// was. [anchor] overrides where the popover anchors (see
/// [showAdaptivePopover]).
Future<int?> pickColor(
  BuildContext context, {
  required String title,
  required int initial,
  List<int> recent = const [],
  ValueChanged<int>? live,
  Rect? anchor,
}) => _pick(
  context,
  title: title,
  initial: initial,
  live: live,
  anchor: anchor,
  width: colorChoicesPopoverWidth(),
  picker: (color, onChanged) => ColorChoices(color: color, recent: recent, onChanged: onChanged),
);

/// [pickColor] with only the custom part (square, hue, hex): for a
/// "Custom colour…" swatch at the end of a row of presets of its own.
Future<int?> pickCustomColor(
  BuildContext context, {
  required String title,
  required int initial,
  ValueChanged<int>? live,
}) => _pick(
  context,
  title: title,
  initial: initial,
  live: live,
  picker: (color, onChanged) => ColorPicker(color: color, showOpacity: false, onChanged: onChanged),
);

typedef _PickerBuilder = Widget Function(int color, ValueChanged<int> onChanged);

Future<int?> _pick(
  BuildContext context, {
  required String title,
  required int initial,
  required ValueChanged<int>? live,
  required _PickerBuilder picker,
  Rect? anchor,
  double width = popoverWidth,
}) async {
  int? picked;
  await showAdaptivePopover<void>(
    context: context,
    anchor: anchor,
    width: width,
    builder: (_) => _PickColor(
      title: title,
      initial: initial,
      picker: picker,
      onChanged: (c) {
        picked = c;
        live?.call(c);
      },
    ),
  );
  return picked;
}

class _PickColor extends StatefulWidget {
  const _PickColor({
    required this.title,
    required this.initial,
    required this.picker,
    required this.onChanged,
  });

  final String title;
  final int initial;
  final _PickerBuilder picker;
  final ValueChanged<int> onChanged;

  @override
  State<_PickColor> createState() => _PickColorState();
}

class _PickColorState extends State<_PickColor> {
  late int _color = widget.initial | 0xFF000000;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Gaps.sm),
        widget.picker(_color, (c) {
          setState(() => _color = c | 0xFF000000);
          widget.onChanged(_color);
        }),
      ],
    );
  }
}
