import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import 'media_controls_api.dart';

/// [MediaControls] on Linux: an MPRIS player on the session bus
/// (`org.mpris.MediaPlayer2.len`), so GNOME's and KDE's media controls,
/// the media keys and `playerctl` reach the open recording. Next and
/// previous skip 10 s (a lecture has no tracks).
///
/// The app has one player name: the instance that showed last owns it;
/// hiding releases it (the controls disappear). Without a session bus
/// (e.g. a bare X session) it quietly does nothing.
class MprisControls implements MediaControls {
  static MprisControls? _current;
  static Future<_Bus?>? _bus;

  final StreamController<MediaCommand> _commands = StreamController.broadcast();

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  void _send(MediaCommand command) {
    if (!_commands.isClosed) _commands.add(command);
  }

  @override
  Future<bool> show(NowPlaying now) async {
    _current = this;
    final bus = await (_bus ??= _Bus.connect((c) => _current?._send(c)));
    await bus?.player.update(now);
    return true;
  }

  @override
  Future<void> hide() async {
    if (_current != this) return; // Another notebook's player took over.
    _current = null;
    final bus = _bus;
    _bus = null;
    await (await bus)?.close();
  }

  @override
  Future<void> dispose() async {
    await hide();
    await _commands.close();
  }
}

/// The session bus connection holding the player name.
class _Bus {
  _Bus(this.client, this.player);

  final DBusClient client;
  final _Player player;

  static const String name = 'org.mpris.MediaPlayer2.len';

  static Future<_Bus?> connect(void Function(MediaCommand) send) async {
    final client = DBusClient.session();
    try {
      final player = _Player(send);
      await client.registerObject(player);
      final reply = await client.requestName(name, flags: {DBusRequestNameFlag.doNotQueue});
      if (reply == DBusRequestNameReply.primaryOwner ||
          reply == DBusRequestNameReply.alreadyOwner) {
        return _Bus(client, player);
      }
      debugPrint('MPRIS: $name is taken');
    } on Object catch (e) {
      debugPrint('MPRIS unavailable: $e');
    }
    unawaited(client.close().catchError((Object _) {}));
    return null;
  }

  Future<void> close() async {
    try {
      await client.releaseName(name);
      await client.unregisterObject(player);
    } on Object catch (e) {
      debugPrint('MPRIS: $e');
    }
    await client.close();
  }
}

/// `/org/mpris/MediaPlayer2`: the root and player interfaces of MPRIS 2.2.
class _Player extends DBusObject {
  _Player(this.send) : super(DBusObjectPath('/org/mpris/MediaPlayer2'));

  final void Function(MediaCommand) send;

  static const String root = 'org.mpris.MediaPlayer2';
  static const String player = 'org.mpris.MediaPlayer2.Player';
  static final DBusObjectPath track = DBusObjectPath('/dev/len/len/recording');

  NowPlaying? _now;
  final Stopwatch _since = Stopwatch();

  /// The position now (ms in the kept audio), moving on while playing.
  int get positionMs {
    final now = _now;
    if (now == null) return 0;
    final moved = now.playing ? (_since.elapsedMilliseconds * now.rate).round() : 0;
    return (now.positionMs + moved).clamp(0, now.durationMs);
  }

  Future<void> update(NowPlaying now) async {
    _now = now;
    _since
      ..reset()
      ..start();
    await emitPropertiesChanged(
      player,
      changedProperties: {
        'PlaybackStatus': _status,
        'Metadata': _metadata,
        'Rate': DBusDouble(now.rate),
      },
    );
    // Clients read the position again (it may have jumped).
    await emitSignal(player, 'Seeked', [DBusInt64(now.positionMs * 1000)]);
  }

  DBusValue get _status => DBusString(_now?.playing ?? false ? 'Playing' : 'Paused');

  DBusValue get _metadata {
    final now = _now;
    return DBusDict.stringVariant({
      'mpris:trackid': track,
      if (now != null) ...{
        'mpris:length': DBusInt64(now.durationMs * 1000),
        'xesam:title': DBusString(now.title.isEmpty ? now.album : now.title),
        'xesam:album': DBusString(now.album),
        'xesam:artist': DBusArray.string([now.album]),
      },
    });
  }

  Map<String, DBusValue> _properties(String interface) => switch (interface) {
    root => {
      'CanQuit': const DBusBoolean(false),
      'CanRaise': const DBusBoolean(false),
      'HasTrackList': const DBusBoolean(false),
      'Identity': const DBusString('Len'),
      'DesktopEntry': const DBusString('dev.len.len'),
      'SupportedUriSchemes': DBusArray.string(const []),
      'SupportedMimeTypes': DBusArray.string(const []),
    },
    player => {
      'PlaybackStatus': _status,
      'Rate': DBusDouble(_now?.rate ?? 1),
      'MinimumRate': const DBusDouble(0.75),
      'MaximumRate': const DBusDouble(2),
      'Metadata': _metadata,
      'Volume': const DBusDouble(1),
      'Position': DBusInt64(positionMs * 1000),
      'CanGoNext': const DBusBoolean(true),
      'CanGoPrevious': const DBusBoolean(true),
      'CanPlay': const DBusBoolean(true),
      'CanPause': const DBusBoolean(true),
      'CanSeek': const DBusBoolean(true),
      'CanControl': const DBusBoolean(true),
    },
    _ => const {},
  };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = _properties(interface)[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(_properties(interface));

  @override
  Future<DBusMethodResponse> setProperty(String interface, String name, DBusValue value) async =>
      DBusMethodErrorResponse.propertyReadOnly();

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == root) {
      // Raise and Quit: not offered (CanRaise, CanQuit false).
      return DBusMethodSuccessResponse();
    }
    if (call.interface != player) return DBusMethodErrorResponse.unknownInterface();
    final command = _command(call);
    if (command == null) return DBusMethodErrorResponse.unknownMethod();
    send(command);
    return DBusMethodSuccessResponse();
  }

  MediaCommand? _command(DBusMethodCall call) {
    MediaCommand of(MediaEvent event, [int? positionMs]) => (event: event, positionMs: positionMs);
    switch (call.name) {
      case 'Play':
        return of(MediaEvent.play);
      case 'Pause':
        return of(MediaEvent.pause);
      case 'PlayPause':
        return of(MediaEvent.toggle);
      case 'Stop':
        return of(MediaEvent.stop);
      case 'Next':
        return of(MediaEvent.forward);
      case 'Previous':
        return of(MediaEvent.rewind);
      case 'Seek' when call.signature == DBusSignature('x'):
        return of(MediaEvent.seek, positionMs + call.values[0].asInt64() ~/ 1000);
      case 'SetPosition' when call.signature == DBusSignature('ox'):
        return of(MediaEvent.seek, call.values[1].asInt64() ~/ 1000);
      case 'OpenUri':
        return null;
    }
    return null;
  }
}
