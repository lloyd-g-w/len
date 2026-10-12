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
