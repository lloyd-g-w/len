/// A folder in the library. Folders nest via [parentId] (null = top level).
class Folder {
  const Folder({
    required this.id,
    required this.name,
    required this.parentId,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;

  /// The containing folder, or null for a top-level folder.
  final String? parentId;

  /// ARGB accent colour of the folder icon.
  final int color;

  /// Milliseconds since epoch.
  final int createdAt;
  final int updatedAt;

  static const Object _keep = Object();

  /// A copy with the given fields replaced; pass `parentId: null` to move
  /// the folder to the top level.
  Folder copyWith({String? name, Object? parentId = _keep, int? color, int? updatedAt}) {
    return Folder(
      id: id,
      name: name ?? this.name,
      parentId: identical(parentId, _keep) ? this.parentId : parentId as String?,
      color: color ?? this.color,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
