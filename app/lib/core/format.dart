/// Human-friendly "last edited" label, e.g. `Just now`, `14:05`, `3 Oct`,
/// `3 Oct 2024`.
String formatEdited(int epochMs, {DateTime? now}) {
  final at = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final current = now ?? DateTime.now();
  final diff = current.difference(at);
  if (diff.inMinutes < 1 && !diff.isNegative) return 'Just now';
  String two(int n) => n.toString().padLeft(2, '0');
  final sameDay = at.year == current.year && at.month == current.month && at.day == current.day;
  if (sameDay) return '${two(at.hour)}:${two(at.minute)}';
  final date = '${at.day} ${_months[at.month - 1]}';
  return at.year == current.year ? date : '$date ${at.year}';
}

/// A day for people, always with its year: `13 Oct 2026`.
String formatDay(DateTime at) => '${at.day} ${_months[at.month - 1]} ${at.year}';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A file size for people, e.g. `512 bytes`, `3.4 MB`, `1.2 GB` (powers of
/// 1024, as `LEN_BLOB_MAX_BYTES` = 200 MiB shows as `200 MB`).
String formatBytes(int bytes) {
  const units = ['KB', 'MB', 'GB', 'TB'];
  if (bytes < 1024) return '$bytes bytes';
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || value == value.roundToDouble() ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}
