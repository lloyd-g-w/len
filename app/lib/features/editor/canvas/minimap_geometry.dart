import 'dart:math' as math;
import 'dart:ui';

import '../../../domain/chunk_grid.dart';

/// One block of a minimap: a world rectangle holding content and how dense
/// it is (0–1).
typedef MinimapCell = ({Rect rect, double weight});

/// What a minimap shows of a canvas's content: its populated chunks
/// ([ChunkGrid]) merged into at most [maxCells] × [maxCells] blocks, so
/// painting it costs the same however large the canvas grows.
class MinimapContent {
  MinimapContent._(this.bounds, this.cells, this.cellSize);

  /// Merges the chunks of [density] (items per chunk, as
  /// `StrokeReader.chunkDensity` reads them) into blocks.
  factory MinimapContent.fromDensity(Map<ChunkKey, int> density, {int maxCells = defaultCells}) {
    if (density.isEmpty) return empty;
    var minX = 1 << 30, minY = 1 << 30, maxX = -(1 << 30), maxY = -(1 << 30);
    for (final key in density.keys) {
      minX = math.min(minX, key.x);
      minY = math.min(minY, key.y);
      maxX = math.max(maxX, key.x);
      maxY = math.max(maxY, key.y);
    }
    // Chunks per block: the content's longer side spans at most maxCells.
    final span = math.max(maxX - minX + 1, maxY - minY + 1);
    final per = (span / maxCells).ceil();
    final columns = (maxX - minX) ~/ per + 1;
    final sums = <int, int>{};
    density.forEach((key, n) {
      final cell = ((key.y - minY) ~/ per) * columns + (key.x - minX) ~/ per;
      sums[cell] = (sums[cell] ?? 0) + n;
    });
    final size = ChunkGrid.size * per;
    final origin = Offset(minX * ChunkGrid.size, minY * ChunkGrid.size);
    // A full block holds denseChunk items in each of its chunks.
    final full = denseChunk * per * per;
    final cells = <MinimapCell>[
      for (final MapEntry(key: cell, value: n) in sums.entries)
        (
          rect: Rect.fromLTWH(
            origin.dx + (cell % columns) * size,
            origin.dy + (cell ~/ columns) * size,
            size,
            size,
          ),
          weight: math.sqrt(math.min(1, n / full)),
        ),
    ];
    final bounds = Rect.fromLTRB(
      origin.dx,
      origin.dy,
      (maxX + 1) * ChunkGrid.size,
      (maxY + 1) * ChunkGrid.size,
    );
    return MinimapContent._(bounds, cells, size);
  }

  /// No content at all.
  static final MinimapContent empty = MinimapContent._(null, const [], ChunkGrid.size);

  /// Blocks along the content's longer side, at most.
  static const int defaultCells = 48;

  /// Items in a chunk at which its block is drawn at full strength.
  static const int denseChunk = 24;

  /// The populated chunks' bounds (null: nothing on the canvas).
  final Rect? bounds;

  /// The blocks, each [cellSize] square.
  final List<MinimapCell> cells;
  final double cellSize;

  bool get isEmpty => bounds == null;
}

/// Which part of the world a minimap shows: the content and the view, with
/// room around them. It holds still while the view moves inside it, so the
/// map doesn't swim under a pan, and refits only when the view leaves it or
/// it has grown far larger than needed.
abstract final class MinimapFrame {
  /// Room around content and view, as a share of their larger side.
  static const double margin = 0.12;

  /// A frame more than this many times as wide as needed (margin included)
  /// is refitted: content stays large on the map after zooming in.
  static const double slack = 1.8;

  /// The world rectangle (of [aspect] = width / height) to show for
  /// [content] and [view], keeping [previous] where it still works.
  static Rect next({
    Rect? previous,
    required Rect? content,
    required Rect view,
    double aspect = 1.5,
  }) {
    final needed = content == null ? view : content.expandToInclude(view);
    final room = math.max(needed.width, needed.height) * margin;
    final fitted = _fitAspect(needed.inflate(room), aspect);
    if (previous != null && _contains(previous, needed) && previous.width <= fitted.width * slack) {
      return previous;
    }
    return fitted;
  }

  static bool _contains(Rect outer, Rect inner) =>
      outer.left <= inner.left &&
      outer.top <= inner.top &&
      outer.right >= inner.right &&
      outer.bottom >= inner.bottom;

