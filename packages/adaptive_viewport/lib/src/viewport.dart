import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'display_housing.dart';
import 'fold_posture.dart';

/// What the screen leaves a layout to work with, read from what the system
/// reports rather than from a list of devices.
///
/// * [padding] — the safe area, with UIKit's mirrored landscape inset
///   removed from the edge that has no housing (see [DisplayHousing.trim]).
/// * [holes] — small obstacles inside the window: a punch-hole camera
///   (measured, per screen, on iOS; [DisplayHousing.punchHoleOf]) and the
///   display cutouts Android reports. A control steps around one of these
///   rather than standing a whole inset in from the edge it is on.
/// * [tabletop] — the fold of a foldable half-open like a laptop, which
///   splits the window into a picture above and a deck below.
/// * [crease] — a fold or hinge running *down* the window (a book), which
///   controls keep off.
@immutable
class ScreenViewport {
  const ScreenViewport({
    required this.size,
    this.padding = EdgeInsets.zero,
    this.holes = const [],
    this.tabletop,
    this.crease,
    this.platform,
  });

  /// [data]'s screen, with the [tabletop] fold worked out by the caller (it
  /// needs the hinge, which [data] does not carry).
  factory ScreenViewport.fromMediaQuery(MediaQueryData data,
      {TabletopFold? tabletop, TargetPlatform? platform}) {
    final holes = <Rect>[];
    final hole = DisplayHousing.punchHoleOf(data);
    if (hole != null) holes.add(hole);
    Rect? crease;
    for (final feature in data.displayFeatures) {
      switch (feature.type) {
        case DisplayFeatureType.cutout:
          if (!feature.bounds.isEmpty) holes.add(feature.bounds);
        case DisplayFeatureType.fold:
        case DisplayFeatureType.hinge:
          final vertical = feature.bounds.height > feature.bounds.width;
          // A seamless fold lying flat is just screen; a physical hinge is a
          // gap in it whatever the posture.
          final inTheWay = feature.type == DisplayFeatureType.hinge ||
              feature.state == DisplayFeatureState.postureHalfOpened;
          if (vertical && inTheWay) crease = feature.bounds;
        case DisplayFeatureType.unknown:
          break;
      }
    }
    return ScreenViewport(
      size: data.size,
      padding: data.padding,
      holes: List.unmodifiable(holes),
      tabletop: tabletop,
      crease: crease,
      platform: platform,
    );
  }

  /// The viewport of the window [context] is in, kept current by the nearest
  /// [ViewportScope] (which also trims the safe area). Without one, the hinge
  /// is still read but a change to it does not rebuild [context].
  static ScreenViewport of(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<_ViewportMarker>();
    return ScreenViewport.fromMediaQuery(
      MediaQuery.of(context),
      tabletop: FoldPosture.tabletopOf(context),
    );
  }

  final Size size;
  final EdgeInsets padding;
  final List<Rect> holes;
  final TabletopFold? tabletop;
  final Rect? crease;

  /// The platform the window is on, for its input; null for the one the app
  /// is running on.
  final TargetPlatform? platform;

  bool get isLandscape => size.width > size.height;

  /// Everything a control must stay off, in window coordinates.
  List<Rect> get obstacles => [...holes, if (crease != null) crease!];

  @override
  bool operator ==(Object other) =>
      other is ScreenViewport &&
      other.size == size &&
      other.padding == padding &&
      listEquals(other.holes, holes) &&
      other.tabletop == tabletop &&
      other.crease == crease &&
      other.platform == platform;

  @override
  int get hashCode => Object.hash(
      size, padding, Object.hashAll(holes), tabletop, crease, platform);

  @override
  String toString() =>
      'ScreenViewport($size, padding: $padding, holes: $holes, '
      'tabletop: $tabletop, crease: $crease, platform: $platform)';
}

/// Put once above the app (in `MaterialApp.builder`): starts the native
/// readings, gives everything below it the safe area of the screen it is
/// actually on, and rebuilds [ScreenViewport.of] readers when the hinge or the
/// interface orientation changes — neither of which changes `MediaQuery` by
/// itself.
class ViewportScope extends StatefulWidget {
  const ViewportScope({super.key, required this.child});

  final Widget child;

  @override
  State<ViewportScope> createState() => _ViewportScopeState();
}

class _ViewportScopeState extends State<ViewportScope>
    with WidgetsBindingObserver {
  static final Listenable _changes = Listenable.merge([
    DisplayHousing.orientation,
    FoldPosture.changes,
  ]);

  @override
  void initState() {
    super.initState();
    DisplayHousing.ensureInitialized();
    FoldPosture.ensureInitialized();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => DisplayHousing.refresh();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _changes,
      builder: (context, child) => MediaQuery(
        data: DisplayHousing.trim(
          MediaQuery.of(context),
          DisplayHousing.orientation.value,
        ),
        child: _ViewportMarker(
          orientation: DisplayHousing.orientation.value,
          hinge: FoldPosture.hinge.value,
          simulateTabletop: FoldPosture.simulateTabletop.value,
          child: child!,
        ),
      ),
      child: widget.child,
    );
  }
}

class _ViewportMarker extends InheritedWidget {
  const _ViewportMarker({
    required this.orientation,
    required this.hinge,
    required this.simulateTabletop,
    required super.child,
  });

  final String? orientation;
  final HingeState? hinge;
  final bool simulateTabletop;

  @override
  bool updateShouldNotify(_ViewportMarker oldWidget) =>
      oldWidget.orientation != orientation ||
      oldWidget.hinge != hinge ||
      oldWidget.simulateTabletop != simulateTabletop;
}
