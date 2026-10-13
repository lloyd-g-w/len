import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'document_controller.dart';
import 'document_layout.dart';
import 'page_swipe.dart';

/// Turning pages by gesture in single-page flow while the whole page
/// shows: a one-finger swipe, a two-finger trackpad swipe, or the wheel.
/// Zoomed in on a page, all of them pan it instead.
class SinglePageTurns {
  SinglePageTurns(this.doc);

  final DocumentController doc;

  /// Wheel scrolling adding up to this (logical pixels; about one mouse
  /// notch) turns a page...
  static const double wheelStep = 50;

  /// ...and then the wheel rests this long, so one flick turns one page.
  /// A pause this long also forgets a partial step.
  static const Duration wheelRest = Duration(milliseconds: 300);

  /// Whether gestures turn pages now: single-page flow, not zoomed in.
  bool get active {
    if (doc.flow != PageFlow.single) return false;
    final fit = doc.frameTarget(doc.currentPage)?.scale;
    return fit != null && doc.viewport.scale <= fit * DocumentController.singleZoomedIn;
  }

  void _turn(int by) => doc.goToPage(doc.currentPage + by);

  // ---------------------------------------------------------------------------
  // One finger

  ({Offset at, Duration time})? _swipe;

  /// A finger that navigates touched down; only one [alone] may swipe.
  void fingerDown(PointerDownEvent e, {required bool alone}) =>
      _swipe = alone && active ? (at: e.localPosition, time: e.timeStamp) : null;

  /// The swiping finger lifted (the last one, still navigating).
  void fingerUp(PointerUpEvent e) {
    final start = _swipe;
    _swipe = null;
    if (start == null || !active) return;
    final delta = e.localPosition - start.at;
    final turn = PageSwipe.turn(delta, e.timeStamp - start.time, doc.viewport.size.width);
    if (turn != 0) _turn(turn);
  }

  /// The gesture became something else (a second finger, a pen, a cancel).
  void cancelSwipe() => _swipe = null;

  // ---------------------------------------------------------------------------
  // Trackpad

  Duration? _padStart;
  Offset _pad = Offset.zero;

  void trackpadStart(PointerPanZoomStartEvent e) {
    _padStart = active ? e.timeStamp : null;
    _pad = Offset.zero;
  }

  void trackpadUpdate(PointerPanZoomUpdateEvent e) {
    _pad = e.localPan;
    if (e.scale != 1) _padStart = null; // A pinch, not a swipe.
  }

  void trackpadEnd(PointerPanZoomEndEvent e) {
    final start = _padStart;
    _padStart = null;
    if (start == null || !active) return;
    final turn = PageSwipe.turn(_pad, e.timeStamp - start, doc.viewport.size.width);
    if (turn != 0) _turn(turn);
  }

  // ---------------------------------------------------------------------------
  // Wheel

  double _wheel = 0;
  Duration _lastWheel = Duration.zero;
  Duration? _turnedAt;

  /// Turns a page for wheel scrolling when [active] (not with Ctrl/⌘,
  /// which zooms). Returns whether it took the event.
  bool wheel(PointerScrollEvent e) {
    final keys = HardwareKeyboard.instance;
    if (!active || keys.isControlPressed || keys.isMetaPressed) return false;
    final d = e.scrollDelta;
    final amount = d.dy.abs() >= d.dx.abs() ? d.dy : d.dx;
    final t = e.timeStamp;
    if (t - _lastWheel > wheelRest) _wheel = 0;
    _lastWheel = t;
    final turned = _turnedAt;
    if (turned != null && t - turned < wheelRest) return true; // Resting.
    _wheel += amount;
    if (_wheel.abs() >= wheelStep) {
      _turn(_wheel > 0 ? 1 : -1);
      _turnedAt = t;
      _wheel = 0;
    }
    return true;
  }
}
