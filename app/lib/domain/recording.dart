import 'package:flutter/foundation.dart';

import 'waveform.dart';

/// One stretch of continuous capture in a [Recording]: it began at wall
/// time [startedAt] (epoch ms) and lasted [durationMs] of audio. Pausing a
/// recording ends a segment; resuming starts the next one.
@immutable
class RecordingSegment {
  const RecordingSegment(this.startedAt, this.durationMs);

  final int startedAt;
  final int durationMs;

  int get endedAt => startedAt + durationMs;

  /// `[startedAt, durationMs]`, as stored and synced.
  List<int> toJson() => [startedAt, durationMs];

  /// Parses `[startedAt, durationMs]`; null when malformed.
  static RecordingSegment? tryParse(Object? json) {
    if (json is! List || json.length < 2) return null;
    final start = json[0], duration = json[1];
    if (start is! int || duration is! int || duration < 0) return null;
    return RecordingSegment(start, duration);
  }

  @override
  bool operator ==(Object other) =>
      other is RecordingSegment && other.startedAt == startedAt && other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(startedAt, durationMs);

  @override
  String toString() => 'RecordingSegment($startedAt, $durationMs)';
}

/// An audio recording made while taking notes in a notebook (synced
/// collection `recordings`). The audio itself is a content-addressed blob.
@immutable
class Recording {
  Recording({
    required this.id,
    required this.notebookId,
    required this.blob,
    required this.durationMs,
    required this.startedAt,
    required this.title,
    required this.mime,
    required this.updatedAt,
    this.waveform = '',
    List<RecordingSegment>? segments,
  }) : segments = List.unmodifiable(
         segments == null || segments.isEmpty
             ? [RecordingSegment(startedAt, durationMs)]
             : segments,
       );

  final String id;
  final String notebookId;

  /// SHA-256 of the audio bytes (see `BlobStore`).
  final String blob;
  final int durationMs;

  /// Wall time (epoch ms) recording began.
  final int startedAt;
  final String title;

  /// MIME type of the audio, e.g. `audio/mp4`.
  final String mime;
  final int updatedAt;

  /// SHA-256 of the recording's [Waveform] blob, or `''` when it has none.
  final String waveform;

  /// Capture segments in order (pauses between them). Never empty: a
  /// recording without pauses is one segment from [startedAt].
  final List<RecordingSegment> segments;

  /// Maps between audio positions and wall-clock times.
  RecordingTimeline get timeline => RecordingTimeline(segments);

  Recording copyWith({String? title, int? updatedAt}) => Recording(
    id: id,
    notebookId: notebookId,
    blob: blob,
    durationMs: durationMs,
    startedAt: startedAt,
    title: title ?? this.title,
    mime: mime,
    updatedAt: updatedAt ?? this.updatedAt,
    waveform: waveform,
    segments: segments,
  );
}

/// Maps audio positions of a recording to the wall-clock times (epoch ms)
/// they were captured at, and back — so ink (whose strokes carry their
/// `createdAt`) can be replayed in step with the audio.
///
/// Pauses leave gaps in wall time that the audio skips: ink written
/// during a pause belongs to the moment the recording resumed.
class RecordingTimeline {
  RecordingTimeline(this.segments) : assert(segments.isNotEmpty);

  final List<RecordingSegment> segments;

  int get durationMs => segments.fold(0, (sum, s) => sum + s.durationMs);

  /// The wall time captured at audio [positionMs] (clamped to the
  /// recording).
  int wallTimeAt(int positionMs) {
    var offset = 0;
    for (final s in segments) {
      if (positionMs < offset + s.durationMs) {
        return s.startedAt + (positionMs - offset).clamp(0, s.durationMs);
      }
      offset += s.durationMs;
    }
    return segments.last.endedAt;
  }

  /// The audio position at which wall time [epochMs] was captured, or null
  /// when it lies outside the recording. Times in a pause map to where the
  /// next segment starts.
  int? positionOf(int epochMs) {
    if (epochMs < segments.first.startedAt || epochMs > segments.last.endedAt) return null;
    var offset = 0;
    for (final s in segments) {
      if (epochMs < s.startedAt) return offset; // In the pause before s.
      if (epochMs <= s.endedAt) return offset + epochMs - s.startedAt;
      offset += s.durationMs;
    }
    return offset;
  }

  /// Whether wall time [epochMs] falls within the recording (pauses
  /// included).
  bool covers(int epochMs) => positionOf(epochMs) != null;
}
