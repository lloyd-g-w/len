import 'version_repository.dart';

/// Which versions a notebook keeps (docs/ARCHITECTURE.md, "Version
/// history"): every automatic version of the last [keepAllFor], then the
/// newest per hour for a week, per day for a month and per week after
/// that, within a budget of [maxVersions] and [maxBytes]; named versions
/// until deleted.
///
/// Buckets are aligned to the epoch (UTC), so every device keeps the same
/// versions, and the versions a later clock keeps are among those an
/// earlier one kept (a day's newest is its last hour's newest): devices
/// thinning at different times never remove more than the latest would.
abstract final class VersionPolicy {
  static const keepAllFor = Duration(days: 1);
  static const hourlyFor = Duration(days: 7);
  static const dailyFor = Duration(days: 30);

  /// The most automatic versions a notebook keeps.
  static const maxVersions = 200;

  /// The most bytes of packs its automatic versions may have added.
  static const maxBytes = 64 * 1024 * 1024;

  static const _hour = 3600 * 1000;
  static const _day = 24 * _hour;
  static const _week = 7 * _day;

  /// The ids among [versions] to remove at [nowMs].
  static Set<String> toRemove(
    List<VersionInfo> versions,
    int nowMs, {
    int maxVersions = maxVersions,
    int maxBytes = maxBytes,
  }) {
    final thinned = [
      for (final v in versions)
        if (v.kind.thinned) v,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // Newest first.
    final remove = <String>{};
    // Buckets (size, index) holding a newer version: a version goes when
    // its own bucket does. Buckets nest (hours in days in weeks), so one
    // newer version keeps covering it as it ages into larger buckets.
    final covered = <(int, int)>{};
    for (final v in thinned) {
      final age = nowMs - v.createdAt;
      if (age >= keepAllFor.inMilliseconds) {
        final bucket = age < hourlyFor.inMilliseconds
            ? _hour
            : age < dailyFor.inMilliseconds
            ? _day
            : _week;
        if (covered.contains((bucket, v.createdAt ~/ bucket))) remove.add(v.id);
      }
      for (final size in const [_hour, _day, _week]) {
        covered.add((size, v.createdAt ~/ size));
      }
    }
    var count = 0, bytes = 0;
    for (final v in thinned) {
      if (remove.contains(v.id)) continue;
      count++;
      bytes += v.size;
      if (count > maxVersions || (bytes > maxBytes && count > 1)) remove.add(v.id);
    }
    return remove;
  }
}
