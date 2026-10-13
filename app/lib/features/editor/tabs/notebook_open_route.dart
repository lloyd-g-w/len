import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';

/// Where a notebook opens from: its cover on screen.
class NotebookOpenOrigin {
  const NotebookOpenOrigin({
    required this.rect,
    required this.cover,
    this.paper,
    this.locate,
    this.dispose,
  });

  /// The cover's global rect when it was tapped.
  final Rect rect;

  /// What flies: a cover that needs nothing inherited beyond the theme
  /// (it is built in the route, away from the library's scopes).
  final Widget cover;

  /// The notebook's paper colour: the cover fades into it, then the editor
  /// fades in over it (default: the theme's background). Dark mode uses the
  /// editor's backdrop instead.
  final Color? paper;

  /// The cover's current global rect, or null when it is gone; the editor
  /// closes back into it.
  final Rect? Function()? locate;

  /// Releases what [cover] holds (e.g. a preview image); called when the
  /// route is disposed, or by whoever drops the origin unused.
  final VoidCallback? dispose;
}

/// The editor's route: "opens" the notebook from its cover.
///
/// With an [origin] the cover grows into the screen (rounded corners easing
/// to square) while it fades to the background and the editor fades in;
/// closing reverses into the cover if it is still on screen, else fades.
/// Without one (search results, new notebooks, imports) the editor fades
/// and scales in slightly. With reduced motion it only fades, quickly.
///
/// The editor is built once, behind the flight, and only clipped, scaled
/// and faded (no relayout); the library under it stays still. The back
/// gesture (incl. Android predictive back) scrubs the same animation.
class NotebookOpenRoute<T> extends PageRoute<T> {
  NotebookOpenRoute({
    required this.builder,
    this.origin,
    this.reduceMotion = false,
    super.settings,
  });

  /// Builds the editor.
  final WidgetBuilder builder;

  /// The tapped cover, if any.
  final NotebookOpenOrigin? origin;

  /// Plain quick fade (the platform asks for less motion).
  final bool reduceMotion;

  bool get _flies => origin != null && !reduceMotion;

  @override
  Duration get transitionDuration => reduceMotion
      ? Motion.fast
      : _flies
      ? Motion.slow + const Duration(milliseconds: 40)
      : Motion.medium;

  @override
  Duration get reverseTransitionDuration => reduceMotion
      ? Motion.fast
      : _flies
      ? Motion.slow - const Duration(milliseconds: 60)
      : Motion.medium;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  // The library stays put under the flight (no slide or fade of its own).
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  void dispose() {
    origin?.dispose?.call();
    super.dispose();
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> _) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _OpenTransition(
    animation: animation,
    origin: _flies ? origin : null,
    scale: !reduceMotion,
    child: child,
  );
}

/// Geometry of the flight: quick start, long settle.
const Curve _geometry = Curves.fastOutSlowIn;

/// The cover fades to the background early (while still small), then the
/// editor fades in, so the two never show through each other.
const Interval _coverFade = Interval(0.1, 0.45, curve: Curves.easeIn);
const Interval _editorFade = Interval(0.4, 0.9, curve: Curves.easeOut);

class _OpenTransition extends StatefulWidget {
  const _OpenTransition({
    required this.animation,
    required this.origin,
    required this.scale,
    required this.child,
  });

  final Animation<double> animation;
  final NotebookOpenOrigin? origin;

  /// Without an origin: scale up slightly while fading in.
  final bool scale;
  final Widget child;

  @override
  State<_OpenTransition> createState() => _OpenTransitionState();
}

class _OpenTransitionState extends State<_OpenTransition> {
  /// Where the editor closes into, decided when closing starts: null =
  /// undecided, false = the cover is gone (fade).
  bool? _returns;
  Rect? _last;

  /// Settles into place both ways: into the screen, and into the cover.
  late CurvedAnimation _flight = _curve();

  CurvedAnimation _curve() =>
      CurvedAnimation(parent: widget.animation, curve: _geometry, reverseCurve: _geometry.flipped);

