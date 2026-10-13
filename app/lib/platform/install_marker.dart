/// The install marker (`readInstallMarker` / `writeInstallMarker`): a small
/// file next to the database holding this installation's device id, which
/// backups leave out, so a restored database is recognised
/// (`data/install_identity.dart`). Browsers have none (their storage is
/// never restored elsewhere): reads give null, writes do nothing.
library;

export 'install_marker_native.dart' if (dart.library.js_interop) 'install_marker_web.dart';
