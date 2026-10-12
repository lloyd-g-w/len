import 'browser_storage_api.dart';

export 'browser_storage_api.dart';

/// Native data lives in files, which nothing evicts.
BrowserStorage? get browserStorage => null;

/// Nothing to request natively.
Future<void> requestPersistentStorageOnStartup() async {}
