import 'package:flutter/material.dart';

import '../adaptive_popover.dart';
import '../app_theme.dart';
import 'color_picker.dart';

/// Asks for an opaque colour with the full picker, in a popover anchored
/// at [context] (a sheet on phones); null if dismissed. [live] sees every
/// change as it is made, for previews.
Future<int?> pickColor(
  BuildContext context, {
  required String title,
  required int initial,
  ValueChanged<int>? live,
}) => showAdaptivePopover<int>(
  context: context,
  builder: (_) => _PickColor(title: title, initial: initial, live: live),
);

class _PickColor extends StatefulWidget {
  const _PickColor({required this.title, required this.initial, this.live});

  final String title;
  final int initial;
  final ValueChanged<int>? live;

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
        Row(
          children: [
            Expanded(child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium)),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_color),
              child: const Text('Apply'),
            ),
          ],
        ),
        const SizedBox(height: Gaps.sm),
        ColorPicker(
          color: _color,
          showOpacity: false,
          onChanged: (c) {
            setState(() => _color = c | 0xFF000000);
            widget.live?.call(_color);
          },
        ),
      ],
    );
  }
}
