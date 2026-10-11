import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/notebook_page.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import '../../documents/progress_dialog.dart' show showMessage;
import 'pdf_interaction.dart';
import 'pdf_page_info.dart';
import 'pdf_text_tool.dart';

/// Ctrl/⌘+C copies selected PDF text, Escape drops the selection (both
/// do nothing without one; the lasso's shortcuts run alongside).
Map<ShortcutActivator, VoidCallback> pdfShortcuts(PdfInteraction pdf) {
  void copy() {
    if (pdf.selection.isEmpty) return;
    Clipboard.setData(ClipboardData(text: pdf.selection.text));
  }

  return {
    const SingleActivator(LogicalKeyboardKey.keyC, control: true): copy,
    const SingleActivator(LogicalKeyboardKey.keyC, meta: true): copy,
    const SingleActivator(LogicalKeyboardKey.escape): pdf.selection.clear,
  };
}

/// Opens [url] outside the app; returns whether it could.
typedef UrlOpener = Future<bool> Function(Uri url);

Future<bool> _launch(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

/// Shows the PDF text selection (with handles and its menu: copy,
/// highlight, select all) over the document, follows links tapped with a
/// navigating finger, and keeps the visible pages' text and links loaded.
///
/// Pointer events pass through to the canvas beneath (the Select text
/// tool itself is a pointer tool of the canvas).
class PdfLayer extends StatefulWidget {
  const PdfLayer({super.key, required this.interaction, this.openUrl = _launch});

  final PdfInteraction interaction;

  /// Opens web addresses (the system browser; tests fake it).
  final UrlOpener openUrl;

  @override
  State<PdfLayer> createState() => _PdfLayerState();
}

class _PdfLayerState extends State<PdfLayer> {
  PdfInteraction get _pdf => widget.interaction;

  int? _tapPointer;

  /// Set while a press goes to the selection menu (seen first, by its own
  /// listener), so it doesn't drop the selection.
  bool _onMenu = false;
  Offset _tapAt = Offset.zero;
  Duration _tapTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _pdf.onLink = _onLink;
  }

  @override
  void dispose() {
    if (_pdf.onLink == _onLink) _pdf.onLink = null;
    super.dispose();
  }

  // Links -----------------------------------------------------------------

  Future<void> _onLink(PdfLinkArea link, PageBackground from) async {
    final target = link.page;
    if (target != null) {
      final page = _pdf.notebookPageOf(from.blob, target, from: _pageIdOf(from));
      if (page != null) {
        _pdf.doc.scrollToPage(page);
      } else {
        showMessage(context, 'Page ${target + 1} of the PDF is not in this notebook');
      }
      return;
    }
    final url = link.url;
    if (url == null) return;
    final open = await confirmAction(
      context,
      title: 'Open link?',
      message: url.toString(),
      confirmLabel: 'Open',
      icon: Icons.open_in_new_rounded,
    );
    if (!open || !mounted) return;
    if (!await widget.openUrl(url) && mounted) showMessage(context, 'Couldn’t open $url');
  }

  String? _pageIdOf(PageBackground bg) =>
      _pdf.doc.pages.where((p) => p.background == bg).firstOrNull?.id;

  /// Follows links tapped by a finger that navigates (stylus-only on);
  /// any press elsewhere drops a selection made with a long press.
  void _onDown(PointerDownEvent e) {
    final selectTool = _pdf.tools.tool == EditorTool.selectText;
    if (_onMenu) {
      _onMenu = false;
      return;
    }
    if (!selectTool && !_pdf.selection.isEmpty) _pdf.selection.clear();
    final navigating = e.kind == PointerDeviceKind.touch && (_pdf.tools.stylusOnly ?? false);
    _tapPointer = navigating && _tapPointer == null ? e.pointer : null;
    _tapAt = e.localPosition;
    _tapTime = e.timeStamp;
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _tapPointer) return;
    _tapPointer = null;
    final quick = e.timeStamp - _tapTime < const Duration(milliseconds: 300);
    if (quick && (e.localPosition - _tapAt).distance < PdfTextTool.tapSlop) {
      _pdf.followLinkAt(e.localPosition);
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer == _tapPointer && (e.localPosition - _tapAt).distance >= PdfTextTool.tapSlop) {
      _tapPointer = null;
    }
  }

  // Menu ------------------------------------------------------------------

  Future<void> _copy() async {
    final text = _pdf.selection.text;
    await Clipboard.setData(ClipboardData(text: text));
    _pdf.selection.clear();
    if (mounted) showMessage(context, 'Copied');
  }

  void _highlight() {
    if (_pdf.highlightSelection() == 0 && mounted) showMessage(context, 'Nothing to highlight');
  }

  @override
  Widget build(BuildContext context) {
    final doc = _pdf.doc;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: (_) => _tapPointer = null,
      child: ListenableBuilder(
        listenable: Listenable.merge([_pdf.selection, doc.viewport, _pdf.info]),
        builder: (context, _) {
          _preload();
          final ends = PdfTextTool.handleEnds(_pdf);
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SelectionPainter(
                      _pdf,
                      // Pages are paper in either theme: a mid-tone accent.
                      HSLColor.fromColor(Theme.of(context).colorScheme.primary)
                          .withLightness(0.45)
                          .toColor(),
                      handles: _pdf.tools.tool == EditorTool.selectText,
                    ),
                  ),
                ),
              ),
              if (_pdf.selection.showsMenu && ends != null) _menu(context, ends),
            ],
          );
        },
      ),
    );
  }

  /// Asks for the text and links of the pages in view.
  void _preload() {
    final doc = _pdf.doc;
    for (final i in doc.layout.visiblePages(doc.viewport.visibleWorld)) {
      final bg = doc.pages[i].background;
      if (bg != null) _pdf.info.isLoaded(bg.blob, bg.pageIndex);
    }
  }

  /// The menu above the selection, or below it when the top of the screen
  /// (the chrome) is too close.
  Widget _menu(BuildContext context, (Offset, Offset) ends) {
    final size = MediaQuery.sizeOf(context);
    const width = 300.0, height = 44.0;
    final (start, end) = ends;
    final left = (start.dx - 24)
        .clamp(Gaps.sm, math.max(Gaps.sm, size.width - width - Gaps.sm))
        .toDouble();
    final above = start.dy - height - 24;
    final roomAbove = MediaQuery.paddingOf(context).top + 64;
    final top = above >= roomAbove ? above : math.min(end.dy + 20, size.height - height - Gaps.sm);
    final scheme = Theme.of(context).colorScheme;
    Widget button(String label, IconData icon, VoidCallback onPressed, String key) =>
        TextButton.icon(
          key: ValueKey(key),
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
    return Positioned(
      left: left,
      top: top,
      child: Listener(
        onPointerDown: (_) => _onMenu = true,
        child: Material(
          elevation: 6,
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Radii.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                button('Copy', Icons.copy_rounded, _copy, 'pdf-copy'),
                button('Highlight', Icons.border_color_rounded, _highlight, 'pdf-highlight'),
                IconButton(
                  key: const ValueKey('pdf-select-all'),
                  tooltip: 'Select all on page',
                  icon: const Icon(Icons.select_all_rounded, size: 20),
                  onPressed: _pdf.selectAll,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the selected lines (and, with the Select text tool, the handles).
class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.pdf, this.color, {required this.handles});

  final PdfInteraction pdf;
  final Color color;
  final bool handles;

  @override
  void paint(Canvas canvas, Size size) {
    final selection = pdf.selection;
    final page = selection.page;
    if (page == null || selection.isEmpty) return;
    final doc = pdf.doc;
    final index = doc.pages.indexWhere((p) => p.id == page.id);
    final frame = index < 0 ? null : doc.layout.frameOf(index);
    if (frame == null) return;
    final fill = Paint()..color = color.withValues(alpha: 0.28);
    for (final r in selection.rects) {
      final a = doc.viewport.toScreen(
        frame.topLeft + Offset(r.left * frame.width, r.top * frame.height),
      );
      final b = doc.viewport.toScreen(
        frame.topLeft + Offset(r.right * frame.width, r.bottom * frame.height),
      );
      canvas.drawRect(Rect.fromPoints(a, b), fill);
    }
    final ends = PdfTextTool.handleEnds(pdf);
    if (!handles || ends == null) return;
    final solid = Paint()
      ..color = color
      ..strokeWidth = 2;
    final rects = selection.rects;
    final scale = doc.viewport.scale;
    final startHeight = rects.first.height * frame.height * scale;
    final endHeight = rects.last.height * frame.height * scale;
    canvas
      ..drawLine(ends.$1, ends.$1 + Offset(0, startHeight), solid)
      ..drawCircle(ends.$1 - const Offset(0, 5), 6, solid)
      ..drawLine(ends.$2, ends.$2 - Offset(0, endHeight), solid)
      ..drawCircle(ends.$2 + const Offset(0, 5), 6, solid);
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => true; // Repainted by the builder's listenables.
}
