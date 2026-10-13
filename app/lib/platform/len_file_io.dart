/// Reading and writing Len files (`data/archive`) where they live:
/// `openFileInput` reads a file (a blob) in chunks natively (null on the
/// web); `openPickedInput` opens a picked or incoming file (natively read
/// in place, in browsers from memory); `fileCrc32` checksums a file off
/// the UI thread (natively; null in browsers); `createLenFileOutput` writes a Len
/// file, asking where first where it can (desktop: to the chosen file;
/// mobile: to a temporary file to share; browsers: to the file chosen in
/// the save picker where there is one, else to a blob of chunks to
/// download; never held in memory whole) and hands it to the user
/// ([LenFileOutput.deliver]). `lenFilesStream` tells whether the browser
/// writes as it goes.
library;

export 'len_file_io_native.dart' if (dart.library.js_interop) 'len_file_io_web.dart';
