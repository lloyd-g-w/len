import 'package:flutter/foundation.dart';

import 'export_options.dart';

/// What the last export chose, for the app's run (UX_AUDIT R22-2): the
/// next sheet starts there. A typed range is not kept (the pages differ).
class ExportMemory {
  ExportMemory._();

  static ExportFormat format = ExportFormat.pdf;

  /// Current page or all pages; null after a typed range or none yet.
  static ExportRange? range;
  static bool templates = true;
  static bool backgrounds = true;

  /// Forgets the choices (tests).
  @visibleForTesting
  static void reset() {
    format = ExportFormat.pdf;
    range = null;
    templates = backgrounds = true;
  }

  /// Keeps [options]; a print ([print]) leaves the export's format alone.
  static void keep(
    ExportOptions options,
    ExportRange? range, {
    required bool choosePages,
    bool print = false,
  }) {
    if (!print) format = options.format;
    templates = options.includeTemplates;
    backgrounds = options.includeBackgrounds;
    if (choosePages && options.format != ExportFormat.len) {
      ExportMemory.range = range == ExportRange.custom ? null : range;
    }
  }
}
