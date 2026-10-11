/// A coloured label the user puts on notebooks and pages (collection `tags`).
class Tag {
  const Tag({required this.id, required this.name, required this.color, required this.createdAt});

  final String id;

  /// Shown as is; matched case-insensitively (library filter, `tag:` search).
  final String name;

  /// ARGB colour of the tag's dot and chip.
  final int color;

  /// Milliseconds since epoch.
  final int createdAt;

  Tag copyWith({String? name, int? color}) =>
      Tag(id: id, name: name ?? this.name, color: color ?? this.color, createdAt: createdAt);

  @override
  bool operator ==(Object other) =>
      other is Tag &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, color, createdAt);
}

/// What a tag is put on.
enum TagTarget { notebook, page }

/// One tag on one notebook or page (collection `taggings`).
typedef Tagging = ({String tagId, String targetId, TagTarget kind});
