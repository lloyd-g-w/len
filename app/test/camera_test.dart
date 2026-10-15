import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/features/camera/camera.dart';
import 'package:len/features/camera/camera_purpose.dart';
import 'package:len/platform/camera_capture.dart';

import 'support/fake_camera.dart';

XFile shot() => XFile.fromData(Uint8List(4), name: 'shot.jpg', path: '/tmp/shot.jpg');

void main() {
  late AppDatabase database;
  late SettingsRepository settings;
  setUp(() {
    database = AppDatabase.inMemory();
    settings = SettingsRepository(database);
  });
  tearDown(() => database.close());

  Camera camera(CameraCapture capture) =>
      Camera(settings: settings, isClosed: () => database.isClosed, capture: capture);

  group('CameraPurpose', () {
    test('survives the settings', () {
      for (final purpose in const [
        ScanNewNotebook(),
        ScanIntoNotebook('nb'),
        ScanIntoNotebook('nb', afterPageId: 'p2'),
        PhotoOnSurface('nb', surfaceId: 'p1', at: Offset(120.5, -40)),
      ]) {
        expect(CameraPurpose.decode(purpose.encode()), purpose);
      }
    });

    test('anything else reads as nothing', () {
      for (final text in [
        '',
        'scan',
        '[]',
        '{"kind":"photo","notebook":"nb"}',
        '{"kind":"scan","notebook":3}',
        '{"kind":"video"}',
      ]) {
        expect(CameraPurpose.decode(text), isNull, reason: text);
      }
    });
  });

  group('Camera', () {
    test('keeps the purpose only while the camera app is in front', () async {
      final capture = FakeCameraCapture();
      final photo = camera(capture).takePhoto(const ScanIntoNotebook('nb', afterPageId: 'p'));
      expect(capture.open, isTrue);
      expect(
        CameraPurpose.decode(settings.cameraPurpose!),
        const ScanIntoNotebook('nb', afterPageId: 'p'),
      );
      final taken = shot();
      capture.answer(taken);
      expect(await photo, taken);
      expect(settings.cameraPurpose, isNull);

      // Cancelled or failed alike.
      final cancelled = camera(capture).takePhoto(const ScanNewNotebook());
      capture.answer(null);
      expect(await cancelled, isNull);
      expect(settings.cameraPurpose, isNull);
      final failing = Camera(
        settings: settings,
        isClosed: () => database.isClosed,
        capture: _FailingCapture(),
      );
      await expectLater(failing.takePhoto(const ScanNewNotebook()), throwsStateError);
      expect(settings.cameraPurpose, isNull);
    });

    test('a photo back after Len was killed comes with its purpose, once', () async {
      // The first run: the camera opens, and Len is killed.
      unawaited(
        camera(FakeCameraCapture())
            .takePhoto(const PhotoOnSurface('nb', surfaceId: 'p', at: Offset(10, 20))),
      );
      // The next run.
      final taken = shot();
      final next = camera(FakeCameraCapture(lost: taken));
      final lost = await next.retrieveLost();
      expect(lost?.photo, taken);
      expect(lost?.purpose, const PhotoOnSurface('nb', surfaceId: 'p', at: Offset(10, 20)));
      expect(settings.cameraPurpose, isNull);
      expect(await next.retrieveLost(), isNull);
    });

    test('no photo back: the purpose is dropped', () async {
      settings.cameraPurpose = const ScanNewNotebook().encode();
      expect(await camera(FakeCameraCapture()).retrieveLost(), isNull);
      expect(settings.cameraPurpose, isNull);
    });

    test('a photo without a purpose still comes back', () async {
      final taken = shot();
      final lost = await camera(FakeCameraCapture(lost: taken)).retrieveLost();
      expect(lost?.photo, taken);
      expect(lost?.purpose, isNull);
    });

    test('not asked while a photo is being taken (that purpose stays)', () async {
      final capture = FakeCameraCapture(lost: shot());
      final c = camera(capture);
      unawaited(c.takePhoto(const ScanNewNotebook()));
      expect(await c.retrieveLost(), isNull);
      expect(capture.retrieved, 0);
      expect(settings.cameraPurpose, isNotNull);
    });

    test('a failing retrieval finds nothing', () async {
      settings.cameraPurpose = const ScanNewNotebook().encode();
      expect(await camera(_FailingCapture()).retrieveLost(), isNull);
      expect(settings.cameraPurpose, isNull);
    });

    test('the system camera finds nothing to retrieve off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const system = SystemCameraCapture();
      expect(system.available, isFalse);
      expect(await system.retrieveLost(), isNull);
    });
  });
}

class _FailingCapture implements CameraCapture {
  @override
  bool get available => true;

  @override
  Future<XFile?> takePhoto() async => throw StateError('No camera app');

  @override
  Future<XFile?> retrieveLost() async => throw StateError('Gone');
}
