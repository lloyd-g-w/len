import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint;

import '../data/app_database.dart';

/// Runs [query] on a worker isolate over a connection of its own to
/// [database]'s file, so a scan of many rows never holds the UI thread.
/// [query] must be sendable to an isolate (capture only plain values). An
/// in-memory database (tests) is queried in place; so is the file if the
/// worker fails.
Future<T> queryInBackground<T>(AppDatabase database, T Function(AppDatabase db) query) async {
  final path = database.path;
  if (path == null) return query(database);
  try {
    return await Isolate.run(() {
      final db = AppDatabase.attach(path);
      try {
        return query(db);
      } finally {
        db.close();
      }
    }, debugName: 'query');
  } on Object catch (e) {
    debugPrint('Background query failed, querying in place: $e');
    return query(database);
  }
}
