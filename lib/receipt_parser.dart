import 'dart:math';
import 'dart:ui' show Rect;
import 'ui.dart' show parseAmount;

/// One line of OCR output with its position in the photo.
class OcrLine {
  const OcrLine(this.text, this.box);
  final String text;
  final Rect box;
}

class ReceiptData {
  const ReceiptData({this.merchant, this.total, this.date, this.dateHasTime = false, this.currency, this.confident = false});
  final String? merchant;
  final double? total;
  final DateTime? date;
  final bool dateHasTime;
  /// ISO code when the receipt makes it obvious (৳ / Tk / "Taka" → BDT, $ → USD, ...).
  final String? currency;
  /// True when the total came from a "Total / Amount due ..." line (not a best guess).
  final bool confident;
}

const _supported = ['USD', 'EUR', 'GBP', 'BDT', 'INR', 'JPY', 'AUD', 'CAD', 'SGD', 'AED', 'SAR', 'MYR', 'CNY', 'CHF', 'TRY'];

// ───────────────────────── text normalisation ─────────────────────────
String _ascii(String s) {
  const bn = '০১২৩৪৫৬৭৮৯', dv = '०१२३४५६७८९';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    var i = bn.indexOf(ch);
    if (i < 0) i = dv.indexOf(ch);
    b.write(i >= 0 ? '$i' : ch);
  }
  return b.toString();
}

/// OCR often reads 0 as O and 1 as l/I inside numbers ("6,5O4", "1S-1O-2O26").
String _fixDigits(String row) => row.split(' ').map((t) {
      if (!RegExp(r'^[\d,.\-:/OoIl]+$').hasMatch(t) || RegExp(r'\d').allMatches(t).length < 2) return t;
      return t.replaceAll(RegExp(r'[Oo]'), '0').replaceAll(RegExp(r'[Il]'), '1');
    }).join(' ');

class _Row {
  _Row(this.text, this.top, this.height);
  final String text;
  final double top, height;
}

/// Groups OCR lines that sit on the same visual row (a label on the left and
/// its value on the right are usually separate OCR lines), tolerant of a
/// slightly tilted photo.
List<_Row> _rows(List<OcrLine> lines) {
  double gap(Rect a, Rect b) => max(0.0, max(a.left, b.left) - min(a.right, b.right));
  final ls = [...lines.where((l) => l.text.trim().isNotEmpty)]..sort((a, b) => a.box.center.dy.compareTo(b.box.center.dy));
  final rows = <List<OcrLine>>[];
  for (final l in ls) {
    List<OcrLine>? hit;
    for (final r in rows.reversed.take(4)) {
      final near = r.reduce((a, b) => gap(a.box, l.box) <= gap(b.box, l.box) ? a : b);
      final h = min(near.box.height, l.box.height);
      if ((near.box.center.dy - l.box.center.dy).abs() < h * .65) { hit = r; break; }
    }
    if (hit == null) { rows.add([l]); } else { hit.add(l); }
  }
  return [for (final r in rows) _makeRow(r)];
}

_Row _makeRow(List<OcrLine> r) {
  r.sort((a, b) => a.box.left.compareTo(b.box.left));
  final txt = _fixDigits(_ascii(r.map((l) => l.text.trim()).join(' ')).replaceAll(RegExp(r'\s+'), ' ').trim());
  return _Row(txt, r.map((l) => l.box.top).reduce(min), r.map((l) => l.box.height).reduce(max));
}

// ───────────────────────── amounts ─────────────────────────
final _currencyWords = RegExp(r'\b(?:tk|bdt|usd|eur|gbp|inr|rs|taka)\b\.?|[৳$€£₹¥]', caseSensitive: false);
final _dateLike = RegExp(r'\d{1,4}\s?[-/.]\s?\d{1,2}\s?[-/.]\s?\d{2,4}');
final _timeLike = RegExp(r'\d{1,2}:\d{2}(?::\d{2})?\s?(?:[AaPp]\.?[Mm]\.?)?');
final _amtRe = RegExp(r'(?<![A-Za-z\d.,])(\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)(?![A-Za-z\d])');

