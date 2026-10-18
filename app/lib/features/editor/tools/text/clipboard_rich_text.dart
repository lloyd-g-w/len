import '../../../../domain/text/html_text.dart';
import '../../../../domain/text/rtf_text.dart';
import '../../../../domain/text/text_data.dart';
import '../../../../platform/rich_clip.dart';

/// The formatted text of [clip] for a box styled as [box]: from its HTML,
/// else from its RTF (apps that offer no HTML: WordPad, …); null when it
/// has neither, or no text.
TextData? richTextOf(RichClip clip, TextData box) {
  if (clip.html case final html?) {
    if (textFromHtml(html, box) case final text?) return text;
  }
  if (clip.rtf case final rtf?) return textFromRtf(rtf, box);
  return null;
}
