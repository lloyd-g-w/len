/// The outline the lasso draws.
enum LassoShape {
  /// A loop drawn freehand.
  freehand('Freehand'),

  /// A rectangle dragged from corner to corner.
  rectangle('Rectangle');

  const LassoShape(this.label);

  final String label;

  static LassoShape parse(Object? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => LassoShape.freehand);
}

/// How much of an item must be inside the lasso for it to be selected.
enum LassoCover {
  /// Any part inside, or crossed by the outline.
  touching('Touching', 'Selects whatever the lasso touches'),

  /// Most of it inside (half a stroke's length, an element's centre):
  /// forgiving with a quick loop.
  mostly('Mostly', 'Selects items mostly inside the lasso'),

  /// All of it inside.
  whole('Whole', 'Selects items entirely inside the lasso');

  const LassoCover(this.label, this.caption);

  final String label;

  /// One line saying what the choice selects.
  final String caption;

  static LassoCover parse(Object? name) =>
      values.firstWhere((c) => c.name == name, orElse: () => LassoCover.mostly);
}

/// The kinds of item the lasso can be told to leave alone. Shapes are
/// strokes and count as ink; links go with images.
enum LassoKind {
  ink('Ink'),
  highlighter('Highlighter'),
  text('Text'),
  images('Images');

  const LassoKind(this.label);

  final String label;
}

/// The lasso's options (persisted with the tool settings): its [shape],
/// how much of an item it must [cover], and which [kinds] it selects.
class LassoConfig {
  const LassoConfig({
    this.shape = LassoShape.freehand,
    this.cover = LassoCover.mostly,
    this.kinds = const {...LassoKind.values},
  });

  final LassoShape shape;
  final LassoCover cover;

  /// What the lasso selects; never empty.
  final Set<LassoKind> kinds;

  bool takes(LassoKind kind) => kinds.contains(kind);

  /// [kinds] with [kind] turned [on]; the last kind stays on.
  LassoConfig toggled(LassoKind kind, bool on) {
    final next = {...kinds};
    on ? next.add(kind) : next.remove(kind);
    return next.isEmpty ? this : copyWith(kinds: next);
  }

  LassoConfig copyWith({LassoShape? shape, LassoCover? cover, Set<LassoKind>? kinds}) =>
      LassoConfig(
        shape: shape ?? this.shape,
        cover: cover ?? this.cover,
        kinds: kinds ?? this.kinds,
      );

  Map<String, Object?> toJson() => {
    'shape': shape.name,
    'cover': cover.name,
    'kinds': [
      for (final k in LassoKind.values)
        if (kinds.contains(k)) k.name,
    ],
  };

  /// Reads [toJson] output; anything missing or malformed takes its default.
  static LassoConfig fromJson(Object? json) {
    if (json is! Map) return const LassoConfig();
    final names = json['kinds'];
    final kinds = names is List
        ? {
            for (final k in LassoKind.values)
              if (names.contains(k.name)) k,
          }
        : const <LassoKind>{};
    return LassoConfig(
      shape: LassoShape.parse(json['shape']),
      cover: LassoCover.parse(json['cover']),
      kinds: kinds.isEmpty ? const {...LassoKind.values} : kinds,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LassoConfig &&
      other.shape == shape &&
      other.cover == cover &&
      other.kinds.length == kinds.length &&
      other.kinds.containsAll(kinds);

  @override
  int get hashCode => Object.hash(shape, cover, Object.hashAllUnordered(kinds));
}
