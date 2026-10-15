import '../core/clock.dart';
import '../data/app_database.dart';
import '../sync/background_pull_worker.dart';
import '../sync/pull_worker.dart';

/// A worker isolate applying pulled pages to the file of [database] (see
/// [BackgroundPullWorker]); null for an in-memory database or if it cannot
/// start.
Future<PullWorker?> startPullWorker(
  AppDatabase database, {
  required String deviceId,
  Clock clock = const Clock(),
}) => BackgroundPullWorker.start(database, deviceId: deviceId, clock: clock);
