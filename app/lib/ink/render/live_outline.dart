import 'dart:ui';

/// The outline of a live stroke: its frozen part (unchanged since the
/// previous frame, except for appended pieces) and its tail. The tail starts
/// with a round cap inside the frozen part, so the two can be drawn one
/// after the other without a seam.
class LiveOutline {
  LiveOutline(this.frozen, this.tail);

  /// An outline that is all tail.
  LiveOutline.of(Path path) : frozen = null, tail = path;

  final Path? frozen;
  final Path tail;

  /// Both in one path (a copy of the frozen part: cloned, then the tail
  /// appended, a block copy; appending the frozen part to a new path went
  /// verb by verb, 4–5× as long: ~0.65 ms at 60k samples). Ink is filled in one
  /// go: two paths filled one after the other darken the antialiased
  /// edge pixels where they overlap (the tail's cap meets the sides of the
  /// frozen part there), which the committed stroke, one path, does not.
  late final Path combined = switch (frozen) {
    null => tail,
    final f => Path.from(f)..addPath(tail, Offset.zero),
  };
}
