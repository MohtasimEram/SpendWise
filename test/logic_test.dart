import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/models.dart';
import 'package:spendwise/screens/add.dart';
import 'package:spendwise/ui.dart';

void main() {
  group('parseAmount', () {
    test('accepts common formats', () {
      expect(parseAmount('12'), 12);
      expect(parseAmount('12.5'), 12.5);
      expect(parseAmount('12,50'), 12.5);
      expect(parseAmount('1,234.56'), 1234.56);
      expect(parseAmount('1.234,56'), 1234.56);
      expect(parseAmount('1,234'), 1234);
    });
    test('rejects garbage', () {
      for (final s in ['', '0', '-5', 'NaN', 'Infinity', '1e9', 'abc', '99999999999999']) {
        expect(parseAmount(s), isNull, reason: s);
      }
    });
    test('signed', () => expect(parseAmount('-40', allowNegative: true), -40));
  });

  group('Group', () {
    test('equal split sums to zero and settles', () {
      final g = Group('g', 'Trip', ['A', 'B', 'C'], [
        {'title': 'Dinner', 'amount': 100.0, 'paidBy': 'A'}
      ], []);
      expect(g.balances.values.fold(0.0, (a, b) => a + b).abs() < 1e-9, isTrue);
      final d = g.debts;
      expect(d.length, 2);
      expect(d.fold(0.0, (a, x) => a + x.$3), closeTo(66.67, 0.011));
    });
    test('settling clears debts', () {
      final g = Group('g', 'x', ['A', 'B'], [
        {'amount': 10.0, 'paidBy': 'A'}
      ], [
        {'from': 'B', 'to': 'A', 'amount': 5.0}
      ]);
      expect(g.debts, isEmpty);
    });
  });

  group('Recurring', () {
    Recurring r(String f, DateTime n, int a) => Recurring(id: 'r', title: 't', amount: 1, currency: 'USD', income: false, cat: 'c', freq: f, next: n, anchor: a);
    test('monthly keeps anchor day through February', () {
      var d = DateTime(2025, 1, 31);
      final rule = r('monthly', d, 31);
      d = rule.advance(d);
      expect(d, DateTime(2025, 2, 28));
      d = rule.advance(d);
      expect(d, DateTime(2025, 3, 31));
    });
    test('yearly leap day', () => expect(r('yearly', DateTime(2024, 2, 29), 29).advance(DateTime(2024, 2, 29)), DateTime(2025, 2, 28)));
  });

  group('receipt parsing', () {
    test('finds total and ISO date', () {
      final x = parseReceipt('Corner Cafe\nSubtotal 10.00\nTOTAL 11.50\n2024-03-05');
      expect(x.merchant, 'Corner Cafe');
      expect(x.total, 11.5);
      expect(x.date, DateTime(2024, 3, 5));
    });
    test('rejects impossible dates', () => expect(parseReceipt('Shop\nTotal 5.00\n31/02/2024').date, isNull));
  });
}
