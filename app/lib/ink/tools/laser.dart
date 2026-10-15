import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'laser_config.dart';
import 'pointer_tool.dart';

export 'laser_config.dart';

/// The laser pointer: the dot under the pointer and its fading trail.
/// Never persisted: points simply expire [lifetime] after they were drawn,
/// or, with [LaserFade.pause] ([holding]), all together: the whole trail
/// and the dot stay while writing and fade over [holdFade] once
/// [LaserConfig.hold] has passed since the last lift (a press before then
/// keeps everything).
///
/// Points live in a fixed-size ring buffer (typed arrays, no per-sample
/// allocation); when it is full the oldest point is overwritten. Time comes
/// from frames ([tick], called by a ticker only while [isVisible]): a point
/// is stamped with the time of the frame that first shows it. Frame time is
/// monotonic and needs no wall clock (and tests' fake time drives it).
class LaserTrail extends ChangeNotifier {
  LaserTrail({this.capacity = 4096})
    : _x = Float64List(capacity),
      _y = Float64List(capacity),
      _t = Float64List(capacity),
      _starts = Uint8List(capacity);

  /// The most points kept (seconds of fast stylus input; a held trail
  /// loses its oldest points past it).
  final int capacity;

  /// How the laser looks; taken from the tool settings when a gesture
  /// starts. Switching how the trail fades ([holding]) while it shows
  /// changes nothing abruptly: a held trail fades on from where it is, one
  /// fading after each stroke goes on fading so beneath what is held next.
  LaserConfig get config => _config;
  LaserConfig _config = const LaserConfig();
  set config(LaserConfig next) {
    if (next == _config) return;
    final wasHolding = holding, head = headAlpha;
    _config = next;
    if (holding == wasHolding || !isVisible) return;
    if (wasHolding) {
      // Every held point fades on from the held trail's opacity.
      final alpha = _held;
      for (var i = _legacy; i < _length; i++) {
        final k = _index(i);
        if (_t[k] != _pending) _t[k] = _now - (1 - alpha) * lifetime.inMilliseconds;
      }
      _legacy = 0;
    } else {
      _legacy = _length;
    }
    // The dot fades on from where it was.
    if (_liftedAt != null) _liftedAt = _now - (1 - head) * _headFade.inMilliseconds;
    notifyListeners();
  }

  /// How long the dot takes to fade after the pointer lifts in dot mode.
  static const Duration dotFade = Duration(milliseconds: 350);

  /// How long a held trail ([holding]) takes to fade once it goes.
  static const Duration holdFade = Duration(milliseconds: 400);

  final Float64List _x, _y, _t;
  final Uint8List _starts;
  int _first = 0;
  int _length = 0;
  double _now = 0;

  Offset? _head;
  bool _pressed = false;

  /// A mouse hovers with the laser: the dot follows it, unpressed.
  bool _hovering = false;

  /// The oldest points, drawn before the trail began to be held
  /// ([holding]), which still fade each on its own.
  int _legacy = 0;

  /// Frame time the pointer lifted ([_pending] until the next frame).
  double? _liftedAt;

  /// Frame time of the last lift of a press ([_pending] until the next
  /// frame; null while pressed): a held trail fades from it. Unlike
  /// [_liftedAt], hovering doesn't reset it.
  double? _releasedAt;

  /// The held trail's opacity as of the last frame.
  double _heldAlpha = 1;

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
  double alphaAt(int i) => holding && i >= _legacy ? _held : _fade(_t[_index(i)], lifetime);

  /// Whether the trail is held while writing and fades all together
  /// ([LaserFade.pause]).
  bool get holding => config.mode == LaserMode.trail && config.fade == LaserFade.pause;