/// Money values on a row, left to right. Dates, times, phone numbers and
/// alphanumeric codes (SKU / invoice numbers) are ignored.
List<double> _amounts(String row) {
  final t = row.replaceAll(_dateLike, ' ').replaceAll(_timeLike, ' ').replaceAll(_currencyWords, ' ');
  final out = <double>[];
  for (final m in _amtRe.allMatches(t)) {
    final raw = m.group(1)!;
    if (raw.replaceAll(RegExp(r'\D'), '').length > 9) continue; // phone / account numbers
    if (RegExp(r'^0\d{6,}$').hasMatch(raw)) continue;
    final v = parseAmount(raw);
    if (v != null) out.add(v);
  }
  return out;
}

final _strongTotal = RegExp(r'grand\s*t[o0]ta[l1]|t[o0]ta[l1]\s*\(?\s*(amount|payable|due|bill|price|sales|incl|inc\b|with)|amount\s*(due|payable|to\s*pay)|net\s*(amount|payable|total|bill)|balance\s*due|payable|you\s*pay|(bill|invoice|order)\s*t[o0]ta[l1]');
final _plainTotal = RegExp(r'\bt[o0]ta[l1]\b');
final _dueOnly = RegExp(r'\bdue\b');
final _subTotal = RegExp(r'sub\s*-?\s*t[o0]ta[l1]');
final _badMoney = RegExp(r'\btax\b|\bvat\b|\bgst\b|discount|saving|change|tender|\bpaid\b|received|round|\btip\b|gratuity|points|deposit|advance|rebate|coupon|cashback|service\s*charge|delivery|shipping|\bfee\b|\bcash\b|\bcard\b|visa|master|bkash|nagad|rocket|upay|payment');
final _badCount = RegExp(r'\bitems?\b|\bqty\b|quantity|\bpcs\b');
final _skipRow = RegExp(r'invoice\s*no|\binv\b|order\s*(no|id|#)|\bsku\b|\btel\b|phone|mobile|\bid\b|\bref\b|\bbin\b|\btin\b|\bnid\b|account|\btrx\b|\btxn\b|auth|serial|token|table');

({double? total, bool confident}) _findTotal(List<_Row> rows) {
  final cands = <({double v, double score, int row})>[];
  for (var i = 0; i < rows.length; i++) {
    final t = rows[i].text.toLowerCase();
    double w = 0;
    if (_strongTotal.hasMatch(t)) {
      w = 100;
    } else if (_subTotal.hasMatch(t)) {
      w = 20;
    } else if (_plainTotal.hasMatch(t) && !_badMoney.hasMatch(t)) {
      w = 80;
    } else if (_dueOnly.hasMatch(t) && !_badMoney.hasMatch(t)) {
      w = 55;
    }
    if (w == 0) continue;
    var vals = _amounts(rows[i].text);
    // Label and value on separate rows (value printed underneath).
    if (vals.isEmpty && i + 1 < rows.length && !RegExp(r'[A-Za-z]{2,}').hasMatch(rows[i + 1].text.replaceAll(_currencyWords, ''))) {
      vals = _amounts(rows[i + 1].text);
    }
    if (vals.isEmpty) continue;
    // "Total items: 3" is a count, not money - but "Total 3 items 25.00" is fine.
    if (w < 100 && _badCount.hasMatch(t) && vals.length < 2 && !RegExp(r'[.,]\d{2}(?!\d)').hasMatch(rows[i].text)) continue;
    cands.add((v: vals.last, score: w + i / rows.length * 8, row: i));
  }
  if (cands.isNotEmpty) {
    // Several lines agreeing on one value (Total = Due) is strong evidence.
    double best = -1, bestV = 0;
    for (final c in cands) {
      final agree = cands.where((o) => o.row != c.row && (o.v - c.v).abs() < .005 && o.score >= 55).length;
      final s = c.score + 22 * agree;
      if (s > best) { best = s; bestV = c.v; }
    }
    return (total: bestV, confident: true);
  }
  // No labelled total: largest plausible amount that is not an id / phone / date row.
  double? mx;
  for (final r in rows) {
    final t = r.text.toLowerCase();
    if (_skipRow.hasMatch(t) || _badMoney.hasMatch(t) || _badCount.hasMatch(t)) continue;
    for (final v in _amounts(r.text)) { if (v >= 1) mx = max(mx ?? 0.0, v); }
  }
  return (total: mx, confident: false);
}

