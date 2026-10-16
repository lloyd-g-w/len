import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/color_picker/eyedropper_scope.dart';
import 'eyedropper_layer.dart';
import 'page_colours.dart';

/// One editor's eyedropper ([EyedropperScope.pick]): "Pick from page" in a
/// colour picker hides the picker's popover or sheet, shows the
/// [EyedropperLayer] until the page is tapped (or the pick is cancelled),
/// hands the colour to the picker, closes it and makes the colour a
/// recent one ([addRecent]). Pen, finger and mouse alike.
class Eyedropper {
  Eyedropper({required this.colours, required this.addRecent});

  final PageColours colours;
  final ValueChanged<int> addRecent;

  Completer<int?>? _waiting;

  /// Whether it waits for a pick.
  bool get active => _waiting != null;

  /// See [PickFromPage].
  Future<void> pick(BuildContext picker, ValueChanged<int> apply) async {
    if (_waiting != null) return;
    final waiting = _waiting = Completer<int?>();
    void finish(int? colour) {
      if (!waiting.isCompleted) waiting.complete(colour);
    }

    final navigator = Navigator.of(picker);
    final route = ModalRoute.of(picker);
    // A popover or sheet steps aside (kept, so its owner still takes the
    // colour); closed some other way meanwhile, the pick is off.
    final popup = route is PopupRoute ? route : null;
    popup?.offstage = true;
    unawaited(popup?.popped.then((_) => finish(null)));
    final entry = OverlayEntry(
      builder: (_) => EyedropperLayer(colours: colours, onDone: finish),
    );
    navigator.overlay!.insert(entry);
    final colour = await waiting.future;
    _waiting = null;
    entry
      ..remove()
      ..dispose();
    if (colour != null && picker.mounted) apply(colour);
    if (popup != null && popup.isActive) {
      if (popup.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(popup);
      }
    }
    if (colour != null) addRecent(colour);
  }

  /// Cancels a pick in progress (the editor closes).
  void dispose() {
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) waiting.complete(null);
  }
}
