// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Available color effects for camera capture.
enum ColorEffect {
  /// No color effect.
  none,

  /// Monochrome (black and white) effect.
  mono,

  /// Negative color effect (inverts colors).
  negative,

  /// Solarize effect (partial color inversion).
  solarize,

  /// Sepia tone effect (brownish monochrome).
  sepia,

  /// Posterize effect (reduces number of color levels).
  posterize,

  /// Whiteboard effect (optimized for whiteboards).
  whiteboard,

  /// Blackboard effect (optimized for blackboards).
  blackboard,

  /// Aqua color effect.
  aqua,
}
