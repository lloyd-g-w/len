import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Builds [child] a frame or more late, at most [perFrame] across the app
/// in one frame and not while its scrollable scrolls; [placeholder] until
/// then.
///
/// For costly parts of many repeated items (a menu button on every tile of
/// a grid): scrolling brings in a row of new items a frame, and only those
/// still there when it stops are completed. [placeholder] should look (and
/// if it can be reached, act) like [child] at rest.
class StaggeredBuild extends StatefulWidget {
  const StaggeredBuild({super.key, required this.placeholder, required this.child});

  /// How many waiting children are built in one frame.
  static const perFrame = 4;

  final Widget placeholder;
  final Widget child;

  @override
  State<StaggeredBuild> createState() => _StaggeredBuildState();
}

class _StaggeredBuildState extends State<StaggeredBuild> {
  static final _waiting = <_StaggeredBuildState>[];
  static bool _scheduled = false;

  bool _built = false;

  /// The scrolling state of the scrollable this waits for, if it scrolls.
  ValueListenable<bool>? _scrolling;

  @override
  void initState() {
    super.initState();
    _waiting.add(this);
    _schedule();
  }

  @override
  void dispose() {
    _waiting.remove(this);
    _scrolling?.removeListener(_scrolled);
    super.dispose();
  }

  static void _schedule() {
    if (_scheduled || _waiting.every((s) => s._scrolling != null)) return;
    _scheduled = true;
    SchedulerBinding.instance
      ..scheduleFrameCallback(_buildSome)
      ..scheduleFrame();
  }

  static void _buildSome(Duration _) {
    _scheduled = false;
    var built = 0;
    for (final state in List.of(_waiting)) {
      if (built == StaggeredBuild.perFrame) break;
      if (!state.mounted || state._waitsForScrolling()) continue;
      _waiting.remove(state);
      state.setState(() => state._built = true);
      built++;
    }
    _schedule();
  }

  /// Whether the enclosing scrollable is scrolling; then this waits until
  /// it stops.
  bool _waitsForScrolling() {
    if (_scrolling != null) return true;
    final scrolling = context.findAncestorStateOfType<ScrollableState>()?.position;
    if (scrolling == null || !scrolling.isScrollingNotifier.value) return false;
    _scrolling = scrolling.isScrollingNotifier..addListener(_scrolled);
    return true;
  }

  void _scrolled() {
    if (_scrolling!.value) return;
    _scrolling!.removeListener(_scrolled);
    _scrolling = null;
    _schedule();
  }

  @override
  Widget build(BuildContext context) => _built ? widget.child : widget.placeholder;
}
