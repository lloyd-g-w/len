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

/// Audio to export as one file: [blobs] joined, cut to [fromMs]…[toMs]
/// (positions in the joined audio; null where nothing is cut away).
/// [startsMs] is null where the blobs join by concatenation (one stream),
/// else each blob is a file of its own starting that far into the
/// joined audio (browser recordings: joined by [joinAudio]).
typedef ExportGroup = ({List<String> blobs, List<int>? startsMs, int? fromMs, int? toMs});

/// The one file a recording exports as: its parts the trim touches (all
/// of them where they join by concatenation, see [Recording.joinable]),
/// with the cut that keeps to the trim. A browser recording's parts are
/// joined into one file too (UX_AUDIT R27-10).
ExportGroup exportGroupOf(Recording r) {
  ExportGroup group(List<String> blobs, List<int>? starts, int fromMs, int toMs, int durationMs) =>
      (
        blobs: blobs,
        startsMs: starts,
        fromMs: fromMs > 0 ? fromMs : null,
        toMs: toMs < durationMs ? toMs : null,
      );
  if (r.joinable) return group(r.blobs.toList(), null, r.trimStartMs, r.trimEndMs, r.durationMs);
  final kept = r.partsTouching(r.trimStartMs, r.trimEndMs);
  final from = r.parts.startOf(kept.first);
  return group(
    [for (var i = kept.first; i < kept.end; i++) r.parts[i].blob],
    [for (var i = kept.first; i < kept.end; i++) r.parts.startOf(i) - from],
    r.trimStartMs - from,
    r.trimEndMs - from,
    r.parts.startOf(kept.end) - from,
  );
}

/// [group] as one file per part (should its parts not join): each part
/// with the cut that keeps to the trim.
List<ExportGroup> partGroupsOf(ExportGroup group) {
  final starts = group.startsMs;
  if (starts == null) return [group];
  return [
    for (final (i, blob) in group.blobs.indexed)
      (
        blobs: [blob],
        startsMs: null,
        fromMs: switch (group.fromMs) {
          final from? when from > starts[i] => from - starts[i],
          _ => null,
        },
        toMs: switch (group.toMs) {
          final to? when i + 1 == starts.length || to < starts[i + 1] => to - starts[i],
          _ => null,
        },
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

/// [parts] (files of [mime], each [startsMs] into the whole: a browser
/// recording's parts) joined into one file cut to [fromMs]…[toMs] of the
/// whole (null: that end not cut), or null when they can't be.
Uint8List? joinAudio(
  String mime,
  List<Uint8List> parts,
  List<int> startsMs, {
  int? fromMs,
  int? toMs,
}) {
  if (parts.length == 1) return cutAudio(mime, parts.single, fromMs: fromMs, toMs: toMs);
  final files = [for (final (i, p) in parts.indexed) (bytes: p, startMs: startsMs[i])];
  return switch (mime) {
    'audio/webm' => WebmCut.join(files, fromMs: fromMs, toMs: toMs),
    'audio/mp4' || 'audio/m4a' => Mp4Cut.join(files, fromMs: fromMs, toMs: toMs),
    _ => null,
  };
}

/// Beyond any audio (fits browsers' integers).
const int _end = 1 << 30;

/// File names for [recordings], one each ("Lecture.aac"; repeated titles
/// numbered).
List<String> recordingFileNames(List<Recording> recordings) {
  final used = <String>{};
  return [for (final r in recordings) _unique(used, safeFileName(r.title), audioExtension(r.mime))];
}

String _unique(Set<String> used, String base, String ext) {
  var name = '$base.$ext';
  for (var n = 2; !used.add(name); n++) {
    name = '$base ($n).$ext';
  }
  return name;
}

/// Part [index] of the file named [name] ("Lecture.webm": "Lecture (part
/// 2).webm"), for parts that could not be joined.
String _partName(String name, int index) {
  if (index == 0) return name;
  final dot = name.lastIndexOf('.');
  return '${name.substring(0, dot)} (part ${index + 1})${name.substring(dot)}';
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
  for (final (n, r) in recordings.indexed) {
    final group = exportGroupOf(r);
    final parts = <Uint8List>[];
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
      parts.add(bytes);
    }
    if (group.startsMs case final starts?) {
      final joined = joinAudio(r.mime, parts, starts, fromMs: group.fromMs, toMs: group.toMs);
      if (joined != null) {
        files.add((bytes: joined, name: names[n]));
        continue;
      }
      // Parts that don't join: one file each, cut where they can be.
      for (final (i, part) in partGroupsOf(group).indexed) {
        final cut = cutAudio(r.mime, parts[i], fromMs: part.fromMs, toMs: part.toMs);
        wider |= cut == null;
        files.add((bytes: cut ?? parts[i], name: _partName(names[n], i)));
      }
      continue;
    }
    final joined = BytesBuilder(copy: false);
    parts.forEach(joined.add);
    final audio = joined.takeBytes();
    final cut = cutAudio(r.mime, audio, fromMs: group.fromMs, toMs: group.toMs);
    wider |= cut == null;
    files.add((bytes: cut ?? audio, name: names[n]));
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
