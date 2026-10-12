import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'laser_config.dart';
import 'pointer_tool.dart';

export 'laser_config.dart';

/// The laser pointer: the dot under the pointer and its fading trail.
/// Never persisted: points simply expire [lifetime] after they were drawn.
///
/// Points live in a fixed-size ring buffer (typed arrays, no per-sample
/// allocation); when it is full the oldest point is overwritten. Time comes
/// from frames ([tick], called by a ticker only while [isVisible]): a point
/// is stamped with the time of the frame that first shows it. Frame time is
/// monotonic and needs no wall clock (and tests' fake time drives it).
class LaserTrail extends ChangeNotifier {
  LaserTrail({this.capacity = 1024})
    : _x = Float64List(capacity),
      _y = Float64List(capacity),
      _t = Float64List(capacity),
      _starts = Uint8List(capacity);

  /// The most points kept (seconds of fast stylus input).
  final int capacity;

  /// How the laser looks; taken from the tool settings when a gesture starts.
  LaserConfig config = const LaserConfig();

  /// How long the dot takes to fade after the pointer lifts in dot mode.
  static const Duration dotFade = Duration(milliseconds: 350);

  final Float64List _x, _y, _t;
  final Uint8List _starts;
  int _first = 0;
  int _length = 0;
  double _now = 0;

  Offset? _head;
  bool _pressed = false;

  /// Frame time the pointer lifted ([_pending] until the next frame).
  double? _liftedAt;

  static const double _pending = -1;

  /// How long a trail point stays visible.
  Duration get lifetime => config.duration;

  /// Number of trail points (oldest first).
  int get length => _length;
  bool get isEmpty => _length == 0;

  /// Whether anything shows: trail points, or the dot.
  bool get isVisible => _length > 0 || headAlpha > 0;

  /// Time of the latest frame (ms).
  double get now => _now;

  /// Point [i] (world), oldest first.
  Offset pointAt(int i) {
    final k = _index(i);
    return Offset(_x[k], _y[k]);
  }

  /// Whether point [i] starts a new stroke of the trail (not joined to i − 1).
  bool startsAt(int i) => i == 0 || _starts[_index(i)] == 1;

  /// Opacity (1 → 0) of point [i] as of [now].
  double alphaAt(int i) => _fade(_t[_index(i)], lifetime);

  /// Where the dot is (world), while it shows.
  Offset? get head => _head;

  /// Opacity of the dot: 1 while the pointer is down, then fading.
  double get headAlpha {
    if (_head == null) return 0;
    if (_pressed) return 1;
    return _fade(_liftedAt ?? _pending, config.mode == LaserMode.dot ? dotFade : lifetime);
  }

  double _fade(double time, Duration over) =>
      time == _pending ? 1 : (1 - (_now - time) / over.inMilliseconds).clamp(0.0, 1.0);

  int _index(int i) => (_first + i) % capacity;

  /// The pointer went down at [world].
  void down(Offset world) {
    _pressed = true;
    _liftedAt = null;
    _head = world;
    if (config.mode == LaserMode.trail) _push(world, start: true);
    notifyListeners();
  }

  /// The pointer moved to [world]; with [record] false only the dot moves.
  void move(Offset world, {bool record = true}) {
    _head = world;
    if (record && config.mode == LaserMode.trail) _push(world, start: _length == 0);
    notifyListeners();
  }

  /// The pointer lifted: the dot fades.
  void up() {
    if (!_pressed) return;
    _pressed = false;
    _liftedAt = _pending;
    notifyListeners();
  }

  void _push(Offset world, {required bool start}) {
    final int k;
    if (_length == capacity) {
      k = _first;
      _first = (_first + 1) % capacity;
    } else {
      k = _index(_length++);
    }
    _x[k] = world.dx;
    _y[k] = world.dy;
    _t[k] = _pending;
    _starts[k] = start ? 1 : 0;
  }

  /// Advances to frame time [nowMs]: stamps new points and drops expired
  /// ones. Call every frame while [isVisible].
  void tick(double nowMs) {
    _now = nowMs;
    for (var i = _length - 1; i >= 0; i--) {
      final k = _index(i);
      if (_t[k] != _pending) break;
      _t[k] = nowMs;
    }
    if (_liftedAt == _pending) _liftedAt = nowMs;
    final cutoff = nowMs - lifetime.inMilliseconds;
    while (_length > 0 && _t[_first] != _pending && _t[_first] <= cutoff) {
      _first = (_first + 1) % capacity;
      _length--;
    }
    if (!_pressed && headAlpha == 0) _head = null;
    notifyListeners();
  }

  void clear() {
    _first = 0;
    _length = 0;
    _head = null;
    _pressed = false;
    _liftedAt = null;
    notifyListeners();
  }
}

/// Moves a [LaserTrail] with the pointer.
class LaserTool implements PointerTool {
  LaserTool(this.trail, {this._config});

  final LaserTrail trail;
  final LaserConfig Function()? _config;

  /// The last screen position added to the trail.
  Offset? _last;

  /// Samples closer than this (screen pixels) to the last recorded one only
  /// move the dot.
  static const double minGap = 1.5;

  @override
  void down(ToolPointer p) {
    if (_config case final config?) trail.config = config();
    _last = p.screen;
    trail.down(p.world);
  }

  @override
  void move(ToolPointer p) {
    final last = _last;
    final record = last == null || (p.screen - last).distance >= minGap;
    if (record) _last = p.screen;
    trail.move(p.world, record: record);
  }

  @override
  void up() => trail.up();

  @override
  void cancel() => trail.up();
}
