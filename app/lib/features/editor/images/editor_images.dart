import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:pasteboard/pasteboard.dart';

import '../../../app_services.dart';
import '../../../core/clock.dart';
import '../../../domain/image_data.dart';
import '../../../domain/surface_element.dart';
import '../../../domain/text/html_text.dart';
import '../../../ink/tool_settings.dart';
import '../../../ink/tools/content_tools.dart';
import '../../../platform/clipboard_html.dart';
import '../../../ui/app_theme.dart';
import '../../camera/camera_purpose.dart';
import '../../documents/progress_dialog.dart';
import '../tools/text/rich_text_controller.dart';
import 'image_import.dart';
import 'image_placement.dart';

/// Reads an image from the system clipboard (null if it holds none).
typedef ClipboardImageReader = Future<Uint8List?> Function();

/// Inserting images into an open editor: from files (picker or drag and
/// drop), the system clipboard or — on Android — the camera (also a photo
/// taken before Android killed Len, [insertRecovered]).
///
/// Every source ends in [insertBytes]: the image is prepared
/// ([ImageImport]), stored as a blob, placed on the page or canvas under
/// the given screen point (the centre by default) as one undoable edit, and
/// selected with the lasso so it can be moved or resized at once.
class EditorImages {
  EditorImages({
    required this.services,
    required this.notebookId,
    required this.content,
    required this.tools,
    this.activateAt,
    this.reveal,
    ClipboardImageReader? readClipboard,
    Future<String?> Function()? readHtml,
    this.clock = const Clock(),
  }) : _readClipboard = readClipboard ?? _systemClipboardImage,
       _readHtml = readHtml ?? readClipboardHtml {
    services.clipboard.addListener(_onInkCopied);
    watchClipboardPastes();
  }

  final AppServices services;

  /// The notebook edited.
  final String notebookId;
  final ContentTools content;
  final ToolSettings tools;
  final Clock clock;

  /// Makes the page under a screen point the edited one (documents).
  final void Function(Offset screen)? activateAt;

  /// Shows point `at` of surface [id] (a page, made the edited one; or the
  /// canvas); false if there is no such surface here.
  final bool Function(String id, Offset at)? reveal;

  final ClipboardImageReader _readClipboard;

  /// Reads HTML from the system clipboard (null if it holds none).
  final Future<String?> Function() _readHtml;

  /// Hash of the system clipboard's image when ink was last copied in the
  /// app: that image is older than the ink, so Ctrl+V pastes the ink.
  String? _imageBeforeInkCopy;

  /// The system clipboard's text when ink was last copied in the app (as
  /// [_imageBeforeInkCopy], for text).
  String? _textBeforeInkCopy;

  /// Whether the camera can be offered (Android only).
  bool get canUseCamera => services.camera.available;

  static final _typeGroups = [
    const XTypeGroup(label: 'Images', extensions: ImageImport.extensions, mimeTypes: ['image/*']),
  ];

  void dispose() => services.clipboard.removeListener(_onInkCopied);

  // ---------------------------------------------------------------------------
  // Sources

  /// Lets the user pick image files and inserts them.
  Future<void> pickFiles(BuildContext context) async {
    final files = await openFiles(acceptedTypeGroups: _typeGroups);
    if (!context.mounted) return;
    await insertFiles(context, files);
  }

  /// Takes a photo with the camera (Android) and inserts it. Should
  /// Android kill Len meanwhile, the photo goes where the screen's centre
  /// was when Len starts again ([insertRecovered]).
  Future<void> takePhoto(BuildContext context) async {
    final XFile? photo;
    try {
      photo = await services.camera.takePhoto(_photoPurpose());
    } on Exception catch (e) {
      if (context.mounted) showMessage(context, 'Couldn’t open the camera');
      debugPrint('Camera failed: $e');
      return;
    }
    if (photo == null || !context.mounted) return;
    await insertFiles(context, [photo]);
  }

  /// Where a photo taken now goes: the screen's centre on the page there.
  PhotoOnSurface _photoPurpose() {
    final centre = content.viewport.size.center(Offset.zero);
    activateAt?.call(centre);
    return PhotoOnSurface(
      notebookId,
      surfaceId: content.model.surfaceId,
      at: content.viewport.toWorld(centre),
    );
  }

  /// Inserts [photo], taken before Android killed Len, centred on [at] on
  /// surface [surfaceId] (shown first); on the shown page's centre if that
  /// page is gone or [at] is out of sight.
  Future<void> insertRecovered(
    BuildContext context,
    XFile photo, {
    required String surfaceId,
    required Offset at,
  }) async {
    final shown = reveal?.call(surfaceId, at) ?? false;
    Offset? screen;
    if (shown) {
      final point = content.viewport.toScreen(at);
      final view = Offset.zero & content.viewport.size;
      if (view.deflate(Gaps.xl).contains(point)) screen = point;
    }
    await insertFiles(context, [photo], screen: screen);
  }

