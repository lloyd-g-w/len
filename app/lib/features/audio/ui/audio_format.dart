/// "0:07", "12:34", "1:02:03".
String formatClock(int ms) {
  final total = (ms < 0 ? 0 : ms) ~/ 1000;
  final h = total ~/ 3600, m = total % 3600 ~/ 60, s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// A length in words, to the minute: "45 s", "12 min", "1 h 17 min", "2 h".
/// Numbers and their units are joined by no-break spaces, so a line never
/// breaks between them.
String formatDuration(int ms) {
  const nb = '\u00A0';
  final seconds = ((ms < 0 ? 0 : ms) / 1000).round();
  if (seconds < 60) return '$seconds${nb}s';
  final minutes = (seconds / 60).round();
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m${nb}min';
  return m == 0 ? '$h${nb}h' : '$h${nb}h $m${nb}min';
}

/// "0.75×", "1×", "1.5×".
String formatRate(double rate) {
  var text = rate.toStringAsFixed(2);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return '$text×';
}

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

/// When a recording was made: "Today, 14:05", "Yesterday, 09:30",
/// "3 Oct, 14:05", "3 Oct 2025, 14:05".
String formatRecordedAt(int epochMs, {DateTime? now}) {
  final at = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final today = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(at.hour)}:${two(at.minute)}';
  final day = DateTime(at.year, at.month, at.day);
  final daysAgo = (DateTime(today.year, today.month, today.day).difference(day).inHours / 24)
      .round(); // DST days have 23 or 25 hours.
  if (daysAgo == 0) return 'Today, $time';
  if (daysAgo == 1) return 'Yesterday, $time';
  final date = '${at.day} ${_months[at.month - 1]}';
  return at.year == today.year ? '$date, $time' : '$date ${at.year}, $time';
}
