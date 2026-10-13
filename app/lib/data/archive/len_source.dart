import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../syncable.dart';
import 'len_format.dart';

/// A Len file opened for import: its manifest is read (so the user can be
/// asked first), its records and blobs not yet. [close] it when done.
class LenSource {
  LenSource._(this.input, this.archive, this.manifest);

  /// Opens [input] and reads its manifest; throws [LenArchiveException] if
  /// it is not a Len file this build reads (and closes [input]).
  static Future<LenSource> open(InputStream input) async {
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(input);
      } on Object catch (e) {
        throw LenArchiveException.notLen('$e');
      }
      final entry = archive.find(LenFormat.manifestName);
      if (entry == null) throw const LenArchiveException.notLen('no manifest');
      final Object? json;
      try {
        json = readJson(entry);
      } on LenArchiveException catch (e) {
        throw LenArchiveException.notLen(e.details);
      }
      return LenSource._(input, archive, LenManifest.fromJson(json));
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
  /// Damaged parts are passed over.
  late final ({Set<String> folders, Map<String, String> notebooks}) contents = _contents();

  ({Set<String> folders, Map<String, String> notebooks}) _contents() {
    final folders = <String>{}, notebooks = <String, String>{};
    for (final part in parts) {
      final List<SyncRecord?> records;
      try {
        records = readRecords(part);
      } on LenArchiveException {
        continue;
      } finally {
        part.closeSync();
      }
      for (final r in records) {
        if (r == null || r.deleted) continue;
        switch (r.collection) {
          case 'folders':
            folders.add(r.id);
          case 'notebooks':
            final title = r.data?['title'];
            notebooks[r.id] = title is String ? title : '';
          case 'templates':
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

  /// The records of [part], null for each line that is not one (not JSON,
  /// or not a record); throws [LenArchiveException] if the part can't be
  /// read at all.
  static List<SyncRecord?> readRecords(ArchiveFile part) {
    final String text;
    try {
      text = utf8.decode(part.readBytes() ?? const []);
    } on Object catch (e) {
      throw LenArchiveException.damaged('${part.name}: $e');
    }
    final records = <SyncRecord?>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty) continue;
      try {
        records.add(SyncRecord.fromJson(jsonDecode(line)));
      } on FormatException catch (e) {
        // Not JSON, or not a record: skipped, the rest is read.
        debugPrint('Skipping a malformed record: ${e.message}');
        records.add(null);
      }
    }
    return records;
  }

  /// The JSON in [entry]; throws [LenArchiveException] if damaged.
  static Object? readJson(ArchiveFile entry) {
    try {
      return jsonDecode(utf8.decode(entry.readBytes() ?? const []));
    } on Object catch (e) {
      throw LenArchiveException.damaged('${entry.name}: $e');
    } finally {
      entry.closeSync();
    }
  }
}
