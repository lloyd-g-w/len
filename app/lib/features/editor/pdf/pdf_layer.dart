import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/notebook_page.dart';
import '../../../ui/app_dialogs.dart';
import '../../documents/progress_dialog.dart' show showMessage;
import 'pdf_interaction.dart';
import 'pdf_page_info.dart';
import 'pdf_selection_handles.dart';
import 'pdf_selection_menu.dart';
import 'pdf_selection_paint.dart';

/// Ctrl/⌘+C copies selected PDF text (then calls [copied]), Escape drops
/// the selection (both do nothing without one; the lasso's shortcuts run
/// alongside).
Map<ShortcutActivator, VoidCallback> pdfShortcuts(PdfInteraction pdf, {VoidCallback? copied}) {
  void copy() {
    if (pdf.selection.isEmpty) return;
    unawaited(Clipboard.setData(ClipboardData(text: pdf.selection.text)));
    copied?.call();
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

/// Shows the PDF text selection (with handles and its [PdfSelectionMenu])
/// over the document, follows links tapped with a navigating finger, and
/// keeps the visible pages' text and links loaded.
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

  /// What changes the pages in view or their text.
  late Listenable _preloads = _preloadsOf(_pdf);

  static Listenable _preloadsOf(PdfInteraction pdf) =>
      Listenable.merge([pdf.selection, pdf.doc.viewport, pdf.info]);

  @override
  void initState() {
    super.initState();
    _pdf.onLink = _onLink;
    _preloads.addListener(_preload);
    _preload();
  }

  @override
  void didUpdateWidget(PdfLayer old) {
    super.didUpdateWidget(old);
    if (old.interaction == widget.interaction) return;
    _preloads.removeListener(_preload);
    _preloads = _preloadsOf(_pdf)..addListener(_preload);
    _preload();
  }

  @override
  void dispose() {
    _preloads.removeListener(_preload);
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
      icon: Symbols.open_in_new_rounded,
    );
    if (!open || !mounted) return;
    if (!await widget.openUrl(url) && mounted) showMessage(context, 'Couldn’t open $url');
  }

  String? _pageIdOf(PageBackground bg) =>
      _pdf.doc.pages.where((p) => p.background == bg).firstOrNull?.id;

  /// Follows links tapped by a finger that navigates (stylus-only or reading);
  /// any press elsewhere drops a selection made with a long press.
  void _onDown(PointerDownEvent e) {
    if (_onSelection) {
      _onSelection = false;
      return;
    }
    if (!_pdf.selection.isEmpty) _pdf.selection.clear();
    final navigating = e.kind == PointerDeviceKind.touch && _pdf.tools.fingersNavigate;
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
    if (!mounted) return; // The editor closed meanwhile (its selection is gone).
    _pdf.selection.clear();
    showMessage(context, 'Copied');
  }

  void _highlight(int color) {
    if (_pdf.highlightSelection(color: color) == 0 && mounted) {
      showMessage(context, 'Nothing to highlight');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: (_) => _tapPointer = null,
      // The view only matters while something is selected: no rebuild per
      // scroll frame otherwise (under the editor's LayoutBuilder it would
      // lay out and repaint the whole editor).
      child: ListenableBuilder(
        listenable: _pdf.selection,
        builder: (context, _) =>
            _pdf.selection.isEmpty ? const SizedBox.shrink() : _selection(context),
      ),
    );
  }

  /// The selected lines, their handles and the menu: they follow the view
  /// by repainting and layout alone; they rebuild when the selection, the
  /// pages' text, the document or its ink (highlights) change.
  Widget _selection(BuildContext context) {
    final doc = _pdf.doc;
    final view = Listenable.merge([_pdf.selection, doc.viewport, doc, _pdf.info]);
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: PdfSelectionPainter(
                  _pdf,
                  // Pages are paper in either theme: a mid-tone accent.
                  HSLColor.fromColor(Theme.of(context).colorScheme.primary)
                      .withLightness(0.45)
                      .toColor(),
                  repaint: view,
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: ListenableBuilder(
              listenable: Listenable.merge([_pdf.selection, doc, doc.surfaces, _pdf.info]),
              builder: (context, _) {
                // Whether there are ends depends on the pages' layout, not
                // on the view.
                if (_pdf.handleEnds == null) return const SizedBox.shrink();
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Listener(
                        behavior: HitTestBehavior.deferToChild,
                        onPointerDown: (_) => _onSelection = true,
                        child: PdfSelectionHandles(interaction: _pdf, relayout: view),
                      ),
                    ),
                    if (_pdf.selection.showsMenu)
                      Positioned.fill(
                        child: PdfSelectionMenu(
                          interaction: _pdf,
                          relayout: view,
                          onPress: () => _onSelection = true,
                          onCopy: _copy,
                          onHighlight: _highlight,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Asks for the text and links of the pages in view (as the view, the
  /// selection or the pages' text change).
  void _preload() {
    final doc = _pdf.doc;
    for (final i in doc.layout.visiblePages(doc.viewport.visibleWorld)) {
      final bg = doc.pages[i].pdf;
      if (bg != null) _pdf.info.isLoaded(bg.blob, bg.pageIndex);
    }
  }
}
