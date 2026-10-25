import 'package:adaptive_viewport/adaptive_viewport.dart';
import 'package:adaptive_viewport/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

ScreenProfile profile(String name) =>
    ScreenProfile.all.firstWhere((profile) => profile.name == name);

ScreenClass classOf(String name) => ScreenClass.of(profile(name).viewport);

void main() {
  test('width classes follow the Material 3 breakpoints', () {
    expect(WidthClass.of(599), WidthClass.compact);
    expect(WidthClass.of(600), WidthClass.medium);
    expect(WidthClass.of(839), WidthClass.medium);
    expect(WidthClass.of(840), WidthClass.expanded);
    expect(WidthClass.of(1199), WidthClass.expanded);
    expect(WidthClass.of(1200), WidthClass.large);
    expect(WidthClass.large.atLeast(WidthClass.expanded), isTrue);
    expect(WidthClass.medium.atLeast(WidthClass.expanded), isFalse);
  });

  test('a phone upright is compact and touch', () {
    final screen = classOf('iPhone 17 Pro portrait');
    expect(screen.width, WidthClass.compact);
    expect(screen.input, InputKind.touch);
    expect(screen.posture, Posture.flat);
    expect(screen.isWide, isFalse);
  });

  test('a phone on its side is wide but short, so not two panes', () {
    for (final name in [
      'iPhone 17 Pro landscapeLeft',
      'Pixel 9 landscape',
      'Galaxy Z Fold 4 cover landscape',
    ]) {
      final screen = classOf(name);
      expect(screen.width.atLeast(WidthClass.expanded), isTrue, reason: name);
      expect(screen.isShortLandscape, isTrue, reason: name);
      expect(screen.isWide, isFalse, reason: name);
    }
  });

  test('tablets, unfolded foldables on their side and desktops are wide', () {
    for (final name in [
      'iPad landscape',
      'iPad Pro 13 landscape',
      'iPhone Duo inner landscape',
      'Android tablet landscape',
      'macOS window',
      'Windows laptop window',
    ]) {
      expect(classOf(name).isWide, isTrue, reason: name);
    }
    for (final name in [
      'iPad portrait',
      'iPad Split View third',
      'Galaxy Z Fold 4 inner book',
      'macOS narrow window',
      'macOS short window',
    ]) {
      expect(classOf(name).isWide, isFalse, reason: name);
    }
  });

  test('postures come from the folds the system reports', () {
    expect(classOf('Galaxy Z Fold 4 inner tabletop').posture, Posture.tabletop);
    expect(classOf('Galaxy Z Flip 4 half-folded').posture, Posture.tabletop);
    expect(classOf('iPhone Duo inner half-folded').posture, Posture.tabletop);
    expect(classOf('Galaxy Z Fold 4 inner book').posture, Posture.book);
    // A fold lying flat is just screen.
    expect(classOf('Pixel Fold inner flat').posture, Posture.flat);
  });

  test('desktops take a pointer; phones and tablets touch', () {
    for (final profile in ScreenProfile.all) {
      expect(
        ScreenClass.of(profile.viewport).isPointer,
        profile.isDesktop,
        reason: profile.name,
      );
    }
  });

  test('chrome comes back on a tap for touch, on a move for a pointer', () {
    expect(ChromePolicy.of(InputKind.touch).revealOnTap, isTrue);
    expect(ChromePolicy.of(InputKind.touch).revealOnHover, isFalse);
    expect(ChromePolicy.of(InputKind.pointer).revealOnHover, isTrue);
    expect(
      ChromePolicy.pointer.hideAfter,
      lessThan(ChromePolicy.touch.hideAfter),
    );
  });

  test('a viewport without a platform takes the running one', () {
    final viewport = ScreenViewport.fromMediaQuery(
      const MediaQueryData(size: Size(1280, 800)),
    );
    expect(viewport.platform, isNull);
    expect(ScreenClass.of(viewport).width, WidthClass.large);
  });
}
