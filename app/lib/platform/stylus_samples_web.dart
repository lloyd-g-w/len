import '../ink/input/sample_source.dart';
import '../ink/input/stylus_batch.dart';
import '../ink/input/wet_ink.dart';

/// Browsers deliver coalesced samples themselves; nothing to add, and there
/// is no low-latency overlay.
SampleSource? openStylusSamples({WetInkStyle? Function()? wetInk, bool Function()? lowLatency}) =>
    null;

/// No stylus batches on the web.
void observeStylusBatches(void Function(List<StylusBatch> batches)? observer) {}
