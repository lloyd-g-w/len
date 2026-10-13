import '../../domain/chunk_grid.dart';
import '../../domain/stroke.dart';

/// What a raster cache (`ChunkRasterCache`) knows about each chunk's
/// content: a version number that changes with every change, the pen
/// strokes appended since its images were made (drawn over them until
/// fresh ones arrive) and whether it was edited while it had no image.
class ChunkVersions {
  /// Content version per chunk; any change gets a fresh number from
  /// [_counter], and chunks without an entry are at [_epoch].
  final Map<ChunkKey, int> _versions = {};
  int _counter = 0;
  int _epoch = 0;

  /// Pen strokes appended to a chunk, with the version that added them.
  final Map<ChunkKey, List<(int, Stroke)>> _overlays = {};

  /// Chunks edited (not just loaded) while they had no image: until one is
  /// made, only their vectors show them as they are.
  final Set<ChunkKey> edited = {};

  /// [chunk]'s current content version.
  int of(ChunkKey chunk) => _versions[chunk] ?? _epoch;

  /// Gives [chunk] a new version (its content changed) and returns it.
  /// Unless [keepOverlay], strokes appended before are forgotten (the
  /// images showing the chunk are gone).
  int bump(ChunkKey chunk, {bool keepOverlay = false}) {
    if (!keepOverlay) _overlays.remove(chunk);
    return _versions[chunk] = ++_counter;
  }

  /// Every chunk changed.
  void bumpAll() {
    _overlays.clear();
    _versions.clear();
    _epoch = ++_counter;
  }

  /// Records [strokes] appended to [chunk] at [version], to draw over its
  /// older images.
  void append(ChunkKey chunk, int version, Iterable<Stroke> strokes) =>
      (_overlays[chunk] ??= []).addAll([for (final s in strokes) (version, s)]);

  /// Strokes appended to [chunk] after version [made].
  List<Stroke> overlay(ChunkKey chunk, int made) => [
    for (final (version, s) in _overlays[chunk] ?? const <(int, Stroke)>[])
      if (version > made) s,
  ];

  /// Forgets strokes appended to [chunk] up to version [oldest] (every
  /// image of it includes them).
  void trim(ChunkKey chunk, int oldest) {
    final overlay = _overlays[chunk];
    if (overlay == null) return;
    overlay.removeWhere((e) => e.$1 <= oldest);
    if (overlay.isEmpty) _overlays.remove(chunk);
  }
}
