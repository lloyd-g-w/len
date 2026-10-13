/// The `new-id` admin command, run after restoring a backup.
library;

import 'config.dart';
import 'record_store.dart';

const _usage = '''
Usage: new-id

Gives the server a new id, so every device uploads its complete copy again
and pulls everything from the start. Run it after restoring a backup (with
the server stopped or running): changes made after the backup was taken
then come back from the devices that have them. Reads LEN_DB_PATH.
''';

/// Runs the `new-id` command; returns the process exit code.
int runNewIdCommand(
  List<String> args,
  Map<String, String> env, {
  required StringSink out,
  required StringSink err,
}) {
  if (args case ['-h' || '--help']) {
    out.write(_usage);
    return 0;
  }
  if (args.isNotEmpty) {
    err.write('new-id: unexpected argument "${args.first}"\n\n$_usage');
    return 64;
  }
  final store = RecordStore.open(Config.dbPathFrom(env));
  try {
    store.rotateServerId();
    out.writeln(
      'new-id: server id is now ${store.serverId}; devices will upload everything again.',
    );
    return 0;
  } finally {
    store.close();
  }
}
