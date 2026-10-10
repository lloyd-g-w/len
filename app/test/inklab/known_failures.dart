/// Metrics the current pen engine fails, each tied to a finding in
/// docs/INK_LAB.md. Remove an entry once the engine is fixed; the suite
/// then guards the fix.
class KnownFailure {
  const KnownFailure(this.metric, this.finding, this.why, {this.cases, this.stabilisers});

  final String metric;
  final String finding;
  final String why;

  /// Case names (null: every case, recordings included).
  final List<String>? cases;

  /// Stabiliser settings (null: all).
  final List<double>? stabilisers;

  bool matches(String id, String caseName, double streamline) =>
      id == metric &&
      (cases == null || cases!.contains(caseName)) &&
      (stabilisers == null || stabilisers!.contains(streamline));
}

const List<KnownFailure> knownFailures = [];

/// The known failure covering [id] on [caseName] at [streamline], if any.
KnownFailure? knownFailure(String id, String caseName, double streamline) {
  for (final k in knownFailures) {
    if (k.matches(id, caseName, streamline)) return k;
  }
  return null;
}
