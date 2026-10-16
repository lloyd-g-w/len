import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:pasteboard/pasteboard.dart';

import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import '../../../domain/text/html_writer.dart';
import '../../../domain/text/text_data.dart';
import '../../../ink/images/element_images.dart';
import '../../../ink/selection/selection_image.dart';
import 'image_signature.dart';

/// Writes the system clipboard: a PNG (maybe still rendering), plain text
/// and / or its HTML as one entry; completes with whether it is there.
typedef SystemClipboardWriter = Future<bool> Function({
  Future<Uint8List?>? png,
  String? text,
  String? html,
});

/// Puts what the lasso copies on the system clipboard as well, for other
/// apps: a picture of it (PNG, transparent, [SelectionImage]) and — when
/// only text boxes were copied — their text, plain and formatted (HTML,
/// [htmlFromTexts]). Len's own paste keeps
/// using the in-app clipboard (`InkClipboard`, ink stays ink): it asks
/// [holdsInk] / [holdsInkText] whether what the system clipboard holds is
/// that picture or text, even converted by the platform.
class ClipboardMirror {
  ClipboardMirror({required this.images, SystemClipboardWriter? write})
    : _write = write ?? Pasteboard.write;

  /// Decoded bitmaps for drawing copied images.
  final ElementImages images;

  final SystemClipboardWriter _write;

  /// The picture last put on the clipboard (its hash, and how it looks).
  ({String sha, Future<ImageSignature?> signature})? _image;

  /// The text last put on the clipboard.
  String? _text;

  /// Counts copies, so a slow one doesn't overwrite a later one's record.
  int _copies = 0;

  Future<bool>? _written;

  /// Whether the last copy's write put it on the system clipboard (null
  /// before the first copy). While it did, nothing there is older than
  /// the ink copied.
  Future<bool>? get written => _written;

  /// Mirrors a copy of [strokes] and [elements] onto the system clipboard.
  /// Call it within the user's gesture (the web's clipboard needs one):
  /// the write starts at once, the picture follows when rendered.
  Future<bool> copy(List<Stroke> strokes, List<SurfaceElement> elements) {
    final copy = ++_copies;
    final boxes = strokes.isEmpty ? textBoxes(elements) : null;
    final text = boxes == null ? null : _plain(boxes);
    _text = text;
    _image = null;
    final png = _render(strokes, elements);
    unawaited(_remember(copy, png));
    return _written = _writeOrText(png, text, boxes == null ? null : htmlFromTexts(boxes));
  }

  /// Writes [png], [text] and [html]; failing that, [text] alone, the usual
  /// way (no image support). Whether either worked; never an error.
  Future<bool> _writeOrText(Future<Uint8List?> png, String? text, String? html) async {
    var written = false;
    try {
      written = await _write(png: png, text: text, html: html);
    } on Object catch (e) {
      debugPrint('Copying to the system clipboard failed: $e');
    }
    if (written || text == null) return written;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } on Object catch (e) {
      debugPrint('Copying text to the system clipboard failed: $e');
      return false;
    }
  }

  /// Whether the system clipboard's image [bytes] is the picture of the
  /// last copy (as written, or as the platform converted it).
  Future<bool> holdsInk(Uint8List bytes) async {
    final own = _image;
    if (own == null) return false;
    if (sha256.convert(bytes).toString() == own.sha) return true;
    final mine = await own.signature;
    if (mine == null) return false;
    final theirs = await ImageSignature.of(bytes, width: mine.width, height: mine.height);
    return theirs != null && mine.matches(theirs);
  }

  /// Whether [text] from the system clipboard is the last copy's text
  /// (whatever line breaks the platform gave it).
  bool holdsInkText(String text) =>
      _text != null && text.replaceAll('\r\n', '\n').trimRight() == _text;

  Future<Uint8List?> _render(List<Stroke> strokes, List<SurfaceElement> elements) async {
    try {
      return await SelectionImage.png(strokes, elements, images: images);
    } on Object catch (e) {
      debugPrint('Rendering the copied selection failed: $e');
      return null;
    }
  }

  Future<void> _remember(int copy, Future<Uint8List?> png) async {
    final bytes = await png;
    if (bytes == null || copy != _copies) return;
    _image = (sha: sha256.convert(bytes).toString(), signature: ImageSignature.of(bytes));
  }

  /// The text of the text boxes among [elements], top to bottom (then left
  /// to right), a blank line between boxes; null if there is none, or if
  /// [elements] are not all text boxes.
  static String? plainText(List<SurfaceElement> elements) {
    final boxes = textBoxes(elements);
    return boxes == null ? null : _plain(boxes);
  }

  static String _plain(List<TextData> boxes) =>
      [for (final b in boxes) b.text.trimRight()].join('\n\n');

  /// The text boxes among [elements] that hold text, top to bottom (then
  /// left to right); null if there is none, or if [elements] are not all
  /// text boxes.
  static List<TextData>? textBoxes(List<SurfaceElement> elements) {
    if (elements.isEmpty || elements.any((e) => e.knownType != ElementType.text)) return null;
    final sorted = [...elements]
      ..sort((a, b) {
        final byTop = a.bounds.top.compareTo(b.bounds.top);
        return byTop != 0 ? byTop : a.bounds.left.compareTo(b.bounds.left);
      });
    final boxes = [for (final e in sorted) TextData.fromJson(e.data)]
        .where((t) => t.text.trim().isNotEmpty)
        .toList();
    return boxes.isEmpty ? null : boxes;
  }
}
