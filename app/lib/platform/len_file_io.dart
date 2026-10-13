/// Reading and writing Len files (`data/archive`) where they live:
/// `openFileInput` reads a file (a blob) in chunks natively (null on the
/// web); `openPickedInput` opens a picked or incoming file (natively read
/// in place, in browsers from memory); `createLenFileOutput` writes a Len
/// file (natively to a temporary file, never held in memory; in browsers
/// to memory) and hands it to the user ([LenFileOutput.deliver]).
library;

export 'len_file_io_native.dart' if (dart.library.js_interop) 'len_file_io_web.dart';
