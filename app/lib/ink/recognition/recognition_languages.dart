import 'dart:ui';

/// A handwriting recognition language: a BCP 47 tag as ML Kit Digital Ink
/// names its models, and a display name.
class RecognitionLanguage {
  const RecognitionLanguage(this.tag, this.name);

  final String tag;
  final String name;

  /// The language subtag (`en` of `en-US`).
  String get language => tag.split('-').first;

  /// The region subtag (`US` of `en-US`), if any.
  String? get region {
    final parts = tag.split('-');
    final last = parts.length > 1 ? parts.last : null;
    return last != null && last.length == 2 && last.toUpperCase() == last ? last : null;
  }
}

/// The languages offered for recognition (a subset of ML Kit's models,
/// the Latin, Cyrillic, Greek and major Asian scripts).
abstract final class RecognitionLanguages {
  static const all = [
    RecognitionLanguage('en-US', 'English (US)'),
    RecognitionLanguage('en-GB', 'English (UK)'),
    RecognitionLanguage('de-DE', 'Deutsch'),
    RecognitionLanguage('fr-FR', 'Français'),
    RecognitionLanguage('es-ES', 'Español'),
    RecognitionLanguage('it-IT', 'Italiano'),
    RecognitionLanguage('pt-BR', 'Português (Brasil)'),
    RecognitionLanguage('pt-PT', 'Português (Portugal)'),
    RecognitionLanguage('nl-NL', 'Nederlands'),
    RecognitionLanguage('sv-SE', 'Svenska'),
    RecognitionLanguage('da-DK', 'Dansk'),
    RecognitionLanguage('fi-FI', 'Suomi'),
    RecognitionLanguage('pl-PL', 'Polski'),
    RecognitionLanguage('cs-CZ', 'Čeština'),
    RecognitionLanguage('hu-HU', 'Magyar'),
    RecognitionLanguage('tr-TR', 'Türkçe'),
    RecognitionLanguage('el-GR', 'Ελληνικά'),
    RecognitionLanguage('ru-RU', 'Русский'),
    RecognitionLanguage('uk-UA', 'Українська'),
    RecognitionLanguage('hi-IN', 'हिन्दी'),
    RecognitionLanguage('ja-JP', '日本語'),
    RecognitionLanguage('ko-KR', '한국어'),
    RecognitionLanguage('zh-Hani-CN', '中文 (简体)'),
  ];

  static const fallback = 'en-US';

  /// The language with [tag], if offered.
  static RecognitionLanguage? byTag(String tag) {
    for (final l in all) {
      if (l.tag == tag) return l;
    }
    return null;
  }

  /// The best language for the device [locales] (in preference order):
  /// the same language and region, else the same language, else English.
  static String forLocales(List<Locale> locales) {
    for (final locale in locales) {
      final region = locale.countryCode;
      final sameLanguage = all.where((l) => l.language == locale.languageCode).toList();
      if (sameLanguage.isEmpty) continue;
      for (final l in sameLanguage) {
        if (region != null && l.region == region) return l.tag;
      }
      return sameLanguage.first.tag;
    }
    return fallback;
  }
}
