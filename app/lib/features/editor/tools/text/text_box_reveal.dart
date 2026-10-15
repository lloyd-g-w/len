import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../../ink/viewport.dart';

/// Keeps the text box being typed in clear of what covers the page's
/// bottom: the phone's docked format bar, or else the bottom chrome and the
/// soft keyboard (a phone held sideways, whose bar floats). When the box,
/// its caret or that edge (as the keyboard opens) changes, the view pans up
/// just enough that the box ends [gap] above the edge, never pushing its top
/// under the chrome; a box too tall for the room keeps its caret's line in
/// view instead. A pan by the user alone doesn't trigger it, so it never
/// fights them.
class TextBoxReveal {
  /// Space kept between the box (or its caret) and the edge.
  static const double gap = 16;

  Object? _last;

  /// Checks after this frame: [box] is the box's screen rect in [host]'s
  /// coordinates, [world] its rect on the page, [bar] the docked bar's key
  /// (null when the bar floats by the box: the host's bottom less [bottom]
  /// is then the edge), [top] the lowest the box's top may go, [field] the
  /// text field's context (for the caret at [caret], a text offset).
  void schedule({
    required BuildContext host,
    required ViewportController viewport,
    required Object id,
    required Rect box,
    required Rect world,
    required GlobalKey? bar,
    required double top,
    required double bottom,
    BuildContext? field,
    int? caret,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hostBox = host.mounted ? host.findRenderObject() : null;
      if (hostBox is! RenderBox || !hostBox.hasSize) return;
      final double edge;
      if (bar == null) {
        edge = hostBox.size.height - bottom;
      } else {
        final barBox = bar.currentContext?.findRenderObject();
        if (barBox is! RenderBox || !barBox.hasSize) return;
        edge = hostBox.globalToLocal(barBox.localToGlobal(Offset.zero)).dy;
      }
      final key = (id, world, edge, caret, viewport.scale);
      if (key == _last) return;
      _last = key;
      final pan = panFor(box, edge, top, _caretRect(hostBox, field, caret));
      if (pan > 0) viewport.panBy(Offset(0, -pan));
    });
  }

  /// How far up to pan so [box] (or, too tall for the room, [caret]) ends
  /// [gap] above [edge] with its top no higher than [top].
  @visibleForTesting
  static double panFor(Rect box, double edge, double top, Rect? caret) {
    final fits = box.height + gap <= edge - top;
    if (!fits && caret != null) return math.max(0.0, caret.bottom + gap - edge);
    final overlap = box.bottom + gap - edge;
    if (overlap <= 0) return 0;
    return math.min(overlap, math.max(0.0, box.top - top));
  }

  /// The caret at text offset [caret] in [host]'s coordinates.
  static Rect? _caretRect(RenderBox host, BuildContext? field, int? caret) {
    if (field == null || caret == null || caret < 0 || !field.mounted) return null;
    final root = field.findRenderObject();
    if (root == null) return null;
    RenderEditable? editable;
    void visit(RenderObject child) {
      if (editable != null) return;
      if (child is RenderEditable) {
        editable = child;
      } else {
        child.visitChildren(visit);
      }
    }

    visit(root);
    final found = editable;
    if (found == null || !found.hasSize) return null;
    final local = found.getLocalRectForCaret(TextPosition(offset: caret));
    return Rect.fromPoints(
      host.globalToLocal(found.localToGlobal(local.topLeft)),
      host.globalToLocal(found.localToGlobal(local.bottomRight)),
    );
  }
}
