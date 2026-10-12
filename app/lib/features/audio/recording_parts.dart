import 'package:cross_file/cross_file.dart';

import '../../data/blob_store.dart';
import '../../data/recording_repository.dart';
import '../../data/spool_storage.dart';
import '../../domain/recording.dart';
import '../../domain/waveform.dart';
import 'backends/audio_backends.dart';
import 'recording_journal.dart';

/// Stores a recording in progress part by part (see
/// `RecordingController.partMs`): each finished capture file becomes a
/// blob at once, and the recording's `recordings` row is saved with the
/// parts so far — so sync uploads them (and garbage collection keeps them)
/// while recording continues. With a [spool] (natively), the capture files
/// live there and a [RecordingJournal] tracks them, so a recording cut
/// off by the app being killed can be recovered.
class RecordingParts {
  /// Starts storing the recording of [_journal] (new: no parts yet).
  RecordingParts(
    this._journal, {
    required this.blobs,
    required this.repository,
    required this.spool,
    required this.extension,
  });

  final BlobStore blobs;
  final RecordingRepository repository;
  final SpoolStorage? spool;
  final String extension;
  RecordingJournal _journal;
  int _nextFile = 0;

  RecordingJournal get journal => _journal;
  List<RecordingPart> get parts => _journal.parts;

  /// Audio stored so far.
  int get storedMs => parts.fold(0, (sum, p) => sum + p.durationMs);

  /// Whether the recording's row exists (a part was stored).
  bool get saved => parts.isNotEmpty;

  /// Starts the next capture file: its path for the recorder (null
  /// without a spool), journalled before the recorder writes to it.
  Future<String?> nextFile() async {
    final spool = this.spool;
    if (spool == null) return null;
    final name = '${_journal.recordingId}-${_nextFile++}.$extension';
    await _write(_journal.copyWith(files: [..._journal.files, name]));
    return spool.pathOf(name);
  }

  /// Records the capture's stretches: [closed] ones and the running one
  /// since [openSince] (null while paused).
  Future<void> timeline(List<RecordingSegment> closed, int? openSince) =>
      _write(_journal.copyWith(segments: closed, openSince: () => openSince));

  /// Stores the finished capture file [audio] (the oldest spool file) as
  /// the next part, [measuredMs] long unless the backend knows better,
  /// and saves the row with [waveform] of the audio so far.
  Future<Recording?> store(
    CapturedAudio? audio,
    int measuredMs, {
    required Waveform Function(int durationMs) waveform,
    required AudioCapture capture,
  }) async {
    final files = _journal.files;
    final parts = [...this.parts];
    if (audio != null) {
      final duration = audio.durationMs ?? measuredMs;
      if (duration > 0) {
        // Streamed into the blob store (no full copy in memory natively).
        final sha = await blobs.putFile(audio.file, mime: audio.mime);
        parts.add(RecordingPart(sha, duration));
      }
      await capture.discard(audio);
    }
    if (files.isNotEmpty) await spool?.delete(files.first);
    final rest = files.isEmpty ? files : files.sublist(1);
    if (parts.length == this.parts.length) {
      await _write(_journal.copyWith(files: rest));
      return null;
    }
    final total = parts.fold(0, (sum, p) => sum + p.durationMs);
    // Small (≈ 36 KB per hour): hashed in place.
    final wave = await blobs.putFile(
      XFile.fromData(waveform(total).encode(), mimeType: Waveform.mime),
      mime: Waveform.mime,
    );
    final journal = _journal.copyWith(parts: parts, files: rest, waveform: wave);
    final recording = save(repository, journal);
    await _write(journal);
    return recording;
  }

  /// Saves the `recordings` row of [journal]'s parts.
  static Recording save(RecordingRepository repository, RecordingJournal journal) =>
      repository.save(
        id: journal.recordingId,
        notebookId: journal.notebookId,
        parts: journal.parts,
        mime: journal.mime,
        title: journal.title,
        segments: journal.timelineFor(journal.parts.fold(0, (sum, p) => sum + p.durationMs)),
        waveform: journal.waveform,
      );

  /// The recording is complete (or discarded): forgets its spool files.
  Future<void> close() async {
    final spool = this.spool;
    if (spool == null) return;
    for (final file in _journal.files) {
      await spool.delete(file);
    }
    await spool.delete(RecordingJournal.nameOf(_journal.recordingId));
  }

  Future<void> _write(RecordingJournal journal) async {
    _journal = journal;
    await spool?.write(RecordingJournal.nameOf(journal.recordingId), journal.encode());
  }
}
