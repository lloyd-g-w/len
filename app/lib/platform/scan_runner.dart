/// Chooses where scanned pages are flattened (`runScanJob`,
/// `renderScanPreview`), documents are found in photos (`detectScanQuad`)
/// and photos are re-encoded (`encodeScanJpeg`): natively on a worker
/// isolate; on the web on the UI thread (flattening in slices).
library;

export 'scan_runner_native.dart' if (dart.library.js_interop) 'scan_runner_web.dart';
