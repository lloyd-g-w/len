import 'dart:ui';

import '../../../domain/paper.dart';
import '../../../domain/templates/user_template.dart';

/// One template in the gallery: a built-in one or one of the user's.
sealed class TemplateEntry {
  const TemplateEntry();

  String get name;
  TemplateCategory get category;
}

class BuiltInTemplate extends TemplateEntry {
  const BuiltInTemplate(this.style);

  final PaperStyle style;

  @override
  String get name => style.label;

  @override
  TemplateCategory get category => style.category;
}

class MyTemplate extends TemplateEntry {
  const MyTemplate(this.template);

  final UserTemplate template;

  @override
  String get name => template.name;

  @override
  TemplateCategory get category => TemplateCategory.mine;
}

/// The gallery's sections: templates matching [query] (and [only] a
/// category, if given), grouped by category in a fixed order. A canvas
/// offers only tiling templates; planners only where [planners] is true.
/// "My templates" is listed (possibly empty, for its Import tile) when it
/// is not filtered out.
List<(TemplateCategory, List<TemplateEntry>)> templateSections({
  bool canvas = false,
  bool planners = true,
  String query = '',
  TemplateCategory? only,
  List<UserTemplate> mine = const [],
}) {
  bool wanted(TemplateCategory c) => only == null || only == c;
  final q = query.trim().toLowerCase();
  final sections = <(TemplateCategory, List<TemplateEntry>)>[];
  for (final category in TemplateCategory.values) {
    if (!wanted(category)) continue;
    if (category == TemplateCategory.mine) {
      if (canvas) continue;
      final entries = [
        for (final t in mine)
          if (q.isEmpty || t.name.toLowerCase().contains(q) || 'my templates'.contains(q))
            MyTemplate(t),
      ];
      if (entries.isNotEmpty || q.isEmpty) sections.add((category, entries));
      continue;
    }
    final entries = [
      for (final style in PaperStyle.builtIn)
        if (style.category == category &&
            (!canvas || style.canvas) &&
            (planners || !style.isPlanner) &&
            style.matches(q))
          BuiltInTemplate(style),
    ];
    if (entries.isNotEmpty) sections.add((category, entries));
  }
  return sections;
}

/// What the template chooser has selected: the page template and, for
/// planners, which dates to generate.
class TemplateSelection {
  const TemplateSelection(this.template, this.plan);

  final PageTemplate template;

  /// Planners: the month range (pages generated when creating or adding)
  /// and the calendar (week start, language) of every planner page.
  final PlannerPlan plan;

  PaperStyle get style => template.style;

  TemplateSelection copyWith({PageTemplate? template, PlannerPlan? plan}) =>
      TemplateSelection(template ?? this.template, plan ?? this.plan);

  /// Whether [entry] is the selected template.
  bool isSelected(TemplateEntry entry) => switch (entry) {
    BuiltInTemplate(:final style) => template.style == style,
    MyTemplate(:final template) => this.template.paper.image == template.blob,
  };

  /// The page template [entry] stands for, in the selected colour and size.
  PageTemplate templateFor(TemplateEntry entry) => switch (entry) {
    BuiltInTemplate(:final style) => template.copyWith(
      paper: paperFor(style),
      clearCustomSize: true,
    ),
    MyTemplate(:final template) => this.template.copyWith(
      paper: template.paper,
      customSize: template.size,
    ),
  };

  /// [style] with the selected date and calendar (planners keep a date
  /// they already have when the style stays a planner).
  Paper paperFor(PaperStyle style) {
    if (!style.isPlanner) return Paper(style);
    final current = template.paper;
    final date = current.style.isPlanner && current.date != null ? current.date! : plan.start;
    return Paper.planner(style, date, calendar: plan.calendar);
  }

  /// Selects [entry].
  TemplateSelection select(TemplateEntry entry) => copyWith(template: templateFor(entry));

  /// The papers of the pages to create: a generated planner, or one page.
  List<Paper> pagesToCreate() =>
      template.style.isPlanner ? plan.papersFor(template.style) : [template.paper];

  /// The page size, e.g. for previews.
  Size get size => template.size;
}
