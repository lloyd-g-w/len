import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'scroll_fade.dart';

/// The popover primitive (REDESIGN §5), for live settings: shows
/// [builder]'s content as a bottom sheet with a handle on phones and as an
/// `overlay` surface ([Radii.md], [Shadows.high]) anchored to [context]'s
/// widget (e.g. the button that opened it) on tablets and desktops — or
/// everywhere, without [sheetOnPhones] (small, quick menus such as the tool
/// switcher). Popovers have no buttons: changes apply live, and an outside
/// tap or Esc closes them.
Future<T?> showAdaptivePopover<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double width = popoverWidth,
  bool sheetOnPhones = true,
}) {
  if (sheetOnPhones && popoverIsSheet(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Gaps.lg,
          0,
          Gaps.lg,
          Gaps.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: builder(context),
      ),
    );
  }
  final box = context.findRenderObject()! as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  return Navigator.of(context).push(
    _PopoverRoute<T>(
      anchor: anchor,
      width: width,
      builder: builder,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      capturedThemes: InheritedTheme.capture(from: context, to: Navigator.of(context).context),
    ),
  );
}

/// Whether [showAdaptivePopover] shows a bottom sheet here (phones) rather
/// than an anchored popover; content can use it to repeat what the sheet
/// covers (e.g. the toolbar's quick slots).
bool popoverIsSheet(BuildContext context) => MediaQuery.sizeOf(context).shortestSide < 600;

/// The width of an anchored popover.
const double popoverWidth = 320;

class _PopoverRoute<T> extends PopupRoute<T> {
  _PopoverRoute({
    required this.anchor,
    required this.width,
    required this.builder,
    required this.barrierLabel,
    required this.capturedThemes,
  });

  final Rect anchor;
  final double width;
  final WidgetBuilder builder;
  final CapturedThemes capturedThemes;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => Motion.fast;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> _) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    return capturedThemes.wrap(
      CustomSingleChildLayout(
        // Keep clear of system bars and of an open on-screen keyboard (the
        // colour picker's hex field).
        delegate: _PopoverLayout(
          anchor: anchor,
          width: width,
          padding: media.padding + EdgeInsets.only(bottom: media.viewInsets.bottom),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            boxShadow: Shadows.high(scheme.brightness),
          ),
          child: Material(
            color: Surfaces.overlay(scheme.brightness),
            shape: Surfaces.shape(scheme, Radii.md),
            clipBehavior: Clip.antiAlias,
            // A cut-off end fades, so a tall popover shows it scrolls.
            child: ScrollFade(
              axis: Axis.vertical,
              extent: Gaps.xl,
              padding: const EdgeInsets.all(Gaps.lg),
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Motion.standard);
    final fade = FadeTransition(opacity: curved, child: child);
    if (Motion.reduced(context)) return fade;
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween(begin: Motion.popoverScale, end: 1.0).animate(curved),
        // Grows from the anchor: down from below it, up from above it.
        alignment: anchor.center.dy < MediaQuery.sizeOf(context).height / 2
            ? Alignment.topCenter
            : Alignment.bottomCenter,
        child: child,
      ),
    );
  }
}

/// Places the popover below the anchor (or above, if there is more room
/// there), horizontally centred on it and kept on screen.
class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout({required this.anchor, required this.width, required this.padding});

  final Rect anchor;
  final double width;
  final EdgeInsets padding;

  static const double _margin = 8;
  static const double _gap = 8;

  double _spaceBelow(Size size) => size.height - padding.bottom - anchor.bottom - _gap - _margin;
  double _spaceAbove() => anchor.top - padding.top - _gap - _margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest;
    final height = math.max(_spaceBelow(size), _spaceAbove());
    return BoxConstraints(
      maxWidth: math.min(width, size.width - 2 * _margin),
      maxHeight: math.max(120, height),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = _spaceBelow(size) >= childSize.height || _spaceBelow(size) >= _spaceAbove();
    final y = below ? anchor.bottom + _gap : anchor.top - _gap - childSize.height;
    final double x = (anchor.center.dx - childSize.width / 2).clamp(
      _margin,
      math.max(_margin, size.width - childSize.width - _margin),
    );
    final top = padding.top + _margin;
    final bottom = size.height - padding.bottom - _margin - childSize.height;
    return Offset(x, y.clamp(top, math.max(top, bottom)).toDouble());
  }

  @override
  bool shouldRelayout(_PopoverLayout old) =>
      old.anchor != anchor || old.width != width || old.padding != padding;
}
