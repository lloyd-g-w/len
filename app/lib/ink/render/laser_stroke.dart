import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../domain/stroke.dart';
import '../tools/laser_config.dart';
import 'laser_ribbon.dart';
import 'outline_spec.dart';
import 'stroke_shaper.dart';

/// One stroke of the laser trail (pointer down to up), shaped by the pen's
/// engine: [StrokeShaper] samples, smooths (the stabiliser), sizes (pressure
/// sensitivity) and tapers it exactly as it does a pen stroke, incrementally
/// (each frame only the tail is recomputed; a finished stroke never again).
/// [emit] then draws it as the laser's soft glow and core ([LaserRibbon])
/// rather than a filled outline, with the trail's fade per point and round
/// caps unless the ends are flat.
///
/// Points are in world units; the stroke is as wide on screen as the
/// laser's size whatever the zoom ([unit]: world units per screen pixel
/// when it began).
class LaserStroke {
  LaserStroke(this.spec, this.unit) : _shaper = StrokeShaper(spec.paramsFor(unit));

  /// The outline parameters of strokes of [config] begun at [unit] world
  /// units per screen pixel: the laser's size as the width, its pressure
  /// sensitivity, stabiliser and ends.
  static OutlineSpec specFor(LaserConfig config, double unit) {
    final width = config.size * unit;
    return OutlineSpec(
      width: width,
      thinning: config.thinning,
      streamline: config.streamline,
      flatCaps: config.ends.style == StrokeEnds.flat,
      unit: unit,
      taperStart: config.ends.taperStart * width,
      taperEnd: config.ends.taperEnd * width,
    );
  }

  final OutlineSpec spec;
  final double unit;

  StrokeShaper _shaper;

  /// The engine shaping the stroke (after [update]).
  @visibleForTesting
  StrokeShaper get shaper => _shaper;

  /// The trail id (`LaserTrail.idAt`) of each input sample of [_shaper].
  final List<int> _ids = [];

  /// The id of the last point added.
  int lastId = -1;

  /// Whether the stroke is complete (the pointer lifted or a new stroke
  /// began): its end taper forms, and it is never recomputed again.
  bool get ended => _ended;
  bool _ended = false;

  bool _dirty = false;

  /// The first input sample still showing (see [emit]).
  int _from = 0;

  /// Fewest expired input samples before the shaper is rebuilt from the
  /// ones still showing (a long press keeps memory bounded).
  static const int rebaseAfter = 1024;

  /// Screen pixels between the points fed to the ribbons (the shaper's
  /// samples are a fraction of a pixel apart; the ribbons' vertices are
  /// most of a frame's cost): [drawStep] along the line, but every
  /// [fineStep] where the width changes by [widthChange] (tapers, pressure).
  static const double drawStep = 4, fineStep = 1, widthChange = 0.35;

  /// Adds the point [id] at ([x], [y]) (world) with [pressure].
  void add(int id, double x, double y, double pressure) {
    assert(!_ended);
    final before = _shaper.inputCount;
    _shaper.add(x, y, spec.radiusFor(pressure));
    if (_shaper.inputCount > before) _ids.add(id);
    lastId = id;
    _dirty = true;
  }

  /// The stroke is complete.
  void end() {
    if (_ended) return;
    _ended = true;
    _dirty = true;
  }

  /// Brings the line up to date with the points added (nothing when none
  /// were since the last call).
  void update() {
    if (!_dirty) return;
    _dirty = false;
    if (_ended) {
      // The whole line (a laser's pen-up hook stays: nothing is kept).
      _shaper.taperEnd = spec.taperEnd;
      _shaper.update(ended: true);
    } else {
      _shaper.update();
    }
  }

  /// Number of samples drawn: all of a complete stroke; of one being drawn,
  /// what live ink shows (with the stabiliser on it trails the pointer).
  int get _shown => _ended ? _shaper.length : _shaper.liveLength;