  /// Opacity of a held trail: 1 while pressed and for [LaserConfig.hold]
  /// after the last lift, then fading over [holdFade].
  double get _held {
    final released = _releasedAt;
    if (_pressed || released == null || released == _pending) return 1;
    final fading = _now - released - config.hold.inMilliseconds;
    return (1 - fading / holdFade.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Where the dot is (world), while it shows.
  Offset? get head => _head;

  /// Opacity of the dot: 1 while the pointer is down or a mouse hovers,
  /// then fading.
  double get headAlpha {
    if (_head == null) return 0;
    if (_pressed || _hovering) return 1;
    if (holding) {
      // With the trail while it is held, else fading like the dot alone.
      final own = _fade(_liftedAt ?? _pending, dotFade);
      return _length > _legacy ? math.max(_held, own) : own;
    }
    return _fade(_liftedAt ?? _pending, _headFade);
  }

  /// How long the dot takes to fade on its own after a lift.
  Duration get _headFade => holding || config.mode == LaserMode.dot ? dotFade : lifetime;

  double _fade(double time, Duration over) =>
      time == _pending ? 1 : (1 - (_now - time) / over.inMilliseconds).clamp(0.0, 1.0);

  int _index(int i) => (_first + i) % capacity;

  /// Whether a hovering mouse shows the dot ([hover]).
  bool get hovering => _hovering;

  /// A mouse hovers at [world] (a presenter pointing without pressing):
  /// the dot follows it, leaving no trail. Null: it left; the dot fades.
  void hover(Offset? world) {
    if (world == null) {
      if (!_hovering) return;
      _hovering = false;
      if (!_pressed) _liftedAt = _pending;
      notifyListeners();
      return;
    }
    if (_pressed) return; // The press draws.
    _hovering = true;
    _liftedAt = null;
    _head = world;
    notifyListeners();
  }

  /// The pointer went down at [world].
  void down(Offset world) {
    _pressed = true;
    _liftedAt = null;
    _releasedAt = null;
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
    _releasedAt = _pending;
    notifyListeners();
  }

  void _push(Offset world, {required bool start}) {
    final int k;
    if (_length == capacity) {
      k = _first;
      _first = (_first + 1) % capacity;
      if (_legacy > 0) _legacy--;
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
    if (_releasedAt == _pending) _releasedAt = nowMs;
    final cutoff = nowMs - lifetime.inMilliseconds;
    if (holding) {
      while (_legacy > 0 && _t[_first] != _pending && _t[_first] <= cutoff) {
        _first = (_first + 1) % capacity;
        _length--;
        _legacy--;
      }
      final alpha = _held;
      if (alpha == 0) _length = _legacy; // Faded: all that was held goes.
      // While it is held in full, frames change nothing.
      final still = _length > 0 && _legacy == 0 && !_pressed && alpha == 1 && _heldAlpha == 1;
      _heldAlpha = alpha;
      if (!_pressed && headAlpha == 0) _head = null;
      if (!still) notifyListeners();
      return;
    }
    while (_length > 0 && _t[_first] != _pending && _t[_first] <= cutoff) {
      _first = (_first + 1) % capacity;
      _length--;
    }
    if (!_pressed && headAlpha == 0) _head = null;
    notifyListeners();
  }

  /// Whether frames change anything: trail points fading or the dot
  /// fading. A dot held still (pressed or hovering) needs none.
  /// A held trail needs them only once lifted, to count down and fade.
  bool get animating =>
      (holding ? _length > 0 && !_pressed || _legacy > 0 : _length > 0) ||
      (_head != null && !_pressed && !_hovering && headAlpha > 0);

  /// Moves the trail and the dot by [delta] (world units): the surface
  /// whose coordinates they are in changed, not where they show.
  void shift(Offset delta) {
    if (delta == Offset.zero) return;
    for (var i = 0; i < _length; i++) {
      final k = _index(i);
      _x[k] += delta.dx;
      _y[k] += delta.dy;
    }
    final head = _head;
    if (head != null) _head = head + delta;
    notifyListeners();
  }

  void clear() {
    _first = 0;
    _length = 0;
    _legacy = 0;
    _head = null;
    _pressed = false;
    _hovering = false;
    _liftedAt = null;
    _releasedAt = null;
    _heldAlpha = 1;
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
