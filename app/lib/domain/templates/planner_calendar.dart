import 'package:intl/date_symbol_data_local.dart' as intl_data;
import 'package:intl/intl.dart';

/// The day planner weeks start on.
enum WeekStart {
  monday(DateTime.monday),
  sunday(DateTime.sunday);

  const WeekStart(this.weekday);

  /// The [DateTime.weekday] of the first day of a week.
  final int weekday;

  /// Parses a stored name; null when unknown.
  static WeekStart? tryParse(Object? value) {
    for (final w in values) {
      if (w.name == value) return w;
    }
    return null;
  }
}

/// The languages planner pages can be printed in, in the order offered:
/// month and day names and date formats come from `intl` (CLDR). Every one is covered by the
/// bundled Inter font (Latin, Greek, Cyrillic), so it also exports to PDF.
enum PlannerLanguage {
  enGB('en-GB', 'English (UK)'),
  enUS('en-US', 'English (US)'),
  cs('cs', 'Čeština'),
  da('da', 'Dansk'),
  de('de', 'Deutsch'),
  es('es', 'Español'),
  fr('fr', 'Français'),
  it('it', 'Italiano'),
  nl('nl', 'Nederlands'),
  nb('nb', 'Norsk bokmål'),
  pl('pl', 'Polski'),
  ptBR('pt-BR', 'Português (Brasil)'),
  ptPT('pt-PT', 'Português (Portugal)'),
  fi('fi', 'Suomi'),
  sv('sv', 'Svenska'),
  tr('tr', 'Türkçe'),
  el('el', 'Ελληνικά'),
  ru('ru', 'Русский'),
  uk('uk', 'Українська');

  const PlannerLanguage(this.tag, this.nativeName);

  /// BCP 47 tag, as stored (`paperData.locale`).
  final String tag;

  /// The language's name in itself, for pickers.
  final String nativeName;

  /// The `intl` locale name (`en_GB`).
  String get intlLocale => tag.replaceAll('-', '_');

  String get languageCode => tag.split('-').first;

  /// Parses a stored tag strictly; null when it is not in the list.
  static PlannerLanguage? tryParse(Object? value) {
    for (final l in values) {
      if (l.tag == value) return l;
    }
    return null;
  }

  /// The language for a device locale: the exact match, else the first
  /// one of the same language, else English (UK).
  static PlannerLanguage forLocale(String languageCode, [String? countryCode]) {
    final exact = '$languageCode-${countryCode ?? ''}';
    for (final l in values) {
      if (l.tag == exact) return l;
    }
    for (final l in values) {
      if (l.languageCode == languageCode) return l;
    }
    return enGB;
  }

  /// The week start customary for this language and region (CLDR).
  WeekStart get customaryWeekStart {
    ensureDateSymbols();
    final first = DateFormat('d', intlLocale).dateSymbols.FIRSTDAYOFWEEK;
    return first == 6 ? WeekStart.sunday : WeekStart.monday;
  }
}

/// The flavour of a planner: the day its weeks start on and the language
/// it is printed in. Part of a planner page's `Paper`.
class PlannerCalendar {
  const PlannerCalendar({this.weekStart = WeekStart.monday, this.language = PlannerLanguage.enGB});

  /// The calendar customary for [language] (its CLDR week start).
  PlannerCalendar.of(PlannerLanguage language)
    : this(weekStart: language.customaryWeekStart, language: language);

  /// The calendar for a device locale (see [PlannerLanguage.forLocale]).
  factory PlannerCalendar.forLocale(String languageCode, [String? countryCode]) =>
      PlannerCalendar.of(PlannerLanguage.forLocale(languageCode, countryCode));

  /// English (UK), weeks from Monday.
  static const PlannerCalendar standard = PlannerCalendar();

  final WeekStart weekStart;
  final PlannerLanguage language;

  PlannerCalendar copyWith({WeekStart? weekStart, PlannerLanguage? language}) =>
      PlannerCalendar(weekStart: weekStart ?? this.weekStart, language: language ?? this.language);

  @override
  bool operator ==(Object other) =>
      other is PlannerCalendar && other.weekStart == weekStart && other.language == language;

  @override
  int get hashCode => Object.hash(weekStart, language);

  @override
  String toString() => 'PlannerCalendar(${weekStart.name}, ${language.tag})';
}

bool _dateSymbolsReady = false;

/// Loads `intl`'s bundled date symbols and patterns for every locale. The
/// data is compiled in, so this completes synchronously (the returned
/// future is only a formality); called before any planner label is
/// formatted.
void ensureDateSymbols() {
  if (_dateSymbolsReady) return;
  // Synchronous for the local data set; the future is already complete.
  intl_data.initializeDateFormatting();
  _dateSymbolsReady = true;
}