  /// [r] grown along one side to [aspect], about its centre.
  static Rect _fitAspect(Rect r, double aspect) {
    final w = math.max(r.width, r.height * aspect);
    return Rect.fromCenter(
      center: r.center,
      width: math.max(w, 1),
      height: math.max(w / aspect, 1),
    );
  }
}

/// Maps a world rectangle into a minimap box of [size], uniformly scaled
/// and centred.
class MinimapProjection {
  MinimapProjection(this.world, this.size) {
    final fit = math.min(size.width / world.width, size.height / world.height);
    scale = fit.isFinite && fit > 0 ? fit : 1;
    origin = size.center(Offset.zero) - world.center * scale;
  }

  /// The world area shown.
  final Rect world;
  final Size size;

  /// Map pixels per world unit.
  late final double scale;
  late final Offset origin;

  Offset toMap(Offset world) => origin + world * scale;
  Rect rectToMap(Rect world) => Rect.fromPoints(toMap(world.topLeft), toMap(world.bottomRight));
  Offset toWorld(Offset map) => (map - origin) / scale;
}

/// The minimap's own viewport, when the user zooms or pans it: a world
/// rectangle inside the frame that fits everything ([MinimapFrame]), of its
/// aspect, at most [maxZoom] times closer. Gestures on the map change it;
/// the canvas's view never does (only [follow] nudges it along).
abstract final class MinimapView {
  /// The narrowest area shown, in content blocks across: closer, a block
  /// would fill the map and show nothing more.
  static const double minBlocks = 3;

  /// The fit can always be zoomed this much at least.
  static const double minZoom = 2;

  /// How far the view's centre stays inside the map's edges when [follow]
  /// keeps it in, as a share of the area shown.
  static const double followInset = 0.1;

  /// The closest zoom over [fit] for blocks [cellSize] wide.
  static double maxZoom(Rect fit, double cellSize) =>
      math.max(minZoom, fit.width / (cellSize * minBlocks));

  /// [shown] scaled by [factor] (> 1 closer) and moved so the world point
  /// that was under [from] (map pixels, on a map of [size]) comes under
  /// [to], kept between [fit] and [maxZoom] times closer, within [fit].
  static Rect transform(
    Rect shown, {
    required Size size,
    required Rect fit,
    required double maxZoom,
    required Offset from,
    required Offset to,
    double factor = 1,
  }) {
    final before = MinimapProjection(shown, size);
    final grabbed = before.toWorld(from);
    final width = (shown.width / factor).clamp(fit.width / maxZoom, fit.width);
    final height = width * shown.height / shown.width;
    final after = MinimapProjection(
      Rect.fromCenter(center: Offset.zero, width: width, height: height),
      size,
    );
    final centre = grabbed - (to - size.center(Offset.zero)) / after.scale;
    return clampInto(Rect.fromCenter(center: centre, width: width, height: height), fit);
  }

  /// [shown] moved as little as needed to keep [view]'s centre inside it
  /// (inset by [followInset]), within [fit].
  static Rect follow(Rect shown, Rect fit, Rect view) {
    final inner = shown.deflate(math.min(shown.width, shown.height) * followInset);
    final c = view.center;
    final dx = c.dx < inner.left
        ? c.dx - inner.left
        : c.dx > inner.right
        ? c.dx - inner.right
        : 0.0;
    final dy = c.dy < inner.top
        ? c.dy - inner.top
        : c.dy > inner.bottom
        ? c.dy - inner.bottom
        : 0.0;
    return clampInto(shown.shift(Offset(dx, dy)), fit);
  }

  /// Whether [view]'s centre is inside [shown] (inset as for [follow]).
  static bool tracks(Rect shown, Rect view) {
    final inner = shown.deflate(math.min(shown.width, shown.height) * followInset);
    final c = view.center;
    const e = 1e-6; // Edges included: where [follow] leaves the centre.
    return c.dx >= inner.left - e &&
        c.dx <= inner.right + e &&
        c.dy >= inner.top - e &&
        c.dy <= inner.bottom + e;
  }

  /// [r] moved into [bounds] (centred along a side it is longer on).
  static Rect clampInto(Rect r, Rect bounds) {
    double along(double lo, double size, double bLo, double bHi) =>
        size >= bHi - bLo ? (bLo + bHi - size) / 2 : lo.clamp(bLo, bHi - size);
    return Rect.fromLTWH(
      along(r.left, r.width, bounds.left, bounds.right),
      along(r.top, r.height, bounds.top, bounds.bottom),
      r.width,
      r.height,
    );
  }
}
