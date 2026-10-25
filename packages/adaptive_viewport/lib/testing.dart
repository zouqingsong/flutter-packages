/// Screens to run a layout over in tests: the phones, foldables, tablets and
/// desktop windows the apps are laid out for, each as the window Flutter
/// reports, with the safe area already trimmed the way [ViewportScope] trims
/// it.
///
/// The numbers are what the simulators and devices report, in logical
/// pixels. A layout that passes on all of these has not been fitted to any
/// one of them.
library;

import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';

import 'adaptive_viewport.dart';

/// One window on one screen, in one posture.
@immutable
class ScreenProfile {
  const ScreenProfile(
    this.name,
    this.size, {
    this.padding = EdgeInsets.zero,
    this.features = const [],
    this.hingeFolded = false,
    this.platform = TargetPlatform.iOS,
  });

  final String name;
  final Size size;
  final EdgeInsets padding;
  final List<DisplayFeature> features;

  /// An iPhone hinge half-folded (iOS reports no fold position; the window
  /// splits in the middle).
  final bool hingeFolded;

  final TargetPlatform platform;

  bool get isDesktop =>
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux;

  bool get isLandscape => size.width > size.height;

  MediaQueryData get mediaQuery => MediaQueryData(
        size: size,
        padding: padding,
        viewPadding: padding,
        displayFeatures: features,
      );

  /// The tabletop fold this profile is in, if any.
  TabletopFold? get tabletop {
    for (final feature in features) {
      final isFold = feature.type == DisplayFeatureType.fold ||
          feature.type == DisplayFeatureType.hinge;
      if (isFold &&
          feature.state == DisplayFeatureState.postureHalfOpened &&
          feature.bounds.width > feature.bounds.height) {
        return TabletopFold(
            top: feature.bounds.top, bottom: feature.bounds.bottom);
      }
    }
    if (hingeFolded &&
        !isLandscape &&
        size.shortestSide >= FoldPosture.innerScreenShortestSide) {
      return TabletopFold(top: size.height / 2, bottom: size.height / 2);
    }
    return null;
  }

  ScreenViewport get viewport => ScreenViewport.fromMediaQuery(
        mediaQuery,
        tabletop: tabletop,
        platform: platform,
      );

  @override
  String toString() => name;

  static DisplayFeature _fold(Rect bounds, DisplayFeatureState state) =>
      DisplayFeature(
          bounds: bounds, type: DisplayFeatureType.fold, state: state);

  static DisplayFeature _cutout(Rect bounds) => DisplayFeature(
        bounds: bounds,
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      );

  static const _half = DisplayFeatureState.postureHalfOpened;
  static const _flat = DisplayFeatureState.postureFlat;
  static const _android = TargetPlatform.android;

