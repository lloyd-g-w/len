/// The Len file format: a zip holding a manifest, records in the sync
/// record format and the blobs they reference (docs/SYNC_PROTOCOL.md,
/// "Len files").
///
/// ```text
/// manifest.json            {"format": "len", "version": 1, "kind", "title", "createdAt"}
/// records/000001.jsonl     one sync record per line, parents first (see [collections])
/// records/000002.jsonl     … (a new part every ~4 MB, so neither side holds them all)
/// blobs.json               {"<sha256>": {"mime", "size"}} for every blob included
/// blobs/<sha256>           a blob's bytes, stored (not compressed)
/// ```
abstract final class LenFormat {
  /// The file name extension, without the dot.
  static const extension = 'len';

  /// The MIME type Len files are registered under.
  static const mime = 'application/x-len';

  /// The `format` of the manifest.
  static const format = 'len';

  /// The format version this build writes and reads.
  static const version = 1;

  static const manifestName = 'manifest.json';
  static const blobIndexName = 'blobs.json';
  static const recordsPrefix = 'records/';
  static const blobsPrefix = 'blobs/';

  /// The entry of records part [n] (1-based); parts sort by name.
  static String recordsName(int n) => '$recordsPrefix${n.toString().padLeft(6, '0')}.jsonl';

  /// The entry of blob [sha].
  static String blobName(String sha) => '$blobsPrefix$sha';

  /// Records of a part beyond this many UTF-8 bytes start the next part.
  static const partBytes = 4 << 20;

  /// The collections a Len file holds, in the order written: parents before
  /// their children, notebooks and pages before the links that lead to
  /// them. (`recognised_text` is left out: its keys hash stroke ids, which
  /// an import replaces; devices that recognise read the copy again.)
  static const collections = [
    'folders',
    'templates',
    'notebooks',
    'pages',
    'outline',
    'recordings',
    'strokes',
    'elements',
  ];
}

/// What a Len file holds.
enum LenArchiveKind {
  /// One notebook.
  notebook,

  /// A folder with its subfolders and their notebooks.
  folder,

  /// The whole library: every folder and notebook (the trash too) and the
  /// user's templates.
  library,
}

/// The manifest of a Len file.
class LenManifest {
  const LenManifest({required this.kind, required this.title, required this.createdAt});

  final LenArchiveKind kind;

  /// The notebook's or folder's title; "Library" for a backup.
  final String title;

  /// When the file was written (ms since epoch).
  final int createdAt;

  Map<String, Object?> toJson() => {
    'format': LenFormat.format,
    'version': LenFormat.version,
    'kind': kind.name,
    'title': title,
    'createdAt': createdAt,
  };

  /// Parses a manifest; throws [LenArchiveException] if it is not one this
  /// build can read.
  factory LenManifest.fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['format'] != LenFormat.format) {
      throw const LenArchiveException.notLen();
    }
    final version = json['version'];
    if (version is! int) throw const LenArchiveException.notLen();
    if (version > LenFormat.version) {
      throw const LenArchiveException('This file was made by a newer version of Len');
    }
    final kind = LenArchiveKind.values.asNameMap()[json['kind']];
    final title = json['title'], createdAt = json['createdAt'];
    if (kind == null || title is! String || createdAt is! int || version < 1) {
      throw const LenArchiveException.notLen();
    }
    return LenManifest(kind: kind, title: title, createdAt: createdAt);
  }
}

/// A Len file that can't be read; [message] is plain words for the user.
class LenArchiveException implements Exception {
  const LenArchiveException(this.message, [this.details]);

  /// Not a Len file, or one too damaged to read.
  const LenArchiveException.notLen([this.details])
    : message = 'This file isn’t a Len file, or it is damaged';

  /// Part of the file is damaged.
  const LenArchiveException.damaged([this.details]) : message = 'This Len file is damaged';

  final String message;

  /// What exactly went wrong (for Details), if known.
  final String? details;

  @override
  String toString() => details == null ? message : '$message ($details)';
}
