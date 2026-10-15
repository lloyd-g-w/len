import 'dart:math' as math;
import 'dart:ui';

import '../../domain/surface_element.dart';
import '../elements/text_edit_session.dart';
import '../elements/text_hit_test.dart';
import '../elements/text_layout.dart';
import '../tool_settings.dart';
import '../viewport.dart';
import 'content_hit_test.dart';
import 'pointer_tool.dart';

/// The Text tool: tap a text box to edit it, tap empty space to start a
/// new one (ending any edit in progress).
class TextTool implements PointerTool {
  TextTool({required this.session, required this.tools, required this.viewport});

  final TextEditSession session;
  final ToolSettings tools;
  final ViewportController viewport;

  /// Narrowest a new box may wrap at, in screen pixels at the current zoom
  /// (it grows with its text up to the edge of the screen, at least this).
  static const double minWrapWidth = 240;

  /// Distance kept from the right edge of the screen, in screen pixels.
  static const double edgeMargin = 24;

  /// Movement (pixels) after which a press is no longer a tap.
  static const double slop = 8;

  ToolPointer? _down;
  ToolPointer? _last;

  @override
  void down(ToolPointer p) => _down = _last = p;

  @override
  void move(ToolPointer p) => _last = p;

  @override
  void up() {
    final down = _down, last = _last;
    _down = _last = null;
    if (down == null || last == null || (last.screen - down.screen).distance > slop) return;
    final hit = ContentHitTest.elementAt(session.model, down.world, type: ElementType.text);
    if (hit != null && hit.id == session.current?.id) return;
    if (hit != null) {
      final line = TextHitTest.checkboxAt(hit, down.world);
      if (line != null) {
        TextHitTest.toggleChecked(session.model, hit, line);
        return;
      }
      _limitAt(hit.rect.left);
      session.edit(hit);
    } else if (session.isEditing) {
      session.end(); // A tap outside finishes the current box first.
    } else {
      startBox(down.world);
    }
  }

  /// Starts a new box (default style, auto width) at world point [at].
  void startBox(Offset at) {
    _limitAt(at.dx);
    session.create(at, style: tools.textStyle);
  }

  /// Starts a box holding [text] (typed with no box open): under the box
  /// finished last when that is in view, else at the middle of the view's
  /// left half.
  void startTyping(String text) {
    final style = tools.textStyle;
    final line = TextLayout.heightOf(style.copyWith(text: ''), TextLayout.minWidth);
    final visible = viewport.visibleWorld;
    final last = session.lastBox;
    var at = last == null || last.surfaceId != session.model.surfaceId
        ? null
        : Offset(last.rect.left, last.rect.bottom + line);
    if (at == null || !visible.deflate(line).contains(at)) {
      final c = visible.center;
      at = Offset(c.dx - math.min(visible.width / 4, maxTypingInset / viewport.scale), c.dy);
    }
    _limitAt(at.dx);
    session.create(at, style: style, text: text);
  }

  /// Furthest left of the centre (screen pixels) a box typed with no box
  /// open starts.
  static const double maxTypingInset = 200;

  /// Auto-width boxes starting at [left] wrap at the screen's edge.
  void _limitAt(double left) {
    final scale = viewport.scale;
    final edge = viewport.visibleWorld.right - edgeMargin / scale;
    session.autoWidthLimit = math.max(edge - left, minWrapWidth / scale);
  }

  @override
  void cancel() => _down = _last = null;
}