  /// Every profile.
  static final List<ScreenProfile> all = [
    // iPhones with a Dynamic Island.
    const ScreenProfile(
      'iPhone 17 Pro portrait',
      Size(402, 874),
      padding: EdgeInsets.only(top: 62, bottom: 34),
    ),
    const ScreenProfile(
      'iPhone 17 Pro landscapeLeft',
      Size(874, 402),
      padding: EdgeInsets.only(right: 62, bottom: 21),
    ),
    const ScreenProfile(
      'iPhone 17 Pro landscapeRight',
      Size(874, 402),
      padding: EdgeInsets.only(left: 62, bottom: 21),
    ),
    const ScreenProfile(
      'iPhone 17 Pro Max portrait',
      Size(440, 956),
      padding: EdgeInsets.only(top: 62, bottom: 34),
    ),
    // Home button, no housing.
    const ScreenProfile(
      'iPhone SE portrait',
      Size(375, 667),
      padding: EdgeInsets.only(top: 20),
    ),
    const ScreenProfile('iPhone SE landscape', Size(667, 375)),
    // iPhone Duo: a cover screen with a punch hole, an inner screen that
    // half-folds.
    const ScreenProfile(
      'iPhone Duo cover portrait',
      Size(466, 678),
      padding: EdgeInsets.only(top: 70, bottom: 34),
    ),
    const ScreenProfile(
      'iPhone Duo cover landscapeLeft',
      Size(678, 466),
      padding: EdgeInsets.only(right: 84, bottom: 34),
    ),
    const ScreenProfile(
      'iPhone Duo cover landscapeRight',
      Size(678, 466),
      padding: EdgeInsets.only(left: 84, bottom: 34),
    ),
    const ScreenProfile(
      'iPhone Duo inner portrait',
      Size(669, 951),
      padding: EdgeInsets.only(top: 44, bottom: 34),
    ),
    const ScreenProfile(
      'iPhone Duo inner half-folded',
      Size(669, 951),
      padding: EdgeInsets.only(top: 44, bottom: 34),
      hingeFolded: true,
    ),
    const ScreenProfile(
      'iPhone Duo inner landscape',
      Size(951, 669),
      padding: EdgeInsets.only(top: 24, bottom: 20),
    ),
    // Galaxy Z Flip 4: a centred hole-punch; a fold across the long side.
    ScreenProfile(
      'Galaxy Z Flip 4 portrait',
      const Size(412, 915),
      padding: const EdgeInsets.only(top: 35, bottom: 24),
      features: [_cutout(const Rect.fromLTRB(192, 6, 220, 32))],
      platform: _android,
    ),
    ScreenProfile(
      'Galaxy Z Flip 4 half-folded',
      const Size(412, 915),
      padding: const EdgeInsets.only(top: 35, bottom: 24),
      features: [
        _cutout(const Rect.fromLTRB(192, 6, 220, 32)),
        _fold(const Rect.fromLTRB(0, 457, 412, 457), _half),
      ],
      platform: _android,
    ),
    ScreenProfile(
      'Galaxy Z Flip 4 landscape',
      const Size(915, 412),
      padding: const EdgeInsets.only(left: 35, bottom: 24),
      features: [_cutout(const Rect.fromLTRB(6, 192, 32, 220))],
      platform: _android,
    ),
    const ScreenProfile(
      'Galaxy Z Flip cover',
      Size(360, 374),
      platform: _android,
    ),
    // Galaxy Z Fold 4: the inner screen folds down its long side.
    ScreenProfile(
      'Galaxy Z Fold 4 inner tabletop',
      const Size(829, 690),
      padding: const EdgeInsets.only(top: 24, bottom: 24),
      features: [_fold(const Rect.fromLTRB(0, 345, 829, 345), _half)],
      platform: _android,
    ),
    ScreenProfile(
      'Galaxy Z Fold 4 inner book',
      const Size(690, 829),
      padding: const EdgeInsets.only(top: 24, bottom: 24),
      features: [_fold(const Rect.fromLTRB(345, 0, 345, 829), _half)],
      platform: _android,
    ),
    const ScreenProfile(
      'Galaxy Z Fold 4 cover portrait',
      Size(344, 882),
      padding: EdgeInsets.only(top: 28, bottom: 24),
      platform: _android,
    ),
    const ScreenProfile(
      'Galaxy Z Fold 4 cover landscape',
      Size(882, 344),
      padding: EdgeInsets.only(left: 28, bottom: 24),
      platform: _android,
    ),
    const ScreenProfile(
      'Android compact portrait',
      Size(360, 640),
      padding: EdgeInsets.only(top: 24, bottom: 24),
      platform: _android,
    ),
    const ScreenProfile(
      'iPad portrait',
      Size(820, 1180),
      padding: EdgeInsets.only(top: 24, bottom: 20),
    ),
    const ScreenProfile(
      'iPad landscape',
      Size(1180, 820),
      padding: EdgeInsets.only(top: 24, bottom: 20),
    ),
    const ScreenProfile(
      'iPad mini portrait',
      Size(744, 1133),
      padding: EdgeInsets.only(top: 24, bottom: 20),
    ),
    const ScreenProfile(
      'iPad Pro 13 landscape',
      Size(1376, 1032),
      padding: EdgeInsets.only(top: 24, bottom: 20),
    ),
    // A third of the screen in Split View: a phone's width, a tablet's
    // height.
    const ScreenProfile(
      'iPad Split View third',
      Size(375, 1032),
      padding: EdgeInsets.only(top: 24, bottom: 20),
    ),
    // Android phones: a centred hole-punch reported as a cutout.
    ScreenProfile(
      'Pixel 9 portrait',
      const Size(412, 923),
      padding: const EdgeInsets.only(top: 52, bottom: 24),
      features: [_cutout(const Rect.fromLTRB(190, 14, 222, 46))],
      platform: _android,
    ),
    ScreenProfile(
      'Pixel 9 landscape',
      const Size(923, 412),
      padding: const EdgeInsets.only(left: 52, bottom: 24),
      features: [_cutout(const Rect.fromLTRB(14, 190, 46, 222))],
      platform: _android,
    ),
    // Unfolded flat: the fold is reported, but is just screen.
    ScreenProfile(
      'Pixel Fold inner flat',
      const Size(841, 701),
      padding: const EdgeInsets.only(top: 24, bottom: 24),
      features: [_fold(const Rect.fromLTRB(420, 0, 421, 701), _flat)],
      platform: _android,
    ),
    const ScreenProfile(
      'Android tablet landscape',
      Size(1280, 800),
      padding: EdgeInsets.only(top: 24, bottom: 48),
      platform: _android,
    ),
    // Desktop windows: any size the user drags them to, no safe area.
    const ScreenProfile(
      'macOS window',
      Size(1280, 800),
      platform: TargetPlatform.macOS,
    ),
    const ScreenProfile(
      'macOS small window',
      Size(720, 520),
      platform: TargetPlatform.macOS,
    ),
    const ScreenProfile(
      'macOS narrow window',
      Size(420, 760),
      platform: TargetPlatform.macOS,
    ),
    const ScreenProfile(
      'macOS short window',
      Size(960, 420),
      platform: TargetPlatform.macOS,
    ),
    const ScreenProfile(
      'macOS full screen',
      Size(1728, 1117),
      platform: TargetPlatform.macOS,
    ),
    const ScreenProfile(
      'Windows laptop window',
      Size(1366, 705),
      platform: TargetPlatform.windows,
    ),
    const ScreenProfile(
      'Linux desktop window',
      Size(1920, 1052),
      platform: TargetPlatform.linux,
    ),
  ];
}
