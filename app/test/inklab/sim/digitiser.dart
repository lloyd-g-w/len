import 'dart:math' as math;
import 'dart:ui';

import 'package:len/ink/input/stylus_batch.dart';
import 'package:len/ink/lab/input_recording.dart';

import '../metrics/truth.dart';
import 'pen_motion.dart';

/// How the simulated S Pen and Android deliver input.
class DigitiserModel {
  const DigitiserModel({
    this.sampleHz = 240,
    this.frameHz = 120,
    this.jitter = 0.08,
    this.pressureNoise = 0.01,
    this.pressureLevels = 4096,
    this.latencyMs = 4,
    this.devicePixelRatio = 2,
    this.batching = true,
    this.upSpike = 0.35,
    this.origin = const Offset(0, 64),
    this.viewSize = const Size(1000, 700),
    this.viewScale = 1,
    this.seed = 1,
  });

  /// Digitiser report rate and display refresh rate.
  final double sampleHz, frameHz;

  /// Positional noise (std dev, logical px) and pressure noise (0..1).
  final double jitter, pressureNoise;

  /// Pressure quantisation steps over 0..1.
  final int pressureLevels;

  /// Sample → app delivery delay.
  final double latencyMs;
  final double devicePixelRatio;

  /// Android-style batching: one `MotionEvent` per frame with historical
  /// samples on the stylus channel. Off: every sample is a pointer event
  /// (web, desktop).
  final bool batching;

  /// Extra pressure the pen-up event reports (a common digitiser artefact).
  final double upSpike;

  /// Where the drawing surface sits in the view (global = local + origin).
  final Offset origin;
  final Size viewSize;
  final double viewScale;
  final int seed;
}

/// One simulated contact: the true [motion] starting [start] seconds into
/// the recording, plus digitiser artefacts that are not part of the truth.
class SimContact {
  const SimContact(
    this.motion, {
    required this.start,
    this.downHook = false,
    this.upHook = false,
    this.bounce = false,
  });

  final PenMotion motion;
  final double start;

  /// A short flick in another direction as the pen lands / lifts.
  final bool downHook, upHook;

  /// An accidental re-contact right after the lift.
  final bool bounce;
}

/// The ground truth of [motion].
Truth truthOf(PenMotion motion) => Truth(
  path: motion.path(),
  pressure: motion.pressures(),
  cusps: [for (final t in motion.cusps) motion.at(t)],
  isTap: motion.duration < 0.08,
);

class _Sample {
  _Sample(this.timeUs, this.pos, this.pressure);
  final int timeUs;
  final Offset pos;
  final double pressure;
}

/// Generates a recording of [contacts] as the app on an Android tablet
/// would receive them (see [DigitiserModel]); returns it with the truth.
class Digitiser {
  Digitiser(this.model) : _rng = math.Random(model.seed);

  final DigitiserModel model;
  final math.Random _rng;
  static const int _baseUs = 5000000000;
  static const int _device = 2; // pointer 0, TOOL_TYPE_STYLUS

  ({InputRecording recording, List<Truth> truth}) record(
    List<SimContact> contacts, {
    required PenSettings pen,
    String note = '',
  }) {
    final strokes = <List<_Sample>>[];
    final truth = <Truth>[];
    for (final c in contacts) {
      strokes.add(_samples(c));
      truth.add(truthOf(c.motion));
      if (c.bounce) strokes.add(_bounce(c, strokes.last.last));
    }
    final events = _EventWriter(model, _device);
    for (final (i, s) in strokes.indexed) {
      events.contact(i + 1, s);
    }
    final meta = RecordingMeta(
      platform: 'sim',
      note: note,
      devicePixelRatio: model.devicePixelRatio,
      viewSize: model.viewSize,
      viewScale: model.viewScale,
      pen: pen,
    );
    return (recording: InputRecording(meta: meta, entries: events.finish()), truth: truth);
  }