  /// Inserts [files] (e.g. dropped ones) around [screen], cascading them.
  Future<void> insertFiles(BuildContext context, List<XFile> files, {Offset? screen}) async {
    var at = screen;
    for (final file in files) {
      final Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } on Exception {
        if (context.mounted) showMessage(context, 'Couldn’t read “${file.name}”');
        continue;
      }
      if (!context.mounted) return;
      await insertBytes(context, bytes, screen: at, name: file.name);
      at = (at ?? content.viewport.size.center(Offset.zero)) + const Offset(32, 32);
    }
  }

  /// Ctrl+V, and the canvas menu's Paste here: pastes an image from the
  /// system clipboard if it holds one that is newer than the ink last
  /// copied in the app; otherwise pastes the app's own clipboard. Text
  /// becomes a text box, formatted when the clipboard has HTML (unless
  /// [plain], Ctrl+Shift+V). What is pasted lands around [screen] (the
  /// middle of the screen by default), selected; the tool stays.
  Future<void> paste(BuildContext context, {bool plain = false, Offset? screen}) async {
    final bytes = plain ? null : await _clipboardImage();
    if (!context.mounted) return;
    if (bytes != null && _hash(bytes) != _imageBeforeInkCopy) {
      await insertBytes(context, bytes, screen: screen);
      return;
    }
    // Plain text newer than the copied ink becomes a new text box.
    final text = await _clipboardText();
    if (!context.mounted) return; // The editor closed meanwhile.
    if (text != null && (services.clipboard.isEmpty || text != _textBeforeInkCopy)) {
      final html = plain || RichTextController.isOwnClip(text) ? null : await _readHtml();
      if (!context.mounted) return;
      final rich = html == null ? null : textFromHtml(html, tools.textStyle);
      content.pasteText(
        rich ?? RichTextController.pasted(text, tools.textStyle),
        at: _worldAt(screen),
      );
    } else if (content.selection.clipboard.isEmpty) {
      if (context.mounted) showMessage(context, 'Nothing to paste');
    } else if (_worldAt(screen) case final at?) {
      content.selection.paste(at);
    } else {
      content.pasteAtCentre();
    }
  }

  /// The world point under [screen], on the page there (null: the centre).
  Offset? _worldAt(Offset? screen) {
    if (screen == null) return null;
    activateAt?.call(screen);
    return content.viewport.toWorld(screen);
  }

  // ---------------------------------------------------------------------------
  // Inserting

  /// Prepares, stores and places one image; returns the new element, or
  /// null if it failed (the user has been told why).
  Future<SurfaceElement?> insertBytes(
    BuildContext context,
    Uint8List bytes, {
    Offset? screen,
    String? name,
  }) async {
    final data = await _prepare(context, bytes, name);
    if (data == null || !context.mounted) return null;
    final viewport = content.viewport;
    final point = screen ?? viewport.size.center(Offset.zero);
    activateAt?.call(point);
    // The active page (and so the viewport mapping) may have changed.
    final at = content.viewport.toWorld(point);
    final box = ImagePlacement.boxFor(
      data,
      at: at,
      area: content.viewport.visibleWorld,
      page: content.viewport.contentBounds,
    );
    final element = ImagePlacement.insert(
      content.model,
      data,
      box,
      id: clock.newId(),
      now: clock.nowMs(),
    );
    // Selected, the tool kept: tap away and write on (a live selection,
    // as the side button's lasso makes).
    content.selection.select(const [], [element]);
    return element;
  }

  Future<ImageData?> _prepare(BuildContext context, Uint8List bytes, String? name) async {
    try {
      // Big files may need re-encoding, which takes a moment. Only that
      // runs behind Cancel: a cancelled task runs on, so it mustn't store.
      final prepared = bytes.length > (2 << 20)
          ? await runWithProgress(context, 'Adding image', () => ImageImport.prepare(bytes))
          : await ImageImport.prepare(bytes);
      return await ImageImport.store(services.blobs, prepared);
    } on Cancelled {
      return null;
    } on ImageImportException catch (e) {
      debugPrint('Image import failed: $e');
      if (context.mounted) {
        showMessage(
          context,
          name == null ? 'That image can’t be opened' : 'Couldn’t open “$name” as an image',
        );
      }
      return null;
    } on Object catch (e) {
      // Storing it failed (e.g. the disk is full): say so, don't crash.
      debugPrint('Image import failed: $e');
      if (context.mounted) showMessage(context, 'Couldn’t add the image');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Clipboard

  Future<Uint8List?> _clipboardImage() async {
    try {
      final bytes = await _readClipboard();
      return bytes == null || bytes.isEmpty ? null : bytes;
    } on Object catch (e) {
      debugPrint('Clipboard image unavailable: $e');
      return null;
    }
  }

  static Future<String?> _clipboardText() async {
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      return text == null || text.trim().isEmpty ? null : text;
    } on Object catch (e) {
      debugPrint('Clipboard text unavailable: $e');
      return null;
    }
  }

  void _onInkCopied() {
    if (services.clipboard.isEmpty) return;
    unawaited(_clipboardText().then((text) => _textBeforeInkCopy = text));
    unawaited(
      _clipboardImage().then((bytes) => _imageBeforeInkCopy = bytes == null ? null : _hash(bytes)),
    );
  }

  static String _hash(Uint8List bytes) => sha256.convert(bytes).toString();

  /// The clipboard's image, or the first image file copied (desktop).
  static Future<Uint8List?> _systemClipboardImage() async {
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
}
