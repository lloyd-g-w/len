import 'dart:async';
import 'dart:io';

import 'package:len_sync_server/len_sync_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Entry point: reads config, opens the store and serves the API.
Future<void> main() async {
  final Config config;
  try {
    config = Config.fromEnvironment(Platform.environment);
  } on ConfigException catch (e) {
    stderr.writeln('len-sync: ${e.message}');
    exit(64); // EX_USAGE
  }

  final store = RecordStore.open(config.dbPath);
  final blobs = BlobStore.open(config.blobDir);
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(
        buildHandler(
          store: store,
          blobs: blobs,
          token: config.token,
          maxBlobBytes: config.blobMaxBytes,
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
  await server.close();
  store.close();
  exit(0);
}

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
