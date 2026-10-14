/// Chooses where scanned pages are flattened (`runScanJob`,
/// `renderScanPreview`): natively on a worker isolate; on the web on the
/// UI thread, in slices.
library;

export 'scan_runner_native.dart' if (dart.library.js_interop) 'scan_runner_web.dart';
