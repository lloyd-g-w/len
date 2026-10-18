import 'text_font.dart';

/// A font the user imported for text boxes (collection `fonts`): one TTF
/// or OTF file stored as a blob. Its [id] is derived from the file
/// ([TextFont.userIdOf]), so importing the same file on two devices makes
/// one font; text refers to it by that id ([font]).
class UserFont {
  const UserFont({
    required this.id,
    required this.name,
    required this.blob,
    required this.createdAt,
  });

  /// The first 32 hex digits of [blob].
  final String id;

  /// The name shown in the font picker (read from the file's name table).
  final String name;

  /// SHA-256 (lowercase hex) of the font file.
  final String blob;

  /// Milliseconds since epoch.
  final int createdAt;

  TextFont get font => TextFont.user(id);

  @override
  bool operator ==(Object other) =>
      other is UserFont &&
      other.id == id &&
      other.name == name &&
      other.blob == blob &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, blob, createdAt);
}
