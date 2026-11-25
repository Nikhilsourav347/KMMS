import 'package:flutter_test/flutter_test.dart';
import 'package:ukm/core/domain.dart';

void main() {
  group('Asia/Kolkata shift windows', () {
    void check(String instant, String date, Shift shift) {
      final window = ShiftWindow.at(DateTime.parse(instant));
      expect(isoDate(window.date), date);
      expect(window.shift, shift);
    }

    test('night shift belongs to its starting date across midnight', () {
      check('2026-11-24T18:30:00Z', '2026-11-24', Shift.night);
      check('2026-11-25T02:59:59Z', '2026-11-24', Shift.night);
    });

    test('08:30 and 20:30 IST are exact cutoffs', () {
      check('2026-11-25T03:00:00Z', '2026-11-25', Shift.morning);
      check('2026-11-25T14:59:59Z', '2026-11-25', Shift.morning);
      check('2026-11-25T15:00:00Z', '2026-11-25', Shift.night);
    });
  });

  test('calculations use exact grams and format fractional kilograms', () {
    final ordered = grams('500.001');
    final produced = grams('200.001') + grams('100');
    expect(kg(produced), '300.001');
    expect(kg(ordered - produced), '200');
    expect(percent(produced, ordered), '60.0%');
    expect(kg(-grams('0.125')), '-0.125');
    expect(parseGrams('0.0001'), isNull);
    expect(parseGrams('1e2'), isNull);
  });

  test('each role receives its required module set', () {
    expect(
      Module.values.where((m) => m.availableTo(StaffRole.manager)),
      Module.values,
    );
    expect(Module.values.where((m) => m.availableTo(StaffRole.admin)), [
      Module.machines,
      Module.schedule,
      Module.reports,
      Module.profile,
    ]);
  });
}
