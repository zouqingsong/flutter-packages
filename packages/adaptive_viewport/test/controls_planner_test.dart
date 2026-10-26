import 'package:adaptive_viewport/adaptive_viewport.dart';
import 'package:adaptive_viewport/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// A camera's controls, the most a live page carries: four tools, the shutter
/// and record, and two view toggles — each tool a 44 × 48 touch target.
ControlsRequest camera(double room, {required bool rail, int tools = 4}) {
  // Down a rail a button is 48 long and 44 thick; across a bar, 44 long and
  // 48 thick.
  final extent = rail ? 48.0 : 44.0;
  final thickness = rail ? 44.0 : 48.0;
  return ControlsRequest(
    room: room,
    tools: ControlGroup.run(
      tools,
      extent: extent,
      thickness: thickness,
      padding: rail ? 8 : 12,
    ),
    primary: rail
        ? const ControlGroup(length: 60 + 12 + 50, thickness: 60)
        : const ControlGroup(length: 60 + 24 + 50, thickness: 60),
    view: ControlGroup.run(
      2,
      extent: extent,
      thickness: thickness,
      padding: rail ? 8 : 12,
    ),
  );
}

void main() {
  group('folds in order, taking the first that fits', () {
    const tools = ControlGroup(length: 100, thickness: 40);
    const primary = ControlGroup(length: 120, thickness: 60);
    const view = ControlGroup(length: 80, thickness: 40);
    ControlsPlan at(double room) => ControlsPlanner.plan(
          ControlsRequest(
            room: room,
            tools: tools,
            primary: primary,
            view: view,
            gap: 10,
          ),
        );

    test('centred while both ends have the room of the longer one', () {
      // 120 + 2 × (100 + 10)
      expect(at(340).fold, ControlsFold.centred);
      expect(at(340).thickness, 60);
    });

    test('spread while the three fit end to end', () {
      // 100 + 120 + 80 + 2 × 10
      expect(at(339).fold, ControlsFold.spread);
      expect(at(320).fold, ControlsFold.spread);
      expect(at(320).thickness, 60);
    });

    test('folded into two lines below that', () {
      // max(100 + 10 + 80, 120)
      final plan = at(190);
      expect(plan.fold, ControlsFold.folded);
      expect(plan.twoLines, isTrue);
      expect(plan.thickness, 60 + 10 + 40);
      expect(at(319).fold, ControlsFold.folded);
    });

    test('regrouped when the tools and toggles do not fit on one line', () {
      // max(100, 120 + 10 + 80) = 210 does not fit 189 either: the plan says
      // so. With a shorter view group, regrouping fits where folding does
      // not.
      expect(at(189).fits, isFalse);
      final plan = ControlsPlanner.plan(
        const ControlsRequest(
          room: 180,
          tools: ControlGroup(length: 140, thickness: 40),
          primary: ControlGroup(length: 100, thickness: 60),
          view: ControlGroup(length: 70, thickness: 40),
          gap: 10,
        ),
      );
      expect(plan.fold, ControlsFold.regrouped);
      expect(plan.fits, isTrue);
      expect(plan.thickness, 60 + 10 + 40);
    });

    test('too short for any: the fold that overflows least', () {
      final plan = at(50);
      expect(plan.fits, isFalse);
      expect(plan.twoLines, isTrue);
    });
  });

  // The rule over every screen: wherever the stage puts the camera's
  // controls, they fit without scrolling — in a rail down a phone on its
  // side, in a bar under the picture upright, on the deck half-folded.
  group('a camera\'s controls fit without scrolling on', () {
    for (final screen in ScreenProfile.all) {
      for (final tools in [2, 4]) {
        test('$screen with $tools tools', () {
          final viewport = screen.viewport;
          final stage = StagePlanner.plan(
            StageRequest(
              viewport: viewport,
              wide: ScreenClass.of(viewport).isWide,
              fullscreen: false,
              hasRail: true,
            ),
          );
          if (stage.railBeside) {
            // The rail's own margin, 10 at each end, inside its padding.
            final room = screen.size.height - stage.railPadding.vertical - 20;
            final plan = ControlsPlanner.plan(
              camera(room, rail: true, tools: tools),
            );
            expect(plan.fits, isTrue, reason: '$plan in $room');
            // A second column still leaves the picture most of the window.
            expect(plan.thickness, lessThan(screen.size.width / 4));
          } else {
            // A bar the window's width, with 12 either side.
            final room = screen.size.width - screen.padding.horizontal - 24;
            final plan = ControlsPlanner.plan(
              camera(room, rail: false, tools: tools),
            );
            expect(plan.fits, isTrue, reason: '$plan in $room');
          }
        });
      }
    }
  });

  test('a Fold\'s cover on its side regroups the rail', () {
    final screen = ScreenProfile.all.firstWhere(
      (screen) => screen.name == 'Galaxy Z Fold 4 cover landscape',
    );
    final stage = StagePlanner.plan(
      StageRequest(
        viewport: screen.viewport,
        wide: false,
        fullscreen: false,
        hasRail: true,
      ),
    );
    final room = screen.size.height - stage.railPadding.vertical - 20;
    expect(
      ControlsPlanner.plan(camera(room, rail: true)).fold,
      ControlsFold.regrouped,
    );
  });

  test('a narrow Android phone upright regroups the bar', () {
    final screen = ScreenProfile.all.firstWhere(
      (screen) => screen.name == 'Android narrow portrait',
    );
    final room = screen.size.width - 24;
    expect(
      ControlsPlanner.plan(camera(room, rail: false)).fold,
      ControlsFold.regrouped,
    );
  });
}
