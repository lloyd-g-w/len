import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_backends.dart';

/// [RecordingKeepAlive] on Android: `RecordingService.kt`, a foreground
/// service of type "microphone" with a notification, driven over the
/// `len/recording_service` channel (`RecordingServicePlugin.kt`).
///
/// There is one service per app, so the notification's buttons go to the
/// instance that showed it last (each open notebook has its own).
class AndroidKeepAlive implements RecordingKeepAlive {
  AndroidKeepAlive() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const MethodChannel _channel = MethodChannel('len/recording_service');

  /// The instance whose recording the notification shows.
  static AndroidKeepAlive? _current;

  final StreamController<KeepAliveAction> _actions = StreamController.broadcast();

  static Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'action') return null;
    final action = KeepAliveAction.values.asNameMap()[call.arguments];
    if (action != null) _current?._actions.add(action);
    return null;
  }

  @override
  Stream<KeepAliveAction> get actions => _actions.stream;

  @override
  Future<void> prepare() async {
    try {
      await _channel.invokeMethod<bool>('prepare');
    } on PlatformException catch (e) {
      debugPrint('Recording service: $e');
    } on MissingPluginException {
      // Not registered: show() reports it.
    }
  }

  @override
  Future<bool> show({required String title, required bool paused, required int elapsedMs}) async {
    _current = this;
    try {
      final shown = await _channel.invokeMethod<bool>('show', {
        'title': title,
        'paused': paused,
        'elapsedMs': elapsedMs,
      });
      return shown ?? false;
    } on PlatformException catch (e) {
      debugPrint('Recording service: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> hide() async {
    if (_current != this) return; // Another notebook's recording took over.
    try {
      await _channel.invokeMethod<void>('hide');
    } on PlatformException catch (e) {
      debugPrint('Recording service: $e');
    } on MissingPluginException {
      // Not registered (e.g. a test engine): nothing to hide.
    }
  }

  @override
  Future<void> dispose() async {
    if (_current == this) _current = null;
    await _actions.close();
  }
}
