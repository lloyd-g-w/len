/// The preset palettes offered by the colour pickers.
abstract final class ColorSwatches {
  /// Inks and brights in two rows of seven: the dark writing inks (the
  /// pen's default ink, blue and red among them, so its quick colours show
  /// as picked), then light and bright colours. No near-twins: Recent and
  /// Custom cover the rest.
  static const List<int> palette = [
    0xFF1A2233, 0xFF4B5563, 0xFF1E3A8A, 0xFF1C4ED8, 0xFF2F9E44, 0xFFDC2626, 0xFF7048E8, //
    0xFFFFFFFF, 0xFF0EA5E9, 0xFF0CA678, 0xFFFACC15, 0xFFF76707, 0xFFC2255C, 0xFFF783AC, //
  ];

  /// Light, saturated hues that read as highlights at low opacity (no
  /// blacks, greys or white): two rows of five, warm to cool.
  static const List<int> highlighter = [
    0xFFFACC15, 0xFFFB923C, 0xFFF87171, 0xFFF472B6, 0xFFC084FC, //
    0xFF60A5FA, 0xFF22D3EE, 0xFF2DD4BF, 0xFF4ADE80, 0xFFA3E635, //
  ];
}
