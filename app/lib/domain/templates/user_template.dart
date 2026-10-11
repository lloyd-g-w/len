import 'dart:ui';

import 'paper.dart';

/// A template the user made: an image (imported, a rendered PDF page or a
/// saved page) stored as a blob, with the page size it suggests.
class UserTemplate {
  const UserTemplate({
    required this.id,
    required this.name,
    required this.blob,
    required this.width,
    required this.height,
    required this.createdAt,
  });

  final String id;
  final String name;

  /// SHA-256 (lowercase hex) of the image blob (PNG or JPEG).
  final String blob;

  /// Page size in world units (96 per inch) for pages made from it.
  final double width;
  final double height;

  /// Milliseconds since epoch.
  final int createdAt;

  Size get size => Size(width, height);

  /// The paper of pages made from this template.
  Paper get paper => Paper.image(blob);

  UserTemplate copyWith({String? name}) => UserTemplate(
    id: id,
    name: name ?? this.name,
    blob: blob,
    width: width,
    height: height,
    createdAt: createdAt,
  );
}
