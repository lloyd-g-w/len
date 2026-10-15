import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Whether [controller]'s scrollable moves fast: more than
/// [viewportsPerSecond] of its viewport a second, measured from frame to
/// frame. Costly work for items coming into view (recording thumbnails)
/// can wait while it is true, as [Image] defers loading during a fling;
/// unlike [Scrollable.recommendDeferredLoadingForContext], a fast drag
/// counts too (a drag reports no velocity).
///
/// Turns false once the speed drops, or [rest] after the last move (a
/// finger held still produces no frames to measure).
class FastScroll extends ChangeNotifier implements ValueListenable<bool> {
  FastScroll(
    this.controller, {
    this.viewportsPerSecond = 2,
    this.rest = const Duration(milliseconds: 100),
  }) {
    controller.addListener(_moved);
  }

  /// The scroll measured (attached to one scrollable at a time).
  final ScrollController controller;

  /// The speed from which scrolling counts as fast.
  final double viewportsPerSecond;

  /// How long without a move before scrolling counts as stopped.
  final Duration rest;

  @override
  bool get value => _fast;
  bool _fast = false;

  bool _sampling = false;
  double? _lastPixels;
  Duration? _lastStamp;
  Timer? _rest;
  bool _disposed = false;

  void _moved() {
    // A fling says how fast it goes: no need to wait for a frame to tell.
    if (!_fast && controller.hasClients && _flings(controller.position)) _set(true);
    if (!_sampling) {
      _sampling = true;
      SchedulerBinding.instance.scheduleFrameCallback(_sample);
    }
    _rest?.cancel();
    _rest = Timer(rest, _settled);
  }

  void _sample(Duration stamp) {
    _sampling = false;
    if (_disposed || !controller.hasClients) return;
    final position = controller.position;
    if (!position.hasPixels || !position.hasViewportDimension) return;
    final pixels = position.pixels;
    final (lastPixels, lastStamp) = (_lastPixels, _lastStamp);
    _lastPixels = pixels;
    _lastStamp = stamp;
    if (lastPixels == null || lastStamp == null) return;
    final seconds = (stamp - lastStamp).inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0) return;
    final speed = (pixels - lastPixels).abs() / seconds;
    _set(speed > viewportsPerSecond * position.viewportDimension || _flings(position));
  }

  /// Whether [position] is in a fling fast enough for its physics to
  /// recommend deferring work.
  static bool _flings(ScrollPosition position) {
    final context = position.context.notificationContext;
    return context != null && position.recommendDeferredLoading(context);
  }

  void _settled() {
    _lastPixels = null;
    _lastStamp = null;
    _set(false);
  }

  void _set(bool fast) {
    if (fast == _fast) return;
    _fast = fast;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _rest?.cancel();
    controller.removeListener(_moved);
    super.dispose();
  }
}
