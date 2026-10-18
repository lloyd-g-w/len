/// HTML and RTF on the system clipboard, for pasting formatted text into
/// text boxes (`readClipboardRich`): HTML read through `pasteboard` on
/// Windows (CF_HTML), Android (`ClipData` HTML text) and Linux
/// (`text/html`, our vendored addition), RTF on Windows ("Rich Text
/// Format") and Linux (`text/rtf` and kin; both our additions); on the web
/// from the `paste` event of a browser paste (`richPastedAs`, no permission
/// needed: HTML and RTF) or the async Clipboard API (HTML only).
library;

export 'clipboard_html_native.dart' if (dart.library.js_interop) 'clipboard_html_web.dart';
export 'rich_clip.dart';
