import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';

import '../ink/render/background_outlines.dart';
import '../ink/render/outline_preparer.dart';

/// Worker isolates: up to three, leaving two cores for the UI and raster
/// threads (one on a machine with three cores or fewer). While the user
/// is touching the screen the UI isolate leaves the building to them.
OutlinePreparer createOutlinePreparer() => BackgroundOutlines(
  workers: math.max(1, math.min(3, Platform.numberOfProcessors - 2)),
  hold: _PointerActivity.recent,
);

/// Whether a pointer is down, or was lifted moments ago (writing goes on).
abstract final class _PointerActivity {
  static bool _listening = false;
  static int _down = 0;
  static final Stopwatch _sinceUp = Stopwatch();

  /// How long after the last pointer-up the user still counts as active.
  static const Duration _grace = Duration(milliseconds: 400);

  static bool recent() {
    if (!_listening) {
      _listening = true;
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onEvent);
    }
    return _down > 0 || (_sinceUp.isRunning && _sinceUp.elapsed < _grace);
  }

  static void _onEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      _down++;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _down = math.max(0, _down - 1);
      _sinceUp
        ..reset()
        ..start();
    }
  }
}
