import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Shows [builder]'s content as a bottom sheet on phones and as a popover
/// anchored to [context]'s widget (e.g. the button that opened it) on
/// tablets and desktops.
Future<T?> showAdaptivePopover<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double width = 340,
}) {
  final media = MediaQuery.of(context);
  if (media.size.shortestSide < 600) {
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
        child: Material(
          color: scheme.surfaceContainerHigh,
          elevation: 6,
          shadowColor: Colors.black38,
          surfaceTintColor: Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.card),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gaps.lg),
            child: Builder(builder: builder),
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
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).animate(curved),
        alignment: Alignment.topCenter,
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
