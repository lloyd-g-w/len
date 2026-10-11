import '../../domain/folder.dart';
import '../../domain/notebook.dart';
import '../../domain/preferences.dart';

/// A library search split into its free text and its `tag:` terms.
typedef ParsedQuery = ({String text, List<String> tags});

/// Pure filtering and sorting rules of the library (unit-tested).
abstract final class LibraryQuery {
  /// Splits [query] into `tag:` terms (`tag:work`, `tag:"school work"`;
  /// lowercased, without the prefix) and the remaining text.
  static ParsedQuery parse(String query) {
    final tags = <String>[];
    final text = query.replaceAllMapped(_tagTerm, (m) {
      final name = (m[1] ?? m[2] ?? '').trim().toLowerCase();
      if (name.isNotEmpty) tags.add(name);
      return ' ';
    });
    return (text: text.trim().replaceAll(_whitespace, ' '), tags: tags);
  }

  static final RegExp _tagTerm = RegExp(
    r'(?:^|(?<=\s))tag:(?:"([^"]*)"?|(\S*))',
    caseSensitive: false,
  );

  /// Whether a notebook with tags named [names] matches every `tag:` term
  /// in [terms]: a term matches a tag whose name starts with it, ignoring
  /// case (so `tag:wo` finds "Work" while typing).
  static bool hasTags(Iterable<String> names, List<String> terms) {
    if (terms.isEmpty) return true;
    final lower = [for (final n in names) n.toLowerCase()];
    return terms.every((t) => lower.any((n) => n.startsWith(t)));
  }

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