  double _gauss() {
    final u = 1 - _rng.nextDouble(), v = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  double _report(double p) {
    final noisy = (p + _gauss() * model.pressureNoise).clamp(0.0, 1.0);
    return (noisy * model.pressureLevels).round() / model.pressureLevels;
  }

  Offset _noisy(Offset p) => p + Offset(_gauss(), _gauss()) * model.jitter;

  List<_Sample> _samples(SimContact c) {
    final m = c.motion;
    final dt = 1 / model.sampleHz;
    final startUs = _baseUs + (c.start * 1e6).round();
    final out = <_Sample>[];
    var t0 = 0.0;
    if (c.downHook) {
      // Lands 2.5 px off and flicks onto the path over three samples.
      final dir = m.at(0.02) - m.at(0);
      final hook = _rotate(dir / math.max(dir.distance, 1e-6), 2.2) * 2.5;
      for (var i = 0; i < 3; i++) {
        out.add(
          _Sample(
            startUs + (i * dt * 1e6).round(),
            _noisy(m.at(0) + hook * (1 - i / 3)),
            _report(0.15 + 0.05 * i),
          ),
        );
      }
      t0 = 3 * dt;
    }
    final n = (m.duration / dt).floor();
    for (var i = 0; i <= n; i++) {
      final t = math.min(m.duration, i * dt);
      out.add(_Sample(startUs + ((t0 + t) * 1e6).round(), _noisy(m.at(t)), _report(m.pressure(t))));
    }
    if (c.upHook) {
      final end = m.at(m.duration);
      final dir = end - m.at(math.max(0, m.duration - 0.02));
      final hook = _rotate(dir / math.max(dir.distance, 1e-6), -2.0) * 3;
      for (var i = 1; i <= 3; i++) {
        final t = t0 + m.duration + i * dt;
        out.add(
          _Sample(
            startUs + (t * 1e6).round(),
            _noisy(end + hook * (i / 3)),
            _report(0.2 - 0.05 * i),
          ),
        );
      }
    }
    // The up event: a hair further on (so Flutter synthesizes a move to
    // it), with spiked pressure.
    final last = out.last;
    final on = out.length > 1 ? last.pos - out[out.length - 2].pos : Offset.zero;
    final nudge = on.distance > 0 ? on / on.distance * 0.4 : const Offset(0.4, 0);
    out.add(
      _Sample(
        last.timeUs + (dt * 1e6).round(),
        last.pos + nudge,
        (last.pressure + model.upSpike).clamp(0, 1),
      ),
    );
    return out;
  }

  /// A brief re-contact 40 ms after [lift], almost where the pen lifted.
  List<_Sample> _bounce(SimContact c, _Sample lift) {
    final dtUs = (1e6 / model.sampleHz).round();
    return [
      for (var i = 0; i < 6; i++)
        _Sample(
          lift.timeUs + 40000 + i * dtUs,
          _noisy(lift.pos + const Offset(1, 0.5)),
          _report(0.12),
        ),
    ];
  }

  static Offset _rotate(Offset v, double a) =>
      Offset(v.dx * math.cos(a) - v.dy * math.sin(a), v.dx * math.sin(a) + v.dy * math.cos(a));
}

/// Turns sample streams into recording entries the way Android + Flutter
/// deliver them: immediate down/up, moves batched once per frame.
class _EventWriter {
  _EventWriter(this.model, this.device);

  final DigitiserModel model;
  final int device;
  final List<(int, int, InputEntry Function(int t))> _timeline = []; // (arrival, order, entry)
  int _order = 0;

  int get _latencyUs => (model.latencyMs * 1000).round();
  int get _frameUs => (1e6 / model.frameHz).round();

  void _at(int arrivalUs, InputEntry Function(int t) entry) =>
      _timeline.add((arrivalUs, _order++, entry));

