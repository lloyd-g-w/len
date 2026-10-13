import 'package:cross_file/cross_file.dart';

import '../../editor/images/image_import.dart';

/// What Len can make of a file handed to it ("Open with", share, drop).
enum IncomingKind { pdf, image, unsupported }

/// An open editor that files could be inserted into.
class ImportDestination {
  const ImportDestination({required this.title, required this.acceptsPdf});

  /// The open notebook's title (for the choice dialog).
  final String title;

  /// Whether PDF pages can be inserted (paged notebooks, not canvases).
  final bool acceptsPdf;
}

/// One thing to do with incoming files.
sealed class ImportStep {
  const ImportStep();
}

/// Import [file] as a new notebook (one page per PDF page).
final class NewPdfNotebook extends ImportStep {
  const NewPdfNotebook(this.file);
  final XFile file;
}

/// Insert [file]'s pages into the open notebook (after the current page).
final class InsertPdfPages extends ImportStep {
  const InsertPdfPages(this.file);
  final XFile file;
}

/// Create one infinite canvas titled [title] holding [files].
final class NewImageCanvas extends ImportStep {
  const NewImageCanvas(this.files, {required this.title});
  final List<XFile> files;
  final String title;
}

/// Insert [files] into the open notebook's current page or canvas.
final class InsertImages extends ImportStep {
  const InsertImages(this.files);
  final List<XFile> files;
}

/// The steps for a batch of incoming files, plus the files Len can't open.
class ImportPlan {
  const ImportPlan(this.steps, {this.unsupported = const []});

  /// In order: inserts into the open notebook first (it is still shown),
  /// then new notebooks, the image canvas last (the last one opened is
  /// the one shown, and images need its editor).
  final List<ImportStep> steps;

  /// Names of files that are neither PDFs nor images.
  final List<String> unsupported;

  /// A friendly explanation of [unsupported], or null if there are none.
  String? get unsupportedMessage => switch (unsupported) {
    [] => null,
    [final name] => 'Couldn’t open “$name”: Len opens PDFs and images',
    _ => 'Couldn’t open ${unsupported.length} files: Len opens PDFs and images',
  };
}

/// Decides what happens to files handed to Len: PDFs become notebooks (or
/// pages of the open notebook), images an infinite canvas (or images on
/// the open page / canvas). Pure logic; `ImportFlow` carries it out.
abstract final class ImportRouter {
  /// Image types the engine can't decode however they are named.
  static const Set<String> _undecodableImages = {'image/svg+xml', 'image/x-icon', 'image/tiff'};

  /// [file]'s name, or the last segment of its path (native `XFile`s
  /// ignore the name they are given).
  static String nameOf(XFile file) {
    if (file.name.isNotEmpty) return file.name;
    final path = file.path.replaceAll(r'\', '/');
    return path.substring(path.lastIndexOf('/') + 1);
  }

  /// Classifies [file] by its MIME type (content URIs may have no
  /// extension) or else its extension.
  static IncomingKind kindOf(XFile file) {
    final mime = file.mimeType?.toLowerCase();
    final name = nameOf(file);
    final dot = name.lastIndexOf('.');
    final ext = dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
    if (mime == 'application/pdf' || ext == 'pdf') return IncomingKind.pdf;
    if (ImageImport.extensions.contains(ext)) return IncomingKind.image;
    if (mime != null && mime.startsWith('image/') && !_undecodableImages.contains(mime)) {
      return IncomingKind.image;
    }
    return IncomingKind.unsupported;
  }

  /// Whether to ask "insert into the open notebook or create a new one?":
  /// only when a notebook is open and something can go into it.
  static bool shouldAsk(List<XFile> files, ImportDestination? open) {
    if (open == null) return false;
    return files.any((f) {
      final kind = kindOf(f);
      return kind == IncomingKind.image || (kind == IncomingKind.pdf && open.acceptsPdf);
    });
  }

  /// The plan for [files]: inserted into [into] (the open notebook, when
  /// the user chose that) or as new notebooks. PDFs that [into] can't take
  /// still become notebooks.
  static ImportPlan plan(List<XFile> files, {ImportDestination? into}) {
    final pdfs = <XFile>[], images = <XFile>[], unsupported = <String>[];
    for (final file in files) {
      switch (kindOf(file)) {
        case IncomingKind.pdf:
          pdfs.add(file);
        case IncomingKind.image:
          images.add(file);
        case IncomingKind.unsupported:
          unsupported.add(nameOf(file));
      }
    }
    final insertPdfs = into != null && into.acceptsPdf;
    final steps = <ImportStep>[
      if (insertPdfs)
        for (final f in pdfs) InsertPdfPages(f),
      if (into != null && images.isNotEmpty) InsertImages(images),
      if (!insertPdfs)
        for (final f in pdfs) NewPdfNotebook(f),
      if (into == null && images.isNotEmpty) NewImageCanvas(images, title: canvasTitleFor(images)),
    ];
    return ImportPlan(steps, unsupported: unsupported);
  }

  /// A canvas title for [images]: the file name of a single image
  /// (`IMG_2041.jpg` → `IMG 2041`), else "Images".
  static String canvasTitleFor(List<XFile> images) {
    if (images.length != 1) return 'Images';
    final name = nameOf(images.single);
    final dot = name.lastIndexOf('.');
    final title = (dot > 0 ? name.substring(0, dot) : name).replaceAll('_', ' ').trim();
    return title.isEmpty ? 'Image' : title;
  }
}
