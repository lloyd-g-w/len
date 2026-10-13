import 'package:flutter/material.dart';

import '../adaptive_popover.dart';
import '../app_theme.dart';
import 'color_picker.dart';

/// Asks for an opaque colour (ARGB) with the full picker, in a popover
/// anchored at [context] (a sheet on phones), with [recent] colours.
/// Like every popover it has no buttons: [live] sees each change as it is
/// made (previews), and closing it returns the last colour picked; null if
/// none was.
Future<int?> pickColor(
  BuildContext context, {
  required String title,
  required int initial,
  List<int> recent = const [],
  ValueChanged<int>? live,
}) async {
  int? picked;
  await showAdaptivePopover<void>(
    context: context,
    builder: (_) => _PickColor(
      title: title,
      initial: initial,
      recent: recent,
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
    required this.recent,
    required this.onChanged,
  });

  final String title;
  final int initial;
  final List<int> recent;
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
        const SizedBox(height: Gaps.md),
        ColorPicker(
          color: _color,
          showOpacity: false,
          recent: widget.recent,
          onChanged: (c) {
            setState(() => _color = c | 0xFF000000);
            widget.onChanged(_color);
          },
        ),
      ],
    );
  }
}
