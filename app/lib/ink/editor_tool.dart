/// The tools selectable in the editor toolbar.
enum EditorTool {
  pen,
  highlighter,
  eraser,
  lasso,
  shape,
  text,
  laser,

  /// Selects the text of imported PDF pages (offered when there are any).
  selectText;

  /// Whether the tool draws ink with the active ink's quick colour and width.
  bool get usesInk => this == pen || this == highlighter || this == shape;
}
