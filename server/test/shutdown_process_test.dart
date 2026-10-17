@TestOn('linux || mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

/// Runs the real server binary and stops it the way Docker does.
void main() {
  test('SIGTERM shuts down cleanly (exit 0, database closed)', () async {
    final dir = await Directory.systemTemp.createTemp('len-sync-shutdown-');
    addTearDown(() => dir.delete(recursive: true));
    final port = 20000 + Random.secure().nextInt(20000);
    final server = await Process.start(
      Platform.resolvedExecutable,
      ['bin/server.dart'],
      environment: {
        'LEN_SYNC_TOKEN': 'shutdown-test-token-0123456789',
        'LEN_DB_PATH': '${dir.path}/len.db',
        'HOST': '127.0.0.1',
        'PORT': '$port',
      },
    );
    final out = StringBuffer();
    final listening = Completer<void>();
    server.stdout.transform(utf8.decoder).listen((s) {
      out.write(s);
      if (s.contains('listening') && !listening.isCompleted) listening.complete();
    });
    server.stderr.transform(utf8.decoder).listen(out.write);
    await listening.future.timeout(const Duration(seconds: 60));

    // A client that keeps its connection open (as the app's does).
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.get('127.0.0.1', port, '/v1/health');
    await (await request.close()).drain<void>();

    // And one listening to the event stream, which never ends by itself.
    final events = await client.get('127.0.0.1', port, '/v1/events');
    events.headers.set('authorization', 'Bearer shutdown-test-token-0123456789');
    final stream = await events.close();
    expect(stream.statusCode, 200);
    final streamEnded = Completer<void>();
    stream.listen(
      (_) {},
      onDone: streamEnded.complete,
      onError: (Object _) {
        if (!streamEnded.isCompleted) streamEnded.complete();
      },
    );

    // And a live connection.
    final live = await WebSocket.connect(
      'ws://127.0.0.1:$port/v1/live',
      headers: {'authorization': 'Bearer shutdown-test-token-0123456789'},
    );
    final liveClosed = Completer<int?>();
    live.listen((_) {}, onDone: () => liveClosed.complete(live.closeCode));

    final stopping = Stopwatch()..start();
    server.kill(ProcessSignal.sigterm);
    final code = await server.exitCode.timeout(const Duration(seconds: 20));
    expect(code, 0, reason: '$out');
    expect('$out', contains('shutting down'));
    expect('$out', isNot(contains('Unhandled exception')));
    // The stream was ended, not waited for until the grace period ran out.
    expect('$out', isNot(contains('forcing closed')));
    expect(stopping.elapsed, lessThan(const Duration(seconds: 8)));
    await streamEnded.future.timeout(const Duration(seconds: 5));
    expect(await liveClosed.future.timeout(const Duration(seconds: 5)), WebSocketStatus.goingAway);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
