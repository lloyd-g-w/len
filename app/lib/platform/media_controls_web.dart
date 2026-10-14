import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'media_controls_api.dart';

/// The browser's media controls (Media Session API): the recording in the
/// browser's media hub, the lock screen of a phone, hardware media keys;
/// play / pause, ±10 s, seeking and stop. Null where the API is missing.
MediaControls Function()? systemMediaControls() =>
    web.window.navigator.has('mediaSession') ? WebMediaControls.new : null;

/// The argument of a seek action handler (missing from `package:web`).
extension type _ActionDetails._(JSObject _) implements JSObject {
  external double? get seekTime;
}

/// [MediaControls] in browsers. Playing in a background tab needs nothing
/// (browsers keep `<audio>` going), so [show] always answers true. The
/// page has one media session: the instance that showed last owns it.
class WebMediaControls implements MediaControls {
  static WebMediaControls? _current;

  final StreamController<MediaCommand> _commands = StreamController.broadcast();

  web.MediaSession get _session => web.window.navigator.mediaSession;

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  void _send(MediaEvent event, [int? positionMs]) {
    if (!_commands.isClosed) _commands.add((event: event, positionMs: positionMs));
  }

  @override
  Future<bool> show(NowPlaying now) async {
    final session = _session;
    if (_current != this) {
      _current = this;
      _setHandlers(true);
    }
    session.metadata = web.MediaMetadata(
      web.MediaMetadataInit(
        title: now.title.isEmpty ? now.album : now.title,
        artist: now.album,
        album: now.album,
        artwork: [web.MediaImage(src: 'icons/Icon-192.png', sizes: '192x192', type: 'image/png')]
            .toJS,
      ),
    );
    session.playbackState = now.playing ? 'playing' : 'paused';
    try {
      if (now.durationMs > 0) {
        session.setPositionState(
          web.MediaPositionState(
            duration: now.durationMs / 1000,
            playbackRate: now.rate,
            position: now.positionMs.clamp(0, now.durationMs) / 1000,
          ),
        );
      }
    } catch (_) {
      // Older browsers: no position state.
    }
    return true;
  }

  void _setHandlers(bool on) {
    void handle(String action, void Function(_ActionDetails details) run) {
      try {
        _session.setActionHandler(action, on ? ((_ActionDetails d) => run(d)).toJS : null);
      } catch (_) {
        // Not supported by this browser.
      }
    }

    handle('play', (_) => _send(MediaEvent.play));
    handle('pause', (_) => _send(MediaEvent.pause));
    handle('seekbackward', (_) => _send(MediaEvent.rewind));
    handle('seekforward', (_) => _send(MediaEvent.forward));
    handle('stop', (_) => _send(MediaEvent.stop));
    handle('seekto', (d) {
      final time = d.seekTime;
      if (time != null) _send(MediaEvent.seek, (time * 1000).round());
    });
  }

  @override
  Future<void> hide() async {
    if (_current != this) return; // Another notebook's player took over.
    _current = null;
    _setHandlers(false);
    _session
      ..metadata = null
      ..playbackState = 'none';
  }

  @override
  Future<void> dispose() async {
    await hide();
    await _commands.close();
  }
}
