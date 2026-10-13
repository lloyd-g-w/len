/// Makes sure only one instance of the app uses the local database
/// (`openTabHandover`). Native platforms already run one process per app;
/// in browsers every tab would otherwise load its own in-memory copy of
/// the SQLite database and overwrite the other's changes in IndexedDB, so
/// one tab holds a Web Lock and others wait or take over ([TabHandover]).
library;

export 'single_instance_native.dart' if (dart.library.js_interop) 'single_instance_web.dart';
export 'tab_handover.dart';
