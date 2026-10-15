import '../core/clock.dart';
import '../data/app_database.dart';
import '../sync/pull_worker.dart';

/// Browsers apply pulled pages on the UI thread (one connection): null.
Future<PullWorker?> startPullWorker(
  AppDatabase database, {
  required String deviceId,
  Clock clock = const Clock(),
}) async => null;
