import 'package:adaptive_viewport/deck_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Size room, {
    double scale = 1,
    VoidCallback? onPressed,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(
            child: SizedBox.fromSize(
              size: room,
              child: DeckActionPanel(actions: [
                for (var i = 0; i < 7; i++)
                  DeckAction(
                    icon: Icons.tune,
                    label: 'Action $i',
                    onPressed: onPressed ?? () {},
                    selected: i == 0,
                  ),
              ]),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('spare deck height reveals every labelled action and callback',
      (tester) async {
    var calls = 0;
    await pump(tester, const Size(320, 320), onPressed: () => calls++);
    for (var i = 0; i < 7; i++) {
      expect(find.text('Action $i'), findsOneWidget);
      await tester.tap(find.text('Action $i'));
    }
    expect(calls, 7);
    expect(find.byType(Scrollable), findsNothing);
    expect(find.byType(PopupMenuButton<int>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a shorter deck loses labels, not actions or tap targets',
      (tester) async {
    await pump(tester, const Size(320, 104));
    expect(find.byType(Tooltip), findsNWidgets(7));
    expect(find.byType(Text), findsNothing);
    for (var i = 0; i < 7; i++) {
      expect(tester.getSize(find.byTooltip('Action $i')), const Size(48, 48));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrower labelled tiles use spare rows before losing labels',
      (tester) async {
    await pump(tester, const Size(360, 160));
    expect(find.text('Action 6'), findsOneWidget);
    for (var i = 0; i < 7; i++) {
      expect(
        tester.getSize(find.byTooltip('Action $i')).width,
        DeckActionPanel.minimumTileWidth,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('only an even shorter deck falls back to a menu', (tester) async {
    var calls = 0;
    await pump(tester, const Size(320, 48), onPressed: () => calls++);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action 6'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('larger type is measured before choosing labelled tiles',
      (tester) async {
    await pump(tester, const Size(320, 400), scale: 2);
    expect(find.text('Action 6'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      DeckActionPanel.formFor(7, const Size(320, 250),
          textScaler: const TextScaler.linear(2)),
      DeckActionForm.icons,
    );
  });
}
