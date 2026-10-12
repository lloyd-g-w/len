/// HTML on the system clipboard, for pasting formatted text into text
/// boxes (`readClipboardHtml`): read through `pasteboard` on Windows
/// (CF_HTML), Android (`ClipData` HTML text) and Linux (`text/html`, our
/// vendored addition); on the web from the `paste` event of a browser paste
/// (`htmlPastedAs`, no permission needed) or the async Clipboard API.
library;

export 'clipboard_html_native.dart' if (dart.library.js_interop) 'clipboard_html_web.dart';
