import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/blob_store.dart';
import '../../domain/recording.dart';
import '../../domain/recording_release.dart';
import '../../platform/file_export.dart' as platform;
import '../documents/export/export_flow.dart' show ExportFile, ExportSaver;
import '../documents/export/export_messages.dart';
import '../documents/export/export_options.dart' show safeFileName;
import '../documents/progress_dialog.dart' show showMessage;
import 'adts.dart';
import 'mp4_cut.dart';
import 'webm_cut.dart';

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

/// One file a recording exports as: [blobs] joined, cut to [fromMs]…[toMs]
/// (positions in the joined audio; null where nothing is cut away).
typedef ExportGroup = ({List<String> blobs, int? fromMs, int? toMs});

/// The files a recording exports as: its parts joined into one where they
/// join by concatenation (see [Recording.joinable]), else one file per part
/// the trim touches (browser recordings), each with the cut that keeps
/// to the trim.
List<ExportGroup> exportGroups(Recording r) {
  ExportGroup group(List<String> blobs, int fromMs, int toMs, int durationMs) =>
      (blobs: blobs, fromMs: fromMs > 0 ? fromMs : null, toMs: toMs < durationMs ? toMs : null);
  if (r.joinable) return [group(r.blobs.toList(), r.trimStartMs, r.trimEndMs, r.durationMs)];
  final kept = r.partsTouching(r.trimStartMs, r.trimEndMs);
  return [
    for (var i = kept.first; i < kept.end; i++)
      group(
        [r.parts[i].blob],
        r.trimStartMs - r.parts.startOf(i),
        r.trimEndMs - r.parts.startOf(i),
        r.parts[i].durationMs,
      ),
  ];
}

/// [audio] (a file of [mime]) cut to [fromMs]…[toMs] (null: that end not
/// cut), or null when it can't be: raw AAC is cut at frame boundaries,
/// browser recordings (WebM, fragmented MP4) at packet boundaries.
Uint8List? cutAudio(String mime, Uint8List audio, {int? fromMs, int? toMs}) {
  if (fromMs == null && toMs == null) return audio;
  return switch (mime) {
    Recording.adtsMime => AdtsReader.cut(audio, fromMs ?? 0, toMs ?? _end),
    'audio/webm' => WebmCut.cut(audio, fromMs: fromMs, toMs: toMs),
    'audio/mp4' || 'audio/m4a' => Mp4Cut.cut(audio, fromMs: fromMs, toMs: toMs),
    _ => null,
  };
}

/// Beyond any audio (fits browsers' integers).
const int _end = 1 << 30;

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
/// a save dialog on desktop, the share sheet on Android (with [toDevice]
/// the system's save dialog), a download in browsers. Missing audio is
/// fetched from the sync server first.
Future<void> exportRecordings(
  BuildContext context,
  List<Recording> recordings, {
  required BlobStore blobs,
  required Future<bool> Function(String sha) fetch,
  ExportSaver save = platform.saveOrShareAll,
  bool toDevice = false,
}) async {
  if (recordings.isEmpty) return;
  final names = recordingFileNames(recordings);
  final files = <ExportFile>[];
  var wider = false; // Some audio couldn't be cut to its trim.
  for (final r in recordings) {
    for (final group in exportGroups(r)) {
      final joined = BytesBuilder(copy: false);
      for (final sha in group.blobs) {
        var bytes = await blobs.read(sha);
        if (bytes == null && await fetch(sha)) bytes = await blobs.read(sha);
        if (bytes == null) {
          if (context.mounted) {
            showMessage(
              context,
              '“${r.title}” is not on this device yet. It downloads when you’re online.',
            );
          }
          return;
        }
        joined.add(bytes);
      }
      final audio = joined.takeBytes();
      final cut = cutAudio(r.mime, audio, fromMs: group.fromMs, toMs: group.toMs);
      wider |= cut == null;
      files.add((bytes: cut ?? audio, name: names[files.length]));
    }
  }
  if (!context.mounted) return;
  final mimes = recordings.map((r) => r.mime).toSet();
  try {
    final saved = await save(
      files,
      mime: mimes.length == 1 ? mimes.single : 'audio/*',
      toDevice: toDevice,
    );
    if (saved == null || !context.mounted) return;
    showExported(
      context,
      saved,
      plural: 'recordings',
      note: wider
          ? 'some audio couldn’t be cut, so it may start earlier or end later than the trim'
          : null,
    );
  } on Exception catch (e) {
    debugPrint('Recording export failed: $e');
    if (!context.mounted) return;
    final subject = recordings.length == 1
        ? '“${recordings.single.title}”'
        : '${recordings.length} recordings';
    showExportFailed(context, subject, e);
  }
}
