/// A folder in the library. Folders nest via [parentId] (null = top level).
class Folder {
  const Folder({
    required this.id,
    required this.name,
    required this.parentId,
    required this.color,
    this.icon,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Keys of the icons a folder may show besides the default folder icon
  /// (null); the UI maps them to glyphs (`features/library/folder_icons.dart`).
  static const List<String> iconKeys = [
    'book',
    'school',
    'work',
    'science',
    'calculate',
    'palette',
    'music',
    'sports',
    'travel',
    'home',
    'favorite',
    'star',
    'lightbulb',
    'code',
    'language',
    'receipt',
    'event',
    'pets',
    'restaurant',
  ];

  final String id;
  final String name;

  /// The containing folder, or null for a top-level folder.
  final String? parentId;

  /// ARGB accent colour of the folder icon.
  final int color;

  /// One of [iconKeys], or null for the default folder icon.
  final String? icon;

  /// Milliseconds since epoch.
  final int createdAt;
  final int updatedAt;

  static const Object _keep = Object();

  /// A copy with the given fields replaced; pass `parentId: null` to move
  /// the folder to the top level and `icon: null` for the default icon.
  Folder copyWith({
    String? name,
    Object? parentId = _keep,
    int? color,
    Object? icon = _keep,
    int? updatedAt,
  }) {
    return Folder(
      id: id,
      name: name ?? this.name,
      parentId: identical(parentId, _keep) ? this.parentId : parentId as String?,
      color: color ?? this.color,
      icon: identical(icon, _keep) ? this.icon : icon as String?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
