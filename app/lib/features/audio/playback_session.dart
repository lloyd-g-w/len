import 'dart:async';

import '../../platform/media_controls_api.dart';
import 'playback_controller.dart';

/// Links a [PlaybackController] to the system's [MediaControls] (Android's
/// media notification and lock screen, MPRIS, the browser's): shows the
/// open recording once it first plays, keeps them current (play / pause,
/// seeks, speed, title), removes them when the player closes, and carries
/// out what they ask — including the system's own requests: pause for a
/// call and play again after it, pause when another app takes the audio
/// or headphones are unplugged, play quieter while ducked.
///
/// The controls are made on first play, so platforms (and tests) that
/// never play never touch them.
class PlaybackSession {
  PlaybackSession(this.playback, {required this.create, required this.album}) {
    playback.addListener(_onPlayback);
  }

  final PlaybackController playback;

  /// Makes the controls; null where the platform has none.
  final MediaControls Function()? create;

  /// The notebook's title (shown under the recording's).
  final String Function() album;

  MediaControls? _controls;
  StreamSubscription<MediaCommand>? _commands;

  /// Whether playback continues while the app is in the background (the
  /// controls are up; Android: their foreground service runs).
  bool get background => _background;
  bool _background = false;

  /// What was last shown (null: hidden).
  Object? _shown;

  /// Paused for a call (transient focus loss): play again when it ends.
  bool _resumeOnGain = false;

  /// Shows, updates and hides are sent in order.
  Future<void> _queue = Future.value();

  bool _disposed = false;

  void _onPlayback() {
    final recording = playback.recording;
    if (recording == null) {
      if (_shown != null) _hide();
      return;
    }
    if (playback.playing) _resumeOnGain = false;
    // Shown from the first play; kept while paused (to play on from there).
    if (_shown == null && !playback.playing) return;
    final key = (
      recording.id,
      recording.title,
      playback.playing,
      playback.rate,
      playback.startMs,
      playback.endMs,
      playback.seeks,
    );
    if (key == _shown) return;
    _shown = key;
    final now = (
      title: recording.title,
      album: album(), // Read on changes only (not every position update).
      playing: playback.playing,
      positionMs: playback.positionMs - playback.startMs,
      durationMs: playback.endMs - playback.startMs,
      rate: playback.rate,
    );
    final controls = _get();
    if (controls == null) return;
    _enqueue(() async {
      final background = await controls.show(now);
      if (_shown != null) _background = background;
    });
  }

  void _hide() {
    _shown = null;
    _background = false;
    _resumeOnGain = false;
    final controls = _controls;
    if (controls != null) _enqueue(controls.hide);
  }

  void _enqueue(Future<void> Function() run) {
    _queue = _queue.then((_) => run()).catchError((Object _) {});
  }

  MediaControls? _get() {
    final existing = _controls;
    if (existing != null || _disposed) return existing;
    final created = create?.call();
    if (created == null) return null;
    _commands = created.commands.listen(_onCommand);
    return _controls = created;
  }

  void _onCommand(MediaCommand command) {
    if (playback.recording == null) return;
    final skip = PlaybackController.skipMs;
    switch (command.event) {
      case MediaEvent.play:
        unawaited(playback.play());
      case MediaEvent.pause:
        unawaited(playback.pause());
      case MediaEvent.toggle:
        unawaited(playback.toggle());
      case MediaEvent.forward:
        unawaited(playback.skip(skip));
      case MediaEvent.rewind:
        unawaited(playback.skip(-skip));
      case MediaEvent.seek:
        final position = command.positionMs;
        if (position != null) unawaited(playback.seek(playback.startMs + position));
      case MediaEvent.stop:
        playback.close();
      case MediaEvent.focusLossTransient:
        if (playback.playing) {
          unawaited(playback.pause());
          _resumeOnGain = true;
        }
      case MediaEvent.focusGain:
        unawaited(playback.setDucked(false));
        if (_resumeOnGain) {
          _resumeOnGain = false;
          unawaited(playback.play());
        }
      case MediaEvent.duck:
        unawaited(playback.setDucked(true));
      case MediaEvent.focusLoss || MediaEvent.noisy:
        _resumeOnGain = false;
        if (playback.playing) unawaited(playback.pause());
      case MediaEvent.failed:
        _background = false;
    }
  }

  void dispose() {
    _disposed = true;
    playback.removeListener(_onPlayback);
    final controls = _controls;
    _controls = null;
    unawaited(_commands?.cancel());
    if (controls != null) {
      if (_shown != null) _enqueue(controls.hide);
      _enqueue(controls.dispose);
    }
    _shown = null;
    _background = false;
  }
}
