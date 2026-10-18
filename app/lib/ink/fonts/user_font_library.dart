import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/blob_store.dart';
import '../../data/font_repository.dart';
import '../../domain/text/font_file.dart';
import '../../domain/text/text_font.dart';
import '../../domain/text/user_font.dart';
import '../../sync/remote_changes.dart';
import 'text_fonts.dart';

/// The fonts the user imported for text boxes: importing and removing
/// them, and loading each into the engine ([TextFonts]) once its file is
/// on the device (fetched through sync when it is not), at launch and
/// whenever sync brings a change.
class UserFontLibrary extends ChangeNotifier {
  UserFontLibrary({
    required this.repository,
    required this.blobs,
    required this.fetch,
    Stream<RemoteChanges>? remoteChanges,
  }) {
    _changes = remoteChanges?.listen((c) {
      if (c.fonts) unawaited(refresh());
    });
  }

  final FontRepository repository;
  final BlobStore blobs;
  /// Fetches a blob through sync (see `SyncController.fetchBlob`).
  final Future<bool> Function(String sha) fetch;
  StreamSubscription<RemoteChanges>? _changes;
  List<UserFont> _fonts = const [];

  /// The imported fonts, by name.
  List<UserFont> get fonts => _fonts;

  /// Reads the library and loads its fonts; also what a change from sync
  /// runs. Completes when every font that can be had is loaded.
  Future<void> refresh() async {
    _fonts = repository.list();
    TextFonts.setLibrary(_fonts);
    notifyListeners();
    await Future.wait([for (final f in _fonts) _ensureLoaded(f)]);
  }

  Future<void> _ensureLoaded(UserFont font) async {
    if (TextFonts.isLoaded(font.id)) return;
    final bytes = await bytesOf(font);
    if (bytes != null) await TextFonts.load(font.id, bytes);
  }

  /// The file of [font], fetched through sync if it is not here yet; null
  /// if it can't be had (offline, not uploaded yet).
  Future<Uint8List?> bytesOf(UserFont font) async {
    final here = await blobs.read(font.blob);
    if (here != null) return here;
    try {
      return await fetch(font.blob) ? await blobs.read(font.blob) : null;
    } on Object catch (e) {
      debugPrint('Font ${font.name} could not be fetched: $e');
      return null;
    }
  }

  /// The file of the user font [font] is (null: bundled, not in the
  /// library, or not to be had).
  Future<Uint8List?> fileOf(TextFont font) async {
    final user = font.isUser ? repository.get(font.name) : null;
    return user == null ? null : bytesOf(user);
  }

  /// Imports the font file [bytes]: stored as a blob, added to the library
  /// under the name its name table gives, and loaded. The same file again
  /// gives the font already here. Throws [FormatException] if [bytes] is
  /// not a TrueType / OpenType font, or the engine can't load it.
  Future<UserFont> import(Uint8List bytes) async {
    final info = FontFileInfo.read(bytes);
    if (info == null) throw const FormatException('Not a TrueType or OpenType font');
    final mime = info.outlines == FontOutlines.cff ? 'font/otf' : 'font/ttf';
    final sha = await blobs.putBytes(bytes, mime: mime);
    if (!await TextFonts.load(TextFont.userIdOf(sha), bytes)) {
      throw const FormatException('The font could not be loaded');
    }
    final font = repository.add(name: info.displayName, blob: sha);
    await refresh();
    return font;
  }

  /// Removes [font]: text using it is shown in the default font (until it
  /// is imported again, [restore]).
  Future<void> remove(UserFont font) async {
    repository.remove(font.id);
    await refresh();
  }

  /// Undoes [remove].
  Future<void> restore(UserFont font) async {
    repository.add(name: font.name, blob: font.blob);
    await refresh();
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }
}
