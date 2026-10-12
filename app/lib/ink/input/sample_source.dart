import 'dart:collection';

import 'package:flutter/gestures.dart';

import 'stylus_batch.dart';

/// A digitiser sample placed in the coordinate space of a pointer event.
class PointerSample {
  const PointerSample({
    required this.localPosition,
    required this.pressure,
    required this.timeStamp,
    this.tilt = 0,
    this.orientation = 0,
  });

  /// Position in the same space as the event's `localPosition`.
  final Offset localPosition;

  /// Raw pressure, in the event's `pressureMin`..`pressureMax` range.
  final double pressure;
  final Duration timeStamp;
  final double tilt, orientation;
}

/// Supplies the samples a platform reported between two pointer events of
/// one contact but Flutter dropped (Android forwards only the newest sample
/// of each batched `MotionEvent`).
///
/// The input controller calls [begin] on pen-down, [between] before handling
/// every later event of that contact (moves and the final up), and [end]
/// when the contact is over. A source never returns a sample twice, never one
/// older than a sample already returned or than the previous event, and
/// nothing after [end].
abstract interface class SampleSource {
  /// Starts tracking the contact that [down] begins.
  void begin(PointerDownEvent down);

  /// Samples of the tracked contact taken after the previous event and
  /// before [event], oldest first. Empty when unknown (late or missing data
  /// simply means fewer samples).
  List<PointerSample> between(PointerEvent event);

  /// Stops tracking; later samples of the contact are ignored. [taperEnd]
  /// is the end taper (world units) the stroke was committed with, for a
  /// platform overlay drawing it (0: none, or not committed).
  void end({double taperEnd = 0});

  /// A pointer hovers over the surface (no contact tracked).
  void hover(PointerHoverEvent event);
}

/// Recent stylus batches as they arrive from the platform, bounded.
class StylusBatchBuffer {
  StylusBatchBuffer({this.capacity = 256});

  /// Most batches kept (a few seconds of input); the oldest go first.
  final int capacity;

  final Queue<StylusBatch> _batches = Queue();

  Iterable<StylusBatch> get batches => _batches;

  void addAll(Iterable<StylusBatch> batches) {
    for (final b in batches) {
      _batches.addLast(b);
      if (_batches.length > capacity) _batches.removeFirst();
    }
  }

  void clear() => _batches.clear();
}

/// Matches batches in a [StylusBatchBuffer] to Flutter pointer events.
///
/// Android timestamps are the key: a pointer event's `timeStamp` is its
/// `MotionEvent`'s event time and a down event's is the contact's down time,
/// so a batch belongs to the tracked contact when its device and down time
/// match, and to the gap before an event with time `T` when its event time
/// lies in `(previous event, T]`. For the batch made into that very event
/// only its historical samples are new; a batch whose event Flutter never
/// delivered contributes all of its samples. Batches that arrive after their
/// event was handled are too late to insert in order and are skipped.
class StylusSampleMerger implements SampleSource {
  StylusSampleMerger(this.buffer, {required this.devicePixelRatio});

  final StylusBatchBuffer buffer;

  /// Physical pixels per logical pixel of the view the events come from.
  final double Function() devicePixelRatio;

  int? _device;
  int _downUs = 0;
  int _lastUs = 0;
  double _lastSampleUs = 0;

  @override
  void hover(PointerHoverEvent event) {}

  @override
  void begin(PointerDownEvent down) {
    final stylus =
        down.kind == PointerDeviceKind.stylus || down.kind == PointerDeviceKind.invertedStylus;
    _device = stylus ? down.device : null;
    _downUs = _lastUs = down.timeStamp.inMicroseconds;
    _lastSampleUs = _downUs.toDouble();
  }

  @override
  List<PointerSample> between(PointerEvent event) {
    final device = _device;
    final t = event.timeStamp.inMicroseconds;
    if (device == null || event.device != device || t <= _lastUs) return const [];
    final from = _lastUs;
    _lastUs = t;
    final picked = <StylusBatch>[
      for (final b in buffer.batches)
        if (b.device == device &&
            _sameUs(b.downTimeUs, _downUs) &&
            b.eventTimeUs > from + 0.5 &&
            b.eventTimeUs < t + 0.5)
          b,
    ]..sort((a, b) => a.eventTimeUs.compareTo(b.eventTimeUs));
    if (picked.isEmpty) return const [];
    final dpr = devicePixelRatio();
    final out = <PointerSample>[];
    for (final b in picked) {
      final samples = _sameUs(b.eventTimeUs, t) ? b.historical : b.samples;
      for (final s in samples) {
        // Never step back in time (a malformed or duplicated batch).
        if (s.timeUs <= _lastSampleUs) continue;
        _lastSampleUs = s.timeUs;
        out.add(_place(s, event, dpr));
      }
    }
    return out;
  }

  @override
  void end({double taperEnd = 0}) => _device = null;

  static bool _sameUs(double a, int b) => (a - b).abs() < 0.5;

  /// Physical view pixels → logical pixels → the event's local space.
  static PointerSample _place(StylusSample s, PointerEvent event, double dpr) {
    final global = Offset(s.x / dpr, s.y / dpr);
    final transform = event.transform;
    final local = transform == null
        ? event.localPosition + (global - event.position)
        : event.localPosition +
              (PointerEvent.transformPosition(transform, global) -
                  PointerEvent.transformPosition(transform, event.position));
    return PointerSample(
      localPosition: local,
      pressure: s.pressure,
      timeStamp: Duration(microseconds: s.timeUs.round()),
      tilt: s.tilt,
      orientation: s.orientation,
    );
  }
}
