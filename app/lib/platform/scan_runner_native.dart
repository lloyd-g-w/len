import 'dart:isolate';

import '../features/documents/scan/scan_job.dart';

/// Renders and encodes [job]'s page on a worker isolate.
Future<ScanOutput> runScanJob(ScanJob job) => Isolate.run(job.run);

/// Renders [job]'s page (no encoding) on a worker isolate, e.g. a thumbnail.
Future<RgbaImage> renderScanPreview(ScanJob job) => Isolate.run(job.render);
