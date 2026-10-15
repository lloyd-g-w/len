import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import '../data/app_database.dart';
import '../data/storage_queries.dart';

/// [StorageQueries.survey] off the UI thread: on a worker isolate with a
/// read-only connection to the database's file, which (with its
/// write-ahead log) is measured on disk. An in-memory database (tests) is
/// surveyed in place. [keep]: notebooks whose files must stay.
Future<StorageSurvey> surveyStorage(AppDatabase database, {Set<String> keep = const {}}) {
  final path = database.path;
  if (path == null) return Future.value(StorageQueries(database.db).survey(keep: keep));
  return _inWorker(path, keep);
}

Future<StorageSurvey> _inWorker(String path, Set<String> keep) =>
    Isolate.run(() => _survey(path, keep), debugName: 'storage survey');

StorageSurvey _survey(String path, Set<String> keep) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    db.execute('PRAGMA busy_timeout = ${AppDatabase.busyTimeoutMs}');
    final survey = StorageQueries(db).survey(keep: keep);
    return survey.withDatabase(_size(path) + _size('$path-wal') + _size('$path-shm'));
  } finally {
    db.close();
  }
}

int _size(String path) {
  final file = File(path);
  return file.existsSync() ? file.lengthSync() : 0;
}
