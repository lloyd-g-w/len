import 'dart:io';

import 'package:len_sync_server/len_sync_server.dart';

/// Blob garbage collection: `dart run bin/gc.dart [--dry-run]` (in the
/// Docker image: `/opt/len-sync/bin/server gc`). See server/README.md.
void main(List<String> args) {
  exitCode = runGcCommand(args, Platform.environment, out: stdout, err: stderr);
}
