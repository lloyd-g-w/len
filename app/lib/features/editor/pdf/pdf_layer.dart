import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/notebook_page.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import '../../documents/progress_dialog.dart' show showMessage;
import '../links/link_menu.dart';
import 'pdf_interaction.dart';
import 'pdf_page_info.dart';
import 'pdf_selection_handles.dart';
import 'pdf_selection_paint.dart';

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
/// Pointer events pass through to the canvas beneath, except on the
/// selection's handles and menu.
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

  /// Movement (logical pixels) below which a press is a tap.
  static const double _tapSlop = 6;

  int? _tapPointer;

  /// Set while a press goes to the selection menu or a handle (seen first,
  /// by their own listener), so it doesn't drop the selection.
  bool _onSelection = false;
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
    if (_onSelection) {
      _onSelection = false;
      return;
    }
    if (!_pdf.selection.isEmpty) _pdf.selection.clear();
    final navigating = e.kind == PointerDeviceKind.touch && (_pdf.tools.stylusOnly ?? false);
    _tapPointer = navigating && _tapPointer == null ? e.pointer : null;
    _tapAt = e.localPosition;
    _tapTime = e.timeStamp;
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _tapPointer) return;
    _tapPointer = null;
    final quick = e.timeStamp - _tapTime < const Duration(milliseconds: 300);
    if (quick && (e.localPosition - _tapAt).distance < _tapSlop) {
      _pdf.followLinkAt(e.localPosition);
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer == _tapPointer && (e.localPosition - _tapAt).distance >= _tapSlop) {
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
          final ends = _pdf.handleEnds;
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: PdfSelectionPainter(
                      _pdf,
                      // Pages are paper in either theme: a mid-tone accent.
                      HSLColor.fromColor(Theme.of(context).colorScheme.primary)
                          .withLightness(0.45)
                          .toColor(),
                    ),
                  ),
                ),
              ),
              if (ends != null)
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.deferToChild,
                    onPointerDown: (_) => _onSelection = true,
                    child: PdfSelectionHandles(interaction: _pdf, ends: ends),
                  ),
                ),
              if (_pdf.selection.showsMenu && ends != null) _menu(context, _selectionOnScreen()),
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

  /// The box around the selected lines on screen.
  Rect _selectionOnScreen() {
    final doc = _pdf.doc;
    final index = doc.pages.indexWhere((p) => p.id == _pdf.selection.page?.id);
    final frame = index < 0 ? null : doc.layout.frameOf(index);
    if (frame == null) return Rect.zero;
    final rects = [
      for (final r in _pdf.selectionRects)
        Rect.fromPoints(
          doc.viewport.toScreen(frame.topLeft + r.topLeft),
          doc.viewport.toScreen(frame.topLeft + r.bottomRight),
        ),
    ];
    return rects.isEmpty ? Rect.zero : rects.reduce((a, b) => a.expandToInclude(b));
  }

  /// The selection's menu, above the selected lines (below them if there
  /// is no room above).
  Widget _menu(BuildContext context, Rect selected) {
    final roomAbove = MediaQuery.paddingOf(context).top + 64;
    final scheme = Theme.of(context).colorScheme;
    Widget button(String label, IconData icon, VoidCallback onPressed, String key) =>
        TextButton.icon(
          key: ValueKey(key),
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: PdfMenuPlacement(selected, roomAbove: roomAbove),
        child: Listener(
          onPointerDown: (_) => _onSelection = true,
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
                  if (_pdf.selectedLink != null)
                    IconButton(
                      key: const ValueKey('pdf-open-link'),
                      tooltip: 'Open link',
                      icon: const Icon(Icons.open_in_new_rounded, size: 20),
                      onPressed: _pdf.openSelectedLink,
                    ),
                  if (_pdf.onLinkSelection case final link?)
                    Builder(
                      builder: (anchor) => IconButton(
                        key: const ValueKey('pdf-link'),
                        tooltip: 'Link…',
                        icon: const Icon(Icons.link_rounded, size: 20),
                        onPressed: () async {
                          final choice = await showLinkMenu(anchor);
                          if (choice != null) link(url: choice == LinkChoice.url);
                        },
                      ),
                    ),
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
      ),
    );
  }
}
