import 'notebook.dart';
import 'paper.dart';

/// What a new notebook starts as: notebook or canvas, template (a built-in
/// style and its look; a planner's calendar), paper colour, page size and
/// orientation, and cover colour. A [NotebookStyle] names one; the
/// new-notebook sheet also remembers the last one used.
///
/// Stored and synced as [toJson]: `{kind, paper, look, paperColor, format,
/// orientation, coverColor}`, and for a planner `weekStart` and `locale`.
class NotebookChoice {
  const NotebookChoice({
    this.kind = NotebookKind.paged,
    this.paper = PaperStyle.collegeRuled,
    this.look = PaperLook.standard,
    this.paperColor = PaperColor.white,
    this.format = PageFormat.a4,
    this.orientation = PageOrientation.portrait,
    this.calendar,
    required this.coverColor,
  }) : assert(paper != PaperStyle.image, 'a user template is no style');

  /// The choice made of [template] (the page's look and colour, its size
  /// unless it has its own); null for a user's image template: a style
  /// names only built-in templates.
  static NotebookChoice? of({
    required NotebookKind kind,
    required PageTemplate template,
    required int coverColor,
  }) {
    if (template.style == PaperStyle.image) return null;
    return NotebookChoice(
      kind: kind,
      paper: template.style,
      look: template.paper.look,
      paperColor: template.color,
      format: template.format,
      orientation: template.orientation,
      calendar: template.style.isPlanner
          ? template.paper.calendar ?? PlannerCalendar.standard
          : null,
      coverColor: coverColor,
    );
  }

  final NotebookKind kind;

  /// A built-in template (never [PaperStyle.image]); planners are
  /// generated from the day the notebook is made.
  final PaperStyle paper;
  final PaperLook look;
  final PaperColor paperColor;
  final PageFormat format;
  final PageOrientation orientation;

  /// A planner's week start and language; ignored for other templates.
  final PlannerCalendar? calendar;

  /// The calendar planners are made in ([calendar], else the standard
  /// one); null for other templates.
  PlannerCalendar? get plannerCalendar =>
      paper.isPlanner ? calendar ?? PlannerCalendar.standard : null;

  /// Opaque ARGB.
  final int coverColor;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'paper': paper.name,
    'look': look.toJson(),
    'paperColor': paperColor.name,
    'format': format.name,
    'orientation': orientation.name,
    'coverColor': coverColor,
    if (plannerCalendar case final c?) ...{'weekStart': c.weekStart.name, 'locale': c.language.tag},
  };

  /// Parses [toJson] output strictly: null when a field is missing (a
  /// planner's calendar included), has the wrong type or an unknown value
  /// (or names an image template).
  static NotebookChoice? fromJson(Map<String, Object?> json) {
    T? named<T extends Enum>(String key, List<T> values) {
      final value = json[key];
      return value is String ? values.asNameMap()[value] : null;
    }

    final kind = named('kind', NotebookKind.values);
    final paper = named('paper', PaperStyle.values);
    final look = PaperLook.fromJson(json['look']);
    final color = json['paperColor'];
    final paperColor = color is String ? PaperColor.tryParse(color) : null;
    final format = named('format', PageFormat.values);
    final orientation = named('orientation', PageOrientation.values);
    final cover = json['coverColor'];
    if (kind == null ||
        paper == null ||
        paper == PaperStyle.image ||
        look == null ||
        paperColor == null ||
        format == null ||
        orientation == null ||
        cover is! int) {
      return null;
    }
    PlannerCalendar? calendar;
    if (paper.isPlanner) {
      final weekStart = WeekStart.tryParse(json['weekStart']);
      final language = PlannerLanguage.tryParse(json['locale']);
      if (weekStart == null || language == null) return null;
      calendar = PlannerCalendar(weekStart: weekStart, language: language);
    }
    return NotebookChoice(
      kind: kind,
      paper: paper,
      look: look,
      paperColor: paperColor,
      format: format,
      orientation: orientation,
      calendar: calendar,
      coverColor: cover,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NotebookChoice &&
      other.kind == kind &&
      other.paper == paper &&
      other.look == look &&
      other.paperColor == paperColor &&
      other.format == format &&
      other.orientation == orientation &&
      other.plannerCalendar == plannerCalendar &&
      other.coverColor == coverColor;

  @override
  int get hashCode =>
      Object.hash(kind, paper, look, paperColor, format, orientation, plannerCalendar, coverColor);
}

/// A notebook style the user saved ([choice] under a [name]); the one
/// marked [isDefault] is what new notebooks start as.
class NotebookStyle {
  const NotebookStyle({
    required this.id,
    required this.name,
    required this.choice,
    this.isDefault = false,
    required this.createdAt,
  });

  final String id;
  final String name;
  final NotebookChoice choice;
  final bool isDefault;

  /// Milliseconds since epoch.
  final int createdAt;
}
