import '../../domain/surface_element.dart';
import '../elements/text_edit_session.dart';
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

  /// Width of a new text box, in screen pixels at the current zoom.
  static const double newBoxWidth = 320;

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
      session.edit(hit);
    } else if (session.isEditing) {
      session.end(); // A tap outside finishes the current box first.
    } else {
      session.create(down.world, width: newBoxWidth / viewport.scale, style: tools.textStyle);
    }
  }

  @override
  void cancel() => _down = _last = null;
}
