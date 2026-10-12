import '../../domain/stroke.dart';

/// Which ends of a stroke a tapered pen narrows.
enum TaperAt {
  start,
  end,
  both;

  bool get atStart => this != end;
  bool get atEnd => this != start;
}

/// The end style of a pen ([PenConfig.ends]): round, flat or tapered, and
/// for tapered ends their length, where they apply and whether the end's
/// follows the pen's speed.
class PenEnds {
  const PenEnds({
    this.style = StrokeEnds.round,
    this.taperLength = 4,
    this.taperAt = TaperAt.both,
    this.followSpeed = true,
  });

  final StrokeEnds style;

  /// Taper length in multiples of the pen's width
  /// ([minTaperLength]..[maxTaperLength]).
  final double taperLength;

  final TaperAt taperAt;

  /// The end taper is longer after a quick flick and shorter after a slow
  /// stop, like a fountain pen's (`Taper.speedScale`); [taperLength] is
  /// its length at an ordinary writing speed. The start's cannot know
  /// where the pen is going, so it is always [taperLength].
  final bool followSpeed;

  static const double minTaperLength = 1;
  static const double maxTaperLength = 12;

  bool get _tapered => style == StrokeEnds.tapered;

  /// Taper lengths (widths) new strokes get; the end's before [followSpeed].
  double get taperStart => _tapered && taperAt.atStart ? taperLength : 0;
  double get taperEnd => _tapered && taperAt.atEnd ? taperLength : 0;

  /// Whether the end taper of a finished stroke follows the pen's speed.
  bool get endFollowsSpeed => taperEnd > 0 && followSpeed;

  /// [style] with these ends.
  StrokeStyle applyTo(StrokeStyle s) =>
      s.copyWith(ends: style, taperStart: taperStart, taperEnd: taperEnd);

  PenEnds copyWith({StrokeEnds? style, double? taperLength, TaperAt? taperAt, bool? followSpeed}) =>
      PenEnds(
        style: style ?? this.style,
        taperLength: taperLength ?? this.taperLength,
        taperAt: taperAt ?? this.taperAt,
        followSpeed: followSpeed ?? this.followSpeed,
      );

  Map<String, Object?> toJson() => {
    'style': style.key,
    'taper': taperLength,
    'at': taperAt.name,
    'speed': followSpeed,
  };

  /// Parses [json] strictly (every field present and valid), or null.
  static PenEnds? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final StrokeEnds style;
    try {
      style = StrokeEnds.parse(json['style']);
    } on FormatException {
      return null;
    }
    final length = json['taper'];
    final at = TaperAt.values.where((a) => a.name == json['at']).firstOrNull;
    final speed = json['speed'];
    if (length is! num ||
        !(length >= minTaperLength && length <= maxTaperLength) ||
        at == null ||
        speed is! bool) {
      return null;
    }
    return PenEnds(style: style, taperLength: length.toDouble(), taperAt: at, followSpeed: speed);
  }

  @override
  bool operator ==(Object other) =>
      other is PenEnds &&
      other.style == style &&
      other.taperLength == taperLength &&
      other.taperAt == taperAt &&
      other.followSpeed == followSpeed;

  @override
  int get hashCode => Object.hash(style, taperLength, taperAt, followSpeed);
}
