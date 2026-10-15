import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/gestures.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/input/stylus_buttons.dart';
import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/recording_codec.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ink/viewport.dart';

/// The Ink Lab's real S Pen recordings (Galaxy Tab S8+, see
/// `docs/INK_LAB.md`): a minute or more of writing and sketching each.
const realRecordings = ['real_spen_01', 'real_spen_02'];

/// The recording [name] from `test/inklab/recordings/`.
InputRecording loadRecording(String name) =>
    RecordingCodec.decode(File('test/inklab/recordings/$name.leninput').readAsBytesSync());

/// The pen strokes of [recording]: stylus contacts that ink (no side
/// button, not cancelled, two samples or more), with their index in
/// [rawContacts] (the numbering the corpus labels use).
List<(int, RawContact)> penContacts(InputRecording recording) => [
  for (final (k, c) in rawContacts(recording).indexed)
    if (c.kind == PointerDeviceKind.stylus &&
        c.buttons & stylusSideButtons == 0 &&
        !c.cancelled &&
        c.samples.length > 1)
      (k, c),
];

/// Draws strokes through the real input pipeline ([InkInputController],
/// hold to snap and scribble to erase on) on fake time, one pointer event
/// per sample, at view scale 1 (world = screen).
class PenRig {
  PenRig() {
    viewport = ViewportController()..setSize(const Size(2400, 1600));
    input = InkInputController(model: model, viewport: viewport, tools: tools, live: live);
  }

  final AppDatabase _db = AppDatabase.inMemory();
  late final SurfaceModel model = SurfaceModel(
    surfaceId: 's',
    repository: StrokeRepository(_db, deviceId: 'd'),
  );
  final ToolSettings tools = ToolSettings(stylusOnly: true);
  final LiveInk live = LiveInk();
  late final ViewportController viewport;
  late final InkInputController input;

  /// Draws [samples] (times from 0) and lifts. Returns the stroke it
  /// committed, if any, and how many strokes it erased (a scribble).
  ({Stroke? stroke, int erased}) draw(List<RawSample> samples) {
    InkEdit? edit;
    fakeAsync((async) {
      final before = model.history.recorded;
      var now = 0;
      PointerEvent event(RawSample s, {bool down = false}) {
        async.elapse(Duration(microseconds: s.timeUs - now));
        now = s.timeUs;
        final time = Duration(microseconds: s.timeUs);
        return down
            ? PointerDownEvent(
                pointer: 1,
                kind: PointerDeviceKind.stylus,
                position: s.position,
                pressure: s.pressure,
                timeStamp: time,
              )
            : PointerMoveEvent(
                pointer: 1,
                kind: PointerDeviceKind.stylus,
                position: s.position,
                pressure: s.pressure,
                timeStamp: time,
              );
      }

      input.handleDown(event(samples.first, down: true) as PointerDownEvent);
      for (final s in samples.skip(1)) {
        input.handleMove(event(s) as PointerMoveEvent);
      }
      input.handleUp(
        PointerUpEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          position: samples.last.position,
          timeStamp: Duration(microseconds: now + 2000),
        ),
      );
      async.flushMicrotasks();
      if (model.history.recorded > before) edit = model.history.takeUndo();
    });
    return (stroke: edit?.added.singleOrNull, erased: edit?.removed.length ?? 0);
  }

  void dispose() {
    model.dispose();
    _db.close();
  }
}

/// Samples [contact] as a fresh stroke: times from 0, moved by [shift].
List<RawSample> fromZero(RawContact contact, {Offset shift = Offset.zero}) {
  final t0 = contact.samples.first.timeUs;
  return [
    for (final s in contact.samples) RawSample(s.position + shift, s.pressure, s.timeUs - t0),
  ];
}

/// [samples] with the pen then resting at their end for [ms], as the S
/// Pen rests in the real recordings ([realRest]).
List<RawSample> withHold(List<RawSample> samples, int ms) {
  final last = samples.last;
  final dt = _medianStep(samples);
  final rest = realRest;
  final out = [...samples];
  for (var t = dt, k = 0; t <= ms * 1000; t += dt, k++) {
    out.add(RawSample(last.position + rest[k % rest.length], last.pressure, last.timeUs + t));
  }
  return out;
}

/// How a resting S Pen's position drifts, sample by sample (relative to
/// where it came to rest): every stretch of the real recordings where the
/// pen stayed within 1.5 px for 30 ms or more, each played forwards and
/// back so that they join.
final List<Offset> realRest = () {
  final out = <Offset>[];
  for (final name in realRecordings) {
    for (final (_, c) in penContacts(loadRecording(name))) {
      final s = c.samples;
      var i = 0;
      while (i < s.length) {
        var j = i;
        while (j + 1 < s.length && (s[j + 1].position - s[i].position).distance <= 1.5) {
          j++;
        }
        if (j - i >= 8 && s[j].timeUs - s[i].timeUs >= 30000) {
          final run = [for (var k = i; k <= j; k++) s[k].position - s[i].position];
          out.addAll([...run, ...run.reversed]);
          i = j + 1;
        } else {
          i++;
        }
      }
    }
  }
  return out;
}();

int _medianStep(List<RawSample> s) {
  final steps = [for (var i = 1; i < s.length; i++) s[i].timeUs - s[i - 1].timeUs]..sort();
  return math.max(500, steps.isEmpty ? 2000 : steps[steps.length ~/ 2]);
}
