/// The preset palettes offered by the colour pickers.
abstract final class ColorSwatches {
  /// Inks and brights, shown as a 10-column grid: two rows of five-colour
  /// families.
  static const List<int> palette = [
    0xFF000000, 0xFF1F2937, 0xFF4B5563, 0xFF9CA3AF, 0xFFFFFFFF, //
    0xFF1E3A8A, 0xFF1C7ED6, 0xFF0EA5E9, 0xFF0CA678, 0xFF2F9E44, //
    0xFF7F1D1D, 0xFFE03131, 0xFFF76707, 0xFFF59F00, 0xFFFACC15, //
    0xFF7048E8, 0xFFC2255C, 0xFFF783AC, 0xFF69DB7C, 0xFF74C0FC, //
  ];

  /// Light, saturated hues that read as highlights at low opacity (no
  /// blacks, greys or white): one row, warm to cool.
  static const List<int> highlighter = [
    0xFFFACC15, 0xFFFB923C, 0xFFF87171, 0xFFF472B6, 0xFFC084FC, //
    0xFF60A5FA, 0xFF22D3EE, 0xFF2DD4BF, 0xFF4ADE80, 0xFFA3E635, //
  ];
}
