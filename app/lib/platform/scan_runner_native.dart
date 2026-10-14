import 'dart:isolate';
import 'dart:typed_data';

import '../features/documents/scan/quad_detector.dart';
import '../features/documents/scan/scan_job.dart';

/// Renders and encodes [job]'s page on a worker isolate.
Future<ScanOutput> runScanJob(ScanJob job) => Isolate.run(job.run);

/// Renders [job]'s page (no encoding) on a worker isolate, e.g. a thumbnail.
Future<RgbaImage> renderScanPreview(ScanJob job) => Isolate.run(job.render);

/// The document's outline in [photo] (its pixels), found on a worker
/// isolate; null if there is no convincing one.
Future<Quad?> detectScanQuad(RgbaImage photo) => Isolate.run(() => QuadDetector.find(photo));

/// [image] as a JPEG of [quality], encoded on a worker isolate.
Future<Uint8List> encodeScanJpeg(RgbaImage image, {required int quality}) =>
    Isolate.run(() => encodeJpeg(image, quality: quality));
