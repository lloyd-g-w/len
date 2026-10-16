import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/audio/recording_controller.dart';
import 'package:len/features/editor/shared/shared_notebooks.dart';

import 'support/fake_audio.dart';
import 'support/tester_clock.dart';

/// Waits (real time) until [done] holds.
Future<void> until(bool Function() done) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > const Duration(seconds: 30)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a notebook closed while recording keeps the microphone until its recording is saved, '
      'and lists it when reopened meanwhile', () async {
    final audio = FakeAudio();
    final clock = FixedClock(DateTime.utc(2026));
    final services = AppServices.create(
      AppDatabase.inMemory(),
      audio: audio.backends,
      clock: clock,
    );
    Notebook notebook(String title) => services.notebooks.create(
      title: title,
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final physics = notebook('Physics'), chemistry = notebook('Chemistry');
    final shared = SharedNotebooks(services);

    final first = shared.acquire(physics);
    expect(await first.audio.recorder.start(), isTrue);
    clock.at = clock.at.add(const Duration(milliseconds: 600)); // Long enough to keep.
    final saving = Completer<void>();
    audio.capture.holdStop = saving.future;
    unawaited(first.audio.recorder.stop());
    shared.release(first); // While its recording is being saved.

    final other = shared.acquire(chemistry);
    expect(await other.audio.recorder.start(), isFalse);
    expect(other.audio.recorder.lastError, contains('Still saving the recording in “Physics”'));

    final reopened = shared.acquire(physics);
    expect(reopened.audio.recordings, isEmpty);
    saving.complete();
    await until(() => reopened.audio.recordings.length == 1);

    expect(await other.audio.recorder.start(), isTrue);
    await other.audio.recorder.stop();
    shared.dispose();
  });

  test('R17-1: a notebook left while recording goes on recording until stopped', () async {
    final audio = FakeAudio();
    final clock = FixedClock(DateTime.utc(2026));
    final services = AppServices.create(
      AppDatabase.inMemory(),
      audio: audio.backends,
      clock: clock,
    );
    Notebook notebook(String title) => services.notebooks.create(
      title: title,
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final physics = notebook('Physics'), chemistry = notebook('Chemistry');
    final shared = SharedNotebooks(services);

    final first = shared.acquire(physics);
    final recorder = first.audio.recorder;
    expect(await recorder.start(), isTrue);
    shared.release(first); // Another tab, or Back to the library.
    await pumpEventQueue();
    expect(recorder.state, RecorderState.recording);
    expect(shared.unattended.value, same(first));
    expect(shared.ids, contains(physics.id));

    // Looking something up elsewhere: that notebook can't record meanwhile.
    final other = shared.acquire(chemistry);
    expect(await other.audio.recorder.start(), isFalse);
    expect(other.audio.recorder.lastError, contains('Already recording in “Physics”'));
    shared.release(other);

    // Back in the lecture: the same recorder, still recording.
    expect(shared.acquire(physics), same(first));
    await pumpEventQueue();
    expect(shared.unattended.value, isNull);
    shared.release(first);
    await pumpEventQueue();
    expect(shared.unattended.value, same(first));

    // Stopped from the notice: saved, then let go.
    clock.at = clock.at.add(const Duration(milliseconds: 600)); // Long enough to keep.
    expect(await recorder.stop(), isNotNull);
    await pumpEventQueue();
    expect(shared.unattended.value, isNull);
    expect(shared.ids, isEmpty);
    expect(services.recordings.listOf(physics.id), hasLength(1));
    shared.dispose();
  });

  test('R17: a notebook trashed here while it records unattended is let go: its recording '
      'is stopped and saved into it, so restoring brings back both', () async {
    final audio = FakeAudio();
    final clock = FixedClock(DateTime.utc(2026));
    final services = AppServices.create(
      AppDatabase.inMemory(),
      audio: audio.backends,
      clock: clock,
    );
    final physics = services.notebooks.create(
      title: 'Physics',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final shared = SharedNotebooks(services);
    final first = shared.acquire(physics);
    final recorder = first.audio.recorder;
    expect(await recorder.start(), isTrue);
    clock.at = clock.at.add(const Duration(milliseconds: 600)); // Long enough to keep.
    shared.release(first);
    await pumpEventQueue();
    expect(shared.unattended.value, same(first));

    services.notebooks.trash(physics.id);
    shared.notebooksChanged();
    await pumpEventQueue();
    expect(shared.unattended.value, isNull);
    expect(shared.peek(physics.id), isNull, reason: 'no empty notebook to show');
    await until(() => shared.ids.isEmpty);
    expect(services.recordings.listOf(physics.id), hasLength(1));

    services.notebooks.restore(physics.id);
    final reopened = shared.acquire(physics);
    expect(reopened, isNot(same(first)));
    expect(reopened.gone, isNull);
    expect(reopened.audio.recordings, hasLength(1));
    shared.dispose();
  });

  test('R17: a recording that finishes saving after its notebook was deleted forever is '
      'deleted with it', () async {
    final audio = FakeAudio();
    final clock = FixedClock(DateTime.utc(2026));
    final services = AppServices.create(
      AppDatabase.inMemory(),
      audio: audio.backends,
      clock: clock,
    );
    final physics = services.notebooks.create(
      title: 'Physics',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final shared = SharedNotebooks(services);
    final first = shared.acquire(physics);
    expect(await first.audio.recorder.start(), isTrue);
    clock.at = clock.at.add(const Duration(milliseconds: 600)); // Long enough to keep.
    shared.release(first);
    await pumpEventQueue();
    final saving = Completer<void>();
    audio.capture.holdStop = saving.future;
    services.notebooks.trash(physics.id);
    shared.notebooksChanged();
    services.notebooks.delete(physics.id); // Delete forever while it saves.
    shared.notebooksChanged();
    saving.complete();
    await until(() => shared.ids.isEmpty);
    expect(services.recordings.listOf(physics.id), isEmpty);
    shared.dispose();
  });
}
