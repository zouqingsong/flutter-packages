// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#if os(macOS)

  import Foundation

  /// macOS has no device orientation concept, but the shared Darwin camera sources are written
  /// against `UIDeviceOrientation`. These stand-ins let those sources compile unmodified; on macOS
  /// the orientation is always treated as `.portrait`, which maps to an unrotated capture.
  @objc public enum UIDeviceOrientation: Int {
    case unknown = 0
    case portrait = 1
    case portraitUpsideDown = 2
    case landscapeLeft = 3
    case landscapeRight = 4
    case faceUp = 5
    case faceDown = 6
  }

  @objc public class UIDevice: NSObject {
    @objc public static let current = UIDevice()
    @objc public let orientation: UIDeviceOrientation = .portrait
  }

#endif
