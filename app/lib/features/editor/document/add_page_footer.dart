import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app_services.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/context_menu_keys.dart';
import 'document_controller.dart';
import 'document_layout.dart';

/// "＋ Add page" below the last page of a continuous document, following
/// the page as the document scrolls and zooms (GoodNotes' end-of-document
/// affordance). Held down (or right-clicked), it asks for a template, like
/// "Add page after" in the page menu. Until it has been held once on this
/// device, a caption under it says so ([caption]).
class AddPageFooter extends StatefulWidget {
  const AddPageFooter({
    super.key,
    required this.doc,
    required this.onAdd,
    required this.onAddWithTemplate,
  });

  final DocumentController doc;
  final VoidCallback onAdd;
  final VoidCallback onAddWithTemplate;

  static const double height = 52, gap = 24;

  /// The one-time notice id ([SettingsRepository.seenTips]) of the caption.
  static const String holdHint = 'add-page-hold';

  /// The caption, in words for the input (UX_AUDIT R14-6): a pointer
  /// right-clicks.
  static String get caption =>
      Targets.touchFirst ? 'Hold for a template' : 'Right-click for a template';

  @override
  State<AddPageFooter> createState() => _AddPageFooterState();
}

class _AddPageFooterState extends State<AddPageFooter> {
  /// Whether the caption shows: read once, not on every scroll frame.
  late bool _hint =
      !(AppScope.maybeRead(context)?.settings.seenTips.contains(AddPageFooter.holdHint) ?? true);

  void _addWithTemplate() {
    if (_hint) {
      AppScope.maybeRead(context)?.settings.markTipSeen(AddPageFooter.holdHint);
      setState(() => _hint = false);
      _moved(); // Without the caption it may end above the screen.
    }
    widget.onAddWithTemplate();
  }

  /// Whether the footer is on screen: it rebuilds when that changes, not
  /// on every scroll frame (it is placed at layout time).
  late final ValueNotifier<bool> _shown = ValueNotifier(_onScreen());

  late Listenable _moves = _movesOf(widget.doc);

  static Listenable _movesOf(DocumentController doc) => Listenable.merge([doc, doc.viewport]);

  @override
  void initState() {
    super.initState();
    _moves.addListener(_moved);
  }

  @override
  void didUpdateWidget(AddPageFooter old) {
    super.didUpdateWidget(old);
    if (old.doc == widget.doc) return;
    _moves.removeListener(_moved);
    _moves = _movesOf(widget.doc)..addListener(_moved);
    _moved();
  }

  @override
  void dispose() {
    _moves.removeListener(_moved);
    _shown.dispose();
    super.dispose();
  }

  void _moved() => _shown.value = _onScreen();

  bool _onScreen() => _placement(widget.doc, hint: _hint) != null;

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    const height = AddPageFooter.height;
    final hint = _hint;
    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: _AddButton(onAdd: widget.onAdd, onAddWithTemplate: _addWithTemplate),
        ),
        if (hint) ...[
          const SizedBox(height: Gaps.xs),
          // A gesture hint: screen readers offer the button's long press.
          // One line (the footer is placed by its height): large text
          // shrinks to fit rather than cutting the hint short.
          ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                AddPageFooter.caption,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
              ),
            ),
          ),
        ],
      ],
    );
    // It follows the last page through layout alone: per scroll frame
    // nothing rebuilds, and only the footer's own layer is painted.
    return RepaintBoundary(
      child: ValueListenableBuilder(
        valueListenable: _shown,
        builder: (context, shown, child) => shown
            ? CustomSingleChildLayout(
                delegate: _FooterLayout(doc, hint: hint, relayout: _moves),
                child: child,
              )
            : const SizedBox.shrink(),
        child: RepaintBoundary(child: footer),
      ),
    );
  }
}

/// Where the footer goes on screen (its left, top and width), null when
/// it is not shown (pages one at a time, no pages, off screen).
({double left, double top, double width})? _placement(
  DocumentController doc, {
  required bool hint,
}) {
  final page = doc.lastPageOnScreen;
  final size = doc.viewport.size;
  if (doc.flow != PageFlow.continuous || page == null) return null;
  final top = page.bottom + AddPageFooter.gap;
  final bottom = top + AddPageFooter.height + (hint ? _captionRoom : 0);
  if (top > size.height || bottom < 0) return null;
  final width = math.min(math.max(page.width * 0.6, 200.0), 360.0);
  return (left: page.center.dx - width / 2, top: top, width: width);
}

/// Places the footer under the last page, as the document scrolls and
/// zooms.
class _FooterLayout extends SingleChildLayoutDelegate {
  _FooterLayout(this.doc, {required this.hint, required super.relayout});

  final DocumentController doc;
  final bool hint;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final at = _placement(doc, hint: hint);
    return BoxConstraints.tightFor(width: at?.width ?? 0);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final at = _placement(doc, hint: hint);
    return at == null ? Offset.zero : Offset(at.left, at.top);
  }

  @override
  bool shouldRelayout(_FooterLayout old) => old.doc != doc || old.hint != hint;
}

/// Room under the button for the caption (inside
/// [DocumentController.footerExtent]).
const double _captionRoom = Gaps.xs + 16;

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onAdd, required this.onAddWithTemplate});

  final VoidCallback onAdd;
  final VoidCallback onAddWithTemplate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A Pencil-edged outline with an Ink +, like the library's New tile.
    return ContextMenuKeys(
      onMenu: onAddWithTemplate,
      child: GestureDetector(
        excludeFromSemantics: true, // The button has the long press.
        onSecondaryTap: onAddWithTemplate,
        child: OutlinedButton.icon(
          onPressed: onAdd,
          onLongPress: onAddWithTemplate,
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.onSurface,
            backgroundColor: Colors.transparent,
            side: BorderSide(color: scheme.outline),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
          ),
          icon: const Icon(Symbols.add_rounded),
          label: const Text('Add page'),
        ),
      ),
    );
  }
}
