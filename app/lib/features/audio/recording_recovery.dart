import 'package:flutter/foundation.dart';

import '../../data/blob_store.dart';
import '../../data/recording_repository.dart';
import '../../data/spool_storage.dart';
import '../../domain/recording.dart';
import 'adts.dart';
import 'recording_controller.dart';
import 'recording_journal.dart';
import 'recording_parts.dart';

/// A recording cut off by the app being killed: its [journal] and the
/// audio in its spool files not stored yet ([unsavedMs]).
@immutable
class InterruptedRecording {
  const InterruptedRecording(this.journal, this.unsavedMs);

  final RecordingJournal journal;
  final int unsavedMs;

  /// Audio stored before the app was killed (already in the recording).
  int get savedMs => journal.parts.fold(0, (sum, p) => sum + p.durationMs);
}

/// Finds recordings left unfinished in the spool (the app was killed while
/// recording) and recovers them: the parts stored before are already in
/// the recording; recovering adds the spool files — raw AAC in ADTS
/// frames, playable up to the last whole frame, so a file cut off mid-way
/// loses at most a frame — as further parts, timed by their frame counts.
class RecordingRecovery {
  RecordingRecovery({required this.spool, required this.blobs, required this.repository});

  final SpoolStorage spool;
  final BlobStore blobs;
  final RecordingRepository repository;

  /// The interrupted recordings with audio to recover. Journals without any
  /// are finished (their stored parts are the recording), and files no
  /// journal knows are deleted. Recordings being made right now (see
  /// [RecordingController.active]) are left alone.
  Future<List<InterruptedRecording>> find() async {
    final names = await spool.list();
    final found = <InterruptedRecording>[];
    final known = <String>{};
    for (final name in names.where(RecordingJournal.isJournal)) {
      final bytes = await spool.read(name);
      final journal = bytes == null ? null : RecordingJournal.tryDecode(bytes);
      if (journal == null) {
        await spool.delete(name);
        continue;
      }
      known.addAll([name, ...journal.files]);
      if (RecordingController.active.contains(journal.recordingId)) continue;
      var unsaved = 0;
      for (final file in journal.files) {
        final audio = await spool.read(file);
        if (audio != null) unsaved += AdtsReader.readAll(audio).durationMs;
      }
      final interrupted = InterruptedRecording(journal, unsaved);
      if (unsaved > 0) {
        found.add(interrupted);
      } else {
        await discard(interrupted);
      }
    }
    for (final name in names) {
      if (!known.contains(name) && !_isActive(name)) await spool.delete(name);
    }
    return found;
  }

  static bool _isActive(String name) => RecordingController.active.any(name.startsWith);

  /// Stores [interrupted]'s unsaved audio as further parts and saves the
  /// recording; null if nothing was playable.
  Future<Recording?> recover(InterruptedRecording interrupted) async {
    final journal = interrupted.journal;
    final parts = [...journal.parts];
    for (final file in journal.files) {
      final bytes = await spool.read(file);
      if (bytes == null) continue;
      final audio = AdtsReader.readAll(bytes);
      if (audio.durationMs == 0) continue;
      parts.add(
        RecordingPart(await blobs.putBytes(audio.frames, mime: journal.mime), audio.durationMs),
      );
    }
    Recording? recording;
    if (parts.isNotEmpty) {
      recording = RecordingParts.save(repository, journal.copyWith(parts: parts));
    }
    await discard(interrupted);
    return recording;
  }

  /// Deletes [interrupted]'s spool files (the parts stored before stay in
  /// the recording).
  Future<void> discard(InterruptedRecording interrupted) async {
    final journal = interrupted.journal;
    for (final file in journal.files) {
      await spool.delete(file);
    }
    await spool.delete(RecordingJournal.nameOf(journal.recordingId));
  }
}
