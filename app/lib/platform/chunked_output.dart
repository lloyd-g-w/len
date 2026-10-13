import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// An append-only [OutputStream] that hands what is written to [sink] in
/// chunks of about [chunkSize] bytes and keeps nothing else, so a large
/// file (a Len backup in a browser) never sits in memory whole. Enough
/// for `ZipEncoder`, which only appends (it can't read back: [subset]
/// throws).
class ChunkedOutput extends OutputStream {
  ChunkedOutput(this.sink, {this.chunkSize = 4 << 20}) : super(byteOrder: ByteOrder.littleEndian);

  /// Always little-endian, as zip is: archive's web zlib encoder sets the
  /// output it deflates into big-endian (for zlib's trailer) and leaves it
  /// so, which byte-swapped every zip header after the first deflated
  /// entry, so browsers wrote Len files that couldn't be opened.
  @override
  ByteOrder get byteOrder => ByteOrder.littleEndian;

  @override
  set byteOrder(ByteOrder _) {}

  /// Gets each chunk, in order.
  final void Function(Uint8List chunk) sink;
  final int chunkSize;

  final BytesBuilder _buffer = BytesBuilder();
  int _length = 0;

  @override
  int get length => _length;

  @override
  void writeByte(int value) {
    _buffer.addByte(value);
    _length++;
    if (_buffer.length >= chunkSize) flush();
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final n = length ?? bytes.length;
    _buffer.add(n == bytes.length ? bytes : bytes.sublist(0, n));
    _length += n;
    if (_buffer.length >= chunkSize) flush();
  }

  @override
  void writeStream(InputStream stream) {
    while (!stream.isEOS) {
      writeBytes(stream.readBytes(math.min(1 << 16, stream.length)).toUint8List());
    }
  }

  /// Hands what is buffered to [sink].
  @override
  void flush() {
    if (_buffer.isNotEmpty) sink(_buffer.takeBytes());
  }

  @override
  void clear() {
    _buffer.clear();
    _length = 0;
  }

  @override
  Uint8List subset(int start, [int? end]) =>
      throw UnsupportedError('A chunked output can’t be read back');
}
