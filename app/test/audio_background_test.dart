import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/spool_storage.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/audio/backends/android_keep_alive.dart';
import 'package:len/features/audio/backends/audio_backends.dart';
import 'package:len/features/audio/recording_controller.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'data_test.dart' show FakeClock;
import 'support/fake_audio.dart';

/// A spool whose [holdWrite]th write waits for [release].
class _HeldSpool extends MemorySpoolStorage {
  int holdWrite = 0;
  int _writes = 0;
  final Completer<void> _held = Completer();

  void release() => _held.complete();

  @override
  Future<void> write(String name, Uint8List bytes) async {
    if (++_writes == holdWrite) await _held.future;
    await super.write(name, bytes);
  }
}

/// Background recording: the keep-alive (Android's foreground service and
/// its notification) follows the recorder, its buttons drive it, and a
/// paused app keeps recording only while it is up.
void main() {
  group('recorder and keep-alive', () {
    late AppServices s;
    late FakeAudio audio;
    late FakeClock clock;
    late String notebookId;

    setUp(() {
      audio = FakeAudio(background: true);
      clock = FakeClock()..now = 100000;
      s = AppServices.create(AppDatabase.inMemory(), clock: clock, audio: audio.backends);
      notebookId = s.notebooks
          .create(
            title: 'Physics',
            kind: NotebookKind.paged,
            paper: PaperStyle.blank,
            coverColor: 1,
          )
          .id;
    });
    tearDown(() => s.dispose());

    RecordingController recorder({FakeAudio? with_}) => RecordingController(
      notebookId: notebookId,
      backends: (with_ ?? audio).backends,
      blobs: s.blobs,
      repository: s.recordings,
      describe: () => 'Physics',
    );

    test('shown while recording, updated on pause / resume, hidden once saved', () async {
      final c = recorder();
      expect(await c.start(), isTrue);
      expect(c.recordsInBackground, isTrue);
      clock.now += 3000;
      await c.pause();
      clock.now += 5000;
      await c.resume();
      clock.now += 1000;
      final saved = await c.stop();
      expect(saved, isNotNull);
      expect(c.recordsInBackground, isFalse);
      expect(audio.log, [
        'permission',
        'keepalive prepare', // Notification permission, before capturing.
        'start',
        'keepalive show Physics recording 0',
        'pause',
        'keepalive show Physics paused 3000',
        'resume',
        'keepalive show Physics recording 3000',
        'stop',
        'keepalive hide', // After the recording is stored.
      ]);
      await c.shutdown();
      expect(audio.log.last, 'keepalive dispose');
      c.dispose();
    });

    test('notification buttons pause, resume and stop (saving) the recording', () async {
      final c = recorder();
      await c.start();
      clock.now += 2000;
      audio.keepAlive.press(KeepAliveAction.pause);
      await pumpEventQueue();
      expect(c.state, RecorderState.paused);
      clock.now += 60000;
      audio.keepAlive.press(KeepAliveAction.resume);
      await pumpEventQueue();
      expect(c.state, RecorderState.recording);
      clock.now += 1500;
      audio.keepAlive.press(KeepAliveAction.stop);
      await pumpEventQueue();
      expect(c.state, RecorderState.idle);
      final saved = s.recordings.listOf(notebookId).single;
      expect(saved.durationMs, 3500);
      expect(audio.keepAlive.shown, isFalse);
      c.dispose();
    });

    test('a keep-alive that fails (or cannot start) leaves recording in front only', () async {
      final c = recorder();
      await c.start();
      expect(c.recordsInBackground, isTrue);
      audio.keepAlive.press(KeepAliveAction.failed);
      expect(c.recordsInBackground, isFalse);
      expect(c.state, RecorderState.recording);
      clock.now += 1000;
      await c.stop();
      c.dispose();

      final refused = FakeAudio(background: true, canShow: false);
      final c2 = recorder(with_: refused);
      await c2.start();
      expect(c2.state, RecorderState.recording);
      expect(c2.recordsInBackground, isFalse);
      clock.now += 1000;
      await c2.stop();
      c2.dispose();
    });

    test('a too-short recording still ends the keep-alive', () async {
      final c = recorder();
      await c.start();
      clock.now += 100;
      expect(await c.stop(), isNull);
      expect(audio.log.last, 'keepalive hide');
      c.dispose();
    });

    test('shut down while starting: no keep-alive is made after it was released', () async {
      final c = recorder();
      final started = c.start();
      await c.shutdown(); // The editor closed before the permission prompt.
      expect(await started, isFalse);
      // Whatever the start made is released too.
      expect(audio.log.where((l) => l == 'keepalive dispose'), hasLength(audio.keepAlives.length));
      // The capture isn't used once disposed.
      expect(audio.log.last, 'keepalive dispose');
      expect(audio.log.where((l) => l == 'dispose'), hasLength(1));
      expect(audio.log.indexOf('dispose'), greaterThan(audio.log.indexOf('permission')));
      c.dispose();
    });

    test('shut down just after the capture started: it is stopped and saved', () async {
      final spool = _HeldSpool();
      final adts = FakeAudio(background: true, adts: true, spool: spool);
      final c = recorder(with_: adts);
      spool.holdWrite = 2; // The timeline journalled once the capture runs.
      final started = c.start();
      await pumpEventQueue();
      expect(adts.log, contains('start'));
      final shutdown = c.shutdown(); // The editor closed meanwhile.
      adts.capture.write(adtsFrames(16)); // ≈ 1 s.
      spool.release();
      await started;
      await shutdown;
      expect(adts.log, containsAllInOrder(['start', 'stop', 'keepalive hide', 'dispose']));
      expect(c.state, RecorderState.idle);
      expect(s.recordings.listOf(notebookId), hasLength(1));
      expect(adts.keepAlives.every((k) => !k.shown), isTrue);
      c.dispose();
    });

    test('platforms without a keep-alive record in front only', () async {
      final plain = FakeAudio();
      final c = recorder(with_: plain);
      await c.start();
      expect(c.recordsInBackground, isFalse);
      expect(plain.log, ['permission', 'start']);
      c.dispose();
    });
  });

  group('Android channel', () {
    const channel = MethodChannel('len/recording_service');
    late List<MethodCall> calls;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          calls.add(call);
          return call.method == 'hide' ? null : true;
        },
      );
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    Future<void> notify(String action) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall('action', action)),
          (_) {},
        );

    test('show / hide carry the state; buttons reach the notebook that showed it', () async {
      final a = AndroidKeepAlive(), b = AndroidKeepAlive();
      final heardA = <KeepAliveAction>[], heardB = <KeepAliveAction>[];
      a.actions.listen(heardA.add);
      b.actions.listen(heardB.add);
      await a.prepare();
      expect(await a.show(title: 'Physics', paused: false, elapsedMs: 1200), isTrue);
      expect(calls.map((c) => c.method), ['prepare', 'show']);
      expect(calls.last.arguments, {'title': 'Physics', 'paused': false, 'elapsedMs': 1200});
      await notify('pause');
      expect(heardA, [KeepAliveAction.pause]);

      await b.show(title: 'Maths', paused: false, elapsedMs: 0);
      await notify('stop');
      await notify('nonsense'); // Unknown actions are ignored.
      expect(heardB, [KeepAliveAction.stop]);
      expect(heardA, [KeepAliveAction.pause]);
      await a.hide(); // Not a's notification any more.
      expect(calls.where((c) => c.method == 'hide'), isEmpty);
      await b.hide();
      expect(calls.last.method, 'hide');
      await a.dispose();
      await b.dispose();
    });

    test('without the native side, show reports failure', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      final k = AndroidKeepAlive();
      await k.prepare();
      expect(await k.show(title: '', paused: false, elapsedMs: 0), isFalse);
      await k.hide();
      await k.dispose();
    });
  });

  testWidgets('Android: with the foreground service, recording survives a paused app and '
      'stops from the notification', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final audio = FakeAudio(background: true);
    final clock = FakeClock()..now = 1000000;
    final services = AppServices.create(
      AppDatabase.inMemory(),
      clock: clock,
      audio: audio.backends,
    );
    addTearDown(services.dispose);
    final nb = services.notebooks.create(
      title: 'Chemistry',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EditorScreen(notebook: nb),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Record audio'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(audio.log, contains('keepalive show Chemistry recording 0'));

    // Screen off / another app: the recording goes on.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    clock.now += 30000;
    await tester.pump(const Duration(milliseconds: 300));
    expect(services.recordings.listOf(nb.id), isEmpty);
    expect(audio.log, isNot(contains('stop')));

    // "Stop" in the notification saves it, still in the background.
    audio.keepAlive.press(KeepAliveAction.stop);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(services.recordings.listOf(nb.id).single.durationMs, 30000);
    expect(audio.keepAlive.shown, isFalse);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(find.byKey(const ValueKey('recording-pill')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });
}
