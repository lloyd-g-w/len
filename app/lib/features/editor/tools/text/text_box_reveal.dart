import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../ink/viewport.dart';

/// Keeps the caret of the text box being typed in on screen, clear of the
/// soft keyboard and the phone's docked format bar: when the box, the
/// caret or the space left (the keyboard opening) changes, the view pans
/// just enough that the caret's line ends [gap] above the bar or the
/// bottom of the view — showing the whole box while it fits below the
/// chrome — or, for a caret gone above the view, that it comes back
/// down. A pan by the user alone doesn't trigger it, so it never fights
/// them.
class TextBoxReveal {
  /// Space kept between the caret (or box) and the bar or the edge.
  static const double gap = 16;

  Object? _last;

  /// Checks after this frame: [box] is the box's screen rect in [host]'s
  /// coordinates, [caret] gives the caret's rect in global coordinates
  /// (null: nothing to do),
  /// [bar] the docked bar's key (null when the bar floats by the box),
  /// [top] the lowest the box's top may go, [bottom] the chrome's height
  /// at the bottom of [host]. [state] identifies the box, its text and
  /// where the caret is (world units: a pan alone does not change it).
  void schedule({
    required BuildContext host,
    required ViewportController viewport,
    required Object state,
    required Rect box,
    required Rect? Function() caret,
    required GlobalKey? bar,
    required double top,
    double bottom = 0,
  }) {
    // One check per frame, with the latest geometry.
    final first = _check == null;
    _check = () {
      final hostBox = host.mounted ? host.findRenderObject() : null;
      if (hostBox is! RenderBox || !hostBox.hasSize) return;
      var limit = hostBox.size.height - bottom;
      if (bar != null) {
        final barBox = bar.currentContext?.findRenderObject();
        if (barBox is! RenderBox || !barBox.hasSize) return;
        limit = math.min(limit, hostBox.globalToLocal(barBox.localToGlobal(Offset.zero)).dy);
      }
      // Where the keyboard starts, should it not have shrunk the host.
      final view = View.maybeOf(host);
      if (view != null) {
        final keyboard =
            (view.physicalSize.height - view.viewInsets.bottom) / view.devicePixelRatio;
        limit = math.min(limit, hostBox.globalToLocal(Offset(0, keyboard)).dy);
      }
      final key = (state, limit);
      if (key == _last) return;
      _last = key;
      final global = caret();
      if (global == null) return; // Not laid out, or the box ended.
      final at = Rect.fromPoints(
        hostBox.globalToLocal(global.topLeft),
        hostBox.globalToLocal(global.bottomRight),
      );
      final pan = panFor(box: box, caret: at, top: top, bottom: limit - gap);
      if (pan != 0) viewport.panBy(Offset(0, -pan));
    };
    if (!first) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final check = _check;
      _check = null;
      check?.call();
    });
  }

  /// The check to run after this frame.
  VoidCallback? _check;

  /// How far to pan the view up (negative: down) so [caret] lies between
  /// [top] and [bottom], showing as much of [box] as fits: its bottom
  /// rises above [bottom] as long as its top stays below [top].
  static double panFor({
    required Rect box,
    required Rect caret,
    required double top,
    required double bottom,
  }) {
    if (caret.top < top) return caret.top - top;
    final caretOverlap = caret.bottom - bottom;
    final boxOverlap = box.bottom - bottom;
    final room = math.max(0.0, box.top - top);
    final pan = math.max(math.min(boxOverlap, room), caretOverlap);
    return pan > 0 ? pan : 0;
  }
}
