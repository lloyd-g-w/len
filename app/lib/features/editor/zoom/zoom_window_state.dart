import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'zoom_frame.dart';

/// The zoom window as a notebook keeps it across launches: the frame
/// while it is open (its page, place and magnification) and the box's
/// height if one was chosen.
@immutable
class ZoomWindowState {
  const ZoomWindowState({this.frame, this.boxHeight});

  /// Where the window was writing; null when it was closed.
  final ZoomFrame? frame;

  /// The box's height dragged by its top edge, if any.
  final double? boxHeight;

  bool get open => frame != null;

  /// Whether there is nothing to remember.
  bool get isEmpty => frame == null && boxHeight == null;

  /// A compact text form for the settings store.
  String encode() {
    final f = frame;
    return [
      f?.surfaceId ?? '',
      f?.origin.dx ?? '',
      f?.origin.dy ?? '',
      f?.scale ?? '',
      boxHeight ?? '',
    ].join(',');
  }

  /// Parses [encode]'s output; null if [text] is missing or malformed.
  static ZoomWindowState? decode(String? text) {
    final parts = text?.split(',');
    if (parts == null || parts.length != 5) return null;
    double? number(String s) {
      final v = double.tryParse(s);
      return v != null && v.isFinite ? v : null;
    }

    final height = number(parts[4]);
    if (parts[4].isNotEmpty && (height == null || height <= 0)) return null;
    if (parts[0].isEmpty) return ZoomWindowState(boxHeight: height);
    final dx = number(parts[1]), dy = number(parts[2]), scale = number(parts[3]);
    if (dx == null || dy == null || scale == null || scale <= 0) return null;
    return ZoomWindowState(
      frame: ZoomFrame(surfaceId: parts[0], origin: Offset(dx, dy), scale: scale),
      boxHeight: height,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ZoomWindowState && other.frame == frame && other.boxHeight == boxHeight;

  @override
  int get hashCode => Object.hash(frame, boxHeight);
}
