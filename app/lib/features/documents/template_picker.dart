import 'package:flutter/material.dart';

import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import '../../ui/dialog_or_sheet.dart';
import '../../ui/segment_label.dart';
import '../../ui/sheet_parts.dart';
import 'templates/page_setup.dart';
import 'templates/planner_options.dart';
import 'templates/template_catalog.dart';
import 'templates/template_chooser.dart';

/// What the template picker is used for.
enum TemplatePickerMode {
  /// Choosing the first page of a new notebook.
  create,

  /// Adding a page to a notebook.
  addPage,

  /// Changing the paper of existing pages (size is fixed).
  change,

  /// Choosing the background of an infinite canvas (no size).
  canvas,
}

/// The user's choice in [TemplatePicker].
class TemplateChoice {
  TemplateChoice(this.template, {this.allPages = false, List<Paper>? papers})
    : papers = papers ?? [template.paper];

  final PageTemplate template;

  /// In [TemplatePickerMode.change]: apply to every page, not just one.
  final bool allPages;

  /// The pages to add ([TemplatePickerMode.addPage]; several for a
  /// generated planner), each in [template]'s colour and size.
  final List<Paper> papers;

  /// The papers for [count] existing pages getting this template: planners
  /// continue period by period (day after day, …), others repeat.
  List<Paper> papersForPages(int count) {
    final result = <Paper>[];
    var paper = template.paper;
    for (var i = 0; i < count; i++) {
      result.add(paper);
      paper = paper.next;
    }
    return result;
  }
}

/// Opens the template picker: a dialog with the gallery and the options
/// side by side on tablets and desktops, a bottom sheet on phones.
Future<TemplateChoice?> showTemplatePicker(
  BuildContext context, {
  required PageTemplate initial,
  TemplatePickerMode mode = TemplatePickerMode.create,
  DateTime? today,
}) => showDialogOrSheet<TemplateChoice>(
  context: context,
  maxWidth: 960,
  maxHeight: 900,
  builder: (_, wide) => TemplatePicker(initial: initial, mode: mode, today: today, wide: wide),
);

/// The selection a chooser starts from: [initial], with planners dated
/// from [today] in [calendar] (or the initial page's date and calendar).
TemplateSelection initialSelection(
  PageTemplate initial,
  DateTime today, {
  PlannerCalendar calendar = PlannerCalendar.standard,
}) {
  final paper = initial.paper;
  return TemplateSelection(
    initial,
    PlannerPlan(start: paper.date ?? today, calendar: paper.calendar ?? calendar),
  );
}

/// Template gallery with live miniatures, paper colours, size and
/// orientation; the actions stay pinned below the scrolling gallery. In a
/// dialog ([wide]) wide enough, the options sit in a column beside the
/// gallery.
class TemplatePicker extends StatefulWidget {
  const TemplatePicker({
    super.key,
    required this.initial,
    required this.mode,
    this.today,
    this.wide = false,
  });

  final PageTemplate initial;
  final TemplatePickerMode mode;

  /// Shown in a dialog (else a bottom sheet with a drag handle above).
  final bool wide;

  /// Today's date, the default start of planners (tests fix it).
  final DateTime? today;

  @override
  State<TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<TemplatePicker> {
  late TemplateSelection _s = initialSelection(
    widget.initial,
    widget.today ?? DateTime.now(),
    calendar: defaultPlannerCalendar(),
  );

  PageTemplate get _t => _s.template;

  bool get _generates =>
      widget.mode == TemplatePickerMode.create || widget.mode == TemplatePickerMode.addPage;

  void _set(TemplateSelection s) => setState(() => _s = s);

  /// Change mode: the template goes to every page, not only this one.
  bool _allPages = false;

  void _done() => Navigator.of(context)
      .pop(TemplateChoice(_t, allPages: _allPages, papers: _generates ? _s.pagesToCreate() : null));

  /// The narrowest dialog that gets the side-by-side layout.
  static const double _splitWidth = 680;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (!widget.wide) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: _layout(context, split: false, top: 0, bottomInset: media.padding.bottom),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) =>
          _layout(context, split: constraints.maxWidth >= _splitWidth, top: Gaps.xl),
    );
  }

  Widget _layout(
    BuildContext context, {
    required bool split,
    required double top,
    double bottomInset = 0,
  }) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.medium;
    final chooser = TemplateChooser(
      selection: _s,
      onChanged: _set,
      canvas: widget.mode == TemplatePickerMode.canvas,
      sizeEditable: _generates,
      generate: _generates,
      tileWidth: compact ? 72 : 80,
      split: split,
    );
    return Column(
      mainAxisSize: widget.wide ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(Gaps.xl, top, Gaps.xl, Gaps.md),
          child: SheetHeader(
            title: _title,
            subtitle: describeSelection(
              _s,
              canvas: widget.mode == TemplatePickerMode.canvas,
              generate: _generates,
            ),
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
        if (split)
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
              ),
              child: chooser,
            ),
          )
        else
          Flexible(
            fit: widget.wide ? FlexFit.tight : FlexFit.loose,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xs, Gaps.xl, Gaps.lg),
              child: chooser,
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(Gaps.xl, Gaps.md, Gaps.xl, Gaps.md + bottomInset),
            child: _actions(),
          ),
        ),
      ],
    );
  }

  String get _title => switch (widget.mode) {
    TemplatePickerMode.create => 'Choose a template',
    TemplatePickerMode.canvas => 'Canvas background',
    TemplatePickerMode.addPage => 'Add page',
    TemplatePickerMode.change => 'Change template',
  };

  /// Cancel and the primary (filled) last; stacked, primary on top, when
  /// they don't fit in a row (large text). Changing a template leads with
  /// "This page · All pages" and one Apply; on phones that is full width,
  /// and the header's ✕ cancels.
  Widget _actions() {
    final cancel = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    );
    final count = _generates ? _s.pagesToCreate().length : 1;
    final primary = FilledButton(
      key: const ValueKey('template-apply'),
      onPressed: _done,
      child: Text(switch (widget.mode) {
        TemplatePickerMode.addPage => count == 1 ? 'Add page' : 'Add $count pages',
        TemplatePickerMode.change => 'Apply',
        _ => 'Use template',
      }),
    );
    final buttons = OverflowBar(
      alignment: MainAxisAlignment.end,
      spacing: Gaps.sm,
      overflowSpacing: Gaps.xs,
      overflowAlignment: OverflowBarAlignment.end,
      overflowDirection: VerticalDirection.up,
      children: [cancel, primary],
    );
    if (widget.mode != TemplatePickerMode.change) return buttons;
    final scope = SegmentedButton<bool>(
      key: const ValueKey('template-scope'),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: false, label: SegmentLabel('This page')),
        ButtonSegment(value: true, label: SegmentLabel('All pages')),
      ],
      selected: {_allPages},
      onSelectionChanged: (s) => setState(() => _allPages = s.single),
    );
    if (!widget.wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gaps.sm,
        children: [
          scope,
          SizedBox(height: Targets.touch, child: primary),
        ],
      );
    }
    return Row(
      children: [
        scope,
        const SizedBox(width: Gaps.md),
        Expanded(child: buttons),
      ],
    );
  }
}
