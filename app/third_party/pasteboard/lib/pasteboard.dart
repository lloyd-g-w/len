import 'dart:async';
import 'dart:typed_data';

import 'src/pasteboard_platform_web.dart'
    if (dart.library.io) 'src/pasteboard_platform_io.dart';
import 'src/pasteboard_platform.dart';

export 'src/cf_html.dart' show encodeCfHtml;
export 'src/pasteboard_platform.dart' show PasteboardKind;

class Pasteboard {
  /// What kinds of content the clipboard holds, without reading it (added
  /// in this copy): Android asks the clip's description (reading the clip
  /// makes Android 12+ announce a paste), Linux the GTK targets, Windows
  /// the formats available, the web reads only where the user already
  /// allowed silent reads. Null where that can't be known (Firefox and
  /// Safari, iOS, macOS, or the platform call failed).
  static Future<Set<PasteboardKind>?> peek() => pasteboard.peek();

  /// Returns the image data of the pasteboard.
  ///
  /// available on iOS, Desktop, Web, Android
  static Future<Uint8List?> get image => pasteboard.image;

  /// only available on Windows, Android, Linux (added in this copy) and the web.
  /// Get "HTML format" from system pasteboard.
  /// HTML format: https://docs.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/aa767917(v=vs.85)
  static Future<String?> get html => pasteboard.html;

  /// Puts a PNG image, plain text and / or an HTML fragment (only with
  /// [text], its plain version) on the system clipboard as one entry
  /// (other apps take the format they understand). Added in this copy;
  /// available on Android, Linux, Windows and the web. [png] may still be
  /// rendering: the web hands the browser a promise of it, as Safari only
  /// lets a user gesture write the clipboard synchronously. [html] is
  /// wrapped as each platform expects (Windows' CF_HTML header, a UTF-8
  /// `<meta>` for GTK). Returns whether the clipboard now holds it.
  static Future<bool> write({Future<Uint8List?>? png, String? text, String? html}) =>
      pasteboard.write(png: png, text: text, html: text == null ? null : html);

  /// available on iOS, Android, Web
  ///
  /// set image data to system pasteboard.
  static Future<void> writeImage(Uint8List? image) =>
      pasteboard.writeImage(image);

  /// available on Desktop, Android.
  ///
  /// Android: paths are content uris, must read by content resolver.
  ///
  /// Get files from system pasteboard.
  static Future<List<String>> files() => pasteboard.files();

  /// Only available on desktop platforms.
  ///
  /// Set files to system pasteboard.
  static Future<bool> writeFiles(List<String> files) =>
      pasteboard.writeFiles(files);

  /// Available on all platforms.
  /// Get text from system pasteboard.
  static Future<String?> get text => pasteboard.text;

  /// Available on all platforms.
  /// Set text to system pasteboard.
  static void writeText(String value) => pasteboard.writeText(value);
}
