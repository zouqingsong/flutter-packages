import 'package:adaptive_viewport/adaptive_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PalettePlan plan(double room, List<PaletteGroup> groups) =>
      PalettePlanner.plan(PaletteRequest(room: room, groups: groups));

  // The drawing palette: tools (with shapes and measures folded behind two
  // buttons), colours (one swatch), history, finish.
  const drawing = [
    PaletteGroup(width: 360, compactWidth: 200),
    PaletteGroup(width: 312, compactWidth: 80),
    PaletteGroup(width: 160),
    PaletteGroup(width: 80),
  ];

  test('a wide window has one row, nothing folded', () {
    final result = plan(1000, drawing);
    expect(result.rows, [
      [0, 1, 2, 3],
    ]);
    expect(result.compact, everyElement(isFalse));
    expect(result.fits, isTrue);
  });

  test('folds a group only where that saves a row', () {
    // 360 + 8 + 312 = 680 needs two rows in full; folded, 200 + 80 + 160 +
    // 80 + 24 = 544 fits one.
    final result = plan(560, drawing);
    expect(result.rows.length, 1);
    expect(result.compact, [true, true, false, false]);

    // Upright phone: two rows either way, so it folds what keeps two.
    final phone = plan(362, drawing);
    expect(phone.rows.length, 2);
    expect(phone.fits, isTrue);
  });

  test('the narrowest phone still fits every group without scrolling', () {
    final result = plan(280, drawing);
    expect(result.fits, isTrue);
    for (final row in result.rows) {
      var width = 0.0;
      for (final i in row) {
        final group = drawing[i];
        width += result.compact[i] ? group.compactWidth! : group.width;
      }
      width += (row.length - 1) * 8;
      expect(width, lessThanOrEqualTo(280));
    }
  });

  test('groups keep their order across rows', () {
    final result = plan(300, drawing);
    expect(result.rows.expand((row) => row).toList(), [0, 1, 2, 3]);
  });

  test('a group wider than the room even compact does not fit', () {
    final result = plan(150, drawing);
    expect(result.fits, isFalse);
  });

  test('height counts rows and the gaps between them', () {
    final result = plan(280, drawing);
    expect(
      PalettePlanner.heightOf(result, rowHeight: 44),
      result.rows.length * 44 + (result.rows.length - 1) * 8,
    );
  });
}
