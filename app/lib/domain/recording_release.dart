import 'recording.dart';
import 'waveform.dart';

/// Releasing the audio a trim leaves out: the parts lying wholly outside a
/// recording's kept range can be dropped (their blobs are then collected
/// like any unreferenced blob), the rest is rewritten to start at the first
/// part kept — positions, timeline and waveform shift with it, so the ink
/// still maps to the same moments.
extension RecordingRelease on Recording {
  /// The parts that audio [startMs]…[endMs] touches: indices
  /// [first]…[end] (exclusive). Parts wholly before or after it lie
  /// outside.
  ({int first, int end}) partsTouching(int startMs, int endMs) {
    var first = 0, end = parts.length, offset = 0;
    for (var i = 0; i < parts.length; i++) {
      final partEnd = offset + parts[i].durationMs;
      if (partEnd <= startMs && i < parts.length - 1) {
        first = i + 1;
      } else if (offset >= endMs && i > first) {
        end = i;
        break;
      }
      offset = partEnd;
    }
    return (first: first, end: end);
  }

  /// The parts lying wholly outside the trim (none when untrimmed).
  List<RecordingPart> get partsOutsideTrim {
    final kept = partsTouching(trimStartMs, trimEndMs);
    return [...parts.take(kept.first), ...parts.skip(kept.end)];
  }

  /// This recording without [partsOutsideTrim]: the kept parts, their
  /// duration, the trim and the timeline moved to begin at the first kept
  /// part, with [waveform] (the old one sliced the same way, or `''`) and
  /// version [updatedAt]. Returns this recording when nothing lies outside.
  Recording withoutPartsOutsideTrim({required String waveform, required int updatedAt}) {
    final kept = partsTouching(trimStartMs, trimEndMs);
    if (kept.first == 0 && kept.end == parts.length) return this;
    final from = parts.startOf(kept.first);
    final keptParts = parts.sublist(kept.first, kept.end);
    final duration = keptParts.fold(0, (sum, p) => sum + p.durationMs);
    final segments = timeline.slice(from, from + duration);
    return Recording(
      id: id,
      notebookId: notebookId,
      parts: keptParts,
      durationMs: duration,
      startedAt: segments.isEmpty ? startedAt : segments.first.startedAt,
      title: title,
      mime: mime,
      updatedAt: updatedAt,
      waveform: waveform,
      segments: segments,
      trimStartMs: trimStartMs - from,
      trimEndMs: trimEndMs - from,
    );
  }

  /// Where the kept parts begin and end in the whole audio (what
  /// [withoutPartsOutsideTrim] keeps of the waveform).
  ({int fromMs, int toMs}) get keptPartsRange {
    final kept = partsTouching(trimStartMs, trimEndMs);
    return (fromMs: parts.startOf(kept.first), toMs: parts.startOf(kept.end));
  }
}

/// Cutting a timeline to a stretch of its audio.
extension RecordingTimelineSlice on RecordingTimeline {
  /// The segments of audio [fromMs]…[toMs], each keeping the wall times it
  /// was captured at (a segment cut at the start begins later).
  List<RecordingSegment> slice(int fromMs, int toMs) {
    final out = <RecordingSegment>[];
    var offset = 0;
    for (final s in segments) {
      final start = offset > fromMs ? offset : fromMs;
      final end = offset + s.durationMs < toMs ? offset + s.durationMs : toMs;
      if (end > start) out.add(RecordingSegment(s.startedAt + start - offset, end - start));
      offset += s.durationMs;
    }
    return out;
  }
}

/// Cutting a waveform to a stretch of its audio.
extension WaveformSlice on Waveform {
  /// The levels of audio [fromMs]…[toMs] (to the nearest bucket).
  Waveform slice(int fromMs, int toMs) {
    final from = (fromMs / bucketMs).round().clamp(0, levels.length);
    final to = (toMs / bucketMs).round().clamp(from, levels.length);
    return Waveform(levels.sublist(from, to), bucketMs: bucketMs);
  }
}
