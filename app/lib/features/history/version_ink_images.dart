import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../data/versions/work_slices.dart';
import '../../domain/stroke.dart';
import '../../ink/render/ink_sketch.dart';

/// What [VersionInkImages] renders: a sheet's [strokes], the part of the
/// world at [frame] (world units) scaled to [width] × [height] pixels.
typedef InkImageKey = ({List<Stroke> strokes, Rect frame, int width, int height});

/// The ink of the history's thumbnails of large content (a canvas of
/// tens of thousands of strokes), rendered at thumbnail resolution into
/// images, one after another in slices of work ([InkSketch]) as rows come
/// into view: so a frame draws an image, not 50,000 strokes.
///
/// Keeps the [maxCount] / [maxBytes] most recently used images, disposing
/// those it drops, and all of them on [dispose]. Callers get their own
/// handle ([ui.Image.clone]) to dispose.
class VersionInkImages {
  VersionInkImages(this._slices, {this.maxCount = 64, this.maxBytes = 32 << 20});

  final WorkSlices _slices;
  final int maxCount;
  final int maxBytes;

  /// Content with fewer strokes is painted directly (it costs a frame
  /// little, and keeps its look exact).
  static const minStrokes = 2000;

  final LinkedHashMap<InkImageKey, ui.Image> _images = LinkedHashMap();
  final Map<InkImageKey, _Job> _jobs = {};
  var _bytes = 0;
  var _disposed = false;
  Future<void> _queue = Future<void>.value();

  /// Bytes the kept images take.
  int get bytes => _bytes;

  /// The image of [key], or null when rendering it was given up (nobody
  /// [wanted] it any more, or this was disposed). The caller owns the
  /// returned handle.
  Future<ui.Image?> image(InkImageKey key, {required bool Function() wanted}) {
    final kept = _images.remove(key);
    if (kept != null) {
      _images[key] = kept;
      return Future.value(kept.clone());
    }
    final running = _jobs[key];
    final job = running != null && !running.givenUp ? running : _jobs[key] = _start(key);
    job.wanted.add(wanted);
    return job.done.future.then((image) => image?.clone());
  }

  _Job _start(InkImageKey key) {
    final job = _Job();
    _queue = _queue.then((_) async {
      ui.Image? image;
      try {
        image = await _render(key, job);
      } on Object {
        // Left blank (the next of the queue runs regardless).
        image = null;
      }
      if (identical(_jobs[key], job)) _jobs.remove(key);
      if (_disposed) {
        image?.dispose();
        image = null;
      }
      if (image != null) _keep(key, image);
      job.done.complete(image);
    });
    return job;
  }

  Future<ui.Image?> _render(InkImageKey key, _Job job) async {
    bool cancelled() => job.givenUp = _disposed || !job.wanted.any((w) => w());
    await _slices.yieldIfDue();
    if (cancelled()) return null;
    final scale = key.width / key.frame.width;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(-key.frame.left, -key.frame.top)
      ..clipRect(key.frame);
    final drawn = await InkSketch.draw(
      canvas,
      key.strokes,
      pixelScale: scale,
      slices: _slices,
      cancelled: cancelled,
    );
    final picture = recorder.endRecording();
    try {
      if (!drawn) return null;
      return await picture.toImage(key.width, key.height);
    } finally {
      picture.dispose();
    }
  }

  void _keep(InkImageKey key, ui.Image image) {
    _images[key] = image;
    _bytes += image.width * image.height * 4;
    while (_images.length > maxCount || (_bytes > maxBytes && _images.length > 1)) {
      final oldest = _images.keys.first;
      final dropped = _images.remove(oldest)!;
      _bytes -= dropped.width * dropped.height * 4;
      dropped.dispose();
    }
  }

  /// Disposes the kept images; renders running stop.
  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _bytes = 0;
  }
}

class _Job {
  /// Whether nobody wanted it any more (a new ask starts anew).
  var givenUp = false;
  final List<bool Function()> wanted = [];
  final Completer<ui.Image?> done = Completer();
}
