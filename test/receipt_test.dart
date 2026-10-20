import 'dart:ui' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/receipt_parser.dart';

void main() {
  final now = DateTime(2026, 10, 19);

  test('Bangladeshi invoice: whole-taka amounts, Total vs Subtotal vs Due', () {
    final r = parseReceiptText('''
Ez Gadgets Bangladesh
Shop 542, 5th Floor, Multiplan Center, Elephant Road, Dhaka.
Tel: 01340258608 | 01308995329
INVOICE
Invoice No: WOO-41681
Date: 15-10-2026, 07:00 PM
Billing To
John Doe
SL. Item Description Warranty Price Qty Total
1 ATK Blazing Sky F1 V2 Series Esports Wireless 1 year 6,499 1 6,499
Mouse - ULTIMATE - Black
(SKU: ATKF1V2UB)
Subtotal : 6,499
Total: 6,564
Paid: 0
Due: 6,564
Total in Words: Six Thousand Five Hundred Sixty Four Taka Only
''', now: now);
    expect(r.merchant, 'Ez Gadgets Bangladesh');
    expect(r.total, 6564);
    expect(r.confident, isTrue);
    expect(r.date, DateTime(2026, 10, 15, 19, 0));
    expect(r.dateHasTime, isTrue);
    expect(r.currency, 'BDT');
  });

  test('labels and values OCR\'d as separate lines are paired by position', () {
    Rect b(double x, double y, double w) => Rect.fromLTWH(x, y, w, 40);
    final r = parseReceiptLines([
      OcrLine('Ez Gadgets Bangladesh', b(390, 185, 520)),
      OcrLine('INVOICE', Rect.fromLTWH(1670, 205, 330, 70)),
      OcrLine('John Doe', b(1760, 485, 250)),
      OcrLine('Subtotal :', b(1620, 1050, 170)), OcrLine('6,499', b(1950, 1055, 100)),
      OcrLine('Total:', b(1625, 1125, 100)), OcrLine('6,564', b(1955, 1131, 100)), // slight tilt
      OcrLine('Paid:', b(1630, 1205, 90)), OcrLine('0', b(2040, 1211, 20)),
      OcrLine('Due:', b(1630, 1255, 80)), OcrLine('6,564', b(1960, 1259, 100)),
    ], now: now);
    expect(r.total, 6564);
    expect(r.merchant, 'Ez Gadgets Bangladesh');
  });

  test('supermarket receipt: VAT, cash and change are not the total', () {
    final r = parseReceiptText('SUPER MART\n123 Main Street\nMilk 2.50\nBread 1.20\nSUBTOTAL 3.70\nVAT 15% 0.56\nTOTAL 4.26\nCASH 5.00\nCHANGE 0.74\n05/03/2024 14:32', now: now);
    expect(r.merchant, 'SUPER MART');
    expect(r.total, 4.26);
    expect(r.date, DateTime(2024, 3, 5, 14, 32));
  });

  test('total including VAT, thousands and currency symbol', () {
    expect(parseReceiptText('Cafe Rio\nTotal (incl. 15% VAT) 115.00', now: now).total, 115);
    expect(parseReceiptText('Cafe Rio\nTOTAL ৳1,250.00', now: now).total, 1250);
    expect(parseReceiptText('Cafe Rio\nTotal Tk 1250', now: now).total, 1250);
    expect(parseReceiptText('Cafe Rio\nGrand Total 1.234,56', now: now).total, 1234.56);
  });

  test('OCR digit confusion and stacked label/value', () {
    expect(parseReceiptText('Shop One\nTotal: 1,2O0', now: now).total, 1200);
    expect(parseReceiptText('Shop One\nAmount Due\n87.40', now: now).total, 87.4);
  });

  test('unlabelled receipt falls back to the largest amount, not a phone number', () {
    final r = parseReceiptText('Bakery House\nTel 01712345678\nCake 450.00\nTea 60.00\n510.00', now: now);
    expect(r.total, 510);
    expect(r.confident, isFalse);
  });

  test('item counts are not totals', () => expect(parseReceiptText('Mart\nTotal items: 3\nTotal 42.00', now: now).total, 42));

  test('text dates', () {
    expect(parseReceiptText('Store\nTotal 5.00\n15 Oct 2026', now: now).date, DateTime(2026, 10, 15));
    expect(parseReceiptText('Store\nTotal 5.00\nOct 15, 2026', now: now).date, DateTime(2026, 10, 15));
  });
}
