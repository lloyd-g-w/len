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

/// The engine passes every metric on every entry (docs/INK_LAB.md,
/// "Findings" F1–F8, all resolved) but where the stabiliser's string makes
/// features sharper than a pen draws (F14). Add an entry, tied to a
/// finding, only with evidence of why the engine cannot meet the limit yet.
const List<KnownFailure> knownFailures = [
  KnownFailure(
    'detail.retraction',
    'F14',
    'the string pulls 7 px loops into tighter curves than the outline\'s '
        'σ 0.7 px follows (1.5 px, limit 1.3)',
    cases: ['fast_loops'],
    stabilisers: [0.4],
  ),
  KnownFailure(
    'smooth.edgeBump16x',
    'F14',
    'where the pen stops and turns within the string the ink turns a real '
        '≈ 100° corner the outline rounds (1.3 px at 16×, limit 1)',
    cases: ['zigzag'],
    stabilisers: [0.4],
  ),
];

/// The known failure covering [id] on [caseName] at [streamline], if any.
KnownFailure? knownFailure(String id, String caseName, double streamline) {
  for (final k in knownFailures) {
    if (k.matches(id, caseName, streamline)) return k;
  }
  return null;
}
