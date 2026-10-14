import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/platform/media_controls_api.dart';
import 'package:len/platform/mpris_native.dart';

/// The MPRIS player on a private bus, as GNOME / KDE / playerctl see it.
void main() {
  late DBusServer server;
  late DBusAddress address;
  late DBusClient desktop;
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('len-mpris');
    server = DBusServer();
    address = await server.listenAddress(DBusAddress.unix(dir: dir));
    MprisControls.connect = () => DBusClient(address);
    desktop = DBusClient(address);
  });
  tearDown(() async {
    MprisControls.connect = DBusClient.session;
    await desktop.close();
    await server.close();
    await dir.delete(recursive: true);
  });

  const name = 'org.mpris.MediaPlayer2.len';
  const player = 'org.mpris.MediaPlayer2.Player';
  DBusRemoteObject remote() =>
      DBusRemoteObject(desktop, name: name, path: DBusObjectPath('/org/mpris/MediaPlayer2'));

  const now = (
    title: 'Lecture 3',
    album: 'Physics',
    playing: false,
    positionMs: 1200,
    durationMs: 40000,
    rate: 1.0,
  );

  test('shows the recording, takes commands, goes away when hidden', () async {
    final controls = MprisControls();
    final heard = <MediaCommand>[];
    controls.commands.listen(heard.add);
    expect(await controls.show(now), isTrue);

    final r = remote();
    expect((await r.getProperty('org.mpris.MediaPlayer2', 'Identity')).asString(), 'Len');
    expect((await r.getProperty(player, 'PlaybackStatus')).asString(), 'Paused');
    expect((await r.getProperty(player, 'Position')).asInt64(), 1200000);
    final metadata = (await r.getProperty(player, 'Metadata')).asStringVariantDict();
    expect(metadata['xesam:title']!.asString(), 'Lecture 3');
    expect(metadata['xesam:album']!.asString(), 'Physics');
    expect(metadata['mpris:length']!.asInt64(), 40000000);

    await r.callMethod(player, 'PlayPause', []);
    await r.callMethod(player, 'Next', []);
    await r.callMethod(player, 'Previous', []);
    await r.callMethod(player, 'Seek', [const DBusInt64(5000000)]);
    await r.callMethod(player, 'SetPosition', [
      DBusObjectPath('/dev/len/len/recording'),
      const DBusInt64(30000000),
    ]);
    await r.callMethod(player, 'Stop', []);
    await pumpEventQueue();
    expect(heard, [
      (event: MediaEvent.toggle, positionMs: null),
      (event: MediaEvent.forward, positionMs: null),
      (event: MediaEvent.rewind, positionMs: null),
      (event: MediaEvent.seek, positionMs: 6200),
      (event: MediaEvent.seek, positionMs: 30000),
      (event: MediaEvent.stop, positionMs: null),
    ]);

    await controls.show((
      title: 'Lecture 3',
      album: 'Physics',
      playing: true,
      positionMs: 2000,
      durationMs: 40000,
      rate: 1.0,
    ));
    expect((await r.getProperty(player, 'PlaybackStatus')).asString(), 'Playing');
    expect((await r.getProperty(player, 'Position')).asInt64(), greaterThanOrEqualTo(2000000));

    await controls.hide();
    expect(await desktop.getNameOwner(name), isNull);
    await controls.dispose();
  });

  test('the latest player owns the name; an earlier one hiding leaves it', () async {
    final a = MprisControls(), b = MprisControls();
    final heardA = <MediaCommand>[], heardB = <MediaCommand>[];
    a.commands.listen(heardA.add);
    b.commands.listen(heardB.add);
    await a.show(now);
    await b.show(now);
    await remote().callMethod(player, 'Play', []);
    await pumpEventQueue();
    expect(heardA, isEmpty);
    expect(heardB, [(event: MediaEvent.play, positionMs: null)]);
    await a.dispose();
    expect(await desktop.getNameOwner(name), isNotNull);
    await b.dispose();
    expect(await desktop.getNameOwner(name), isNull);
  });
}
