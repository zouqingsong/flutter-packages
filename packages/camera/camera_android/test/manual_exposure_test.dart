// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:camera_android/src/android_camera.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Manual Exposure Time Tests', () {
    late AndroidCamera androidCamera;

    setUp(() {
      androidCamera = AndroidCamera();
    });

    test('setManualExposureTime method exists and does not throw UnimplementedError', () async {
      const int cameraId = 1;
      const int exposureTime = 5000; // 5ms in microseconds

      // This test verifies that the method exists and isn't throwing UnimplementedError
      // We expect it to throw a different exception (like PlatformException) since we don't have real camera
      expect(
        () async => await androidCamera.setManualExposureTime(cameraId, exposureTime),
        throwsA(isNot(isA<UnimplementedError>())),
      );
    });

    test('setManualExposureTime validates positive exposure time assertion', () async {
      const int cameraId = 1;
      const int exposureTime = -1000; // Negative value should trigger assertion

      // This should trigger the assertion for positive exposure time
      expect(
        () async => await androidCamera.setManualExposureTime(cameraId, exposureTime),
        throwsA(isA<AssertionError>()),
      );
    });

    test('setManualExposureTime with valid positive exposure time', () async {
      const int cameraId = 1;
      const int exposureTime = 10000; // 10ms - valid positive value

      // This test just verifies the method accepts valid input without assertion errors
      // It will likely throw a PlatformException due to missing native implementation in test
      try {
        await androidCamera.setManualExposureTime(cameraId, exposureTime);
      } catch (e) {
        // Expect any exception other than UnimplementedError or AssertionError
        expect(e, isNot(isA<UnimplementedError>()));
        expect(e, isNot(isA<AssertionError>()));
      }
    });
  });
}
