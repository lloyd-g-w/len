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

/// Findings (docs/INK_LAB.md, "Findings").
const _tail = 'F1 ink behind the tip changes';
const _pop = 'F2 pop at pen-up';
const _hooks = 'F3 pen-lift hooks';
const _bounce = 'F4 bounces flash';
const _raw = 'F5 stabiliser 0 smooths nothing';
const _cost = 'F6 live cost grows with length';
const _overlay = 'F7 wet-ink overlay';
const _tips = 'F8 tips cut short';

const _tailWhy =
    'capsule runs are merged against the direction where the run started '
    '(0.02 rad), so each new sample moves the far end of the last capsule and '
    'the whole edge tilts; corners and the smoothing window also reshape ink '
    'behind the tip';

const List<KnownFailure> knownFailures = [
  // F1: whole edges re-tilt while straight-ish runs grow.
  KnownFailure('temporal.behindTip', _tail, _tailWhy, cases: ['lines', 'hooks', 'bounces']),
  KnownFailure('temporal.settle', _tail, _tailWhy, cases: ['lines', 'hooks', 'bounces']),
  KnownFailure(
    'temporal.behindTip',
    _tail,
    _tailWhy,
    cases: ['zigzag', 'pressure_swell', 'cursive', 'long_stroke', 'spiral', 'rec:sim_hooks'],
    stabilisers: [0.4, 1],
  ),
  KnownFailure(
    'temporal.settle',
    _tail,
    _tailWhy,
    cases: ['zigzag', 'pressure_swell', 'cursive', 'long_stroke', 'spiral', 'rec:sim_hooks'],
    stabilisers: [0.4, 1],
  ),
  KnownFailure('temporal.behindTip', _tail, _tailWhy, cases: ['rec:sim_hooks'], stabilisers: [0]),
  KnownFailure('temporal.settle', _tail, _tailWhy, cases: ['rec:sim_hooks'], stabilisers: [0]),
  // F2: the last live frame and the committed stroke differ beyond the tip.
  KnownFailure(
    'pop.pixels',
    _pop,
    'the committed outline (hooks trimmed, ends levelled, runs re-merged) '
        'differs from the last live frame along the whole stroke',
    cases: ['lines', 'hooks', 'rec:sim_hooks'],
    stabilisers: [0.4, 1],
  ),
  KnownFailure(
    'pop.max',
    _pop,
    'a whole edge strip flips coverage at pen-up',
    cases: ['hooks', 'rec:sim_hooks'],
    stabilisers: [0.4, 1],
  ),
  // F3: the flicks are drawn as ~3 px nubs.
  KnownFailure(
    'ends.nub',
    _hooks,
    'the hook trimmer misses the simulated landing/lift flicks: ~3 px nubs',
    cases: ['hooks'],
  ),
  KnownFailure(
    'fidelity.hausdorff',
    _hooks,
    'the untrimmed nubs are the farthest ink from the true path (and, '
        'against raw samples, the flick is only half drawn)',
    cases: ['hooks', 'rec:sim_hooks'],
  ),
  KnownFailure(
    'fidelity.rms',
    _hooks,
    'the nubs dominate the mean',
    cases: ['hooks'],
    stabilisers: [0],
  ),
  // F4
  KnownFailure(
    'temporal.vanished',
    _bounce,
    'a bounce is drawn live for a frame or two and only dropped at pen-up',
    cases: ['bounces'],
  ),
  // F5: digitiser jitter reaches the ink unfiltered.
  KnownFailure(
    'smooth.edgeBump16x',
    _raw,
    'positionSigma is 0 at stabiliser 0: digitiser jitter shows as bumps at 16x',
    stabilisers: [0],
  ),
  KnownFailure(
    'smooth.facet',
    _raw,
    'positionSigma is 0 at stabiliser 0: jitter kinks the centre line',
    stabilisers: [0],
  ),
  KnownFailure(
    'fidelity.hausdorff',
    _tips,
    'cusp tips and tight loop tops end ~0.55 px short of the true path even '
        'without stabiliser (just over the 0.5 px limit)',
    cases: ['long_stroke', 'zigzag'],
    stabilisers: [0],
  ),
  KnownFailure(
    'detail.retraction',
    _tips,
    'cusp tips and tight loop tops end ~0.55 px short of the true path even '
        'without stabiliser (just over the 0.5 px limit)',
    cases: ['long_stroke', 'zigzag'],
    stabilisers: [0],
  ),
  // F6: every frame rebuilds and re-tessellates the whole live stroke.
  KnownFailure(
    'perf.flatness',
    _cost,
    'the live outline is rebuilt from all points every frame (O(length))',
  ),
  KnownFailure(
    'perf.subpaths',
    _cost,
    'one sub-path per capsule: thousands of sub-paths for the GPU each frame',
  ),
  KnownFailure(
    'perf.frameCost',
    _cost,
    'O(length) rebuild; the absolute time also depends on the machine',
    cases: ['long_stroke'],
  ),
  // F7: the overlay draws a different, unsmoothed shape.
  KnownFailure(
    'overlay.ghost',
    _overlay,
    'overlay capsules (raw samples, EMA 0.65, no stabiliser or radius '
        'smoothing) stick out of the ink Flutter later draws',
  ),
  KnownFailure(
    'overlay.gap',
    _overlay,
    'the overlay retracts before Flutter has drawn the same ink',
    cases: ['cursive', 'long_stroke'],
    stabilisers: [1],
  ),
  KnownFailure(
    'overlay.gap',
    _overlay,
    'the overlay retracts before Flutter has drawn the same ink',
    cases: ['hooks', 'pressure_swell', 'zigzag', 'rec:sim_hooks'],
    stabilisers: [0.4, 1],
  ),
];

/// The known failure covering [id] on [caseName] at [streamline], if any.
KnownFailure? knownFailure(String id, String caseName, double streamline) {
  for (final k in knownFailures) {
    if (k.matches(id, caseName, streamline)) return k;
  }
  return null;
}