  PointerEntry _pointer(
    int t,
    PointerType type,
    int pointer,
    _Sample s, {
    bool synthesized = false,
  }) {
    final global = s.pos + model.origin;
    return PointerEntry(
      t,
      type: type,
      kind: PointerDeviceKind.stylus,
      pointer: pointer,
      device: device,
      timeStampUs: s.timeUs,
      position: global,
      localPosition: s.pos,
      pressure: type == PointerType.hover ? 0 : s.pressure,
      buttons: type == PointerType.hover || type == PointerType.up ? 0 : 1,
      synthesized: synthesized,
    );
  }

  StylusSample _physical(_Sample s) {
    final g = (s.pos + model.origin) * model.devicePixelRatio;
    return StylusSample(timeUs: s.timeUs.toDouble(), x: g.dx, y: g.dy, pressure: s.pressure);
  }

  void contact(int pointer, List<_Sample> samples) {
    final down = samples.first, up = samples.last;
    // Hovering in: three hover events at 100 Hz before the pen lands.
    for (var i = 3; i >= 1; i--) {
      final s = _Sample(down.timeUs - i * 10000, down.pos + Offset(0, -i * 1.5), 0);
      _at(s.timeUs + _latencyUs, (t) => _pointer(t, PointerType.hover, pointer, s));
    }
    _at(down.timeUs + _latencyUs, (t) => _pointer(t, PointerType.down, pointer, down));
    final moves = samples.sublist(1, samples.length - 1);
    if (!model.batching) {
      for (final s in moves) {
        _at(s.timeUs + _latencyUs, (t) => _pointer(t, PointerType.move, pointer, s));
      }
    } else {
      _batchedMoves(pointer, down, moves, upArrival: up.timeUs + _latencyUs);
    }
    final upArrival = up.timeUs + _latencyUs;
    _at(upArrival, (t) => _pointer(t, PointerType.move, pointer, up, synthesized: true));
    _at(upArrival, (t) => _pointer(t, PointerType.up, pointer, up));
  }

  /// Groups [moves] into one MotionEvent per frame (the last flushed at the up).
  void _batchedMoves(int pointer, _Sample down, List<_Sample> moves, {required int upArrival}) {
    var i = 0;
    while (i < moves.length) {
      final arrival = moves[i].timeUs + _latencyUs;
      var dispatch = (arrival / _frameUs).ceil() * _frameUs;
      if (dispatch > upArrival) dispatch = upArrival;
      final batch = <_Sample>[];
      while (i < moves.length && moves[i].timeUs + _latencyUs <= dispatch) {
        batch.add(moves[i++]);
      }
      final last = batch.last;
      if (batch.length > 1) {
        final b = StylusBatch(
          device: device,
          downTimeUs: down.timeUs.toDouble(),
          eventTimeUs: last.timeUs.toDouble(),
          samples: [for (final s in batch) _physical(s)],
        );
        _at(dispatch, (t) => BatchEntry(t, [b]));
      }
      _at(dispatch, (t) => _pointer(t, PointerType.move, pointer, last));
    }
  }

  /// The entries in arrival order, with a frame after every vsync at which
  /// input arrived (and one more, which shows the committed stroke).
  List<InputEntry> finish() {
    _timeline.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    final start = _timeline.first.$1 - _frameUs;
    final out = <InputEntry>[];
    var nextFrame = (_timeline.first.$1 / _frameUs).ceil() * _frameUs;
    var dirty = 0;
    void frame() {
      out.add(FrameEntry(nextFrame - start + 500, vsyncUs: nextFrame));
    }

    for (final (arrival, _, make) in _timeline) {
      while (arrival > nextFrame) {
        if (dirty > 0) {
          frame();
          dirty--;
        }
        nextFrame += _frameUs;
      }
      out.add(make(arrival - start));
      dirty = 2;
    }
    while (dirty-- > 0) {
      frame();
      nextFrame += _frameUs;
    }
    return out;
  }
}
