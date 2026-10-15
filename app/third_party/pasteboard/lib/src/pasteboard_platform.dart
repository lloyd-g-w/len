import 'dart:typed_data';

abstract class PasteboardPlatform {
  Future<Uint8List?> get image;

  Future<String?> get html;

  Future<void> writeImage(Uint8List? image);

  Future<bool> write({Future<Uint8List?>? png, String? text});

  Future<List<String>> files();

  Future<bool> writeFiles(List<String> files);

  Future<String?> get text;

  void writeText(String value);
}
