import 'dart:io';
import 'dart:math' as math;

import '../ink/render/background_outlines.dart';
import '../ink/render/outline_preparer.dart';

/// Worker isolates (two, or one on a two-core machine).
OutlinePreparer createOutlinePreparer() =>
    BackgroundOutlines(workers: math.max(1, math.min(2, Platform.numberOfProcessors - 1)));
