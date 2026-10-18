part of 'text_box_editor.dart';

/// The box being edited as laid out over the page: the field in world
/// units with its outlines and grips, and the format bar.
extension _TextBoxEditorLayout on _TextBoxEditorState {
  /// The editor around the box being edited (rebuilt as the view moves).
  Widget _editor(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_session, widget.viewport]),
      builder: (context, _) {
        final element = _session.current;
        if (element == null) return const SizedBox.shrink();
        // Over pages, the part with the caret (the bar goes with it).
        final bounds = _revealBounds(element);
        _scheduleReveal(element, bounds);
        if (_text.breaks.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _measureRooms());
        }
        final scale = widget.viewport.scale;
        // The box sits on the paper, not the chrome: ink blue in both themes
        // (like the selection handles).
        const accent = AppTheme.seed;
        // The outline sits a few pixels outside the text, which is laid out
        // exactly as it renders.
        final pad = 6 / scale;
        final cursor = 2 / scale;
        final frames = _session.frames;
        final outline = IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: accent.withValues(alpha: 0.7), width: 1.5 / scale),
              borderRadius: BorderRadius.circular(4 / scale),
            ),
          ),
        );
        final width = element.rect.width + RichTextField.caretMargin(cursor);
        final box = SizedBox(
          width: width,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // One outline per page the text is on.
              if (frames.length < 2)
                Positioned(left: -pad, top: -pad, right: -pad, bottom: -pad, child: outline)
              else
                for (final f in frames)
                  Positioned.fromRect(
                    rect: f.shift(-element.rect.topLeft).inflate(pad),
                    child: outline,
                  ),
              TextSelectionTheme(
                data: TextSelectionThemeData(
                  selectionColor: accent.withValues(alpha: 0.25),
                  selectionHandleColor: accent,
                ),
                child: DefaultTextEditingShortcuts(
                  child: RichTextField(
                    controller: _text,
                    focusNode: _focus,
                    cursorWidth: cursor,
                    cursorColor: accent,
                    onDone: _session.end,
                    // Past the box's start, Ctrl+Z undoes the page's edits.
                    onUndo: _session.undo,
                    onRedo: _session.redo,
                  ),
                ),
              ),
              Positioned.fill(
                child: TextSelectionTheme(
                  data: TextSelectionThemeData(
                    selectionColor: accent.withValues(alpha: 0.25),
                    selectionHandleColor: accent,
                  ),
                  child: DefaultTextEditingShortcuts(
                    child: TableEditorLayer(
                      box: _text,
                      cell: _cell,
                      cellFocus: _cellFocus,
                      rangeFocus: _rangeFocus,
                      scale: scale,
                      cursorWidth: cursor,
                      accent: accent,
                      onDone: _session.end,
                      onUndo: _session.undo,
                      onRedo: _session.redo,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        // For screen readers, the box and its bar stay where they are in the
        // reading order, however the box grows or scrolls: on the web the
        // field's text input lives in its semantics node's element, and a
        // node moved among its siblings (the box grown past the top of the
        // view sorting before the toolbar) loses the keyboard focus, and
        // the keys typed after it.
        return Semantics(
          container: true,
          explicitChildNodes: true,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                // Inside the transform: around it, the semantics box would
                // only take taps where the box is untransformed.
                child: Transform(
                  transform: _matrix(element),
                  child: Semantics(
                    container: true,
                    sortKey: const OrdinalSortKey(0),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        box,
                        // The grips sit on the first page's part.
                        Positioned(
                          left: 0,
                          top: 0,
                          width: width,
                          height: frames.length < 2 ? null : element.rect.height,
                          bottom: frames.length < 2 ? 0 : null,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _grip(
                                scale,
                                accent,
                                pad: pad,
                                alignment: Alignment.topLeft,
                                icon: Symbols.open_with_sharp,
                                tooltip: 'Move',
                                onDrag: (d) => _session.setRect(_session.current!.rect.shift(d)),
                              ),
                              for (final side in [Alignment.centerLeft, Alignment.centerRight])
                                _grip(
                                  scale,
                                  accent,
                                  pad: pad,
                                  alignment: side,
                                  icon: Symbols.drag_indicator_sharp,
                                  tooltip: 'Width',
                                  onDrag: (d) => _resize(side.x, d),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Semantics(
                container: true,
                sortKey: const OrdinalSortKey(1),
                // The bar formats the cell edited, if any.
                child: ListenableBuilder(
                  listenable: _text,
                  builder: (context, _) => TextFormatBar(
                    anchor: bounds,
                    dockedKey: _dockedBar,
                    controller: _formatted,
                    tools: widget.tools,
                    onBoxChanged: (box) => widget.tools.textStyle = box.withFlow(null),
                    onDelete: () {
                      _session.setData(const TextData());
                      _session.end();
                    },
                    onDone: _session.end,
                    refocus: _refocus,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
