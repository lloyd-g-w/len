import '../ink/render/outline_preparer.dart';
import '../ink/render/sliced_outline_preparer.dart';

/// Browsers build outlines on the UI thread, in time-budgeted slices.
OutlinePreparer createOutlinePreparer() => SlicedOutlinePreparer();
