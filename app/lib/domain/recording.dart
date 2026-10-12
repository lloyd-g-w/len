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

/// One file of a [Recording]'s audio: content-addressed blob [blob] holding
/// [durationMs] of audio. Long recordings are captured in parts (see
/// `RecordingController.partMs`) so finished parts can sync while
/// recording continues; played one after the other they are the
/// recording.
@immutable
class RecordingPart {
  const RecordingPart(this.blob, this.durationMs);

  /// SHA-256 of the part's audio bytes (see `BlobStore`).
  final String blob;
  final int durationMs;

  /// `[blob, durationMs]`, as stored and synced.
  List<Object> toJson() => [blob, durationMs];

  /// Parses `[blob, durationMs]`; null when malformed (the blob id is
  /// checked by the caller).
  static RecordingPart? tryParse(Object? json) {
    if (json is! List || json.length != 2) return null;
    final blob = json[0], duration = json[1];
    if (blob is! String || duration is! int || duration < 0) return null;
    return RecordingPart(blob, duration);
  }

  @override
  bool operator ==(Object other) =>
      other is RecordingPart && other.blob == blob && other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(blob, durationMs);

  @override
  String toString() => 'RecordingPart($blob, $durationMs)';
}

/// Where audio position [positionMs] of a recording lies: part [index],
/// [offsetMs] into it.
typedef PartPosition = ({int index, int offsetMs});

/// Maps positions of a recording to its [RecordingPart]s and back.
extension RecordingPartsMap on List<RecordingPart> {
  /// The position in the whole recording at which part [index] begins.
  int startOf(int index) => take(index).fold(0, (sum, p) => sum + p.durationMs);

  /// The part playing at [positionMs] (clamped to the recording; a
  /// position on a boundary belongs to the later part).
  PartPosition partAt(int positionMs) {
    var start = 0;
    for (var i = 0; i < length - 1; i++) {
      if (positionMs < start + this[i].durationMs) {
        return (index: i, offsetMs: (positionMs - start).clamp(0, this[i].durationMs));
      }
      start += this[i].durationMs;
    }
    return (index: length - 1, offsetMs: (positionMs - start).clamp(0, last.durationMs));
  }
}

/// An audio recording made while taking notes in a notebook (synced
/// collection `recordings`). The audio itself is one or more
/// content-addressed blobs ([parts]).
@immutable
class Recording {
  Recording({
    required this.id,
    required this.notebookId,
    required List<RecordingPart> parts,
    required this.durationMs,
    required this.startedAt,
    required this.title,
    required this.mime,
    required this.updatedAt,
    this.waveform = '',
    List<RecordingSegment>? segments,
    this.trimStartMs = 0,
    int? trimEndMs,
  }) : trimEndMs = trimEndMs ?? durationMs,
       segments = List.unmodifiable(
         segments == null || segments.isEmpty
             ? [RecordingSegment(startedAt, durationMs)]
             : segments,
       ),
       parts = List.unmodifiable(parts);

  final String id;
  final String notebookId;

  /// The audio, in order (never empty).
  final List<RecordingPart> parts;

  /// Audio length (the sum of the [parts]).
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

  /// Where the kept audio begins and ends (positions in the whole audio;
  /// `0` and [durationMs] when untrimmed). Trimming is non-destructive:
  /// the parts keep all the audio, playback, export and the overview keep
  /// to this range.
  final int trimStartMs, trimEndMs;

  /// Whether the recording is trimmed.
  bool get trimmed => trimStartMs > 0 || trimEndMs < durationMs;

  /// Length of the kept audio (what the user hears and is shown).
  int get lengthMs => trimEndMs - trimStartMs;

  /// The shortest audio a trim keeps.
  static const int minTrimMs = 1000;

  /// The audio position at which ink made at wall time [epochMs] was heard,
  /// or null when that lies outside the kept audio (ink made before the
  /// trim start then counts as written before the recording, ink made after
  /// its end as written after it).
  int? inkPositionOf(int epochMs) {
    final position = timeline.positionOf(epochMs);
    return position == null || position < trimStartMs || position > trimEndMs ? null : position;
  }

  /// The wall time at which the kept audio ends when the end is trimmed
  /// away, else null: ink made after it is not replayed (always shown).
  int? get keptUntil => trimEndMs < durationMs ? timeline.wallTimeAt(trimEndMs) : null;

  /// MIME type of raw AAC in ADTS frames: parts of this type joined byte
  /// by byte are one playable stream.
  static const String adtsMime = 'audio/aac';

  /// Whether the parts can be joined into one file by concatenation.
  bool get joinable => parts.length == 1 || mime == adtsMime;

  /// The blobs of the audio, in order.
  Iterable<String> get blobs => parts.map((p) => p.blob);

  /// Maps between audio positions and wall-clock times.
  RecordingTimeline get timeline => RecordingTimeline(segments);

  Recording copyWith({String? title, int? updatedAt, int? trimStartMs, int? trimEndMs}) =>
      Recording(
        id: id,
        notebookId: notebookId,
        parts: parts,
        durationMs: durationMs,
        startedAt: startedAt,
        title: title ?? this.title,
        mime: mime,
        updatedAt: updatedAt ?? this.updatedAt,
        waveform: waveform,
        segments: segments,
        trimStartMs: trimStartMs ?? this.trimStartMs,
        trimEndMs: trimEndMs ?? this.trimEndMs,
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
