#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

/// Two readings Flutter does not carry by itself:
///
/// * `adaptive_viewport/hinge` (event channel) — the hinge of a foldable
///   iPhone: `{status: int, angle: double}`, status being the raw
///   `UIHingeStatus` (0 unknown, 1 closed, 2 partially open, 3 fully open)
///   and angle in radians; `nil` when there is no hinge, the OS is older than
///   iOS 27.1, or the app was built against an SDK without UIHinge.
/// * `adaptive_viewport/display_housing` (method channel) — the interface
///   orientation's name, answered to `interfaceOrientation` and pushed on a
///   rotation: a turn between the two landscapes changes neither the window's
///   size nor its insets, so Flutter would not otherwise hear of it.
@interface AdaptiveViewportPlugin : NSObject <FlutterPlugin, FlutterStreamHandler>
@end

NS_ASSUME_NONNULL_END
