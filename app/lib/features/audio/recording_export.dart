import 'package:flutter/material.dart';

import '../../data/blob_store.dart';
import '../../domain/recording.dart';
import '../../platform/file_export.dart' as platform;
import '../documents/export/export_flow.dart' show ExportFile, ExportSaver;
import '../documents/export/export_options.dart' show safeFileName;
import '../documents/progress_dialog.dart' show showMessage;

/// The file extension of audio of [mime] (`m4a` for AAC in MP4).
String audioExtension(String mime) => switch (mime) {
  'audio/mp4' || 'audio/m4a' || 'audio/aac' => 'm4a',
  'audio/webm' => 'webm',
  'audio/wav' || 'audio/x-wav' => 'wav',
  'audio/ogg' => 'ogg',
  _ => 'audio',
};

/// File names for [recordings] ("Lecture.m4a"; repeated titles numbered).
List<String> recordingFileNames(List<Recording> recordings) {
  final used = <String>{};
  return [
    for (final r in recordings)
      () {
        final base = safeFileName(r.title);
        final ext = audioExtension(r.mime);
        var name = '$base.$ext';
        for (var n = 2; !used.add(name); n++) {
          name = '$base ($n).$ext';
        }
        return name;
      }(),
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
  for (final (i, r) in recordings.indexed) {
    var bytes = await blobs.read(r.blob);
    if (bytes == null && await fetch(r.blob)) bytes = await blobs.read(r.blob);
    if (bytes == null) {
      if (context.mounted) {
        showMessage(context, '“${r.title}” is not on this device yet. Sync and try again.');
      }
      return;
    }
    files.add((bytes: bytes, name: names[i]));
  }
  if (!context.mounted) return;
  final mimes = recordings.map((r) => r.mime).toSet();
  try {
    final saved = await save(files, mime: mimes.length == 1 ? mimes.single : 'audio/*');
    if (saved == null || !context.mounted) return;
    showMessage(context, files.length == 1 ? 'Saved $saved' : 'Saved ${files.length} recordings');
  } on Exception catch (e) {
    if (context.mounted) showMessage(context, 'Export failed: $e');
  }
}
