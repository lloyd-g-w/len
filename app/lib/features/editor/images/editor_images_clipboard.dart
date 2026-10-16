part of 'editor_images.dart';

/// Reading the system clipboard for [EditorImages.paste], and telling what
/// there is older than the ink last copied in the app.
extension _EditorImagesClipboard on EditorImages {
  /// The system clipboard's image (null if it holds none or can't be read).
  Future<Uint8List?> _clipboardImage() async {
    try {
      final bytes = await _readClipboard();
      return bytes == null || bytes.isEmpty ? null : bytes;
    } on Object catch (e) {
      debugPrint('Clipboard image unavailable: $e');
      return null;
    }
  }

  /// Whether the system clipboard's image [bytes] is no newer than the ink
  /// copied in the app: there before the copy, or its picture.
  Future<bool> _isInk(Uint8List bytes) async =>
      !services.clipboard.isEmpty &&
      (_hash(bytes) == _imageBeforeInkCopy || await services.clipboardMirror.holdsInk(bytes));

  /// As [_isInk], for the system clipboard's [text].
  bool _isInkText(String text) =>
      text == _textBeforeInkCopy || services.clipboardMirror.holdsInkText(text);

  Future<void> _rememberOlder(Future<bool>? written) async {
    if (written != null && await written) return;
    // A later copy decides for itself.
    if (!identical(written, services.clipboardMirror.written)) return;
    final text = await _clipboardText();
    final bytes = await _clipboardImage();
    if (!identical(written, services.clipboardMirror.written)) return;
    _textBeforeInkCopy = text;
    _imageBeforeInkCopy = bytes == null ? null : _hash(bytes);
  }
}

/// The system clipboard's text, if it holds any that isn't blank.
Future<String?> _clipboardText() async {
  try {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    return text == null || text.trim().isEmpty ? null : text;
  } on Object catch (e) {
    debugPrint('Clipboard text unavailable: $e');
    return null;
  }
}

/// The fingerprint of an image the clipboard held.
String _hash(Uint8List bytes) => sha256.convert(bytes).toString();

/// The clipboard's image, or the first image file copied (desktop).
Future<Uint8List?> _systemClipboardImage() async {
  final image = await Pasteboard.image;
  if (image != null && image.isNotEmpty) return image;
  final desktop = const {
    TargetPlatform.linux,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  }.contains(defaultTargetPlatform);
  if (kIsWeb || !desktop) return null; // Android lists content URIs.
  for (final path in await Pasteboard.files()) {
    final ext = path.split('.').last.toLowerCase();
    if (ImageImport.extensions.contains(ext)) return XFile(path).readAsBytes();
  }
  return null;
}
