import '../data/raster_store.dart';

/// Browsers keep no raster cache: chunks are rasterised again each time.
Future<RasterStore?> openRasterStore({required int format, int maxBytes = 96 << 20}) async => null;
