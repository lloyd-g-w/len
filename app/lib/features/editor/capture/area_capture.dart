import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../../core/file_names.dart';
import '../../../platform/file_export.dart' as platform;
import '../../documents/export/export_messages.dart';
import '../clipboard/clipboard_mirror.dart' show SystemClipboardWriter;
import '../editor_session.dart';
import '../eyedropper/page_colours.dart';
import 'area_capturer.dart';
import 'capture_layer.dart';

/// Saves a captured PNG (`platform.saveOrShare` by default).
typedef CaptureSaver = Future<platform.ExportedFiles?> Function(
  Uint8List bytes, {
  required String name,
  required String mime,
});

/// A capture under way: the picture (null if nothing was there to
/// capture) and whether it reached the system clipboard.
typedef CaptureResult = ({CapturedArea? shot, bool copied});

/// One editor's area capture ("Capture area" in Insert ⊕, "Copy as image"
/// in the selection menu): the user drags a rectangle over the page or
/// canvas ([CaptureLayer]); what it covers — paper, template, PDF page,
/// images, ink, shapes, text, not the editor's chrome — is rendered
/// ([AreaCapturer]) and copied to the system clipboard as a PNG, and a
/// small bar offers to save it or insert it as an image (undoable).
class AreaCapture {
  AreaCapture({
    required this.session,
    required this.colours,
    SystemClipboardWriter? write,
    CaptureSaver? save,
    AreaCapturer? capturer,
  }) : _write = write ?? Pasteboard.write,
       _save = save ?? _saveOrShare,
       capturer = capturer ?? AreaCapturer(session.services);

  final EditorSession session;

  /// The surface on screen (where it is, how screen points map to it).
  final PageColours colours;
  final AreaCapturer capturer;
  final SystemClipboardWriter _write;
  final CaptureSaver _save;

  OverlayEntry? _entry;

  /// Where the capture was started (the editor's chrome or layers).
  BuildContext? _host;

  /// Whether the capture layer is showing.
  bool get active => _entry != null;

  static Future<platform.ExportedFiles?> _saveOrShare(
    Uint8List bytes, {
    required String name,
    required String mime,
  }) => platform.saveOrShare(bytes, name: name, mime: mime);

  /// Shows the [CaptureLayer] to drag the area over.
  void start(BuildContext context) => _show(context);

  /// The selection menu's "Copy as image": the selection's bounding box,
  /// with everything under it, copied as at once (with the bar).
  void copySelection(BuildContext context) {
    final area = selectionArea();
    if (area == null) return;
    final global = _toGlobal(area);
    session.content.selection.clear();
    _show(context, initial: global, result: copy(area));
  }

  void _show(BuildContext context, {Rect? initial, Future<CaptureResult>? result}) {
    if (_entry != null) return;
    // Saving and inserting run on after the layer has gone.
    _host = context;
    final entry = _entry = OverlayEntry(
      builder: (_) => CaptureLayer(
        free: () => colours.free,
        onSurface: colours.onSurface,
        isPalm: colours.isPalm,
        initial: initial,
        result: result,
        capture: (global) {
          final area = areaOf(global);
          return area == null ? null : copy(area);
        },
        onSave: (shot) => _after(shot, _saveShot),
        onInsert: (shot) => _after(shot, _insert),
        onDone: _close,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  /// Closes the layer and runs [action] on [shot] in the editor.
  void _after(CapturedArea shot, Future<void> Function(BuildContext, CapturedArea) action) {
    _close();
    final host = _host;
    if (host != null && host.mounted) unawaited(action(host, shot));
  }

  void _close() {
    final entry = _entry;
    _entry = null;
    entry
      ?..remove()
      ..dispose();
  }

  /// Takes the layer away (the editor closes).
  void dispose() => _close();

  /// [global] (a rectangle on screen) in the surface's units: document
  /// coordinates of a paged notebook, world coordinates of a canvas.
  Rect? areaOf(Rect global) {
    final bounds = colours.bounds;
    if (bounds == null) return null;
    final local = global.intersect(bounds).shift(-bounds.topLeft);
    if (local.isEmpty) return null;
    final viewport = session.doc?.viewport ?? session.canvasViewport!;
    return Rect.fromPoints(viewport.toWorld(local.topLeft), viewport.toWorld(local.bottomRight));
  }

  Rect _toGlobal(Rect area) {
    final viewport = session.doc?.viewport ?? session.canvasViewport!;
    final origin = colours.bounds?.topLeft ?? Offset.zero;
    return Rect.fromPoints(
      viewport.toScreen(area.topLeft),
      viewport.toScreen(area.bottomRight),
    ).shift(origin);
  }

  /// The lasso selection's bounding box (its frame, as on screen) in the
  /// surface's units; null with nothing selected.
  Rect? selectionArea() {
    final selection = session.content.selection;
    final frame = selection.frame;
    if (frame == null || selection.isEmpty) return null;
    final corners = frame.corners;
    var box = Rect.fromPoints(corners.first, corners.first);
    for (final c in corners) {
      box = box.expandToInclude(Rect.fromPoints(c, c));
    }
    final doc = session.doc;
    if (doc == null) return box;
    final index = doc.pages.indexWhere((p) => p.id == selection.model.surfaceId);
    final page = index < 0 ? null : doc.layout.frameOf(index);
    return page == null ? null : box.shift(page.topLeft);
  }

  /// Renders [area] (see [areaOf]) and puts it on the system clipboard.
  /// The clipboard write starts at once (the web needs it within the
  /// user's gesture); the picture follows when rendered.
  Future<CaptureResult> copy(Rect area) async {
    final shot = render(area);
    final written = _write(png: shot.then((s) => s?.png)).catchError((Object e) {
      debugPrint('Copying the captured area failed: $e');
      return false;
    });
    return (shot: await shot, copied: await written);
  }

  /// [area] as a picture, at the resolution the screen shows it or more.
  Future<CapturedArea?> render(Rect area) async {
    final dpr = WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio ?? 1;
    final doc = session.doc;
    try {
      if (doc != null) {
        return await capturer.pages(
          area,
          pages: doc.pages,
          layout: doc.layout,
          screenScale: doc.viewport.scale * dpr,
        );
      }
      return await capturer.canvas(
        area,
        notebook: session.notebook,
        screenScale: session.canvasViewport!.scale * dpr,
      );
    } on Object catch (e) {
      debugPrint('Capturing the area failed: $e');
      return null;
    }
  }

  Future<void> _saveShot(BuildContext context, CapturedArea shot) async {
    final name = '${safeFileName(session.notebook.title)} capture.png';
    try {
      final saved = await _save(shot.png, name: name, mime: 'image/png');
      if (saved != null && context.mounted) showExported(context, saved, plural: 'images');
    } on Object catch (e) {
      if (context.mounted) showExportFailed(context, '“$name”', e);
    }
  }

  /// Inserts [shot] as an image as large as the area it shows, on the
  /// page (or canvas) in the middle of the screen, selected (one undoable
  /// edit, `EditorImages.insertBytes`).
  Future<void> _insert(BuildContext context, CapturedArea shot) async {
    await session.images.insertBytes(context, shot.png, size: shot.area.size);
  }
}
