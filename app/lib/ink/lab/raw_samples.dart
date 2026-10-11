import 'package:flutter/gestures.dart';

import '../input/sample_source.dart';
import 'input_recording.dart';
import 'replay_events.dart';

/// One digitiser sample of a contact, in the surface's local (screen)
/// logical pixels, with pressure normalised to 0..1 by the device range.
class RawSample {
  const RawSample(this.position, this.pressure, this.timeUs);
  final Offset position;
  final double pressure;
  final int timeUs;
}

/// Every digitiser sample of one contact (pen-down to pen-up), unfiltered:
/// what the device reported, before the input controller's minimum
/// spacing, pressure smoothing or the outline engine.
class RawContact {
  RawContact(this.kind, this.pointer, this.downUs, {this.buttons = 0});
  final PointerDeviceKind kind;
  final int pointer;
  final int downUs;

  /// Buttons held at pen-down (a held S Pen side button erases).
  final int buttons;
  int upUs = 0;
  bool cancelled = false;
  final List<RawSample> samples = [];
}

/// Extracts the raw samples of every contact in [recording]: pointer
/// events plus the historical stylus samples matched to them (the same
/// matching the app uses, [StylusSampleMerger]).
List<RawContact> rawContacts(InputRecording recording) {
  final buffer = StylusBatchBuffer(capacity: 1 << 20);
  final merger = StylusSampleMerger(
    buffer,
    devicePixelRatio: () => recording.meta.devicePixelRatio,
  );
  final contacts = <RawContact>[];
  RawContact? current;
  void add(PointerEvent e, Offset at, double raw, int timeUs) {
    final range = e.pressureMax - e.pressureMin;
    final p = range > 0 ? ((raw - e.pressureMin) / range).clamp(0.0, 1.0) : 0.5;
    final samples = current!.samples;
    if (samples.isNotEmpty && samples.last.timeUs >= timeUs) return;
    samples.add(RawSample(at, p, timeUs));
  }

  for (final entry in recording.entries) {
    switch (entry) {
      case BatchEntry():
        buffer.addAll(entry.batches);
      case PointerEntry(type: PointerType.down) when current == null:
        final e = pointerEventOf(entry) as PointerDownEvent;
        current = RawContact(entry.kind, entry.pointer, entry.timeStampUs, buttons: entry.buttons);
        contacts.add(current);
        merger.begin(e);
        add(e, e.localPosition, e.pressure, entry.timeStampUs);
      case PointerEntry(type: PointerType.move || PointerType.up || PointerType.cancel)
          when entry.pointer == current?.pointer:
        final e = pointerEventOf(entry);
        if (entry.type == PointerType.cancel) {
          current!.cancelled = true;
        } else {
          for (final s in merger.between(e)) {
            add(e, s.localPosition, s.pressure, s.timeStamp.inMicroseconds);
          }
          // A synthesized move carries the up event's position but not a
          // pressure the device measured; the up itself repeats it.
          if (!entry.synthesized) add(e, e.localPosition, e.pressure, entry.timeStampUs);
        }
        if (entry.type != PointerType.move) {
          current!.upUs = entry.timeStampUs;
          merger.end();
          current = null;
        }
      default:
        break;
    }
  }
  return contacts;
}
