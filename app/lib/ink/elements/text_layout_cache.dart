import '../../domain/text/text_data.dart';
import 'text_layout.dart';

/// The layout of the text box being edited, kept between uses: measuring
/// its width and height and splitting it across pages read one layout, so
/// a keystroke lays the box out once (beside the editing field's own).
class TextLayoutCache {
  TextBoxLayout? _layout;
  double _width = 0;

  /// [data] laid out at [width] (unbounded: as wide as its text); the
  /// cache owns it (valid until the next call or [dispose]).
  TextBoxLayout of(TextData data, double width) {
    final cached = _layout;
    if (cached != null && _width == width && cached.data == data) return cached;
    cached?.dispose();
    _width = width;
    return _layout = TextLayout.layout(data, width);
  }

  /// Width [data] needs without wrapping (see [TextLayout.naturalWidth]).
  double naturalWidth(TextData data) => TextLayout.naturalWidthOf(of(data, double.infinity));

  void dispose() {
    _layout?.dispose();
    _layout = null;
  }
}
