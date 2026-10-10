/// Makes sure only one instance of the app uses the local database
/// (`claimSingleInstance`). Native platforms already run one process per
/// app; in browsers every tab would otherwise load its own in-memory copy
/// of the SQLite file and overwrite the other's changes in IndexedDB.
library;

export 'single_instance_native.dart' if (dart.library.js_interop) 'single_instance_web.dart';
