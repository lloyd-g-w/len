import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../domain/paper.dart';
import '../../../domain/templates/user_template.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/menus.dart';
import '../../../ui/text_prompt.dart';
import '../../editor/images/image_import.dart';
import '../pdf/pdf_import.dart';
import '../pdf/pdf_renderer.dart';
import '../progress_dialog.dart';

/// Width in pixels of templates rendered from PDF pages and saved pages
/// (≈ 240 dpi on A4: crisp when zoomed in, light enough to sync).
const int templateRenderWidth = 2000;

/// Making and managing the user's own templates ("My templates").
abstract final class UserTemplates {
  static const _types = [
    XTypeGroup(label: 'Images and PDFs', extensions: [...ImageImport.extensions, 'pdf']),
  ];

  /// The page size (world units) for an image of [width] × [height]
  /// pixels: as wide as A4 for portrait images, as tall as A4 is wide for
  /// landscape ones.
  static ui.Size pageSizeFor(int width, int height) {
    final short = PageFormat.a4.width;
    return width >= height
        ? ui.Size(short * width / height, short)
        : ui.Size(short, short * height / width);
  }

  /// Picks an image or a PDF (then one of its pages) and adds it to My
  /// templates. Returns the new template, or null if cancelled or failed
  /// (the user has been told why).
  static Future<UserTemplate?> import(BuildContext context) async {
    final file = await openFile(acceptedTypeGroups: _types);
    if (file == null || !context.mounted) return null;
    final name = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final services = AppScope.read(context);
    try {
      if (file.name.toLowerCase().endsWith('.pdf')) {
        return await _importPdf(context, services, file, name);
      }
      return await runWithProgress(context, 'Importing template', () async {
        final image = await ImageImport.prepare(await file.readAsBytes());
        final sha = await services.blobs.putBytes(image.bytes, mime: image.mime);
        return services.templates.create(
          name: name,
          blob: sha,
          size: pageSizeFor(image.width, image.height),
        );
      });
    } on Exception catch (e) {
      if (context.mounted) showMessage(context, 'Could not import ${file.name}: ${_reason(e)}');
      return null;
    }
  }

  static Future<UserTemplate?> _importPdf(
    BuildContext context,
    AppServices services,
    XFile file,
    String name,
  ) async {
    final renderer = PdfRenderer(services.blobs);
    try {
      final sha = await services.blobs.putFile(file, mime: 'application/pdf');
      final sizes = await renderer.pageSizes(sha);
      if (sizes.isEmpty) throw const FormatException('The PDF has no pages');
      var index = 0;
      if (sizes.length > 1) {
        if (!context.mounted) return null;
        final answer = await showTextPrompt(
          context,
          title: 'Which page?',
          label: 'Page (1–${sizes.length})',
          initialValue: '1',
          confirmLabel: 'Import',
          keyboardType: TextInputType.number,
        );
        final page = int.tryParse(answer ?? '');
        if (page == null) return null;
        index = page.clamp(1, sizes.length) - 1;
      }
      if (!context.mounted) return null;
      return await runWithProgress(context, 'Importing template', () async {
        final image = await renderer.render(sha, index, templateRenderWidth);
        if (image == null) throw const FormatException('Cannot render the page');
        final png = await _png(image);
        final blob = await services.blobs.putBytes(png, mime: 'image/png');
        return services.templates.create(
          name: sizes.length > 1 ? '$name, page ${index + 1}' : name,
          blob: blob,
          size: sizes[index] * worldPerPoint,
        );
      });
    } finally {
      await renderer.dispose();
    }
  }

  /// Adds the PNG [png] (e.g. a rendered page) to My templates, asking for
  /// a name. [size] is the page size of pages made from it.
  static Future<UserTemplate?> savePng(
    BuildContext context,
    Uint8List png, {
    required ui.Size size,
    String name = 'My template',
  }) async {
    final services = AppScope.read(context);
    final chosen = await showTextPrompt(
      context,
      title: 'Save as template',
      label: 'Name',
      initialValue: name,
      confirmLabel: 'Save',
      icon: Icons.dashboard_customize_outlined,
    );
    if (chosen == null || chosen.isEmpty || !context.mounted) return null;
    final blob = await services.blobs.putBytes(png, mime: 'image/png');
    final template = services.templates.create(name: chosen, blob: blob, size: size);
    if (context.mounted) showMessage(context, 'Saved “$chosen” to My templates');
    return template;
  }

  /// The menu of one of the user's templates: rename or delete. Returns
  /// whether anything changed.
  static Future<bool> showMenu(BuildContext context, UserTemplate template, {Offset? at}) async {
    final action = await showContextMenuAt<String>(
      context,
      at: at,
      items: const [
        MenuRow(value: 'rename', icon: Icons.edit_outlined, label: 'Rename…'),
        MenuRow(
          value: 'delete',
          icon: Icons.delete_outline_rounded,
          label: 'Delete…',
          destructive: true,
        ),
      ],
    );
    if (action == null || !context.mounted) return false;
    final repo = AppScope.read(context).templates;
    if (action == 'rename') {
      final name = await showTextPrompt(
        context,
        title: 'Rename template',
        label: 'Name',
        initialValue: template.name,
        confirmLabel: 'Rename',
      );
      if (name == null || name.isEmpty) return false;
      repo.rename(template.id, name);
      return true;
    }
    final confirmed = await confirmAction(
      context,
      title: 'Delete “${template.name}”?',
      message: 'Pages already using it keep their background.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return false;
    repo.delete(template.id);
    return true;
  }

  static Future<Uint8List> _png(ui.Image image) async {
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  static String _reason(Exception e) => switch (e) {
    ImageImportException(:final message) => message,
    FormatException(:final message) => message,
    _ => 'unsupported or damaged file',
  };

  /// A resolution for rendering a page of [size] as a template image.
  static double renderScaleFor(ui.Size size) =>
      math.min(templateRenderWidth / size.width, templateRenderWidth * 1.5 / size.height);
}
