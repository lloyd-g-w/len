import 'package:uuid/uuid.dart';

/// Source of time and identifiers. Injected so tests can be deterministic.
class Clock {
  const Clock();

  static const _uuid = Uuid();

  /// Milliseconds since the Unix epoch.
  int nowMs() => DateTime.now().millisecondsSinceEpoch;

  /// The local date and time now (by [nowMs]).
  DateTime nowDate() => DateTime.fromMillisecondsSinceEpoch(nowMs());

  /// A new random (v4) identifier.
  String newId() => _uuid.v4();
}
