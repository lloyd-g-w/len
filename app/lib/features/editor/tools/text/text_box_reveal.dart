import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../ink/viewport.dart';

/// Keeps the text box being typed in clear of the phone's docked format
/// bar: when the box (or the bar, as the keyboard opens) changes, the view
/// pans up just enough that the box ends [gap] above the bar, never
/// pushing its top under the chrome. A pan by the user alone doesn't
/// trigger it, so it never fights them.
class TextBoxReveal {
  /// Space kept between the box and the bar.
  static const double gap = 16;

  Object? _last;

  /// Checks after this frame: [box] is the box's screen rect in [host]'s
  /// coordinates, [bar] the docked bar's key (null when the bar floats by
  /// the box), [top] the lowest the box's top may go.
  void schedule({
    required BuildContext host,
    required ViewportController viewport,
    required Object id,
    required Rect box,
    required GlobalKey? bar,
    required double top,
  }) {
    if (bar == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hostBox = host.mounted ? host.findRenderObject() : null;
      final barBox = bar.currentContext?.findRenderObject();
      if (hostBox is! RenderBox || barBox is! RenderBox || !barBox.hasSize) return;
      final barTop = hostBox.globalToLocal(barBox.localToGlobal(Offset.zero)).dy;
      final key = (id, box, barTop);
      if (key == _last) return;
      _last = key;
      final overlap = box.bottom + gap - barTop;
      if (overlap <= 0) return;
      final room = math.max(0.0, box.top - top);
      final pan = math.min(overlap, room);
      if (pan > 0) viewport.panBy(Offset(0, -pan));
    });
  }
}
