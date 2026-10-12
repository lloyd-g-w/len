import 'dart:io';
import 'dart:math' as math;

import '../ink/render/background_outlines.dart';
import '../ink/render/outline_preparer.dart';

/// Worker isolates: up to three, leaving two cores for the UI and raster
/// threads (one on a machine with three cores or fewer).
OutlinePreparer createOutlinePreparer() =>
    BackgroundOutlines(workers: math.max(1, math.min(3, Platform.numberOfProcessors - 2)));
