/// The system's media controls for a playing recording (see
/// `features/audio/playback_session.dart`): Android's media session and
/// notification, MPRIS on Linux, the Media Session API in browsers.
library;

/// What the media controls show. Positions are in the kept audio of the
/// recording (`0…durationMs`); [album] is the notebook.
typedef NowPlaying = ({
  String title,
  String album,
  bool playing,
  int positionMs,
  int durationMs,
  double rate,
});

/// What the media controls (or the system around them) ask of the player.
enum MediaEvent {
  play,
  pause,
  toggle,

  /// Skip 10 s ahead / back (also a headset's next / previous).
  forward,
  rewind,

  /// Jump to `positionMs` (in the kept audio).
  seek,

  /// Close the player.
  stop,

  /// Another app took the audio for good: pause.
  focusLoss,

  /// A call or an assistant took the audio for a while: pause, and play
  /// again at [focusGain].
  focusLossTransient,
  focusGain,

  /// Another app plays something short over it: play quieter until
  /// [focusGain] (where the system doesn't duck by itself).
  duck,

  /// Headphones unplugged (or a Bluetooth headset gone): pause.
  noisy,

  /// The controls stopped working (Android: the service could not go to
  /// the foreground); playback no longer continues in the background.
  failed,
}

/// One [MediaEvent]; [positionMs] for [MediaEvent.seek].
typedef MediaCommand = ({MediaEvent event, int? positionMs});

/// Media controls for one player. The latest instance to [show] owns the
/// system's controls (one per app).
abstract interface class MediaControls {
  /// Shows or updates the controls. True when playback now continues
  /// while the app is in the background (Android: its foreground service
  /// runs), false when it could not start.
  Future<bool> show(NowPlaying now);

  /// Removes the controls (the player closed).
  Future<void> hide();

  /// What the user (or the system) asked for.
  Stream<MediaCommand> get commands;

  Future<void> dispose();
}
