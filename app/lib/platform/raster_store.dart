/// Opens the level-of-detail raster cache (`openRasterStore`): files on
/// Android/Linux/Windows; none on the web.
library;

export 'raster_store_native.dart' if (dart.library.js_interop) 'raster_store_web.dart';
