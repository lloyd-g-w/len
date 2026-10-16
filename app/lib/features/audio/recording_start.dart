part of 'recording_controller.dart';

/// Starting a recording: the microphone permission, the capture, its
/// parts and the background keep-alive.
extension _RecordingStart on RecordingController {
  Future<bool> _start() async {
    _set(RecorderState.starting);
    lastError = null;
    final capture = _capture ??= backends.capture();
    try {
      final inUse = busy?.call();
      if (inUse != null) throw AudioUnavailable(inUse);
      final reason = await backends.unavailable?.call();
      if (reason != null) throw AudioUnavailable(reason);
      const denied = RecordingController.microphoneDenied;
      if (!await capture.requestPermission()) throw const AudioUnavailable(denied);
      await _keepAlive.prepare();
      final format = await capture.format();
      final spool = format.recoverable ? await backends.spool?.call() : null;
      if (_disposed) throw const _ShutDown();
      final parts = _openParts(format, spool);
      await capture.start(await parts.nextFile());
      if (_disposed) {
        // Shut down while starting (the editor closed during the
        // permission prompt): don't leave the microphone running.
        await capture.stop().then((audio) => audio == null ? null : capture.discard(audio));
        throw const _ShutDown();
      }
    } on Object catch (e) {
      if (e is AudioUnavailable) {
        lastError = e.message;
      } else if (e is! _ShutDown) {
        debugPrint('Recording failed to start: $e');
        lastError = 'Couldn’t start recording';
      }
      await _closeParts();
      _set(RecorderState.idle);
      return false;
    }
    _stopwatch.clear();
    _waveform.clear();
    _fileStartMs = 0;
    _stopwatch.run();
    await _journalTimeline();
    _levels = capture.levels.listen(_onLevel);
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _set(RecorderState.recording);
    await _showKeepAlive();
    return true;
  }

  /// Starts or updates the background keep-alive for the current state.
  Future<void> _showKeepAlive() async {
    if (!_state.isActive) return;
    await _keepAlive.show(
      title: describe?.call() ?? '',
      paused: _state == RecorderState.paused,
      elapsedMs: elapsedMs,
    );
  }
}

/// [RecordingController.start] gave up because the controller shut down.
class _ShutDown implements Exception {
  const _ShutDown();
}
