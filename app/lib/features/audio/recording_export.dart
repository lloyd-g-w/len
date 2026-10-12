import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/blob_store.dart';
import '../../domain/recording.dart';
import '../../platform/file_export.dart' as platform;
import '../documents/export/export_flow.dart' show ExportFile, ExportSaver;
import '../documents/export/export_options.dart' show safeFileName;
import '../documents/progress_dialog.dart' show showMessage;
import 'adts.dart';

/// The file extension of audio of [mime] (`m4a` for AAC in MP4, `aac` for
/// raw AAC in ADTS frames).
String audioExtension(String mime) => switch (mime) {
  'audio/mp4' || 'audio/m4a' => 'm4a',
  'audio/aac' => 'aac',
  'audio/webm' => 'webm',
  'audio/wav' || 'audio/x-wav' => 'wav',
  'audio/ogg' => 'ogg',
  _ => 'audio',
};

/// Whether [r]'s export keeps to its trim: raw AAC is cut at frame
/// boundaries; other formats (browser recordings, whole MP4 / WebM files)
/// would need decoding, so they export untrimmed.
bool exportsTrimmed(Recording r) => r.trimmed && r.mime == Recording.adtsMime;

/// The files a recording exports as: its parts joined into one where they
/// join by concatenation (see [Recording.joinable]), else one file per part
/// (browser recordings), as lists of blobs.
List<List<String>> exportGroups(Recording r) => r.joinable
    ? [r.blobs.toList()]
    : [
        for (final sha in r.blobs) [sha],
      ];

/// File names for [recordings]' [exportGroups] ("Lecture.aac"; repeated
/// titles numbered; parts exported separately as "Lecture (part 2).webm").
List<String> recordingFileNames(List<Recording> recordings) {
  final used = <String>{};
  String unique(String base, String ext) {
    var name = '$base.$ext';
    for (var n = 2; !used.add(name); n++) {
      name = '$base ($n).$ext';
    }
    return name;
  }

  return [
    for (final r in recordings)
      for (final (i, _) in exportGroups(r).indexed)
        unique(
          i == 0 ? safeFileName(r.title) : '${safeFileName(r.title)} (part ${i + 1})',
          audioExtension(r.mime),
        ),
  ];
}

/// Hands [recordings]' audio to the user through the app's export path:
/// a save dialog on desktop, the share sheet on Android, a download in
/// browsers. Missing audio is fetched from the sync server first.
Future<void> exportRecordings(
  BuildContext context,
  List<Recording> recordings, {
  required BlobStore blobs,
  required Future<bool> Function(String sha) fetch,
  ExportSaver save = platform.saveOrShareAll,
}) async {
  if (recordings.isEmpty) return;
  final names = recordingFileNames(recordings);
  final files = <ExportFile>[];
  for (final r in recordings) {
    for (final group in exportGroups(r)) {
      final joined = BytesBuilder(copy: false);
      for (final sha in group) {
        var bytes = await blobs.read(sha);
        if (bytes == null && await fetch(sha)) bytes = await blobs.read(sha);
        if (bytes == null) {
          if (context.mounted) {
            showMessage(context, '“${r.title}” is not on this device yet. Sync and try again.');
          }
          return;
        }
        joined.add(bytes);
      }
      final audio = joined.takeBytes();
      files.add((
        bytes: exportsTrimmed(r) ? AdtsReader.cut(audio, r.trimStartMs, r.trimEndMs) : audio,
        name: names[files.length],
      ));
    }
  }
  if (!context.mounted) return;
  final mimes = recordings.map((r) => r.mime).toSet();
  try {
    final saved = await save(files, mime: mimes.length == 1 ? mimes.single : 'audio/*');
    if (saved == null || !context.mounted) return;
    showMessage(
      context,
      recordings.length == 1 ? 'Saved $saved' : 'Saved ${recordings.length} recordings',
    );
  } on Exception catch (e) {
    if (context.mounted) showMessage(context, 'Export failed: $e');
  }
}
