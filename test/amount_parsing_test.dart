import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/features/transactions/presentation/quick_add_sheet.dart';

void main() {
  group('parseAmountInput', () {
    test('plain numbers', () {
      expect(parseAmountInput('1234'), 1234);
      expect(parseAmountInput('1234.50'), 1234.50);
      expect(parseAmountInput(' 99.9 '), 99.9);
      expect(parseAmountInput(''), isNull);
    });

    test('US grouping (comma thousands, dot decimal)', () {
      expect(parseAmountInput('1,234.50'), 1234.50);
      expect(parseAmountInput('1,234,567.89'), 1234567.89);
    });

    test('European/LatAm grouping (dot thousands, comma decimal)', () {
      // Regression: this used to strip the comma → 1.23450 → 1.2345.
      expect(parseAmountInput('1.234,50'), 1234.50);
      expect(parseAmountInput('1.234.567,89'), 1234567.89);
    });

    test('comma as a lone decimal mark', () {
      expect(parseAmountInput('1234,5'), 1234.5);
      expect(parseAmountInput('0,99'), 0.99);
    });
  });
}
