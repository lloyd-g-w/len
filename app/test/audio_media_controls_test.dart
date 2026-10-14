import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/audio/notebook_audio.dart';
import 'package:len/features/audio/playback_controller.dart';
import 'package:len/features/audio/ui/playback_keys.dart';
import 'package:len/platform/media_controls_android.dart';
import 'package:len/platform/media_controls_api.dart';

import 'data_test.dart' show FakeClock;
import 'support/fake_audio.dart';

/// 60 s of audio, kept from 10 s to 50 s.
Recording _lecture(String notebookId, {String id = 'r', String title = 'Lecture 3'}) => Recording(
  id: id,
  notebookId: notebookId,
  parts: [RecordingPart('ab' * 32, 60000)],
  durationMs: 60000,
  startedAt: 10000,
  title: title,
  mime: Recording.adtsMime,
  updatedAt: 1,
  segments: const [RecordingSegment(10000, 60000)],
  trimStartMs: 10000,
  trimEndMs: 50000,
);

/// Background playback: the system's media controls (Android's media
/// notification and lock screen, MPRIS, the browser's) follow the player,
/// drive it, and the system's requests (calls, other apps, unplugged
/// headphones) pause it.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late AppServices s;
  late FakeAudio audio;
  late String notebookId;
  late NotebookAudio notebook;

  setUp(() {
    audio = FakeAudio(mediaControls: true);
    s = AppServices.create(
      AppDatabase.inMemory(),
      clock: FakeClock()..now = 100000,
      audio: audio.backends,
    );
    notebookId = s.notebooks
        .create(title: 'Physics', kind: NotebookKind.paged, paper: PaperStyle.blank, coverColor: 1)
        .id;
    notebook = NotebookAudio(s, notebookId: notebookId, platform: TargetPlatform.android);
  });
  tearDown(() {
    notebook.dispose();
    s.dispose();
  });

  PlaybackController playback() => notebook.playback;
  FakeMediaControls controls() => audio.controls.single;
  List<String> shown() => audio.log.where((l) => l.startsWith('controls')).toList();

  /// Screen off or another app in front, and back.
  void lifecycle(List<AppLifecycleState> states) {
    for (final state in states) {
      binding.handleAppLifecycleStateChanged(state);
    }
  }

  void toBackground() => lifecycle(const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]);
  void toForeground() => lifecycle(const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]);

  /// Lets the queued show / hide calls run.
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  group('controls follow the player', () {
    test('shown from the first play, updated on changes, hidden on close', () async {
      final p = playback();
      await p.open(_lecture(notebookId), autoplay: false);
      await flush();
      expect(audio.controls, isEmpty); // Not before anything plays.
      expect(notebook.session.background, isFalse);

      await p.play();
      await flush();
      // Positions and length in the kept audio; the notebook as album.
      expect(shown(), ['controls Lecture 3 · Physics playing 0/40000']);
      expect(notebook.session.background, isTrue);

      // Position updates while playing don't resend (the system extrapolates).
      audio.player.emit(12000);
      audio.player.emit(12200);
      await flush();
      expect(shown(), hasLength(1));

      await p.seek(30000);
      await p.setRate(1.5);
      await p.pause();
      await flush();
      expect(shown().skip(1), [
        'controls Lecture 3 · Physics playing 20000/40000',
        'controls Lecture 3 · Physics playing 20000/40000',
        'controls Lecture 3 · Physics paused 20000/40000',
      ]);
      expect(controls().shown!.rate, 1.5);

      p.close();
      await flush();
      expect(shown().last, 'controls hide');
      expect(notebook.session.background, isFalse);
    });

    test('commands drive the player (seeks in the kept audio)', () async {
      final p = playback();
      await p.open(_lecture(notebookId));
      await flush();
      final c = controls();

      c.send(MediaEvent.pause);
      expect(p.playing, isFalse);
      c.send(MediaEvent.play);
      expect(p.playing, isTrue);
      c.send(MediaEvent.toggle);
      expect(p.playing, isFalse);
      c.send(MediaEvent.seek, 5000);
      expect(p.positionMs, 15000);
      c.send(MediaEvent.forward);
      expect(p.positionMs, 25000);
      c.send(MediaEvent.rewind);
      c.send(MediaEvent.rewind);
      expect(p.positionMs, 10000); // Not before the kept start.
      c.send(MediaEvent.stop);
      expect(p.recording, isNull);
      await flush();
      expect(shown().last, 'controls hide');
    });

    test('a call pauses and playback resumes after it; another app stops it for good', () async {
      final p = playback();
      await p.open(_lecture(notebookId));
      final c = controls();

      c.send(MediaEvent.focusLossTransient);
      expect(p.playing, isFalse);
      c.send(MediaEvent.focusGain);
      expect(p.playing, isTrue);

      c.send(MediaEvent.focusLoss);
      expect(p.playing, isFalse);
      c.send(MediaEvent.focusGain);
      expect(p.playing, isFalse);
    });

    test('paused by the user during a call stays paused after it', () async {
      final p = playback();
      await p.open(_lecture(notebookId));
      final c = controls();
      c.send(MediaEvent.focusLossTransient);
      await p.play(); // The user plays on…
      await p.pause(); // …and pauses again.
      c.send(MediaEvent.focusGain);
      expect(p.playing, isFalse);
    });

    test('ducking plays quieter until the focus comes back', () async {
      final p = playback();
      await p.open(_lecture(notebookId));
      final c = controls();
      c.send(MediaEvent.duck);
      expect(audio.log.last, 'volume ${PlaybackController.duckedVolume}');
      expect(p.playing, isTrue);
      c.send(MediaEvent.focusGain);
      expect(audio.log.last, 'volume 1.0');
    });

    test('unplugged headphones pause', () async {
      final p = playback();
      await p.open(_lecture(notebookId));
      controls().send(MediaEvent.noisy);
      expect(p.playing, isFalse);
      controls().send(MediaEvent.focusGain); // Never resumes by itself.
      expect(p.playing, isFalse);
    });

    test('a failed service no longer counts as background playback', () async {
      await playback().open(_lecture(notebookId));
      await flush();
      expect(notebook.session.background, isTrue);
      controls().send(MediaEvent.failed);
      expect(notebook.session.background, isFalse);
    });
  });

  group('app in the background (Android)', () {
    test('playback goes on with the controls up, and the position keeps the ink in step', () async {
      final p = playback();
      await p.open(_lecture(notebookId));
      await flush();
      toBackground();
      addTearDown(toForeground);
      expect(p.playing, isTrue);
      // Positions keep arriving while the screen is off: back in front,
      // the ink veil is where the audio is.
      audio.player.emit(42000);
      expect(p.wallTime, 10000 + 42000);
    });

    test('without them it pauses', () async {
      final p = playback();
      await p.open(_lecture(notebookId));
      await flush();
      controls().background = false;
      await p.seek(20000); // Shown again: the service could not start.
      await flush();
      toBackground();
      addTearDown(toForeground);
      expect(p.playing, isFalse);
    });
  });

  group('desktop media keys', () {
    KeyDownEvent key(LogicalKeyboardKey logical) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.mediaPlayPause,
      logicalKey: logical,
      timeStamp: Duration.zero,
    );

    testWidgets('play / pause, next and previous skip on Windows; ignored on Android', (
      tester,
    ) async {
      final p = playback();
      await p.open(_lecture(notebookId), autoplay: false);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        handlePlaybackKey(notebook, key(LogicalKeyboardKey.mediaPlayPause)),
        KeyEventResult.handled,
      );
      expect(p.playing, isTrue);
      handlePlaybackKey(notebook, key(LogicalKeyboardKey.mediaTrackNext));
      expect(p.positionMs, 20000);
      handlePlaybackKey(notebook, key(LogicalKeyboardKey.mediaRewind));
      expect(p.positionMs, 10000);
      handlePlaybackKey(notebook, key(LogicalKeyboardKey.mediaStop));
      expect(p.playing, isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        handlePlaybackKey(notebook, key(LogicalKeyboardKey.mediaPlayPause)),
        KeyEventResult.ignored,
      );
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('Android channel', () {
    const channel = AndroidMediaControls.channel;
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          calls.add(call);
          return call.method == 'show' ? true : null;
        },
      );
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    Future<void> event(Object? arguments) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall('event', arguments)),
          (_) {},
        );

    const now = (
      title: 'Lecture 3',
      album: 'Physics',
      playing: true,
      positionMs: 1200,
      durationMs: 40000,
      rate: 1.25,
    );

    test('show / hide carry the state; events reach the player that showed it', () async {
      final a = AndroidMediaControls(), b = AndroidMediaControls();
      final heardA = <MediaCommand>[], heardB = <MediaCommand>[];
      a.commands.listen(heardA.add);
      b.commands.listen(heardB.add);
      expect(await a.show(now), isTrue);
      expect(calls.single.method, 'show');
      expect(calls.single.arguments, {
        'title': 'Lecture 3',
        'album': 'Physics',
        'playing': true,
        'positionMs': 1200,
        'durationMs': 40000,
        'rate': 1.25,
      });
      await event({'action': 'pause', 'positionMs': null});
      await event({'action': 'seek', 'positionMs': 5000});
      await event({'action': 'focusLossTransient'});
      expect(heardA, [
        (event: MediaEvent.pause, positionMs: null),
        (event: MediaEvent.seek, positionMs: 5000),
        (event: MediaEvent.focusLossTransient, positionMs: null),
      ]);

      await b.show(now);
      await event({'action': 'noisy'});
      await event({'action': 'nonsense'}); // Unknown events are ignored.
      await event('stop'); // Malformed.
      expect(heardB, [(event: MediaEvent.noisy, positionMs: null)]);
      expect(heardA, hasLength(3));
      await a.hide(); // Not a's controls any more.
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
      final c = AndroidMediaControls();
      expect(await c.show(now), isFalse);
      await c.hide();
      await c.dispose();
    });
  });
}
