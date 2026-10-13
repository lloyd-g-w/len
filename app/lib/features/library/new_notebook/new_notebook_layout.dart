part of '../new_notebook_sheet.dart';

/// The footer's hairline: the form scrolls under it.
BoxDecoration _footerEdge(BuildContext context) => BoxDecoration(
  border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
);

/// The sheet's two layouts: a dialog with the preview beside the form, a
/// phone sheet with a preview strip above it.
extension _NewNotebookLayout on _NewNotebookSheetState {
  Widget _header(BuildContext context) => SheetHeader(
    title: _canvas ? 'New canvas' : 'New notebook',
    // Dialogs close with Cancel; sheets with the ✕ (DESIGN §6.3).
    onClose: widget.wide ? null : () => Navigator.of(context).pop(),
  );

  Widget _preview(double height) => Center(
    child: NotebookPreview(kind: _kind, coverColor: _cover, template: _template, height: height),
  );

  Widget _wideLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The preview beside the form.
        Container(
          width: 320,
          // The preview lies on the sheet itself, a hairline beside the form.
          decoration: BoxDecoration(border: Border(right: Surfaces.chromeEdge(scheme))),
          padding: const EdgeInsets.all(Gaps.xl),
          child: LayoutBuilder(builder: (context, c) => _preview(c.maxHeight.clamp(120.0, 220.0))),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.lg, Gaps.xl, Gaps.sm),
                child: _header(context),
              ),
              Expanded(
                // Fades where the form runs on under the footer (large text).
                child: ScrollFade(
                  axis: Axis.vertical,
                  padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.sm, Gaps.xl, Gaps.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _form(context, wide: true),
                  ),
                ),
              ),
              Container(
                decoration: _footerEdge(context),
                padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.md, Gaps.xl, Gaps.lg),
                child: SheetActions(
                  onCancel: () => Navigator.of(context).pop(),
                  primary: FilledButton(onPressed: _submit, child: const Text('Create')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _phoneLayout(BuildContext context) {
    final media = MediaQuery.of(context);
    // With the keyboard up, or in a short window (a phone held sideways),
    // the preview yields its space to the form.
    final keyboard = media.viewInsets.bottom > 0 || media.size.height < 520;
    // Large text needs the room more than the preview does.
    final previewHeight = media.textScaler.scale(10) > 11.5 ? 88.0 : 120.0;
    // As tall as the form (tablets in portrait), at most nearly the screen.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.94),
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, Gaps.sm),
              child: _header(context),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: Gaps.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The preview scrolls away with the form, so the form
                    // keeps the screen when it is long (large text).
                    AnimatedSize(
                      duration: Motion.medium,
                      curve: Motion.standard,
                      child: keyboard
                          ? const SizedBox(width: double.infinity)
                          : ClipRect(
                              child: Container(
                                height: previewHeight + Gaps.lg * 2,
                                padding: const EdgeInsets.symmetric(vertical: Gaps.lg),
                                child: _preview(previewHeight),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _form(context, wide: false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              decoration: _footerEdge(context),
              padding: EdgeInsets.fromLTRB(
                Gaps.xl,
                Gaps.md,
                Gaps.xl,
                Gaps.md + (keyboard ? 0 : media.padding.bottom),
              ),
              child: SheetActions(
                stacked: true,
                primary: FilledButton(onPressed: _submit, child: const Text('Create')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
