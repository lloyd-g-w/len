/// Where a PDF went to be printed (`platform/print_document`).
enum PrintHandoff {
  /// A print dialog opened here (Android's print framework, the browser's):
  /// it speaks for itself.
  dialog,

  /// Handed to the default PDF reader's print command (Windows).
  reader,

  /// Opened in the default viewer, to be printed from there (Linux, a
  /// Windows reader without a print command, a browser tab).
  viewer,

  /// Downloaded, to be printed from there (a browser that can't show PDFs
  /// and blocked a new tab).
  downloaded,
}