// ───────────────────────── date & time ─────────────────────────
const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

DateTime? _valid(int y, int m, int d, DateTime now) {
  if (y < 2000 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  if (dt.month != m || dt.day != d) return null; // e.g. 31 Feb rolled over
  if (dt.isAfter(now.add(const Duration(days: 1)))) return null;
  return dt;
}

int _yy(String s) => s.length == 2 ? 2000 + int.parse(s) : int.parse(s);

DateTime? _dateIn(String t, DateTime now) {
  final iso = RegExp(r'(\d{4})\s?[-/.]\s?(\d{1,2})\s?[-/.]\s?(\d{1,2})').firstMatch(t);
  if (iso != null) {
    final d = _valid(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!), now);
    if (d != null) return d;
  }
  final dmy = RegExp(r'(?<!\d)(\d{1,2})\s?[-/.]\s?(\d{1,2})\s?[-/.]\s?(\d{4}|\d{2})(?!\d)').firstMatch(t);
  if (dmy != null) {
    final a = int.parse(dmy[1]!), b = int.parse(dmy[2]!), y = _yy(dmy[3]!);
    final d = _valid(y, b, a, now) ?? _valid(y, a, b, now); // dd/mm first, then mm/dd
    if (d != null) return d;
  }
  final mon = _months.join('|');
  final dMonY = RegExp('(\\d{1,2})(?:st|nd|rd|th)?[\\s\\-/.]*($mon)[a-z]*\\.?[\\s\\-/.,]*(\\d{4}|\\d{2})', caseSensitive: false).firstMatch(t);
  if (dMonY != null) {
    final d = _valid(_yy(dMonY[3]!), _months.indexOf(dMonY[2]!.toLowerCase()) + 1, int.parse(dMonY[1]!), now);
    if (d != null) return d;
  }
  final monDY = RegExp('($mon)[a-z]*\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})', caseSensitive: false).firstMatch(t);
  if (monDY != null) {
    final d = _valid(int.parse(monDY[3]!), _months.indexOf(monDY[1]!.toLowerCase()) + 1, int.parse(monDY[2]!), now);
    if (d != null) return d;
  }
  return null;
}

({int h, int m})? _timeIn(String t) {
  for (final x in RegExp(r'(?<!\d)(\d{1,2}):(\d{2})(?::\d{2})?\s?([AaPp])?\.?[Mm]?\.?').allMatches(t)) {
    var h = int.parse(x[1]!);
    final m = int.parse(x[2]!);
    final ap = x[3]?.toLowerCase();
    if (m > 59) continue;
    if (ap != null) {
      if (h < 1 || h > 12) continue;
      if (ap == 'p' && h < 12) h += 12;
      if (ap == 'a' && h == 12) h = 0;
    } else if (h > 23) {
      continue;
    }
    return (h: h, m: m);
  }
  return null;
}

({DateTime? date, bool hasTime}) _findDate(List<_Row> rows, DateTime now) {
  // Prefer a row labelled "date"; otherwise the first row that holds a valid date.
  final order = [...rows.where((r) => RegExp(r'\bd[a2]te\b', caseSensitive: false).hasMatch(r.text)), ...rows];
  for (final r in order) {
    final d = _dateIn(r.text, now);
    if (d == null) continue;
    final tm = _timeIn(r.text) ?? _timeIn(rows.map((x) => x.text).join(' '));
    return tm == null ? (date: d, hasTime: false) : (date: DateTime(d.year, d.month, d.day, tm.h, tm.m), hasTime: true);
  }
  return (date: null, hasTime: false);
}

