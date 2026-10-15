import 'dart:typed_data';

/// A kind of content the clipboard offers, as [PasteboardPlatform.peek]
/// tells (added in Len's copy).
enum PasteboardKind {
  /// An image (Android `image/*`, a GTK image target, a Windows DIB).
  image,

  /// Plain text (or something the platform turns into text).
  text,

  /// HTML (rich text).
  html,

  /// Files or URIs (desktop file managers).
  files;

  /// The kinds named in a platform's answer; unknown names are skipped.
  static Set<PasteboardKind> parse(Iterable<Object?> names) => {
        for (final name in names)
          for (final kind in values)
            if (kind.name == name) kind,
      };
}

abstract class PasteboardPlatform {
  /// What the clipboard holds, told without reading its content; null
  /// where that can't be known without reading it.
  Future<Set<PasteboardKind>?> peek();

  Future<Uint8List?> get image;

  Future<String?> get html;

  Future<void> writeImage(Uint8List? image);

  Future<bool> write({Future<Uint8List?>? png, String? text, String? html});

  Future<List<String>> files();

  Future<bool> writeFiles(List<String> files);

  Future<String?> get text;

  void writeText(String value);
}
