import '../ink/render/outline_preparer.dart';

/// Browsers build outlines on the UI thread.
OutlinePreparer createOutlinePreparer() => const InlineOutlinePreparer();
