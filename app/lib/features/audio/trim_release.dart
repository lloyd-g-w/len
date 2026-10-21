import 'package:flutter/foundation.dart';

import '../../data/blob_store.dart';
import '../../data/recording_repository.dart';
import '../../domain/recording.dart';
import '../../domain/recording_release.dart';
import '../../domain/waveform.dart';

/// What dropping [recording]'s parts outside its trim frees on this
/// device: their blobs present here and not [shared] with other recordings
/// (a duplicated notebook's). Of those, the ones a version of the notebook
/// names ([namedByVersions]) stay until no version does (thinned or
/// deleted: versions restore the audio they were made with), [held]; the
/// rest go after garbage collection's grace, [freed]. Null when no part
/// lies wholly outside the trim.
({int freed, int held})? releasableBytes(
  Recording recording, {
  required BlobStore blobs,
  required Set<String> shared,
  bool Function(String sha)? namedByVersions,
}) {
  final outside = recording.partsOutsideTrim;
  if (outside.isEmpty) return null;
  var freed = 0, held = 0;
  for (final sha in {
    for (final p in outside)
      if (!shared.contains(p.blob)) p.blob,
  }) {
    final size = blobs.sizeOf(sha) ?? 0;
    if (namedByVersions?.call(sha) ?? false) {
      held += size;
    } else {
      freed += size;
    }
  }
  return (freed: freed, held: held);
}

/// Drops recording [id]'s parts lying wholly outside its trim, for good
/// (their blobs are collected once unreferenced past the grace period, on
/// this device and the server; other devices take the shorter parts list
/// with the row). The kept audio, the trim, the timeline and the waveform
/// are moved to begin at the first kept part. Returns the stored recording
/// and the one it replaced (for undo), or null when nothing lay outside.
Future<({Recording before, Recording after})?> releaseOutsideTrim(
  String id, {
  required RecordingRepository repository,
  required BlobStore blobs,
  required Future<bool> Function(String sha) fetch,
}) async {
  final before = repository.get(id);
  if (before == null || before.partsOutsideTrim.isEmpty) return null;
  final waveform = await _slicedWaveform(before, blobs, fetch);
  // The row may have changed while the waveform loaded (sync, another edit).
  final current = repository.get(id);
  if (current == null || current.updatedAt != before.updatedAt) return null;
  final after = repository.replace(
    before.withoutPartsOutsideTrim(waveform: waveform, updatedAt: before.updatedAt),
  );
  return after == null ? null : (before: before, after: after);
}

/// [recording]'s waveform cut to its kept parts and stored, or `''` when it
/// has none (or it cannot be had): the scrubber then shows a flat line.
Future<String> _slicedWaveform(
  Recording recording,
  BlobStore blobs,
  Future<bool> Function(String sha) fetch,
) async {
  final sha = recording.waveform;
  if (sha.isEmpty) return '';
  try {
    var bytes = await blobs.read(sha);
    if (bytes == null && await fetch(sha)) bytes = await blobs.read(sha);
    final waveform = bytes == null ? null : Waveform.decode(bytes);
    if (waveform == null) return '';
    final kept = recording.keptPartsRange;
    return await blobs.putBytes(
      waveform.slice(kept.fromMs, kept.toMs).encode(),
      mime: Waveform.mime,
    );
  } on Object catch (e) {
    debugPrint('Waveform could not be cut: $e');
    return '';
  }
}
