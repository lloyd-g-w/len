import 'dart:async';
import 'dart:io';

import 'package:len_sync_server/len_sync_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Entry point: reads config, opens the store and serves the API.
/// `server gc …` runs blob garbage collection instead (see bin/gc.dart),
/// `server new-id` gives the server a new id (after restoring a backup).
Future<void> main(List<String> args) async {
  final command = switch (args.firstOrNull) {
    'gc' => runGcCommand,
    'new-id' => runNewIdCommand,
    _ => null,
  };
  if (command != null) {
    exit(command(args.sublist(1), Platform.environment, out: stdout, err: stderr));
  }
  final Config config;
  try {
    config = Config.fromEnvironment(Platform.environment);
  } on ConfigException catch (e) {
    stderr.writeln('len-sync: ${e.message}');
    exit(64); // EX_USAGE
  }

  final store = RecordStore.open(config.dbPath);
  final blobs = BlobStore.open(config.blobDir);
  final requests = RequestTracker();
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(requests.middleware)
      .addHandler(
        buildHandler(
          store: store,
          blobs: blobs,
          token: config.token,
          maxBlobBytes: config.blobMaxBytes,
          blobIdleTimeout: config.blobIdleTimeout,
          cors: config.cors,
        ),
      );

  final server = await shelf_io.serve(handler, config.host, config.port);
  stdout.writeln(
    'len-sync: listening on ${config.host}:${server.port}, '
    'db ${config.dbPath}, blobs ${config.blobDir}',
  );

  await _waitForShutdownSignal();
  stdout.writeln('len-sync: shutting down');
  // Stop accepting connections, let requests in flight finish (a push
  // commits, an upload completes) and only then close the database; give
  // up after a grace period that fits Docker's default stop timeout (10 s).
  final closing = server.close();
  final grace = Stopwatch()..start();
  if (!await requests.drain(_shutdownGrace)) {
    stderr.writeln('len-sync: ${requests.inFlight} request(s) still running, closing anyway');
    await server.close(force: true);
  } else {
    // A handler can return a streaming response, so the request tracker
    // may be idle while close() still waits for a client reading forever.
    final remaining = _shutdownGrace - grace.elapsed;
    if (remaining <= Duration.zero) {
      await server.close(force: true);
    } else {
      // (`closing` is a Future<ServerSocket> at runtime: time out a void
      // view of it, or the void callback fails the type check.)
      await closing
          .then<void>((_) {})
          .timeout(
            remaining,
            onTimeout: () async {
              stderr.writeln('len-sync: forcing closed stalled client connection(s)');
              await server.close(force: true);
            },
          );
    }
  }
  // close(force: true) also finishes the original close() future.
  await closing;
  store.close(); // checkpoints the WAL
  exit(0);
}

const _shutdownGrace = Duration(seconds: 8);

/// Completes on the first SIGINT or SIGTERM.
Future<void> _waitForShutdownSignal() {
  final done = Completer<void>();
  void onSignal(ProcessSignal _) {
    if (!done.isCompleted) done.complete();
  }

  ProcessSignal.sigint.watch().listen(onSignal);
  ProcessSignal.sigterm.watch().listen(onSignal);
  return done.future;
}
