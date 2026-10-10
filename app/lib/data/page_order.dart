/// Fractional sort keys for ordered pages.
///
/// Moving or inserting a page only rewrites that page's key (the midpoint of
/// its new neighbours), so concurrent reorders on two devices rarely touch
/// the same records. When neighbouring keys get too close to split, the
/// caller renumbers the whole list.
abstract final class PageOrder {
  /// Smallest gap that is still split; below it [between] returns null.
  static const double minGap = 1e-9;

  /// A key strictly between [before] and [after] (either may be null for
  /// "start" / "end"), or null if the gap is exhausted.
  static double? between(double? before, double? after) {
    if (before == null && after == null) return 1;
    if (before == null) return after! - 1;
    if (after == null) return before + 1;
    if (after - before < minGap) return null;
    final mid = before + (after - before) / 2;
    return mid > before && mid < after ? mid : null;
  }

  /// [count] increasing keys strictly between [before] and [after], or null
  /// if they do not fit.
  static List<double>? spread(double? before, double? after, int count) {
    if (count == 0) return const [];
    if (after == null) {
      final start = before ?? 0;
      return [for (var i = 1; i <= count; i++) start + i];
    }
    final start = before ?? after - count - 1;
    final step = (after - start) / (count + 1);
    if (step < minGap) return null;
    final keys = [for (var i = 1; i <= count; i++) start + step * i];
    for (var i = 0; i < keys.length; i++) {
      final lower = i == 0 ? start : keys[i - 1];
      if (!(keys[i] > lower && keys[i] < after)) return null;
    }
    return keys;
  }

  /// The key for moving the item at [from] to index [to] of [keys] (the
  /// current ascending keys), or null if the list must be renumbered.
  static double? forMove(List<double> keys, int from, int to) {
    final rest = [...keys]..removeAt(from);
    final before = to > 0 ? rest[to - 1] : null;
    final after = to < rest.length ? rest[to] : null;
    return between(before, after);
  }
}
