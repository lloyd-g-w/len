part of 'editor_screen.dart';

/// The editor's shortcuts, keys and layout: the surface, its layers and
/// the chrome.
extension _EditorLayout on _EditorScreenState {
  /// The editor's keyboard shortcuts (with [tabs], the tab strip's).
  Map<ShortcutActivator, VoidCallback> _shortcuts(OpenNotebooks? tabs) => editorScreenShortcuts(
    _session,
    shortcutsHelp: () => unawaited(showKeyboardShortcuts(context)),
    search: _search,
    toggleFocus: _toggleFocus,
    present: _present,
    turnPage: _focus && _session.doc != null ? _turn : null,
    tabs: tabs,
    closeTab: widget.secondPane
        ? _closePane
        : tabs == null
        ? null
        : () => tabs.close(_notebook.id),
    export: _session.commands != null
        ? () => unawaited(_session.commands!.export(context))
        : _session.canvasNav != null
        ? () => unawaited(exportCanvasFlow(context, notebook: _session.notebook))
        : null,
    print: _session.commands != null
        ? () => unawaited(_session.commands!.print(context))
        : _session.canvasNav != null
        ? () => unawaited(printCanvasFlow(context, notebook: _session.notebook))
        : null,
    goToPage: _session.commands == null
        ? null
        : () => unawaited(
            _session.commands!.goToPagePrompt(context, backgrounds: _session.backgrounds),
          ),
    paste: () => _session.images.paste(context),
    pastePlain: () => _session.images.paste(context, plain: true),
    pdfCopied: () => showMessage(context, 'Copied'),
  );

  /// Escape first leaves focus mode, then closes a chrome menu opened
  /// with a tap (focus stayed here, out of the menu's reach); the Menu
  /// key opens the canvas menu. The audio
  /// player's keys (Space, ← / →) come before the editor's shortcuts.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final escape = event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape;
    if (escape && _focus) {
      _setFocus(false);
      return KeyEventResult.handled;
    }
    // From a toolbar or bar button reached with Tab, Escape goes back to
    // the page (where the editor's shortcuts work again).
    if (escape && !node.hasPrimaryFocus) {
      node.requestFocus();
      return KeyEventResult.handled;
    }
    if (escape && _guard.closeMenus()) return KeyEventResult.handled;
    if (escape && _session.content.leaveTextTool()) return KeyEventResult.handled;
    // The Menu key or Shift+F10 on the page: the canvas menu, at the
    // middle of the view.
    if (node.hasPrimaryFocus && ContextMenuKeys.accepts(event)) {
      unawaited(_openMenu(_session.viewport.size.center(Offset.zero)));
      return KeyEventResult.handled;
    }
    // A character typed into a text box goes to the text, past the
    // editor's single-key shortcuts (Space turning pages, P for the pen…).
    if (typesCharacter(event)) return KeyEventResult.skipRemainingHandlers;
    // With the Text tool and no box open, typing starts a box (letters
    // are not tool shortcuts then).
    if (node.hasPrimaryFocus && _typeIntoNewBox(event)) return KeyEventResult.handled;
    return handlePlaybackKey(_audio, event);
  }

  /// Starts a text box with the character [event] types, when the Text
  /// tool is on and no box is open.
  bool _typeIntoNewBox(KeyEvent event) {
    if (event is! KeyDownEvent || isTyping()) return false;
    final character = typedCharacter(event);
    return character != null && _session.content.typeText(character);
  }

  Widget _buildArea(
    BuildContext context,
    BoxConstraints constraints,
    OpenNotebooks? tabs,
    bool band,
  ) {
    final layout = _toolbar.layout(
      size: constraints.biggest,
      safe: MediaQuery.paddingOf(context),
      tabs: tabs,
      focus: _focus,
      band: band,
      split: widget.split?.isSplit ?? false,
      // Read above the Scaffold, which takes the keyboard off its body's
      // insets (shrinking the body instead).
      keyboard: MediaQuery.viewInsetsOf(this.context).bottom > 0,
    );
    _session.setChromeInsets(layout.covered);
    widget.messageInset.value = layout.covered.bottom;
    _guard.laidOut(compact: layout.compactBar);
    return CanvasGuardScope(
      guard: _guard,
      child: EyedropperScope(pick: _eyedropper.pick, child: _buildLayers(layout, tabs, band)),
    );
  }

  Widget _buildLayers(ChromeLayout layout, OpenNotebooks? tabs, bool band) => Listener(
    onPointerDown: (e) {
      // What opens from here (dialogs, sheets) belongs to this editor.
      _services.routeOwners.current = this;
      // Its first contact also gives this pane the split's full chrome
      // (the contact itself still draws, scrolls or taps as usual).
      if (_pane case final pane?) widget.split!.use(pane);
    },
    child: EditorLayers(
      key: _areaKey,
      canvasKey: _canvasKey,
      session: _session,
      notebook: _notebook,
      layout: layout,
      focusNode: _focusNode,
      guard: _guard,
      audio: _audio,
      search: _search,
      chrome: _buildChrome(layout, tabs, band),
      onFollowLink: _followLink,
      onDrop: _use,
      split: _pane == null ? null : (controller: widget.split!, pane: _pane),
      menu: _menu,
      onCloseMenu: _closeMenu,
    ),
  );

  /// The chrome; in a split view it dims while the other pane is in use.
  Widget _buildChrome(ChromeLayout layout, OpenNotebooks? tabs, bool band) {
    final split = widget.split;
    final pane = _pane;
    if (split == null || pane == null) return _chromeHost(layout, tabs, band, dimmed: false);
    return ListenableBuilder(
      listenable: split,
      builder: (context, _) => _chromeHost(layout, tabs, band, dimmed: split.isDimmed(pane)),
    );
  }

  Widget _chromeHost(ChromeLayout layout, OpenNotebooks? tabs, bool band, {required bool dimmed}) =>
      EditorChromeHost(
        dimmed: dimmed,
        presenting: _presenting,
        split: widget.split,
        session: _session,
        layout: layout,
        commands: _commands,
        title: _notebook.title,
        subtitle: folderNameOf(_services, _notebook),
        audio: _audio,
        hud: _hud,
        tips: _tips,
        tabs: tabs,
        secondPane: widget.secondPane,
        band: band,
        splitMenu: (widget.split?.available ?? false) && !widget.secondPane
            ? SplitViewMenu(tabs: _services.openNotebooks, notebookId: _notebook.id)
            : null,
        navigatorActivity: _session.doc?.viewport,
      );
}
