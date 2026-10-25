/// User-selectable app and input preferences (stored locally, not synced).
library;

/// Light/dark appearance.
enum ThemePreference {
  system,
  light,
  dark;

  static ThemePreference parse(String? value) =>
      values.firstWhere((v) => v.name == value, orElse: () => system);
}

/// What the S Pen side button (or a stylus barrel button) does while held.
enum PenButtonAction {
  eraser,
  lasso,
  none;

  static PenButtonAction parse(String? value) =>
      values.firstWhere((v) => v.name == value, orElse: () => eraser);
}

/// Where the editor's tool palette sits.
enum ToolbarPlacement {
  /// Docked: inside the top bar when it fits there on one row, else a row
  /// attached under it; at the bottom on phones (panes under 600 dp).
  docked,

  /// Free-floating; dragged anywhere by its grip.
  floating;

  static ToolbarPlacement parse(String? value) =>
      values.firstWhere((v) => v.name == value, orElse: () => docked);
}

/// How the library lays out notebooks.
enum LibraryLayout {
  grid,
  list;

  static LibraryLayout parse(String? value) =>
      values.firstWhere((v) => v.name == value, orElse: () => grid);
}

/// Library sort order.
enum LibrarySort {
  edited,
  created,
  name;

  static LibrarySort parse(String? value) =>
      values.firstWhere((v) => v.name == value, orElse: () => edited);
}

/// A tool whose toolbar strip shows quick colours and sizes.
enum SlotTool {
  pen,
  highlighter,
  laser;

  /// The name shown in Settings.
  String get label => switch (this) {
    pen => 'Pen',
    highlighter => 'Highlighter',
    laser => 'Laser pointer',
  };
}

/// How many quick colour and size slots a tool's strip shows
/// ([min]..[max] each; [defaults] three and three).
class SlotCounts {
  const SlotCounts(this.colors, this.sizes)
    : assert(colors >= min && colors <= max && sizes >= min && sizes <= max);

  /// Fewest and most slots in each row.
  static const int min = 1;
  static const int max = 5;

  static const SlotCounts defaults = SlotCounts(3, 3);

  final int colors;
  final int sizes;

  /// A copy with the given counts replaced (each clamped to [min]..[max]).
  SlotCounts copyWith({int? colors, int? sizes}) =>
      SlotCounts((colors ?? this.colors).clamp(min, max), (sizes ?? this.sizes).clamp(min, max));

  /// Parses "colours,sizes" ([toString]); [defaults] when missing or invalid.
  static SlotCounts parse(String? value) {
    final parts = value?.split(',');
    if (parts == null || parts.length != 2) return defaults;
    final colors = int.tryParse(parts[0]), sizes = int.tryParse(parts[1]);
    bool valid(int? n) => n != null && n >= min && n <= max;
    return valid(colors) && valid(sizes) ? SlotCounts(colors!, sizes!) : defaults;
  }

  @override
  String toString() => '$colors,$sizes';

  @override
  bool operator ==(Object other) =>
      other is SlotCounts && other.colors == colors && other.sizes == sizes;

  @override
  int get hashCode => Object.hash(colors, sizes);
}
