import '../features/documents/scan/quad_detector.dart';
import '../features/documents/scan/scan_job.dart';

/// Renders and encodes [job]'s page on the UI thread, yielding between bands.
Future<ScanOutput> runScanJob(ScanJob job) => job.runSliced(_yield);

/// Renders [job]'s page (no encoding) on the UI thread, yielding between
/// bands, e.g. a thumbnail.
Future<RgbaImage> renderScanPreview(ScanJob job) => job.renderSliced(_yield);

/// The document's outline in [photo] (its pixels); null if there is no
/// convincing one. Detection works on a small copy: it runs in one go.
Future<Quad?> detectScanQuad(RgbaImage photo) async {
  await _yield();
  return QuadDetector.find(photo);
}

Future<void> _yield() => Future<void>.delayed(Duration.zero);
