/// The `gc` admin command: blob garbage collection from the command line.
library;

import 'blob_gc.dart';
import 'blob_store.dart';
import 'config.dart';
import 'record_store.dart';

const _usage = '''
Usage: gc [--dry-run] [--grace-days <days>]

Deletes blobs that no live record has referenced for the grace period
(default 30 days; see server/README.md, "Blob garbage collection").
Blobs found unreferenced for the first time are only marked, so run this
regularly (e.g. daily from cron). Safe while the server is running.

Reads LEN_DB_PATH and LEN_BLOB_DIR like the server.

  --dry-run           Report what would be deleted; change nothing.
  --grace-days <n>    Grace period in days (at least 1).
  -h, --help          Show this help.
''';

/// Runs the `gc` command with [args] and environment [env], writing to
/// [out] / [err]. Returns the process exit code.
int runGcCommand(
  List<String> args,
  Map<String, String> env, {
  required StringSink out,
  required StringSink err,
}) {
  var dryRun = false;
  var graceDays = BlobGc.defaultGrace.inDays;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--dry-run':
        dryRun = true;
      case '--grace-days' when i + 1 < args.length:
        final days = int.tryParse(args[++i]);
        if (days == null || days < 1) {
          err.writeln('gc: --grace-days must be a positive integer');
          return 64;
        }
        graceDays = days;
      case '-h' || '--help':
        out.write(_usage);
        return 0;
      default:
        err.write('gc: unexpected argument "${args[i]}"\n\n$_usage');
        return 64;
    }
  }

  final dbPath = Config.dbPathFrom(env);
  final blobDir = Config.blobDirFrom(env);
  final records = RecordStore.open(dbPath);
  try {
    final blobs = BlobStore.open(blobDir);
    final result = BlobGc(records, blobs, grace: Duration(days: graceDays)).run(dryRun: dryRun);
    final verb = dryRun ? 'would delete' : 'deleted';
    out.writeln(
      'gc: ${result.stored} blobs, ${result.referenced} referenced, '
      '${result.waiting.length} unreferenced within the $graceDays-day grace period, '
      '$verb ${result.deleted.length} (${_mib(result.deletedBytes)}).',
    );
    for (final sha in result.deleted) {
      out.writeln('  $verb $sha');
    }
    return 0;
  } finally {
    records.close();
  }
}

String _mib(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