  @override
  void didUpdateWidget(_OpenTransition old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      _flight.dispose();
      _flight = _curve();
    }
  }

  @override
  void dispose() {
    _flight.dispose();
    super.dispose();
  }

  /// The cover's rect now, in this route's coordinates; null to fade.
  Rect? _coverRect(AnimationStatus status) {
    final origin = widget.origin;
    if (origin == null) return null;
    if (status != AnimationStatus.reverse) _returns = null;
    final live = origin.locate?.call();
    if (status == AnimationStatus.reverse) {
      _returns ??= live != null;
      if (!_returns!) return null;
    }
    final global = live ?? _last ?? origin.rect;
    _last = global;
    final overlay = Navigator.maybeOf(context)?.overlay?.context.findRenderObject();
    if (overlay is! RenderBox || !overlay.hasSize) return global;
    return global.shift(overlay.globalToLocal(Offset.zero));
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    // Dark mode flies on the editor's dark backdrop: over light paper the
    // fading editor would read as a pale flash on every open and close.
    final fill = brightness == Brightness.dark
        ? Surfaces.canvasBackdrop(brightness)
        : widget.origin?.paper ?? Theme.of(context).scaffoldBackgroundColor;
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: widget.animation,
        child: widget.child,
        builder: (context, child) {
          final t = widget.animation.value;
          final status = widget.animation.status;
          final full = Offset.zero & constraints.biggest;
          final from = _coverRect(status);
          final flying = from != null && !status.isCompleted;
          final p = _flight.value;
          final rect = from == null ? full : Rect.lerp(from, full, p)!;
          final radius = Radius.circular(flying ? Radii.sm * (1 - p * p) : 0);
          final double editorOpacity;
          final double scale;
          if (from != null) {
            editorOpacity = _editorFade.transform(t);
            // The editor, shrunk to cover the flight, grows with it.
            scale = flying ? math.max(rect.width / full.width, rect.height / full.height) : 1;
          } else {
            editorOpacity = Motion.standard.transform(t);
            scale = widget.scale ? 0.96 + 0.04 * Motion.standard.transform(t) : 1;
          }
          final coverOpacity = 1 - _coverFade.transform(t);
          return Stack(
            fit: StackFit.expand,
            children: [
              // Soft lift under the flight, gone by the time it fills the screen.
              Positioned.fromRect(
                rect: rect,
                child: Offstage(
                  offstage: !flying,
                  child: Opacity(
                    opacity: (1 - p).clamp(0, 1),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(radius),
                        boxShadow: Shadows.high(brightness),
                      ),
                    ),
                  ),
                ),
              ),
              ClipRRect(
                clipper: _RectClipper(rect, radius),
                clipBehavior: flying ? Clip.antiAlias : Clip.none,
                child: ColoredBox(
                  color: flying ? fill : Colors.transparent,
                  child: Transform(
                    transform: _scaleInto(rect.center, full.center, scale),
                    child: Opacity(opacity: editorOpacity.clamp(0, 1), child: child),
                  ),
                ),
              ),
              // The cover, laid out at the flight's size, fading out.
              Positioned.fromRect(
                rect: rect,
                child: IgnorePointer(
                  child: Offstage(
                    offstage: !flying || coverOpacity <= 0,
                    child: Opacity(
                      opacity: coverOpacity.clamp(0, 1),
                      child: widget.origin?.cover ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Scales by [scale] about [from], moving it to [to].
Matrix4 _scaleInto(Offset to, Offset from, double scale) =>
    Matrix4.translationValues(to.dx, to.dy, 0)
      ..multiply(Matrix4.diagonal3Values(scale, scale, 1))
      ..multiply(Matrix4.translationValues(-from.dx, -from.dy, 0));

class _RectClipper extends CustomClipper<RRect> {
  const _RectClipper(this.rect, this.radius);

  final Rect rect;
  final Radius radius;

  @override
  RRect getClip(Size size) => RRect.fromRectAndRadius(rect, radius);

  @override
  bool shouldReclip(_RectClipper old) => old.rect != rect || old.radius != radius;
}
