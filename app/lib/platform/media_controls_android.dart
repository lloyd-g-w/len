import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'media_controls_api.dart';

/// [MediaControls] on Android: `PlaybackService.kt`, a foreground service
/// of type "mediaPlayback" with a media session and notification, driven
/// over the `len/playback_service` channel (`PlaybackServicePlugin.kt`).
///
/// There is one service per app, so its events go to the instance that
/// showed it last (each open notebook has its own player).
class AndroidMediaControls implements MediaControls {
  AndroidMediaControls() {
    channel.setMethodCallHandler(_onCall);
  }

  /// The channel to `PlaybackServicePlugin.kt`.
  static const MethodChannel channel = MethodChannel('len/playback_service');

  /// The instance whose player the service shows.
  static AndroidMediaControls? _current;

  final StreamController<MediaCommand> _commands = StreamController.broadcast();

  static Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'event') return null;
    final args = call.arguments;
    if (args is! Map) return null;
    final event = MediaEvent.values.asNameMap()[args['action']];
    final position = args['positionMs'];
    if (event != null) {
      _current?._commands.add((event: event, positionMs: position is int ? position : null));
    }
    return null;
  }

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  @override
  Future<bool> show(NowPlaying now) async {
    _current = this;
    try {
      final shown = await channel.invokeMethod<bool>('show', {
        'title': now.title,
        'album': now.album,
        'playing': now.playing,
        'positionMs': now.positionMs,
        'durationMs': now.durationMs,
        'rate': now.rate,
      });
      return shown ?? false;
    } on PlatformException catch (e) {
      debugPrint('Playback service: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> hide() async {
    if (_current != this) return; // Another notebook's player took over.
    try {
      await channel.invokeMethod<void>('hide');
    } on PlatformException catch (e) {
      debugPrint('Playback service: $e');
    } on MissingPluginException {
      // Not registered (e.g. a test engine): nothing to hide.
    }
  }

  @override
  Future<void> dispose() async {
    if (_current == this) _current = null;
    await _commands.close();
  }
}
