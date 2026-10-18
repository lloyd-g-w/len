import 'package:flutter/services.dart';

import 'low_latency_ink_native.dart' show lowLatencyInkChannel;
import 'stylus_samples.dart' show stylusEdgesSupported;

/// Keeps Android's Back gesture (gesture navigation) off a stylus writing
/// from the screen's left or right edge, while an editor shows.
///
/// The native side (`StylusEdgeGuard.kt`) watches the stylus itself: while
/// it hovers or touches, a 200-dp band around its y is excluded from system
/// gestures at both edges; fingers and mice never are. Dart only says when
/// that may happen: `[edges, true]` once some editor shows, `[edges,
/// false]` once none does, on the low-latency ink channel. A no-op off
/// Android ([supported] false).
class StylusEdges {
  /// Sends its messages only where [supported].
  StylusEdges({required this.supported});

  /// Whether the platform has the native side (Android).
  final bool supported;

  static const _channel = BasicMessageChannel<Object?>(
    lowLatencyInkChannel,
    StandardMessageCodec(),
  );

  int _holders = 0;

  /// Whether some editor shows (the edges are guarded).
  bool get guarded => _holders > 0;

  /// An editor shows; it calls [release] once it no longer does.
  void hold() {
    if (_holders++ == 0) _send(true);
  }

  /// An editor that [hold] went away or out of sight.
  void release() {
    assert(_holders > 0, 'release without hold');
    if (_holders == 0) return;
    if (--_holders == 0) _send(false);
  }

  void _send(bool on) {
    if (supported) _channel.send(['edges', on]).ignore();
  }
}

/// The app's [StylusEdges].
final StylusEdges stylusEdges = StylusEdges(supported: stylusEdgesSupported);
