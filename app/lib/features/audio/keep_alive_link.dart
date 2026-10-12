import 'dart:async';

import 'backends/audio_backends.dart';

/// A [RecordingController]'s link to the platform's [RecordingKeepAlive]
/// (Android's foreground service), made on first use: shows and updates
/// it, passes its notification's buttons on, and knows whether the
/// recording continues in the background.
class KeepAliveLink {
  KeepAliveLink(this.create, {required this.onAction});

  /// Makes the keep-alive; null where the platform needs none.
  final RecordingKeepAlive Function()? create;

  /// Pause / resume / stop pressed in the notification.
  final void Function(KeepAliveAction action) onAction;

  RecordingKeepAlive? _keepAlive;
  StreamSubscription<KeepAliveAction>? _actions;

  /// Whether the recording continues while the app is in the background.
  bool background = false;

  RecordingKeepAlive? _get() {
    final existing = _keepAlive;
    if (existing != null) return existing;
    final created = create?.call();
    if (created == null) return null;
    _actions = created.actions.listen((action) {
      if (action == KeepAliveAction.failed) {
        background = false;
      } else {
        onAction(action);
      }
    });
    return _keepAlive = created;
  }

  /// Asks for what it needs, before the first recording.
  Future<void> prepare() async => _get()?.prepare();

  /// Starts or updates it.
  Future<void> show({required String title, required bool paused, required int elapsedMs}) async {
    final keepAlive = _get();
    if (keepAlive == null) return;
    try {
      background = await keepAlive.show(title: title, paused: paused, elapsedMs: elapsedMs);
    } on Object {
      background = false;
    }
  }

  /// Ends it: the recording is saved (the app may be suspended again).
  Future<void> hide() async {
    background = false;
    await _keepAlive?.hide();
  }

  Future<void> dispose() async {
    unawaited(_actions?.cancel());
    await _keepAlive?.dispose();
    _keepAlive = null;
  }
}
