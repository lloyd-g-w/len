import '../data/app_database.dart';

/// Browsers have one connection and no isolates sharing it: runs [query]
/// on the UI thread, in a task of its own after the current frame.
Future<T> queryInBackground<T>(AppDatabase database, T Function(AppDatabase db) query) =>
    Future(() => query(database));
