import 'package:flutter/material.dart';

import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import '../../ui/color_dot.dart';
import 'template_preview.dart';

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
  const TemplateChoice(this.template, {this.allPages = false});

  final PageTemplate template;

  /// In [TemplatePickerMode.change]: apply to every page, not just one.
  final bool allPages;
}

/// Opens the template picker as a bottom sheet.
Future<TemplateChoice?> showTemplatePicker(
  BuildContext context, {
  required PageTemplate initial,
  TemplatePickerMode mode = TemplatePickerMode.create,
}) => showModalBottomSheet<TemplateChoice>(
  context: context,
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 720),
  builder: (_) => TemplatePicker(initial: initial, mode: mode),
);

/// Template gallery with live miniatures, paper colours, size and
/// orientation.
class TemplatePicker extends StatefulWidget {
  const TemplatePicker({super.key, required this.initial, required this.mode});

  final PageTemplate initial;
  final TemplatePickerMode mode;

  @override
  State<TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<TemplatePicker> {
  late PageTemplate _t = widget.initial;

  bool get _sizeEditable =>
      widget.mode == TemplatePickerMode.create || widget.mode == TemplatePickerMode.addPage;

  void _set(PageTemplate t) => setState(() => _t = t);

  void _done({bool allPages = false}) =>
      Navigator.of(context).pop(TemplateChoice(_t, allPages: allPages));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, Gaps.xl + media.padding.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: Gaps.lg),
            _TemplateGrid(selected: _t, onSelect: _set),
            if (widget.mode != TemplatePickerMode.canvas) ...[
              const SizedBox(height: Gaps.xl),
              _label(context, 'Paper colour'),
              Wrap(
                spacing: Gaps.sm,
                children: [
                  for (final c in PaperColor.values)
                    ColorDot(
                      color: c.paper.toARGB32(),
                      size: 36,
                      tooltip: c.label,
                      selected: _t.color == c,
                      onTap: () => _set(_t.copyWith(color: c)),
                    ),
                ],
              ),
            ],
            if (_sizeEditable) ...[
              const SizedBox(height: Gaps.xl),
              _label(context, 'Page size'),
              _SizeRow(template: _t, onChanged: _set),
            ],
            const SizedBox(height: Gaps.xl),
            _actions(),
          ],
        ),
      ),
    );
  }

  String get _title => switch (widget.mode) {
    TemplatePickerMode.create || TemplatePickerMode.canvas => 'Choose a template',
    TemplatePickerMode.addPage => 'Add page',
    TemplatePickerMode.change => 'Change template',
  };

  Widget _actions() {
    if (widget.mode != TemplatePickerMode.change) {
      return FilledButton.icon(
        onPressed: _done,
        icon: Icon(widget.mode == TemplatePickerMode.addPage ? Icons.note_add : Icons.check),
        label: Text(widget.mode == TemplatePickerMode.addPage ? 'Add page' : 'Use template'),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _done(allPages: true),
            child: const Text('Apply to all pages'),
          ),
        ),
        const SizedBox(width: Gaps.md),
        Expanded(
          child: FilledButton(onPressed: _done, child: const Text('Apply to this page')),
        ),
      ],
    );
  }

  static Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: Gaps.sm),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}

class _TemplateGrid extends StatelessWidget {
  const _TemplateGrid({required this.selected, required this.onSelect});

  final PageTemplate selected;
  final ValueChanged<PageTemplate> onSelect;

  @override
  Widget build(BuildContext context) {
    final landscape = selected.orientation == PageOrientation.landscape;
    return Wrap(
      spacing: Gaps.md,
      runSpacing: Gaps.md,
      children: [
        for (final style in PaperStyle.ordered)
          _TemplateTile(
            template: selected.copyWith(style: style),
            width: landscape ? 112 : 84,
            selected: selected.style == style,
            onTap: () => onSelect(selected.copyWith(style: style)),
          ),
      ],
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final PageTemplate template;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: template.style.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.control),
        child: Padding(
          padding: const EdgeInsets.all(Gaps.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 2.5 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TemplatePreview(template: template, width: width),
                ),
              ),
              const SizedBox(height: Gaps.xs),
              SizedBox(
                width: width + 8,
                child: Text(
                  template.style.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected ? scheme.primary : null,
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SizeRow extends StatelessWidget {
  const _SizeRow({required this.template, required this.onChanged});

  final PageTemplate template;
  final ValueChanged<PageTemplate> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Gaps.md,
      runSpacing: Gaps.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Wrap(
          spacing: Gaps.sm,
          children: [
            for (final f in PageFormat.values)
              ChoiceChip(
                label: Text(f.label),
                selected: template.format == f,
                onSelected: (_) => onChanged(template.copyWith(format: f)),
              ),
          ],
        ),
        SegmentedButton<PageOrientation>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: PageOrientation.portrait,
              icon: Icon(Icons.crop_portrait_rounded),
              tooltip: 'Portrait',
            ),
            ButtonSegment(
              value: PageOrientation.landscape,
              icon: Icon(Icons.crop_landscape_rounded),
              tooltip: 'Landscape',
            ),
          ],
          selected: {template.orientation},
          onSelectionChanged: (s) => onChanged(template.copyWith(orientation: s.single)),
        ),
      ],
    );
  }
}
