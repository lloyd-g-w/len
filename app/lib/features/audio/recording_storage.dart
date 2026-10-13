part of 'recording_controller.dart';

/// Storing a recording in progress (see [RecordingParts]): finished capture
/// files become parts, the timeline is journalled for recovery, and the
/// spool files are let go once the recording is stored.
extension _RecordingStorage on RecordingController {
  /// Forgets the recording's spool files (stored, or not worth keeping).
  Future<void> _closeParts({bool keepFiles = false}) async {
    final parts = _parts;
    _parts = null;
    if (parts == null) return;
    RecordingController.active.remove(parts.journal.recordingId);
    if (keepFiles) return;
    try {
      await parts.close();
    } on Object {
      // Left for the next start's recovery check to clean up.
    }
  }

  /// Moves the capture on to a new file and stores the finished one.
  Future<void> _split() async {
    final parts = _parts, capture = _capture;
    if (parts == null || capture == null) return;
    try {
      final at = elapsedMs;
      final audio = await capture.split(await parts.nextFile());
      final measured = at - _fileStartMs;
      _fileStartMs = at;
      await parts.store(audio, measured, waveform: _waveform.build, capture: capture);
    } on Object catch (e) {
      // The audio stays in its file; stop stores what it can.
      debugPrint('Recording part failed to store: $e');
      lastError = 'Part of the recording could not be stored';
    }
  }

  /// Journals the capture's stretches (for recovery).
  Future<void> _journalTimeline() async {
    try {
      await _parts?.timeline(_stopwatch.closed, _stopwatch.runningSince);
    } on Object {
      // Recovery only: never stop a recording over it.
    }
  }

  /// Starts storing a new recording captured in [format] (its files in
  /// [spool], when recoverable).
  RecordingParts _openParts(CaptureFormat format, SpoolStorage? spool) {
    final now = clock.nowMs();
    final parts = _parts = RecordingParts(
      RecordingJournal(
        recordingId: clock.newId(),
        notebookId: notebookId,
        title: RecordingController.defaultTitle(now),
        mime: format.mime,
        openSince: now,
      ),
      blobs: blobs,
      repository: repository,
      spool: spool,
      extension: format.extension,
    );
    RecordingController.active.add(parts.journal.recordingId);
    return parts;
  }

  /// Stores the last capture file and the final timeline of [segments]
  /// once the part being stored is done. Returns the stored recording, or
  /// null if nothing was kept (too short).
  Future<Recording?> _storeLast(RecordingParts? parts, List<RecordingSegment> segments) async {
    await _work;
    final audio = await _capture?.stop();
    if (parts == null) return null;
    final measured = segments.fold(0, (sum, s) => sum + s.durationMs) - _fileStartMs;
    if (!parts.saved && (audio?.durationMs ?? measured) < RecordingController.minimumMs) {
      if (audio != null) await _capture?.discard(audio);
      return null;
    }
    await parts.timeline(segments, null);
    await parts.store(audio, measured, waveform: _waveform.build, capture: _capture!);
    if (!parts.saved) return null;
    final recording = repository.get(parts.journal.recordingId);
    if (recording != null) onSaved?.call(recording);
    return recording;
  }
}
