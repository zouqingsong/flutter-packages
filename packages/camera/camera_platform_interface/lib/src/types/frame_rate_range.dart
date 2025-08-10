// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Represents a frame rate range with minimum and maximum values.
class FrameRateRange {
  /// Creates a [FrameRateRange] with the given minimum and maximum frame rates.
  const FrameRateRange(this.minFrameRate, this.maxFrameRate);

  /// The minimum frame rate in frames per second.
  final int minFrameRate;

  /// The maximum frame rate in frames per second.
  final int maxFrameRate;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is FrameRateRange &&
            other.minFrameRate == minFrameRate &&
            other.maxFrameRate == maxFrameRate);
  }

  @override
  int get hashCode => Object.hash(minFrameRate, maxFrameRate);

  @override
  String toString() {
    return 'FrameRateRange(minFrameRate: $minFrameRate, maxFrameRate: $maxFrameRate)';
  }
}
