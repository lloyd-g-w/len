import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../tools/laser.dart';
import 'laser_ribbon.dart';
import 'laser_stroke.dart';
import 'outline_spec.dart';

/// The strokes of a [LaserTrail], each a [LaserStroke] kept between frames
/// and fed only the points recorded since the last frame, so a frame that
/// only fades the trail recomputes nothing but the opacities.
///
/// Rebuilt from the trail's points when what shapes them changes (size,
/// pressure sensitivity, stabiliser, ends) or the points move
/// ([LaserTrail.revision]).
class LaserStrokes {
  final List<LaserStroke> _strokes = [];
  int _revision = -1;
  LaserConfig? _config;
  OutlineSpec? _spec;

  /// The id of the next trail point to feed.
  int _next = 0;

  /// Number of strokes (tests).
  int get length => _strokes.length;

  /// The strokes, oldest first.
  @visibleForTesting
  List<LaserStroke> get strokes => _strokes;

  /// Brings the strokes up to date with [trail], new strokes begun at
  /// [scale] (the viewport's: screen pixels per world unit).
  void sync(LaserTrail trail, double scale) {
    final config = trail.config;
    if (trail.revision != _revision || !_sameShape(config, _config)) {
      _strokes.clear();
      _revision = trail.revision;
      _config = config;
      _spec = null;
      _next = trail.firstId;
    }
    final first = trail.firstId;
    var expired = 0;
    while (expired < _strokes.length && _strokes[expired].lastId < first) {
      expired++;
    }
    if (expired > 0) _strokes.removeRange(0, expired);
    for (var i = math.max(0, _next - first); i < trail.length; i++) {
      final id = first + i;
      final last = _strokes.isEmpty ? null : _strokes.last;
      if (last == null || last.lastId != id - 1 || trail.beganStrokeAt(i)) {
        last?.end();
        _strokes.add(LaserStroke(_specAt(config, scale), 1 / scale));
      }
      final p = trail.pointAt(i);
      _strokes.last.add(id, p.dx, p.dy, trail.pressureAt(i));
    }
    _next = first + trail.length;
    if (!trail.pressed && _strokes.isNotEmpty) _strokes.last.end();
  }

  /// Draws every stroke into [glow] and [core] at the trail's opacities,
  /// mapped to the screen by `world × scale + (ox, oy)`.
  void emit(
    LaserRibbon glow,
    LaserRibbon core,
    LaserTrail trail, {
    required double glowScale,
    required double scale,
    double ox = 0,
    double oy = 0,
  }) {
    final first = trail.firstId;
    double alphaOf(int id) {
      final i = id - first;
      return i < 0 || i >= trail.length ? 0 : trail.alphaAt(i);
    }

    for (final stroke in _strokes) {
      stroke.emit(glow, core, alphaOf: alphaOf, glowScale: glowScale, scale: scale, ox: ox, oy: oy);
    }
  }

  /// One spec for the strokes begun at one zoom (its shape parameters are
  /// worked out once).
  OutlineSpec _specAt(LaserConfig config, double scale) {
    final unit = 1 / scale;
    final spec = _spec;
    if (spec != null && spec.unit == unit) return spec;
    return _spec = LaserStroke.specFor(config, unit);
  }

  static bool _sameShape(LaserConfig a, LaserConfig? b) =>
      b != null &&
      a.mode == b.mode &&
      a.size == b.size &&
      a.thinning == b.thinning &&
      a.streamline == b.streamline &&
      a.ends == b.ends;
}
