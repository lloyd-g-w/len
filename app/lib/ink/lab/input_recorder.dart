import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

import '../input/stylus_batch.dart';
import 'input_recording.dart';

/// Collects an [InputRecording]: feed it the surface's pointer events
/// ([addPointer]), the platform's stylus batches ([addBatches]) and frame
/// boundaries ([addFrame], [addTimings]) in the order they arrive;
/// [attachToScheduler] wires the last two to Flutter's scheduler.
class InputRecorder {
  InputRecorder({required this.meta}) {
    _clock.start();
  }

  /// The settings stored with the recording (update when the pen changes).
  RecordingMeta meta;
  final Stopwatch _clock = Stopwatch();
  final List<InputEntry> _entries = [];
  bool _attached = false;

  /// Called after every entry (e.g. to update live statistics).
  void Function(InputEntry entry)? onEntry;

  List<InputEntry> get entries => _entries;
  bool get isEmpty => !_entries.any((e) => e is PointerEntry && e.type == PointerType.down);

  /// The recording so far.
  InputRecording get recording => InputRecording(meta: meta, entries: List.of(_entries));

  /// Forgets everything recorded so far.
  void clear() {
    _entries.clear();
    _clock
      ..reset()
      ..start();
  }

  int get _now => _clock.elapsedMicroseconds;

  void _add(InputEntry e) {
    _entries.add(e);
    onEntry?.call(e);
  }

  /// Records [e] if it is a pointer event that matters for drawing.
  void addPointer(PointerEvent e) {
    final type = switch (e) {
      PointerDownEvent() => PointerType.down,
      PointerMoveEvent() => PointerType.move,
      PointerUpEvent() => PointerType.up,
      PointerCancelEvent() => PointerType.cancel,
      PointerHoverEvent() => PointerType.hover,
      _ => null,
    };
    if (type == null) return;
    _add(
      PointerEntry(
        _now,
        type: type,
        kind: e.kind,
        pointer: e.pointer,
        device: e.device,
        timeStampUs: e.timeStamp.inMicroseconds,
        position: e.position,
        localPosition: e.localPosition,
        pressure: e.pressure,
        pressureMin: e.pressureMin,
        pressureMax: e.pressureMax,
        buttons: e.buttons,
        synthesized: e.synthesized,
        tilt: e.tilt,
        orientation: e.orientation,
      ),
    );
  }

  void addBatches(List<StylusBatch> batches) {
    if (batches.isNotEmpty) _add(BatchEntry(_now, batches));
  }

  void addFrame(Duration vsync) => _add(FrameEntry(_now, vsyncUs: vsync.inMicroseconds));

  void addTimings(List<FrameTiming> timings) {
    for (final f in timings) {
      _add(
        TimingEntry(
          _now,
          frameNumber: f.frameNumber,
          vsyncStartUs: f.timestampInMicroseconds(FramePhase.vsyncStart),
          buildUs: f.buildDuration.inMicroseconds,
          rasterUs: f.rasterDuration.inMicroseconds,
          totalUs: f.totalSpan.inMicroseconds,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Scheduler wiring

  static InputRecorder? _active;
  static bool _frameCallbackAdded = false;

  /// Starts receiving frame boundaries and timings (one recorder at a time).
  void attachToScheduler() {
    if (_attached) return;
    _attached = true;
    _active = this;
    final scheduler = SchedulerBinding.instance;
    if (!_frameCallbackAdded) {
      // Persistent callbacks cannot be removed; one forwards to the active
      // recorder, if any.
      _frameCallbackAdded = true;
      scheduler.addPersistentFrameCallback((_) {
        _active?.addFrame(SchedulerBinding.instance.currentSystemFrameTimeStamp);
      });
    }
    scheduler.addTimingsCallback(addTimings);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    if (identical(_active, this)) _active = null;
    SchedulerBinding.instance.removeTimingsCallback(addTimings);
  }
}
