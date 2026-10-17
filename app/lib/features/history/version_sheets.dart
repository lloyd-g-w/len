import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../data/versions/versions.dart';
import '../../data/versions/work_slices.dart';
import '../../domain/notebook_page.dart';
import '../../domain/paper.dart';
import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../editor/document/page_backgrounds.dart';
import 'version_ink_images.dart';

/// A surface of a version ready to paint: its page (for a canvas, the
/// frame around its content, which starts at [origin] on the canvas).
typedef VersionSheet = ({
  NotebookPage page,
  List<Stroke> strokes,
  List<SurfaceElement> elements,
  Offset? origin,
});

/// Loads and keeps what version surfaces hold, for the history's
/// thumbnails and previews (packs fetched when not on this device).
class VersionSheets {
  VersionSheets(this.versions, {this.backgrounds});

  final Versions versions;

  /// Page backgrounds (PDF pages, scans) drawn beneath the ink; owned:
  /// disposed with this.
  final PageBackgrounds? backgrounds;

  /// The thumbnails' ink of large content, rendered in the same slices as
  /// the loads.
  late final VersionInkImages inkImages = VersionInkImages(_slices);

  /// Disposes [backgrounds] and the [inkImages].
  void dispose() {
    backgrounds?.dispose();
    inkImages.dispose();
  }

  final Map<String, Future<VersionSheet?>> _loaded = {};
  final Map<String, Future<VersionBody?>> _bodies = {};

  /// The load running last: loads run one after the other, so their
  /// slices ([WorkSlices]) are short turns rather than a dozen thumbnails'
  /// slices in each, with a turn between loads once one is due.
  Future<void> _queue = Future<void>.value();
  final WorkSlices _slices = WorkSlices();

  Future<T> _inTurn<T>(Future<T> Function() load) {
    final next = _queue.then((_) async {
      await _slices.yieldIfDue();
      return load();
    });
    _queue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// The body of [version] (its pages), or null when it cannot be had.
  Future<VersionBody?> body(NotebookVersion version) =>
      _bodies[version.id] ??= _inTurn(() => versions.content.body(version))
          .then<VersionBody?>((body) => body)
          .catchError((Object _) => null);

  /// Page [page] of [version] (null: its canvas, or the page it changed
  /// first, else its first), or null when its content cannot be had
  /// (offline, not on the server) or it has no page.
  Future<VersionSheet?> of(NotebookVersion version, VersionPage? page) async {
    if (page == null) {
      final body = await this.body(version);
      if (body == null) return null;
      final canvas = body.canvas;
      if (canvas == null) {
        final first = body.page(version.summary.focus ?? '') ?? body.pages.firstOrNull;
        return first == null ? null : of(version, first);
      }
      final key = 'canvas:${canvas.packs.join()}';
      return _loaded[key] ??= _inTurn(() => _load(version, canvas, null))
          .catchError((Object _) => null);
    }
    final key = '${page.id}:${page.content.packs.join()}:${page.fields}';
    return _loaded[key] ??= _inTurn(() => _load(version, null, page))
        .catchError((Object _) => null);
  }

  Future<VersionSheet?> _load(
    NotebookVersion version,
    VersionSurface? canvas,
    VersionPage? page,
  ) async {
    final content = versions.content;
    if (page != null) {
      await content.ensure([page.content]);
      final c = await content.load(page.content, page.id);
      return (
        page: VersionContent.pageOf(version, page),
        strokes: c.strokes,
        elements: c.elements,
        origin: null,
      );
    }
    canvas ??= VersionSurface.empty;
    await content.ensure([canvas]);
    final c = await content.load(canvas, version.notebookId);
    final frame = _frame([
      for (final s in c.strokes) s.bounds,
      for (final e in c.elements) e.bounds,
    ]);
    final origin = frame.topLeft;
    final paper = Paper.fromData(
      PaperStyle.parse(version.notebook['paper'] as String),
      version.notebook['paperData'] as Map<String, Object?>,
    );
    return (
      page: NotebookPage(
        id: version.notebookId,
        notebookId: version.notebookId,
        sortKey: 0,
        width: frame.width,
        height: frame.height,
        paper: paper ?? Paper.blank,
        paperColor: PaperColor.parse(version.notebook['paperColor'] as String?),
      ),
      // Where they are on the canvas (shared with the other versions'
      // sheets), painted moved by [origin].
      strokes: c.strokes,
      elements: c.elements,
      origin: origin,
    );
  }

  /// Content bounds padded to a page-like shape, never smaller than a
  /// readable minimum.
  static Rect _frame(List<Rect> bounds) {
    if (bounds.isEmpty) return const Rect.fromLTWH(0, 0, 480, 640);
    final content = bounds.reduce((a, b) => a.expandToInclude(b));
    const aspect = 0.75;
    var w = math.max(content.width * 1.1, 480.0);
    var h = math.max(content.height * 1.1, 480 / aspect);
    if (w / h > aspect) {
      h = w / aspect;
    } else {
      w = h * aspect;
    }
    return Rect.fromCenter(center: content.center, width: w, height: h);
  }
}
