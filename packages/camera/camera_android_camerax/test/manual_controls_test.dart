// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:camera_android_camerax/src/android_camera_camerax.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Manual Camera Controls - CameraX Implementation', () {
    late AndroidCameraCameraX cameraX;

    setUp(() {
      cameraX = AndroidCameraCameraX();
    });

    group('Manual Focus Distance', () {
      test('setManualFocusDistance throws notSupported exception', () async {
        expect(
          () => cameraX.setManualFocusDistance(0, 0.5),
          throwsA(isA<CameraException>()
              .having((e) => e.code, 'code', 'notSupported')
              .having((e) => e.description, 'description', contains('Manual focus distance control is not supported'))),
        );
      });

      test('getMinFocusDistance returns 0.0', () async {
        final double minDistance = await cameraX.getMinFocusDistance(0);
        expect(minDistance, equals(0.0));
      });

      test('getMaxFocusDistance returns 1.0', () async {
        final double maxDistance = await cameraX.getMaxFocusDistance(0);
        expect(maxDistance, equals(1.0));
      });
    });

    group('Manual Exposure Time', () {
      test('setManualExposureTime throws notSupported exception', () async {
        expect(
          () => cameraX.setManualExposureTime(0, 1000),
          throwsA(isA<CameraException>()
              .having((e) => e.code, 'code', 'notSupported')
              .having((e) => e.description, 'description', contains('Manual exposure time control is not supported'))),
        );
      });

      test('getMinExposureTime returns default minimum', () async {
        final int minExposure = await cameraX.getMinExposureTime(0);
        expect(minExposure, equals(125));
      });

      test('getMaxExposureTime returns default maximum', () async {
        final int maxExposure = await cameraX.getMaxExposureTime(0);
        expect(maxExposure, equals(1000000));
      });
    });

    group('Manual ISO', () {
      test('setManualIso throws notSupported exception', () async {
        expect(
          () => cameraX.setManualIso(0, 200),
          throwsA(isA<CameraException>()
              .having((e) => e.code, 'code', 'notSupported')
              .having((e) => e.description, 'description', contains('Manual ISO control is not supported'))),
        );
      });

      test('getMinIso returns default minimum', () async {
        final int minIso = await cameraX.getMinIso(0);
        expect(minIso, equals(100));
      });

      test('getMaxIso returns default maximum', () async {
        final int maxIso = await cameraX.getMaxIso(0);
        expect(maxIso, equals(3200));
      });
    });
  });
}
