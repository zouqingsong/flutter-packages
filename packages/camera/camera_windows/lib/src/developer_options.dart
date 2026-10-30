// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';

/// Switches for behaviour that is still being proved out on real hardware.
///
/// None of these is a user preference: they exist so a build can be pointed at a
/// different internal path while that path is being measured, and they default to
/// the behaviour that has been everywhere.
class CameraWindowsDeveloperOptions {
  CameraWindowsDeveloperOptions._();

  /// Not the camera API's channel: these calls carry no camera, and none of this
  /// is part of the plugin's public contract.
  static const MethodChannel _channel = MethodChannel(
    'plugins.flutter.io/camera_windows/developer',
  );

  /// Draws the preview from a D3D11 texture shared with the capture engine
  /// instead of from a CPU pixel buffer.
  ///
  /// Off by default. The choice is read when a camera is opened, and a camera
  /// that is already running keeps the path it started with, so this takes effect
  /// the next time one opens.
  ///
  /// Returns false when nothing answers on the other end — a test, or a platform
  /// that is not this plugin.
  static Future<bool> setGpuPreviewTexture(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setGpuPreviewTexture', enabled);
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Whether the GPU preview is switched on at the moment.
  static Future<bool> gpuPreviewTexture() async {
    try {
      return await _channel.invokeMethod<bool>('gpuPreviewTexture') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
