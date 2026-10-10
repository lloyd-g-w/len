import 'package:uuid/uuid.dart';

/// Source of time and identifiers. Injected so tests can be deterministic.
class Clock {
  const Clock();

  static const _uuid = Uuid();

  /// Milliseconds since the Unix epoch.
  int nowMs() => DateTime.now().millisecondsSinceEpoch;

  /// A new random (v4) identifier.
  String newId() => _uuid.v4();
}
