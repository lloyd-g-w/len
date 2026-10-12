import 'dart:convert';
import 'dart:typed_data';

import '../../domain/recording.dart';

/// What is known about a recording in progress, kept next to its files in
/// the spool (`SpoolStorage`, `<id>.json`) and rewritten whenever it
/// changes (start, each finished part, pause, resume), so a recording cut
/// off by the app being killed can be recovered (`RecordingRecovery`).
class RecordingJournal {
  RecordingJournal({
    required this.recordingId,
    required this.notebookId,
    required this.title,
    required this.mime,
    this.parts = const [],
    this.segments = const [],
    this.openSince,
    this.files = const [],
    this.waveform = '',
  });

  final String recordingId;
  final String notebookId;
  final String title;
  final String mime;

  /// Parts already stored as blobs (and in the `recordings` row).
  final List<RecordingPart> parts;

  /// Closed stretches of capture (pauses between them).
  final List<RecordingSegment> segments;

  /// Wall time the running stretch began; null while paused.
  final int? openSince;

  /// Spool files of audio not stored as blobs yet, in order: the file being
  /// written last.
  final List<String> files;

  /// The last stored waveform blob, `''` for none.
  final String waveform;

  /// The journal's file name in the spool.
  static String nameOf(String recordingId) => '$recordingId.json';

  /// Whether spool file [name] is a journal.
  static bool isJournal(String name) => name.endsWith('.json');

  RecordingJournal copyWith({
    List<RecordingPart>? parts,
    List<RecordingSegment>? segments,
    int? Function()? openSince,
    List<String>? files,
    String? waveform,
  }) => RecordingJournal(
    recordingId: recordingId,
    notebookId: notebookId,
    title: title,
    mime: mime,
    parts: parts ?? this.parts,
    segments: segments ?? this.segments,
    openSince: openSince == null ? this.openSince : openSince(),
    files: files ?? this.files,
    waveform: waveform ?? this.waveform,
  );

  Uint8List encode() => utf8.encode(
    jsonEncode({
      'recording': recordingId,
      'notebook': notebookId,
      'title': title,
      'mime': mime,
      'parts': [for (final p in parts) p.toJson()],
      'segments': [for (final s in segments) s.toJson()],
      'openSince': openSince,
      'files': files,
      'waveform': waveform,
    }),
  );

  /// Parses an encoded journal; null when malformed.
  static RecordingJournal? tryDecode(Uint8List bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      final parts = [for (final p in json['parts']! as List) RecordingPart.tryParse(p)!];
      final segments = [for (final s in json['segments']! as List) RecordingSegment.tryParse(s)!];
      return RecordingJournal(
        recordingId: json['recording']! as String,
        notebookId: json['notebook']! as String,
        title: json['title']! as String,
        mime: json['mime']! as String,
        parts: parts,
        segments: segments,
        openSince: json['openSince'] as int?,
        files: [for (final f in json['files']! as List) f as String],
        waveform: json['waveform']! as String,
      );
    } on Object {
      return null;
    }
  }

  /// The timeline of [durationMs] of audio captured in the closed
  /// [segments] plus, when [openSince] is set, a running stretch from then:
  /// the running stretch gets what the closed ones don't cover, and
  /// otherwise the last stretch is lengthened or cut so the timeline
  /// matches the audio (wall-clock and audio time drift apart slightly).
  List<RecordingSegment> timelineFor(int durationMs) {
    final result = <RecordingSegment>[];
    var left = durationMs;
    for (final s in segments) {
      if (left <= 0) break;
      final d = s.durationMs < left ? s.durationMs : left;
      result.add(RecordingSegment(s.startedAt, d));
      left -= d;
    }
    final open = openSince;
    if (open != null) {
      if (left > 0 || result.isEmpty) result.add(RecordingSegment(open, left < 0 ? 0 : left));
    } else if (left > 0) {
      if (result.isEmpty) return [RecordingSegment(segments.firstOrNull?.startedAt ?? 0, left)];
      final last = result.removeLast();
      result.add(RecordingSegment(last.startedAt, last.durationMs + left));
    }
    return result.isEmpty ? [RecordingSegment(open ?? 0, 0)] : result;
  }
}
