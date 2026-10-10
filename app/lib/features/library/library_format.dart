import '../../core/format.dart';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// A short date for library cards: `Just now`, `14:05` (today), `Yesterday`,
/// `Monday` (this week), `3 Oct`, `3 Oct 2024`.
String formatLibraryDate(int epochMs, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final at = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final label = formatEdited(epochMs, now: current);
  if (label == 'Just now') return label;
  // Calendar days in UTC, so daylight-saving changes don't shift them.
  final today = DateTime.utc(current.year, current.month, current.day);
  final days = today.difference(DateTime.utc(at.year, at.month, at.day)).inDays;
  if (days == 0) return label;
  if (days == 1) return 'Yesterday';
  if (days > 1 && days < 7) return _weekdays[at.weekday - 1];
  return label;
}

/// `1 page`, `12 pages`.
String pageCountLabel(int n) => n == 1 ? '1 page' : '$n pages';
