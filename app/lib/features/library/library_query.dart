import '../../domain/folder.dart';
import '../../domain/notebook.dart';
import '../../domain/preferences.dart';

/// Pure filtering and sorting rules of the library (unit-tested).
abstract final class LibraryQuery {
  /// Whether [text] matches a search [query]: every whitespace-separated
  /// term occurs in it, case-insensitively. An empty query matches all.
  static bool matches(String text, String query) => matcher(query)(text);

  /// A predicate equivalent to [matches] for a fixed [query], parsing the
  /// query once (for filtering many items).
  static bool Function(String text) matcher(String query) {
    final terms = query.toLowerCase().split(_whitespace).where((t) => t.isNotEmpty).toList();
    if (terms.isEmpty) return (_) => true;
    return (text) {
      final haystack = text.toLowerCase();
      return terms.every(haystack.contains);
    };
  }

  static final RegExp _whitespace = RegExp(r'\s+');

  /// [notebooks] sorted by [sort]: newest first for dates, A→Z for names.
  static List<Notebook> sorted(Iterable<Notebook> notebooks, LibrarySort sort) {
    int byName(Notebook a, Notebook b) {
      final c = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return c != 0 ? c : a.id.compareTo(b.id);
    }

    final list = notebooks.toList();
    list.sort(switch (sort) {
      LibrarySort.edited => (a, b) {
        final c = b.editedAt.compareTo(a.editedAt);
        return c != 0 ? c : byName(a, b);
      },
      LibrarySort.created => (a, b) {
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : byName(a, b);
      },
      LibrarySort.name => byName,
    });
    return list;
  }

  /// The folder a notebook is displayed in: its folder if that still
  /// exists, otherwise the root (null).
  static String? folderOf(Notebook notebook, Map<String, Folder> folders) {
    final id = notebook.folderId;
    return id != null && folders.containsKey(id) ? id : null;
  }
}
