import '../../core/format.dart';
import '../../domain/notebook_version.dart';

/// How versions are named in the history (sentence case, no full stops).
abstract final class VersionLabels {
  /// The time of day it was made: `14:02`.
  static String time(NotebookVersion v) {
    final at = DateTime.fromMillisecondsSinceEpoch(v.createdAt);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}';
  }

  /// The day heading a group of versions: `Today`, `Yesterday`, `13 Oct 2026`.
  static String day(int epochMs, {required DateTime now}) {
    final at = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(at.year, at.month, at.day);
    final days = today.difference(that).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return formatDay(at);
  }

  /// The day and time, for titles: `13 Oct 2026, 14:02`.
  static String when(NotebookVersion v) =>
      '${formatDay(DateTime.fromMillisecondsSinceEpoch(v.createdAt))}, ${time(v)}';

  /// What the row says first: its name, or what made it.
  static String title(NotebookVersion v) => switch (v) {
    NotebookVersion(:final name?) => name,
    NotebookVersion(kind: VersionKind.restore) => 'Before restoring',
    NotebookVersion(kind: VersionKind.named) => 'Saved version',
    _ => 'Edited',
  };

  /// Which device made it: `This device`, `Android`.
  static String device(NotebookVersion v, {required String thisDevice}) => v.deviceId == thisDevice
      ? 'This device'
      : v.deviceName.isEmpty
      ? 'Another device'
      : v.deviceName;

  /// What changed since the version before ([first]: there was none).
  static String summary(NotebookVersion v, {bool first = false}) {
    final s = v.summary;
    if (first) {
      final parts = [if (v.canvas == null) _count(s.pages, 'page'), _count(s.strokes, 'stroke')];
      return parts.join(', ');
    }
    final parts = [
      if (s.pagesAdded > 0) '${_count(s.pagesAdded, 'page')} added',
      if (s.pagesRemoved > 0) '${_count(s.pagesRemoved, 'page')} removed',
      if (s.pagesEdited > 0) '${_count(s.pagesEdited, 'page')} edited',
      if (s.strokesAdded > 0) '${_count(s.strokesAdded, 'stroke')} added',
      if (s.strokesRemoved > 0) '${_count(s.strokesRemoved, 'stroke')} erased',
    ];
    if (parts.isEmpty) return v.canvas == null ? 'No changes to pages' : 'No ink added or erased';
    final text = parts.join(', ');
    return text[0].toUpperCase() + text.substring(1);
  }

  static String _count(int n, String noun) => n == 1 ? '1 $noun' : '$n ${noun}s';
}
