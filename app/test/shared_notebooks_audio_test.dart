import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/shared/shared_notebooks.dart';

import 'support/fake_audio.dart';

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
    final services = AppServices.create(AppDatabase.inMemory(), audio: audio.backends);
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
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final saving = Completer<void>();
    audio.capture.holdStop = saving.future;
    shared.release(first); // Stops and saves the recording.

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
}
