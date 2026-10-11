import 'dart:ui';

import '../../../ink/tools/pointer_tool.dart';
import 'pdf_interaction.dart';
import 'pdf_text_selection.dart';

/// The Select text tool: drag across the text of a PDF page to select it
/// (or drag a handle of the selection to change it), tap a word to select
/// it, tap a link to follow it, tap elsewhere to deselect. When the
/// pointer lifts, the selection's menu (copy, highlight) is offered.
class PdfTextTool implements PointerTool {
  PdfTextTool(this.interaction);

  final PdfInteraction interaction;

  /// Screen distance within which a press grabs a selection handle.
  static const double handleReach = 24;

  /// Movement (logical pixels) below which a press is a tap.
  static const double tapSlop = 6;

  PdfPagePoint? _down;
  Offset _downScreen = Offset.zero;
  int? _anchor;
  bool _dragged = false;

  PdfSelection get _selection => interaction.selection;

  @override
  void down(ToolPointer p) {
    _downScreen = p.screen;
    _dragged = false;
    _anchor = null;
    final at = _down = interaction.pageAt(p.screen);
    if (at == null) return;
    // A handle of the current selection: keep the other end.
    final handle = _handleAt(p.screen);
    if (handle != null) {
      _anchor = handle == 0 ? _selection.end - 1 : _selection.start;
      _selection.showsMenu = false;
      return;
    }
    final glyphs = interaction.info.glyphs(at.pdf.blob, at.pdf.pageIndex);
    _anchor = glyphs?.indexAt(at.normalized);
  }

  @override
  void move(ToolPointer p) {
    final at = _down;
    if (at == null) return;
    if (!_dragged && (p.screen - _downScreen).distance < tapSlop) return;
    _dragged = true;
    final glyphs = interaction.info.glyphs(at.pdf.blob, at.pdf.pageIndex);
    final anchor = _anchor;
    if (glyphs == null || anchor == null) return;
    final frame = interaction.doc.layout.frameOf(at.index);
    if (frame == null) return;
    final world = interaction.doc.viewport.toWorld(p.screen) - frame.topLeft;
    final focus = glyphs.nearestIndex(Offset(world.dx / frame.width, world.dy / frame.height));
    if (focus == null) return;
    final (a, b) = focus >= anchor ? (anchor, focus + 1) : (focus, anchor + 1);
    _selection.select(at.page, glyphs, a, b);
  }

  @override
  void up() {
    final at = _down;
    _down = null;
    if (at == null) {
      _selection.clear();
      return;
    }
    if (_dragged) {
      if (!_selection.isEmpty) _selection.showsMenu = true;
      return;
    }
    // A tap: links first, then a word, else deselect.
    if (interaction.followLinkAt(_downScreen)) return;
    if (!interaction.selectWordAt(_downScreen)) _selection.clear();
  }

  @override
  void cancel() {
    _down = null;
    _anchor = null;
  }

  /// 0 for the start handle, 1 for the end handle, or null.
  int? _handleAt(Offset screen) {
    final ends = handleEnds(interaction);
    if (ends == null) return null;
    if ((ends.$1 - screen).distance <= handleReach) return 0;
    if ((ends.$2 - screen).distance <= handleReach) return 1;
    return null;
  }

  /// Where the selection's start and end handles are on screen: the
  /// top-left of its first line and the bottom-right of its last.
  static (Offset, Offset)? handleEnds(PdfInteraction interaction) {
    final selection = interaction.selection;
    final page = selection.page;
    if (page == null || selection.isEmpty) return null;
    final rects = selection.rects;
    if (rects.isEmpty) return null;
    final doc = interaction.doc;
    final index = doc.pages.indexWhere((p) => p.id == page.id);
    final frame = index < 0 ? null : doc.layout.frameOf(index);
    if (frame == null) return null;
    Offset screen(Offset n) =>
        doc.viewport.toScreen(frame.topLeft + Offset(n.dx * frame.width, n.dy * frame.height));
    return (screen(rects.first.topLeft), screen(rects.last.bottomRight));
  }
}
