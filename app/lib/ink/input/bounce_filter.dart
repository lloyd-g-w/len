import 'dart:ui';

/// Detects stylus "bounces": a tiny accidental contact the digitiser reports
/// just after the pen lifts (common on Samsung tablets). Without filtering,
/// each bounce becomes a one-point stroke that renders as a stray dot at the
/// end of the previous stroke.
///
/// A contact is a bounce when it starts very soon after the previous lift,
/// close to where that lift happened, and is itself tiny and brief.
/// Deliberate dots (dotting an "i", full stops) are placed further away or
/// later and are therefore kept.
class BounceFilter {
  BounceFilter({
    this.maxGap = const Duration(milliseconds: 120),
    this.maxContact = const Duration(milliseconds: 80),
    this.maxDistance = 16,
    this.maxTravel = 3,
  });

  /// Longest pause between the previous lift and the bounce's touch-down.
  final Duration maxGap;

  /// Longest duration of the bounce contact itself.
  final Duration maxContact;

  /// Furthest (screen px) the bounce may start from the previous lift.
  final double maxDistance;

  /// Furthest (screen px) the bounce may travel while in contact.
  final double maxTravel;

  Duration? _liftTime;
  Offset? _liftPosition;

  /// Records where and when a stylus stroke ended.
  void recordLift(Duration time, Offset position) {
    _liftTime = time;
    _liftPosition = position;
  }

  /// Forgets the previous lift (e.g. after a tool or page change).
  void reset() {
    _liftTime = null;
    _liftPosition = null;
  }

  /// Whether a contact that started at [down] and is still touching at
  /// [now] could still turn out to be a bounce. Such a contact is not shown
  /// yet, so a bounce never flashes; once this is false it never will be a
  /// bounce ([isBounce] needs the same, or tighter, conditions).
  bool mightBounce({
    required Duration down,
    required Duration now,
    required Offset start,
    required double travel,
  }) {
    final liftTime = _liftTime;
    final liftPosition = _liftPosition;
    if (liftTime == null || liftPosition == null) return false;
    final gap = down - liftTime;
    return !gap.isNegative &&
        gap <= maxGap &&
        now - down <= maxContact &&
        (start - liftPosition).distance <= maxDistance &&
        travel <= maxTravel;
  }

  /// Whether a contact from [down] to [up] (screen positions [start]..[end],
  /// travelling [travel] px in total) is an accidental bounce.
  bool isBounce({
    required Duration down,
    required Duration up,
    required Offset start,
    required double travel,
  }) {
    final liftTime = _liftTime;
    final liftPosition = _liftPosition;
    if (liftTime == null || liftPosition == null) return false;
    final gap = down - liftTime;
    return !gap.isNegative &&
        gap <= maxGap &&
        up - down <= maxContact &&
        (start - liftPosition).distance <= maxDistance &&
        travel <= maxTravel;
  }
}
