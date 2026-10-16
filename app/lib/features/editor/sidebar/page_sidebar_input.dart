part of 'page_sidebar.dart';

/// The sidebar's keyboard (one Tab stop, ↑ ↓ Home End, Ctrl+arrows to
/// move a page) and pointers (dragging a page, or holding it for its menu).
extension _SidebarInput on _PageSidebarState {
  /// The page whose tile Tab stops at: the focused one, else the page on
  /// screen.
  String? get _stop {
    for (final MapEntry(:key, :value) in _focus.entries) {
      if (value.hasFocus) return key;
    }
    final current = _current.value;
    return current >= 0 && current < _pages.length ? _pages[current].id : null;
  }

  /// Keeps the Tab stop on the page on screen (without rebuilding).
  void _updateStop() {
    final stop = _stop;
    for (final MapEntry(:key, :value) in _focus.entries) {
      value.skipTraversal = key != stop;
    }
  }

  /// The index of the page whose tile has focus, or -1.
  int get _focused {
    final focused = FocusManager.instance.primaryFocus;
    for (final MapEntry(:key, :value) in _focus.entries) {
      if (value == focused) return _pages.indexWhere((p) => p.id == key);
    }
    return -1;
  }

  /// ↑ ↓ to the page before or after, Home and End to the first and last;
  /// ← → stay (they would turn the page behind).
  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed || keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final at = _focused;
    if (at == -1) return KeyEventResult.ignored;
    final next = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => at - 1,
      LogicalKeyboardKey.arrowDown => at + 1,
      LogicalKeyboardKey.home => 0,
      LogicalKeyboardKey.end => _pages.length - 1,
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowRight => at,
      _ => null,
    };
    if (next == null) return KeyEventResult.ignored;
    _focusPage(next.clamp(0, _pages.length - 1));
    return KeyEventResult.handled;
  }

  /// Moves focus to page [index]'s tile, scrolling it into view (and so
  /// into being) first.
  void _focusPage(int index) {
    final node = _focusOf(_pages[index]);
    _follow(index, animate: false);
    if (node.context != null) return node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focus.containsValue(node)) node.requestFocus();
    });
  }

  /// Moves [page] a place toward [direction] (Ctrl+arrows), says where
  /// it went and keeps it focused.
  void _step(NotebookPage page, AxisDirection direction) {
    final from = _pages.indexWhere((p) => p.id == page.id);
    if (from == -1) return;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final to = pageStep(from, direction, columns: 1, count: _pages.length, rtl: rtl);
    if (to == from) return;
    widget.commands.edits.move(page, to);
    announcePageMove(context, from, to);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _pages.indexWhere((p) => p.id == page.id);
      if (index != -1) _focusPage(index);
    });
  }

  /// A press on page [index]: a mouse drags it once it moves; touch and
  /// pens once held (until then the column scrolls).
  void _pointerDown(BuildContext item, int index, PointerDownEvent event) {
    final mouse = event.kind == PointerDeviceKind.mouse;
    if (mouse && event.buttons != kPrimaryButton) return;
    _press = (
      pointer: event.pointer,
      at: event.position,
      index: index,
      moved: false,
      dragged: false,
    );
    final list = SliverReorderableList.maybeOf(item);
    if (list == null) return;
    list.startItemDragReorder(
      index: index,
      event: event,
      recognizer: mouse
          ? ImmediateMultiDragGestureRecognizer(debugOwner: this)
          : DelayedMultiDragGestureRecognizer(delay: kLongPressTimeout, debugOwner: this),
    );
  }

  void _pointerMove(PointerMoveEvent event) {
    final press = _press;
    if (press == null || press.moved || event.pointer != press.pointer) return;
    if ((event.position - press.at).distance > kTouchSlop) {
      _press = (
        pointer: press.pointer,
        at: press.at,
        index: press.index,
        moved: true,
        dragged: press.dragged,
      );
    }
  }

  /// Let go: a page held until it lifted, without moving, opens its menu
  /// there (as a long press does elsewhere).
  void _pointerUp(PointerUpEvent event) {
    final press = _press;
    _press = null;
    if (press == null || event.pointer != press.pointer) return;
    if (press.dragged && !press.moved) unawaited(_menu(press.index, event.position));
  }

  void _dragStarted(int index) {
    _dragging = true;
    final press = _press;
    if (press == null || press.index != index) return;
    _press = (
      pointer: press.pointer,
      at: press.at,
      index: press.index,
      moved: press.moved,
      dragged: true,
    );
  }

  /// A page dragged from [from] dropped at [to]: one undoable move.
  void _dropped(int from, int to) {
    _dragging = false;
    if (from == to || from >= _pages.length) return;
    widget.commands.edits.move(_pages[from], to);
    announcePageMove(context, from, to);
  }
}
