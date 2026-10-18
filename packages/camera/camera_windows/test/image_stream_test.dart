// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:camera_windows/camera_windows.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = BasicMessageChannel<Object?>(
    CameraWindows.imageStreamChannelName,
    StandardMessageCodec(),
  );

  final sentToPlatform = <Object?>[];

  setUp(() {
    sentToPlatform.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (Object? message) async {
          sentToPlatform.add(message);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, null);
  });

  // Delivers a frame to the plugin as the platform side would.
  Future<void> sendFrame({required int cameraId, required int width, required int height}) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      CameraWindows.imageStreamChannelName,
      const StandardMessageCodec().encodeMessage(<String, Object?>{
        'bytes': Uint8List(width * height * 4),
        'width': width,
        'height': height,
        'bytesPerRow': width * 4,
        'cameraId': cameraId,
      }),
      (_) {},
    );
  }

  test('reports that it can stream images', () {
    expect(CameraWindows().supportsImageStreaming(), isTrue);
  });

  test('asks the platform to start on listen and stop on cancel', () async {
    final plugin = CameraWindows();
    final StreamSubscription<CameraImageData> subscription = plugin
        .onStreamedFrameAvailable(7)
        .listen((_) {});
    await pumpEventQueue();

    expect(sentToPlatform, hasLength(1));
    expect(sentToPlatform.last, containsPair('command', 'start'));
    expect(sentToPlatform.last, containsPair('cameraId', 7));

    await subscription.cancel();
    await pumpEventQueue();

    expect(sentToPlatform.last, containsPair('command', 'stop'));
  });

  test('hands a streamed frame to every listener of that camera', () async {
    final plugin = CameraWindows();
    final first = <CameraImageData>[];
    final second = <CameraImageData>[];

    final subscriptions = <StreamSubscription<CameraImageData>>[
      plugin.onStreamedFrameAvailable(3).listen(first.add),
      plugin.onStreamedFrameAvailable(3).listen(second.add),
    ];
    await pumpEventQueue();

    // One stream per camera: two listeners must not ask the platform twice,
    // because a camera can only be opened once.
    expect(sentToPlatform, hasLength(1));

    await sendFrame(cameraId: 3, width: 2, height: 2);
    await pumpEventQueue();

    expect(first, hasLength(1));
    expect(second, hasLength(1));

    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  });

  test('decodes a frame as one bgra8888 plane', () async {
    final plugin = CameraWindows();
    final images = <CameraImageData>[];
    final StreamSubscription<CameraImageData> subscription = plugin
        .onStreamedFrameAvailable(3)
        .listen(images.add);
    await pumpEventQueue();

    await sendFrame(cameraId: 3, width: 4, height: 2);
    await pumpEventQueue();

    expect(images, hasLength(1));
    final CameraImageData image = images.single;
    expect(image.format.group, ImageFormatGroup.bgra8888);
    expect(image.width, 4);
    expect(image.height, 2);
    expect(image.planes, hasLength(1));
    expect(image.planes.single.bytes, hasLength(4 * 2 * 4));
    expect(image.planes.single.bytesPerRow, 4 * 4);
    expect(image.planes.single.bytesPerPixel, 4);

    await subscription.cancel();
  });

  test('ignores a frame for a camera nobody is watching', () async {
    final plugin = CameraWindows();
    // The platform decides when it starts sending, so a frame can arrive before
    // anything subscribed; that must not throw.
    await sendFrame(cameraId: 99, width: 1, height: 1);

    expect(plugin.imageStreamControllers, isEmpty);
  });
}
