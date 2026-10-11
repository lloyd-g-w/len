/// File paths among command-line [args]: plain paths as given, `file://`
/// URIs converted to paths; options (`-x`, `--x`) are skipped.
List<String> incomingPathsFromArgs(List<String> args, {bool? windows}) => [
  for (final arg in args)
    if (arg.startsWith('file://'))
      ?_filePath(arg, windows)
    else if (arg.isNotEmpty && !arg.startsWith('-'))
      arg,
];

String? _filePath(String uri, bool? windows) {
  try {
    return Uri.parse(uri).toFilePath(windows: windows);
  } on FormatException {
    return null;
  } on UnsupportedError {
    return null;
  }
}
