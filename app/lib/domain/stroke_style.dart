import 'stroke.dart';

/// How a pen stroke's ends are shaped.
enum StrokeEnds {
  /// A round cap at the width the pressure gives.
  round,

  /// A butt cap, square to the stroke's direction.
  flat,

  /// Narrowing to a point over a length ([StrokeStyle.taperStart],
  /// [StrokeStyle.taperEnd]); an end without a taper is round.
  tapered;

  /// The end style named [value]; throws [FormatException] for others.
  static StrokeEnds parse(Object? value) => switch (value) {
    'round' => round,
    'flat' => flat,
    'taper' => tapered,
    _ => throw const FormatException('Malformed stroke style: e'),
  };

  /// The name [parse] reads.
  String get key => switch (this) {
    round => 'round',
    flat => 'flat',
    tapered => 'taper',
  };
}

/// Per-stroke rendering parameters, stored with the stroke so it renders
/// identically on every device regardless of the local tool settings.
class StrokeStyle {
  const StrokeStyle({
    this.opacity = 1,
    this.thinning = 0.5,
    this.streamline = 0,
    this.unit = 0,
    this.ends = StrokeEnds.round,
    this.taperStart = 0,
    this.taperEnd = 0,
    this.startPhase = 0,
    this.cutEnd = false,
  });

  /// Overall ink opacity, 0..1 (the stroke colour itself is stored opaque).
  final double opacity;

  /// How strongly pressure changes the width, 0 (none) .. 1 (strong).
  final double thinning;

  /// Stabiliser: how much input jitter is smoothed away, 0..1.
  final double streamline;

  /// World units per screen pixel when the stroke was written (the inverse
  /// of the zoom), 0 when unknown. Digitiser jitter and pen hooks are
  /// screen-sized, so the outline smooths at this scale; without it, the
  /// scale is estimated from the points' spacing (`StrokeOutline.unitOf`).
  final double unit;

  /// The shape of the ends (the highlighter's are always flat).
  final StrokeEnds ends;

  /// With [StrokeEnds.tapered]: the lengths over which the start and the
  /// end narrow to a point, in multiples of the stroke's width (0: that end
  /// is round). The end's is resolved when the stroke is finished (it may
  /// follow the pen's speed at the lift, `PenEnds.endFollowsSpeed`).
  final double taperStart;
  final double taperEnd;

  /// 0: the stroke starts where the pen landed (its pen-down hook is
  /// trimmed, and its centre line is resampled from there). Otherwise the
  /// start is a cut (the pixel eraser): nothing is trimmed, and the first
  /// resampled point lies this many resampling steps (0 < phase ≤ 1)
  /// after the first point, where it lay in the stroke it was cut from,
  /// so the rest of the ink does not move.
  final double startPhase;

  /// Whether the end is a cut (the pixel eraser): its pen-up hook is not
  /// trimmed.
  final bool cutEnd;

  /// The longest taper ([taperStart], [taperEnd]), in widths.
  static const double maxTaper = 24;

  /// The style of a stroke of [tool] created without one (generated
  /// content, tests).
  static StrokeStyle defaultsFor(InkTool tool) => switch (tool) {
    InkTool.highlighter => const StrokeStyle(opacity: 0.35, thinning: 0, streamline: 0.5),
    InkTool.ballpoint => const StrokeStyle(),
  };

  StrokeStyle copyWith({
    double? opacity,
    double? thinning,
    double? streamline,
    double? unit,
    StrokeEnds? ends,
    double? taperStart,
    double? taperEnd,
    double? startPhase,
    bool? cutEnd,
  }) => StrokeStyle(
    opacity: opacity ?? this.opacity,
    thinning: thinning ?? this.thinning,
    streamline: streamline ?? this.streamline,
    unit: unit ?? this.unit,
    ends: ends ?? this.ends,
    taperStart: taperStart ?? this.taperStart,
    taperEnd: taperEnd ?? this.taperEnd,
    startPhase: startPhase ?? this.startPhase,
    cutEnd: cutEnd ?? this.cutEnd,
  );

  /// Compact JSON for storage and sync.
  Map<String, Object?> toJson() => {
    'o': opacity,
    'th': thinning,
    'sl': streamline,
    if (unit > 0) 'u': unit,
    'e': ends.key,
    if (ends == StrokeEnds.tapered) ...{'ts': taperStart, 'te': taperEnd},
    if (startPhase > 0) 'cs': startPhase,
    if (cutEnd) 'ce': true,
  };

  /// Parses [json] strictly: `o`, `th` and `sl` are required, in 0..1;
  /// `u` is omitted when 0; `e` (ends) is required, and with `taper` so are
  /// `ts` and `te` (0..[maxTaper]), which are absent otherwise; `cs`
  /// ([startPhase], 0 < cs ≤ 1) and `ce` ([cutEnd], `true`) only for cut
  /// ends. Throws
  /// [FormatException] when malformed. Unknown fields are ignored.
  static StrokeStyle fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Malformed stroke style');
    double read(String key, double max, {bool required = false}) {
      final v = json[key];
      if (v == null && !required) return 0;
      if (v is num && v.isFinite && v >= 0 && v <= max) return v.toDouble();
      throw FormatException('Malformed stroke style: $key');
    }

    final ends = StrokeEnds.parse(json['e']);
    final tapered = ends == StrokeEnds.tapered;
    if (!tapered && (json.containsKey('ts') || json.containsKey('te'))) {
      throw const FormatException('Malformed stroke style: taper without e: taper');
    }
    final phase = read('cs', 1);
    if (json.containsKey('cs') && phase <= 0) {
      throw const FormatException('Malformed stroke style: cs');
    }
    final cutEnd = json['ce'];
    if (cutEnd != null && cutEnd != true) throw const FormatException('Malformed stroke style: ce');
    return StrokeStyle(
      opacity: read('o', 1, required: true),
      thinning: read('th', 1, required: true),
      streamline: read('sl', 1, required: true),
      unit: read('u', 1e6),
      ends: ends,
      taperStart: tapered ? read('ts', maxTaper, required: true) : 0,
      taperEnd: tapered ? read('te', maxTaper, required: true) : 0,
      startPhase: phase,
      cutEnd: cutEnd == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StrokeStyle &&
      other.opacity == opacity &&
      other.thinning == thinning &&
      other.streamline == streamline &&
      other.unit == unit &&
      other.ends == ends &&
      other.taperStart == taperStart &&
      other.taperEnd == taperEnd &&
      other.startPhase == startPhase &&
      other.cutEnd == cutEnd;

  @override
  int get hashCode => Object.hash(
    opacity,
    thinning,
    streamline,
    unit,
    ends,
    taperStart,
    taperEnd,
    startPhase,
    cutEnd,
  );

  @override
  String toString() => 'StrokeStyle(${toJson()})';
}
