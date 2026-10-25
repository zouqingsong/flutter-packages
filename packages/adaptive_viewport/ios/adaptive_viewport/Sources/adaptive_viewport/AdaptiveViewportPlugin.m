#import "AdaptiveViewportPlugin.h"

#import <UIKit/UIKit.h>

// UIHinge arrived in the iOS 27.1 SDK. Building with an older Xcode leaves the
// plugin in place but always reporting "no hinge".
#if __has_include(<UIKit/UIHingeInteraction.h>)
#define AV_HAS_HINGE 1
#else
#define AV_HAS_HINGE 0
#endif

static const NSInteger kAVAttachRetries = 20;
static const double kAVAttachRetryDelay = 0.25;

/// The window to observe. The interaction reports the hinge of whatever
/// hierarchy it is in, so any view of the app's window will do; the window
/// itself outlives every view controller swap.
static UIWindow *_Nullable AVAppWindow(void) API_AVAILABLE(ios(13.0)) {
  UIWindow *fallback = nil;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:UIWindowScene.class]) continue;
    for (UIWindow *window in ((UIWindowScene *)scene).windows) {
      if (window.isKeyWindow) return window;
      if (fallback == nil) fallback = window;
    }
  }
  return fallback;
}

/// The interface orientation's name, or nil before the app has a scene.
static NSString *_Nullable AVInterfaceOrientation(void) API_AVAILABLE(ios(13.0)) {
  UIWindowScene *scene = nil;
  for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
    if (![candidate isKindOfClass:UIWindowScene.class]) continue;
    if (scene == nil || candidate.activationState == UISceneActivationStateForegroundActive) {
      scene = (UIWindowScene *)candidate;
    }
  }
  if (scene == nil) return nil;
  UIInterfaceOrientation orientation;
  if (@available(iOS 16.0, *)) {
    orientation = scene.effectiveGeometry.interfaceOrientation;
  } else {
    orientation = scene.interfaceOrientation;
  }
  switch (orientation) {
    case UIInterfaceOrientationPortrait:
      return @"portrait";
    case UIInterfaceOrientationPortraitUpsideDown:
      return @"portraitUpsideDown";
    // Named for the home button's side: the top of the device, where the
    // housing is, is on the opposite edge.
    case UIInterfaceOrientationLandscapeLeft:
      return @"landscapeLeft";
    case UIInterfaceOrientationLandscapeRight:
      return @"landscapeRight";
    default:
      return nil;
  }
}

@interface AdaptiveViewportPlugin ()
@property(nonatomic, copy, nullable) FlutterEventSink sink;
@property(nonatomic, strong, nullable) FlutterMethodChannel *housing;
@property(nonatomic, copy, nullable) NSString *lastOrientation;
@property(nonatomic, strong, nullable) id<NSObject> rotationObserver;
@property(nonatomic, strong, nullable) id<UIInteraction> interaction;
@property(nonatomic, weak, nullable) UIView *host;
@end

@implementation AdaptiveViewportPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  AdaptiveViewportPlugin *instance = [[AdaptiveViewportPlugin alloc] init];
  FlutterEventChannel *channel =
      [FlutterEventChannel eventChannelWithName:@"adaptive_viewport/hinge"
                                binaryMessenger:[registrar messenger]];
  [channel setStreamHandler:instance];
  [instance attachHousingTo:[registrar messenger]];
}

- (void)attachHousingTo:(NSObject<FlutterBinaryMessenger> *)messenger {
  FlutterMethodChannel *housing =
      [FlutterMethodChannel methodChannelWithName:@"adaptive_viewport/display_housing"
                                  binaryMessenger:messenger];
  [housing setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    if ([call.method isEqualToString:@"interfaceOrientation"]) {
      if (@available(iOS 13.0, *)) {
        result(AVInterfaceOrientation());
      } else {
        result(nil);
      }
    } else {
      result(FlutterMethodNotImplemented);
    }
  }];
  self.housing = housing;

  [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
  __weak AdaptiveViewportPlugin *weakSelf = self;
  self.rotationObserver = [NSNotificationCenter.defaultCenter
      addObserverForName:UIDeviceOrientationDidChangeNotification
                  object:nil
                   queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *_) {
                // The interface turns after the device does, at the end of the
                // rotation animation, so it is read again once that has settled.
                [weakSelf pushOrientation];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                                 [weakSelf pushOrientation];
                               });
              }];
}

- (void)pushOrientation {
  if (@available(iOS 13.0, *)) {
    NSString *value = AVInterfaceOrientation();
    if (value == self.lastOrientation || [value isEqualToString:self.lastOrientation]) return;
    self.lastOrientation = value;
    [self.housing invokeMethod:@"interfaceOrientation" arguments:value];
  }
}

- (void)dealloc {
  if (self.rotationObserver != nil) {
    [NSNotificationCenter.defaultCenter removeObserver:self.rotationObserver];
  }
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(FlutterEventSink)events {
  self.sink = events;
  [self attachWithRetries:kAVAttachRetries];
  return nil;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
  self.sink = nil;
  [self detach];
  return nil;
}

/// The first listen can come before the scene has a window, so it is retried
/// briefly rather than reporting "no hinge" for the whole session.
- (void)attachWithRetries:(NSInteger)retries {
#if AV_HAS_HINGE
  if (@available(iOS 27.1, *)) {
    if (self.sink == nil || self.interaction != nil) return;
    UIWindow *window = AVAppWindow();
    if (window == nil) {
      if (retries > 0) {
        __weak AdaptiveViewportPlugin *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(kAVAttachRetryDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         [weakSelf attachWithRetries:retries - 1];
                       });
      } else {
        self.sink([NSNull null]);
      }
      return;
    }
    __weak AdaptiveViewportPlugin *weakSelf = self;
    UIHingeInteraction *interaction = [[UIHingeInteraction alloc]
        initWithUpdateHandler:^(UIHingeInteraction *_, UIHingeInteractionUpdate *update) {
          FlutterEventSink sink = weakSelf.sink;
          if (sink == nil) return;
          UIHinge *hinge = update.hinge;
          if (hinge == nil) {
            sink([NSNull null]);
            return;
          }
          sink(@{
            @"status" : @(hinge.status),
            @"angle" : @(hinge.angle),
          });
        }];
    [window addInteraction:interaction];
    self.interaction = interaction;
    self.host = window;
    return;
  }
#endif
  if (self.sink != nil) self.sink([NSNull null]);
}

- (void)detach {
  if (self.interaction != nil) [self.host removeInteraction:self.interaction];
  self.interaction = nil;
  self.host = nil;
}

@end
