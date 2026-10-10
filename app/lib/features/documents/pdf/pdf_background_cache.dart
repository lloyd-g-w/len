import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../data/blob_store.dart';
import '../../../domain/notebook_page.dart';
import '../../editor/document/page_backgrounds.dart';
import 'pdf_renderer.dart';

typedef _Key = ({PageBackground background, int width});

/// Renders PDF page backgrounds on demand, at a resolution matching the
/// current zoom, and caches the results (least recently used first out).
///
/// Resolutions are quantised to steps of √2, so zooming re-renders a page
/// only a few times; until a sharper image is ready, the best cached one is
/// shown. Blobs not yet on this device are fetched through [fetch].
class PdfBackgroundCache extends ChangeNotifier implements PageBackgrounds {
  PdfBackgroundCache({
    required this.blobs,
    required this.fetch,
    PdfRenderer? renderer,
    this.budgetBytes = 160 << 20,
  }) : _renderer = renderer ?? PdfRenderer();

  final BlobStore blobs;

  /// Downloads a blob; returns whether it is available now.
  final Future<bool> Function(String sha) fetch;

  /// Memory budget for cached images (4 bytes per pixel).
  final int budgetBytes;

  final PdfRenderer _renderer;
  final LinkedHashMap<_Key, ui.Image> _images = LinkedHashMap();
  final Set<_Key> _pending = {};
  final Map<PageBackground, int> _wanted = {};
  final Set<String> _fetching = {};
  final Set<String> _missing = {};
  bool _disposed = false;

  static const int minWidth = 256;
  static const int maxWidth = 2896;

  /// The rendering width used for a requested [pixelWidth].
  static int bucketFor(double pixelWidth) {
    if (!pixelWidth.isFinite || pixelWidth <= minWidth) return minWidth;
    final steps = (2 * math.log(pixelWidth / minWidth) / math.ln2).ceil();
    return math.min(maxWidth, (minWidth * math.pow(math.sqrt2, steps)).round());
  }

  @override
  ui.Image? imageFor(PageBackground background, double pixelWidth) {
    final key = (background: background, width: bucketFor(pixelWidth));
    final hit = _images.remove(key);
    if (hit != null) {
      _images[key] = hit; // Most recently used.
      return hit;
    }
    _wanted[background] = key.width;
    if (_pending.add(key)) unawaited(_render(key));
    return _bestFor(background);
  }

  @override
  bool isMissing(PageBackground background) => _missing.contains(background.blob);

  /// Forgets that blobs were unavailable, e.g. after a sync.
  void retryMissing() {
    if (_missing.isEmpty) return;
    _missing.clear();
    notifyListeners();
  }

  ui.Image? _bestFor(PageBackground background) {
    ui.Image? best;
    for (final entry in _images.entries) {
      if (entry.key.background != background) continue;
      if (best == null || entry.value.width > best.width) best = entry.value;
    }
    return best;
  }

  Future<void> _render(_Key key) async {
    final sha = key.background.blob;
    try {
      if (!blobs.has(sha)) {
        if (_missing.contains(sha) || !_fetching.add(sha)) return;
        final ok = await fetch(sha);
        _fetching.remove(sha);
        if (!ok) _missing.add(sha);
        if (!_disposed) notifyListeners(); // Repaint re-requests the image.
        return;
      }
      final image = await _renderer.render(
        sha,
        blobs.fileOf(sha).path,
        key.background.pageIndex,
        key.width,
        stillWanted: () => !_disposed && _wanted[key.background] == key.width,
      );
      if (image == null) return;
      if (_disposed) {
        image.dispose();
        return;
      }
      _images[key] = image;
      _evict();
      notifyListeners();
    } catch (e) {
      debugPrint('Cannot render PDF page ${key.background.pageIndex} of $sha: $e');
      _missing.add(sha);
    } finally {
      _pending.remove(key);
    }
  }

  void _evict() {
    var bytes = _images.values.fold<int>(0, (sum, i) => sum + i.width * i.height * 4);
    while (bytes > budgetBytes && _images.length > 1) {
      final oldest = _images.keys.first;
      final image = _images.remove(oldest)!;
      bytes -= image.width * image.height * 4;
      image.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _renderer.dispose();
    super.dispose();
  }
}
