import 'dart:async';

import 'package:len_sync_server/len_sync_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final request = Request('GET', Uri.parse('http://localhost/v1/pull'));

  test('drain waits for requests in flight', () async {
    final tracker = RequestTracker();
    final release = Completer<void>();
    final handler = tracker.middleware((_) async {
      await release.future;
      return Response.ok('done');
    });

    expect(await tracker.drain(Duration.zero), isTrue);
    final response = handler(request);
    await pumpEventQueue();
    expect(tracker.inFlight, 1);

    var drained = false;
    final draining = tracker.drain(const Duration(seconds: 5)).then((ok) => drained = ok);
    await pumpEventQueue();
    expect(drained, isFalse);

    release.complete();
    expect((await response).statusCode, 200);
    await draining;
    expect(drained, isTrue);
    expect(tracker.inFlight, 0);
  });

  test('drain gives up after the timeout', () async {
    final tracker = RequestTracker();
    final handler = tracker.middleware((_) => Completer<Response>().future);
    unawaited(Future.sync(() => handler(request)));
    await pumpEventQueue();
    expect(await tracker.drain(const Duration(milliseconds: 10)), isFalse);
    expect(tracker.inFlight, 1);
  });

  test('a failing handler is no longer counted', () async {
    final tracker = RequestTracker();
    final handler = tracker.middleware((_) => throw StateError('boom'));
    await expectLater(Future.sync(() => handler(request)), throwsStateError);
    expect(tracker.inFlight, 0);
    expect(await tracker.drain(Duration.zero), isTrue);
  });
}