  // Reused between frames.
  final List<double> _x = [], _y = [], _a = [], _w = [];

  /// Draws the stroke into [glow] and [core] ([glowScale] × the core's
  /// width), mapped to the screen by `world × scale + (ox, oy)`, each point
  /// at the opacity [alphaOf] gives its trail id (0: expired). The expired
  /// start is skipped, keeping one point to fade from.
  void emit(
    LaserRibbon glow,
    LaserRibbon core, {
    required double Function(int id) alphaOf,
    required double glowScale,
    double scale = 1,
    double ox = 0,
    double oy = 0,
  }) {
    update();
    final count = _ids.length;
    while (_from + 1 < count && alphaOf(_ids[_from + 1]) <= 0) {
      _from++;
    }
    if (_from >= rebaseAfter && _from > count ~/ 2) _rebase();
    final n = _shown;
    if (n < 2) return;
    final s = _shaper;
    // Output sample j lies on input segment k (input samples k → k + 1)
    // from [_firstOf] k on.
    var k = math.max(_from, s.startSample);
    final j0 = k == s.startSample ? 0 : math.min(n, _firstOf(k, n));
    if (n - j0 < 2) return;
    final fine = math.max(1, (fineStep / (s.p.step * scale)).floor());
    final wide = math.max(fine, (drawStep / (s.p.step * scale)).floor());
    final toScreen = 1 / unit;
    _x.clear();
    _y.clear();
    _a.clear();
    _w.clear();
    var alphaK = alphaOf(_ids[k]);
    var alphaNext = k + 1 < count ? alphaOf(_ids[k + 1]) : alphaK;
    var segStart = k == s.startSample ? 0 : _firstOf(k, n);
    var segEnd = _firstOf(k + 1, n);
    final r = s.r;
    for (var j = j0; ;) {
      while (j >= segEnd && k + 1 < count && segEnd < n) {
        k++;
        alphaK = alphaNext;
        alphaNext = k + 1 < count ? alphaOf(_ids[k + 1]) : alphaK;
        segStart = segEnd;
        segEnd = _firstOf(k + 1, n);
      }
      final u = segEnd > segStart ? ((j - segStart) / (segEnd - segStart)).clamp(0.0, 1.0) : 0.0;
      _x.add(s.x[j] * scale + ox);
      _y.add(s.y[j] * scale + oy);
      _a.add(alphaK + (alphaNext - alphaK) * u);
      _w.add(r[j] * toScreen);
      if (j == n - 1) break;
      // A wide step, unless the width changes over it.
      final far = math.min(j + wide, n - 1);
      j = (r[far] - r[j]).abs() * toScreen < widthChange ? far : math.min(j + fine, n - 1);
    }
    final round = !spec.flatCaps;
    final capStart = round && j0 == 0;
    glow.add(_x, _y, _a, _w, scale: glowScale, capStart: capStart, capEnd: round);
    core.add(_x, _y, _a, _w, capStart: capStart, capEnd: round);
  }

  /// The first output sample after input sample [k] ([n] past the line).
  int _firstOf(int k, int n) => _shaper.firstSampleOf(k) ?? n;

  /// Rebuilds the shaper from the input samples still showing (the one
  /// before them as the spline's lead-in), its samples falling where they
  /// fell: what shows is unchanged but at the faded start.
  void _rebase() {
    final old = _shaper;
    final from = _from - 1;
    final params = OutlineSpec(
      width: spec.width,
      thinning: spec.thinning,
      streamline: spec.streamline,
      flatCaps: spec.flatCaps,
      unit: spec.unit,
    ).paramsFor(unit);
    final shaper = StrokeShaper(params, start: 1, phase: old.phaseAt(_from));
    for (var i = from; i < old.inputCount; i++) {
      shaper.add(old.inputX(i), old.inputY(i), old.inputR(i));
    }
    _ids.removeRange(0, from);
    _shaper = shaper;
    _from = 1;
    _dirty = true;
    update();
  }
}
