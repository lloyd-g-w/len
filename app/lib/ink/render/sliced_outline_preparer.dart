import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/stroke.dart';
import 'outline_preparer.dart';
import 'stroke_renderer.dart';

/// Builds outlines on the calling thread in time-budgeted slices: the
/// web's preparer, where no isolate can build them (see ARCHITECTURE,
/// *Platforms*).
///
/// Outlines are built until [budget] is spent; if that was all of them the
/// returned future is synchronous (callers continue at once, as with
/// [InlineOutlinePreparer]). Otherwise the strokes done so far are
/// reported, the event loop gets a turn (a frame can be drawn) and the
/// next slice follows, so a dense page that arrives at once (opening a
/// notebook, going to a page) never blocks the tab for long.
class SlicedOutlinePreparer implements OutlinePreparer {
  SlicedOutlinePreparer({
    this.budget = const Duration(milliseconds: 8),
    Future<void> Function()? yieldToFrame,
  }) : _yield = yieldToFrame ?? (() => Future<void>.delayed(Duration.zero));

  /// UI-thread time spent building before yielding.
  final Duration budget;

  final Future<void> Function() _yield;

  @override
  Future<void> prepare(List<Stroke> strokes, {void Function(List<Stroke> ready)? onReady}) {
    final done = _slice(strokes, 0, onReady);
    if (done == strokes.length) return SynchronousFuture(null);
    return _rest(strokes, done, onReady);
  }

  Future<void> _rest(List<Stroke> strokes, int from, void Function(List<Stroke>)? onReady) async {
    while (from < strokes.length) {
      await _yield();
      from = _slice(strokes, from, onReady);
    }
  }

  /// Builds outlines from [from] on until [budget] is spent (at least one)
  /// and reports them; returns where it stopped.
  int _slice(List<Stroke> strokes, int from, void Function(List<Stroke>)? onReady) {
    final clock = Stopwatch()..start();
    var i = from;
    while (i < strokes.length) {
      StrokeRenderer.pathOf(strokes[i++]);
      if (clock.elapsed >= budget) break;
    }
    if (i > from) onReady?.call(strokes.sublist(from, i));
    return i;
  }

  @override
  void close() {}
}
