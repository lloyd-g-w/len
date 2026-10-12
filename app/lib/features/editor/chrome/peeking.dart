import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';

/// Shows [child] while [activity] notifies (e.g. pages scroll or turn) and
/// for [linger] afterwards, then fades it out of the way — so a floating
/// control (the page indicator) doesn't sit over the page for good.
/// Touching or hovering it keeps it shown. Without [enabled] it simply
/// stays.
class Peeking extends StatefulWidget {
  const Peeking({
    super.key,
    required this.activity,
    required this.child,
    this.enabled = true,
    this.linger = const Duration(milliseconds: 1500),
  });

  final Listenable? activity;
  final Widget child;
  final bool enabled;
  final Duration linger;

  @override
  State<Peeking> createState() => _PeekingState();
}

class _PeekingState extends State<Peeking> {
  bool _shown = true;
  bool _held = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.activity?.addListener(_peek);
    _restart();
  }

  @override
  void didUpdateWidget(Peeking old) {
    super.didUpdateWidget(old);
    if (old.activity != widget.activity) {
      old.activity?.removeListener(_peek);
      widget.activity?.addListener(_peek);
    }
    if (old.enabled != widget.enabled) _peek();
  }

  @override
  void dispose() {
    widget.activity?.removeListener(_peek);
    _timer?.cancel();
    super.dispose();
  }

  void _peek() {
    if (!mounted) return;
    if (!_shown) setState(() => _shown = true);
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    if (!widget.enabled || _held) return;
    _timer = Timer(widget.linger, () {
      if (mounted && !_held) setState(() => _shown = false);
    });
  }

  void _hold(bool held) {
    _held = held;
    _peek();
  }

  @override
  Widget build(BuildContext context) {
    final visible = !widget.enabled || _shown;
    // Hidden, it lets touches through to the page beneath.
    return ExcludeSemantics(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: MouseRegion(
        onEnter: (_) => _hold(true),
        onExit: (_) => _hold(false),
        child: Listener(
          onPointerDown: (_) => _hold(true),
          onPointerUp: (_) => _hold(false),
          onPointerCancel: (_) => _hold(false),
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: visible ? Motion.fast : Motion.slow,
            curve: Motion.standard,
            child: widget.child,
          ),
        ),
        ),
      ),
    );
  }
}
