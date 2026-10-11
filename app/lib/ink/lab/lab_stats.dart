import 'dart:math' as math;

import 'input_recording.dart';

/// Live input statistics for the Ink Lab, updated entry by entry: the
/// digitiser rate and samples per frame of the latest contact, and recent
/// frame build / raster times.
class LabStats {
  /// Frames averaged for the timing figures.
  static const int window = 120;

  int? _contact;
  int _samples = 0;
  int _firstUs = 0, _lastUs = 0;
  int _frames = 0;
  final List<TimingEntry> _timings = [];

  /// Contacts (pen-downs) seen.
  int contacts = 0;

  /// Digitiser samples per second in the latest contact (pointer events
  /// plus historical samples).
  double get sampleHz {
    final span = (_lastUs - _firstUs) / 1e6;
    return span <= 0 || _samples < 2 ? 0 : (_samples - 1) / span;
  }

  /// Samples received per frame during the latest contact.
  double get samplesPerFrame => _frames == 0 ? 0 : _samples / _frames;

  /// Samples in the latest contact.
  int get samples => _samples;

  double get buildMs => _mean((t) => t.buildUs) / 1000;
  double get rasterMs => _mean((t) => t.rasterUs) / 1000;
  double get maxBuildMs => _max((t) => t.buildUs) / 1000;
  double get maxRasterMs => _max((t) => t.rasterUs) / 1000;

  /// Vsync → raster end, i.e. roughly how long a frame takes to reach the
  /// screen after it starts.
  double get latencyMs => _mean((t) => t.totalUs) / 1000;

  void add(InputEntry e) {
    switch (e) {
      case PointerEntry(type: PointerType.down):
        _contact = e.pointer;
        contacts++;
        _samples = 1;
        _frames = 0;
        _firstUs = _lastUs = e.timeStampUs;
      case PointerEntry(type: PointerType.move || PointerType.up) when e.pointer == _contact:
        if (!e.synthesized && e.type == PointerType.move) _samples++;
        _lastUs = math.max(_lastUs, e.timeStampUs);
        if (e.type == PointerType.up) _contact = null;
      case BatchEntry() when _contact != null:
        for (final b in e.batches) {
          _samples += b.samples.length - 1;
        }
      case FrameEntry() when _contact != null:
        _frames++;
      case TimingEntry():
        _timings.add(e);
        if (_timings.length > window) _timings.removeAt(0);
      default:
        break;
    }
  }

  double _mean(int Function(TimingEntry) f) =>
      _timings.isEmpty ? 0 : _timings.map(f).reduce((a, b) => a + b) / _timings.length;

  double _max(int Function(TimingEntry) f) =>
      _timings.isEmpty ? 0 : _timings.map(f).reduce(math.max).toDouble();
}
