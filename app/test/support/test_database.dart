import 'package:len/data/app_database.dart';

/// Opens the databases of sync test devices: in memory, unless a test runs
/// them on files (`sync_worker_test.dart`: pulls then go through a worker
/// isolate with its own connection).
AppDatabase Function() openTestDatabase = AppDatabase.inMemory;
