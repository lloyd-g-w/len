/// What an export had to leave out or simplify, to tell the user at the
/// end ("Saved “Lecture.pdf” · 2 images couldn't be included") instead of
/// dropping it silently.
class ExportReport {
  /// PDF pages under the ink whose file isn't on this device (left out).
  int missingBackgrounds = 0;

  /// Images that couldn't be read or embedded (left out).
  int missingImages = 0;

  /// PDF pages that could only be included as pictures (their text and
  /// links aren't selectable).
  int rasterizedPages = 0;

  bool get isEmpty => missingBackgrounds == 0 && missingImages == 0 && rasterizedPages == 0;

  /// "2 images couldn't be included", several joined with "; ", or null
  /// when nothing was lost.
  String? get summary {
    String n(int count, String one, String many) => count == 1 ? '1 $one' : '$count $many';
    final parts = [
      if (missingBackgrounds > 0)
        '${n(missingBackgrounds, 'PDF page', 'PDF pages')} not on this device '
            '${missingBackgrounds == 1 ? 'was' : 'were'} left out',
      if (missingImages > 0) '${n(missingImages, 'image', 'images')} couldn’t be included',
      if (rasterizedPages > 0)
        '${n(rasterizedPages, 'PDF page', 'PDF pages')} '
            '${rasterizedPages == 1 ? 'was' : 'were'} included as a picture',
    ];
    return parts.isEmpty ? null : parts.join('; ');
  }
}
