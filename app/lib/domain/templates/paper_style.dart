/// How the template gallery groups templates.
enum TemplateCategory {
  basic('Basic'),
  writing('Writing'),
  planners('Planners'),
  paper('Paper'),

  /// Templates the user imported (images, PDF pages, saved pages).
  mine('My templates');

  const TemplateCategory(this.label);

  final String label;
}

/// The period one page of a date-aware planner template covers.
enum PlannerPeriod { day, week, month }

/// A built-in background pattern ("template") drawn behind ink, or
/// [image] for a user's own template.
///
/// The registry of built-in templates: stored and synced by [name]; the
/// geometry of each is built by `PaperPattern.of`.
enum PaperStyle {
  blank('Blank', 0, TemplateCategory.basic, canvas: true),
  dotted('Dotted', 32, TemplateCategory.basic, canvas: true),

  /// Narrow ruled (6.35 mm).
  narrowRuled('Narrow ruled', 24, TemplateCategory.writing, canvas: true, keywords: 'lined'),

  /// College ruled (7.1 mm).
  collegeRuled('College ruled', 27, TemplateCategory.writing, canvas: true, keywords: 'lined'),

  /// Wide ruled (8.5 mm).
  wideRuled('Wide ruled', 32, TemplateCategory.writing, canvas: true, keywords: 'lined'),
  cornell('Cornell notes', 27, TemplateCategory.writing, keywords: 'study lecture cue summary'),
  todo('To-do list', 32, TemplateCategory.writing, keywords: 'checklist tasks checkbox'),
  meeting('Meeting notes', 27, TemplateCategory.writing, keywords: 'agenda attendees actions'),
  dailyPlanner(
    'Daily planner',
    27,
    TemplateCategory.planners,
    period: PlannerPeriod.day,
    keywords: 'day schedule agenda calendar',
  ),
  weeklyPlanner(
    'Weekly planner',
    27,
    TemplateCategory.planners,
    period: PlannerPeriod.week,
    keywords: 'week agenda calendar',
  ),
  monthlyCalendar(
    'Monthly calendar',
    27,
    TemplateCategory.planners,
    period: PlannerPeriod.month,
    keywords: 'month calendar planner',
  ),
  gridSmall('Small grid', 19, TemplateCategory.paper, canvas: true, keywords: 'squared'),

  /// Large grid (8.5 mm).
  gridLarge('Large grid', 32, TemplateCategory.paper, canvas: true, keywords: 'squared'),

  /// Millimetre graph paper: 1 mm, 5 mm and 1 cm lines.
  graph('Graph paper', 18.9, TemplateCategory.paper, canvas: true, keywords: 'millimetre mm'),

  /// Five squares per inch, a bold line every inch, and a header.
  engineering(
    'Engineering',
    19.2,
    TemplateCategory.paper,
    canvas: true,
    keywords: 'quad maths math',
  ),
  isometric('Isometric', 32, TemplateCategory.paper, canvas: true, keywords: '3d triangle'),
  music('Music staff', 9, TemplateCategory.paper, canvas: true, keywords: 'score notes stave'),
  storyboard('Storyboard', 27, TemplateCategory.paper, keywords: 'frames comic film'),

  /// A user's template: an image (blob) stretched over the page.
  image('Image', 0, TemplateCategory.mine);

  const PaperStyle(
    this.label,
    this.spacing,
    this.category, {
    this.period,
    this.canvas = false,
    this.keywords = '',
  });

  /// Human-readable name for pickers.
  final String label;

  /// Pattern pitch in world units (line distance, grid cell, dot spacing,
  /// staff line distance for [music], 5 mm for [graph]). Zero when there is
  /// no repeating pattern.
  final double spacing;

  final TemplateCategory category;

  /// For date-aware planners: what one page covers.
  final PlannerPeriod? period;

  /// Whether the pattern tiles, so it can be an infinite canvas background.
  final bool canvas;

  /// Extra search terms for the template picker.
  final String keywords;

  /// The built-in templates in the order they are offered.
  static List<PaperStyle> get builtIn => [
    for (final s in values)
      if (s != image) s,
  ];

  /// Whether the pattern consists of horizontal writing lines.
  bool get isRuled => this == wideRuled || this == collegeRuled || this == narrowRuled;

  /// Whether pages of this template carry a date.
  bool get isPlanner => period != null;

  /// Whether a page of this style needs parameters ([isPlanner], [image]).
  bool get needsParams => isPlanner || this == image;

  /// Whether this template matches a picker search for [query].
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final text = '$label ${category.label} $keywords'.toLowerCase();
    return q.split(RegExp(r'\s+')).every(text.contains);
  }

  /// Parses a stored name; an unknown one (corrupt data) reads as [blank].
  static PaperStyle parse(String value) =>
      values.firstWhere((p) => p.name == value, orElse: () => blank);
}
