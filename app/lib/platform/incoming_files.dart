/// Files handed to Len by the operating system (`openIncomingFiles`):
///
/// * **Android:** "Open with" (`ACTION_VIEW`) and "Share" (`ACTION_SEND`,
///   `ACTION_SEND_MULTIPLE`) of PDFs and images. `IncomingFiles.kt` copies
///   the content URIs into the app's cache and sends them over the
///   `len/incoming_files` channel, at launch (cold start) and later
///   (`onNewIntent`, warm start).
/// * **Linux / Windows:** file paths (or `file://` URIs) on the command
///   line, e.g. `len notes.pdf` or the desktop entry's `%U`.
/// * **Web:** the PWA's File Handling API (`launchQueue`, `file_handlers`
///   in `manifest.json`).
///
/// And links (`incomingLinks`): `len://sync?…` setup links opened on
/// Android (the `len` scheme's intent filter; a `link` call on the same
/// channel) or given on a desktop's command line (`len "len://sync?…"`).
library;

export 'incoming_files_native.dart' if (dart.library.js_interop) 'incoming_files_web.dart';
