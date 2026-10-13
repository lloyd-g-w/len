/// Where a `RecordingController` is.
enum RecorderState {
  idle,

  /// Asking for permission / starting the recorder.
  starting,
  recording,
  paused,

  /// Storing the finished recording.
  saving;

  /// Recording or paused (the bar shows the recording controls).
  bool get isActive => this == recording || this == paused;
}
