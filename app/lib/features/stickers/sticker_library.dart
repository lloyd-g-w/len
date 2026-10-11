import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/sticker_repository.dart';
import '../../domain/stickers/sticker.dart';
import '../../sync/sync_controller.dart';
import 'builtin_stickers.dart';

/// The stickers the panel offers: the user's (synced) and the built-in
/// ones, by category. Follows changes brought by sync.
class StickerLibrary extends ChangeNotifier {
  StickerLibrary(this.repository, {SyncController? sync}) {
    _remote = sync?.remoteChanges.listen((c) {
      if (c.stickers) reload();
    });
    reload();
  }

  final StickerRepository repository;
  StreamSubscription<Object?>? _remote;

  List<Sticker> _mine = const [];

  /// The user's stickers, newest first.
  List<Sticker> get mine => _mine;

  /// Every sticker: the user's first, then the built-in ones.
  List<Sticker> get all => [..._mine, ...BuiltinStickers.all];

  /// Categories with stickers: the user's (in order of their newest
  /// sticker), then the built-in ones.
  List<String> get categories =>
      {for (final s in _mine) s.category, ...BuiltinStickers.categories}.toList();

  /// Categories of the user's own stickers, for filing new ones.
  List<String> get userCategories =>
      {StickerRepository.defaultCategory, for (final s in _mine) s.category}.toList();

  /// Stickers in [category] (all if null).
  List<Sticker> inCategory(String? category) => category == null
      ? all
      : [
          for (final s in all)
            if (s.category == category) s,
        ];

  void reload() {
    _mine = repository.list();
    notifyListeners();
  }

  Sticker save({required String name, required String category, required StickerContent content}) {
    final sticker = repository.create(name: name, category: category, content: content);
    reload();
    return sticker;
  }

  void rename(Sticker sticker, String name) {
    repository.update(sticker.id, name: name);
    reload();
  }

  void move(Sticker sticker, String category) {
    repository.update(sticker.id, category: category);
    reload();
  }

  void delete(Sticker sticker) {
    repository.delete(sticker.id);
    reload();
  }

  void restore(Sticker sticker) {
    repository.restore(sticker.id);
    reload();
  }

  @override
  void dispose() {
    unawaited(_remote?.cancel());
    super.dispose();
  }
}
