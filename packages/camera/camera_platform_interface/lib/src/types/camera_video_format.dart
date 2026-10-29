// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' show Size;

/// One picture format a camera can deliver.
///
/// A camera negotiates a size *and* a frame rate together, so a picker that
/// offers real modes needs both. [codec] is the device's own name for the stream
/// format (`mjpg`, `h264`), and is empty where the platform hides it — macOS
/// decodes a UVC camera's compressed modes in the driver, so only uncompressed
/// formats are visible there.
class CameraVideoFormat {
  /// Creates a [CameraVideoFormat] for [size], up to [maxFrameRate].
  const CameraVideoFormat({
    required this.size,
    required this.maxFrameRate,
    this.codec = '',
  });

  /// The frame size the camera delivers.
  final Size size;

  /// The fastest rate this size supports.
  final int maxFrameRate;

  /// The device's name for the stream format, or empty when it is not reported.
  final String codec;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is CameraVideoFormat &&
            other.size == size &&
            other.maxFrameRate == maxFrameRate &&
            other.codec == codec);
  }

  @override
  int get hashCode => Object.hash(size, maxFrameRate, codec);

  @override
  String toString() {
    final String name = codec.isEmpty ? '' : '$codec, ';
    return 'CameraVideoFormat($name$size @ $maxFrameRate)';
  }
}
