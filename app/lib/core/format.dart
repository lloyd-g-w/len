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
  const months = [
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
  final date = '${at.day} ${months[at.month - 1]}';
  return at.year == current.year ? date : '$date ${at.year}';
}
