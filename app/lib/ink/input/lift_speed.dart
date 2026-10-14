import 'dart:ui';

import '../render/taper.dart';

/// The pen's speed as it lifts, from a stroke's kept points (screen px and
/// whole-ms times, as the low-latency overlay's model keeps them): what a
/// tapered end that follows the speed (`PenEnds.endFollowsSpeed`) is scaled by.
class LiftSpeed {
  final List<double> _x = [], _y = [];
  final List<int> _t = [];

  /// Forgets the previous contact.
  void reset() {
    _x.clear();
    _y.clear();
    _t.clear();
  }

  /// Adds a kept point at [screen], [timeMs].
  void add(Offset screen, int timeMs) {
    // Only the last points matter.
    if (_x.length >= 64) {
      _x.removeRange(0, 32);
      _y.removeRange(0, 32);
      _t.removeRange(0, 32);
    }
    _x.add(screen.dx);
    _y.add(screen.dy);
    _t.add(timeMs);
  }

  /// Screen px per ms over the last points (`Taper.liftSpeed`).
  double get speed => Taper.liftSpeed((i) => _x[i], (i) => _y[i], (i) => _t[i], _x.length);

  /// The end taper's scale (`Taper.speedScale`).
  double get scale => Taper.speedScale(speed);
}