// ───────────────────────── merchant ─────────────────────────
final _junk = RegExp(r'\b(invoice|receipt|bill|billing|tax|vat|date|time|tel|phone|mobile|email|e-mail|www|http|order|cashier|customer|address|road|street|floor|block|sector|city|welcome|thank|thanks|memo|item|items|qty|price|total|amount|subtotal|gstin|reg|copy|duplicate|original|table|guest|server|pos|terminal|tran|trx|sl|description|warranty)\b|@|\.com|\.net|\.org|shop\s*\d|\b(dhaka|chittagong|chattogram)\b|\d{5,}', caseSensitive: false);

String? _findMerchant(List<OcrLine> lines) {
  final ls = lines.where((l) => l.text.trim().isNotEmpty).toList();
  if (ls.isEmpty) return null;
  final bottom = ls.map((l) => l.box.bottom).reduce(max), top0 = ls.map((l) => l.box.top).reduce(min);
  final limit = top0 + (bottom - top0) * .35;
  bool ok(OcrLine l) {
    final t = _ascii(l.text).trim();
    final letters = RegExp(r'[A-Za-z]').allMatches(t).length;
    final digits = RegExp(r'\d').allMatches(t).length;
    return t.length >= 3 && t.length <= 45 && letters >= 3 && digits <= t.length * .3 && !_junk.hasMatch(t.toLowerCase());
  }

  final byPos = [...ls]..sort((a, b) => a.box.top.compareTo(b.box.top));
  var cands = byPos.where((l) => l.box.center.dy <= limit && ok(l)).take(6).toList();
  if (cands.isEmpty) cands = byPos.take(8).where(ok).toList();
  if (cands.isEmpty) return null;
  final maxH = cands.map((l) => l.box.height).reduce(max);
  final pick = cands.firstWhere((l) => l.box.height >= maxH * .7); // names are printed larger; topmost wins ties
  return _ascii(pick.text).replaceAll(RegExp(r'^[^A-Za-z0-9]+|[\s\-:,.|*]+$'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ───────────────────────── currency ─────────────────────────
String? _findCurrency(String text) {
  final t = text;
  if (RegExp(r'৳|\btk\b\.?|\btaka\b|\bbdt\b', caseSensitive: false).hasMatch(t)) return 'BDT';
  if (RegExp(r'€').hasMatch(t)) return 'EUR';
  if (RegExp(r'£').hasMatch(t)) return 'GBP';
  if (RegExp(r'₹|\brupees?\b').hasMatch(t.toLowerCase())) return 'INR';
  for (final c in _supported) { if (RegExp('\\b$c\\b').hasMatch(t)) return c; }
  if (RegExp(r'\$').hasMatch(t)) return 'USD';
  return null;
}

// ───────────────────────── public API ─────────────────────────
ReceiptData parseReceiptLines(List<OcrLine> lines, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final rows = _rows(lines);
  final total = _findTotal(rows);
  final date = _findDate(rows, n);
  return ReceiptData(
    merchant: _findMerchant(lines),
    total: total.total,
    date: date.date,
    dateHasTime: date.hasTime,
    currency: _findCurrency(_ascii(lines.map((l) => l.text).join('\n'))),
    confident: total.confident,
  );
}

/// Plain-text variant (no geometry): every text line is its own row.
ReceiptData parseReceiptText(String text, {DateTime? now}) {
  final raw = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final lines = [for (final (i, l) in raw.indexed) OcrLine(l, Rect.fromLTWH(0, i * 24.0, max(40.0, l.length * 9.0), 18))];
  return parseReceiptLines(lines, now: now);
}
