import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../../platform/browser_inflate.dart';
import '../syncable.dart';
import 'len_format.dart';
import 'ranged_input.dart';
import 'ranged_zip.dart';

/// The folders and notebooks a Len file holds (notebook id → title).
typedef LenContents = ({Set<String> folders, Map<String, String> notebooks});

/// A Len file opened for import: its manifest is read (so the user can be
/// asked first), its records and blobs not yet. [close] it when done.
class LenSource {
  LenSource._(this.input, this.archive, this.manifest);

  /// Opens [input] and reads its manifest (and, for a backup, its
  /// [contents]); throws [LenArchiveException] if it is not a Len file this
  /// build reads (and closes [input]). A [RangedInput] (a big file in a
  /// browser) is read in slices: its zip structure first, then each entry
  /// as it is read ([load]).
  static Future<LenSource> open(InputStream input) async {
    try {
      final Archive archive;
      try {
        if (input is RangedInput) await RangedZip.prepare(input.file);
        archive = ZipDecoder().decodeStream(input);
      } on Object catch (e) {
        throw LenArchiveException.notLen('$e');
      }
      final entry = archive.find(LenFormat.manifestName);
      if (entry == null) throw const LenArchiveException.notLen('no manifest');
      final Object? json;
      try {
        await load(entry);
        json = readJson(entry);
      } on LenArchiveException catch (e) {
        throw LenArchiveException.notLen(e.details);
      }
      final source = LenSource._(input, archive, LenManifest.fromJson(json));
      if (source.manifest.kind == LenArchiveKind.library) {
        source._contents = await source._readContents();
      }
      return source;
    } catch (_) {
      await input.close();
      rethrow;
    }
  }

  final InputStream input;
  final Archive archive;
  final LenManifest manifest;

  /// The records parts, in order.
  late final List<ArchiveFile> parts = [
    for (final f in archive.files)
      if (f.isFile && f.name.startsWith(LenFormat.recordsPrefix)) f,
  ]..sort((a, b) => a.name.compareTo(b.name));

  /// The folders and notebooks the file holds (notebook id → title), read
  /// from the start of its records: they come before pages and content.
  /// Damaged parts are passed over. Read when a backup opens.
  LenContents get contents => _contents ?? const (folders: {}, notebooks: {});
  LenContents? _contents;

  Future<LenContents> _readContents() async {
    final folders = <String>{}, notebooks = <String, String>{};
    for (final part in parts) {
      final List<String> lines;
      try {
        lines = await recordLines(part);
      } on LenArchiveException {
        continue;
      }
      // Parsed only up to the first content record (pages, strokes…).
      for (final line in lines) {
        final r = parseRecord(line);
        if (r == null || r.deleted) continue;
        switch (r.collection) {
          case 'folders':
            folders.add(r.id);
          case 'notebooks':
            final title = r.data?['title'];
            notebooks[r.id] = title is String ? title : '';
          case 'templates' || 'notebook_styles':
            break;
          default:
            return (folders: folders, notebooks: notebooks);
        }
      }
    }
    return (folders: folders, notebooks: notebooks);
  }

  /// Closes the file.
  Future<void> close() => input.close();

  /// Loads [entry]'s data where the file is read in slices (a
  /// [RangedInput]), before it is read; does nothing otherwise. Only the
  /// entry read last stays loaded.
  static Future<void> load(ArchiveFile entry) async {
    final raw = entry.rawContent;
    if (raw is! ZipFile) return;
    final stored = raw.getStream(decompress: false);
    if (stored is RangedInput) await stored.loadRest();
  }

  /// [entry]'s content in pieces of at most [piece] bytes: stored entries
  /// (blobs) straight from the file, loading each piece first where the
  /// file is read in slices; others decompressed whole first.
  static Stream<List<int>> chunks(ArchiveFile entry, {int piece = 1 << 20}) async* {
    final raw = entry.rawContent;
    final stored = raw is ZipFile && raw.compressionMethod == CompressionType.none;
    if (!stored) await load(entry);
    final InputStream? content;
    try {
      content = stored ? raw.getStream(decompress: false) : entry.getContent();
    } on Object catch (e) {
      throw FormatException('Unreadable entry ${entry.name}: $e');
    }
    if (content == null) return;
    content.reset();
    while (!content.isEOS) {
      final n = content.length < piece ? content.length : piece;
      if (content is RangedInput) await content.loadNext(n);
      yield content.readBytes(n).toUint8List();
    }
  }

  /// The lines of [part] that aren't empty, each a record ([parseRecord]);
  /// throws [LenArchiveException] if the part can't be read at all. In a
  /// browser it is inflated and decoded off the UI thread
  /// ([inflateUtf8Text]); parsing is left to the caller, a line at a time,
  /// so a big part needn't hold the UI thread.
  static Future<List<String>> recordLines(ArchiveFile part) async {
    final String text;
    try {
      await load(part);
      text = await _textOf(part);
    } on LenArchiveException {
      rethrow;
    } on Object catch (e) {
      throw LenArchiveException.damaged('${part.name}: $e');
    }
    return [
      for (final line in const LineSplitter().convert(text))
        if (line.isNotEmpty) line,
    ];
  }

  /// The record [line] holds; null if it is not one (not JSON, or not a
  /// record).
  static SyncRecord? parseRecord(String line) {
    try {
      return SyncRecord.fromJson(jsonDecode(line));
    } on FormatException catch (e) {
      // Not JSON, or not a record: skipped, the rest is read.
      debugPrint('Skipping a malformed record: ${e.message}');
      return null;
    }
  }

  /// [entry]'s content as text: inflated by the browser where it can,
  /// else decompressed here.
  static Future<String> _textOf(ArchiveFile entry) async {
    final raw = entry.rawContent;
    if (raw is ZipFile && raw.compressionMethod == CompressionType.deflate) {
      if (await inflateUtf8Text(raw.getRawContent()) case final text?) return text;
    }
    return utf8.decode(_bytesOf(entry));
  }

  /// [entry]'s content, decompressed afresh and not kept on the entry, so
  /// it needn't be closed: closing an entry read from a file ends its data
  /// there, and a part is read twice (a backup's contents, then its import).
  static Uint8List _bytesOf(ArchiveFile entry) => entry.rawContent?.readBytes() ?? Uint8List(0);

  /// The JSON in [entry]; throws [LenArchiveException] if damaged.
  static Object? readJson(ArchiveFile entry) {
    try {
      return jsonDecode(utf8.decode(_bytesOf(entry)));
    } on Object catch (e) {
      throw LenArchiveException.damaged('${entry.name}: $e');
    }
  }
}
