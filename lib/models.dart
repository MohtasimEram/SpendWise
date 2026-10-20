import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Defensive readers: a malformed document must never crash the app.
double asDouble(dynamic v) {
  final x = v is num ? v.toDouble() : 0.0;
  return x.isFinite ? x : 0.0;
}

String _s(dynamic v, [String d = '']) => v is String ? v : d;
DateTime _dt(dynamic v) => v is Timestamp ? v.toDate() : DateTime.now();
List<String> _strs(dynamic v) => v is List ? [for (final e in v) '$e'] : <String>[];
List<Map<String, dynamic>> _maps(dynamic v) => v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : <Map<String, dynamic>>[];

/// A single income or expense. [amount] is in [currency]; [base] is the
/// amount converted to the user's base currency (used for all reports).
class Txn {
  final String id, currency, cat, note;
  final double amount, base;
  final bool income;
  final DateTime date;
  final List<String> tags;
  const Txn({required this.id, required this.amount, required this.currency, required this.base, required this.income, required this.cat, required this.date, this.note = '', this.tags = const []});
  factory Txn.fromMap(String id, Map<String, dynamic> m) => Txn(
      id: id, amount: asDouble(m['amount']), currency: _s(m['currency'], 'USD'), base: asDouble(m['base']),
      income: m['income'] == true, cat: _s(m['cat'], 'def_other'), date: _dt(m['date']),
      note: _s(m['note']), tags: _strs(m['tags']));
  Map<String, dynamic> toMap() => {'amount': amount, 'currency': currency, 'base': base, 'income': income, 'cat': cat, 'date': Timestamp.fromDate(date), 'note': note, 'tags': tags};
}

class Category {
  final String id, name, icon;
  final int color;
  final bool income;
  final String? parent;
  const Category(this.id, this.name, this.icon, this.color, {this.income = false, this.parent});
  factory Category.fromMap(String id, Map<String, dynamic> m) => Category(id, _s(m['name']), _s(m['icon'], 'other'), m['color'] is int ? m['color'] as int : 0xFF94A3B8, income: m['income'] == true, parent: m['parent'] is String ? m['parent'] as String : null);
  Map<String, dynamic> toMap() => {'name': name, 'icon': icon, 'color': color, 'income': income, 'parent': parent};
  static const other = Category('def_other', 'Other', 'other', 0xFF94A3B8);
}

/// Budget doc id == category id, or 'all' for overall spending.
class Budget {
  final String id;
  final double limit;
  final bool weekly;
  const Budget(this.id, this.limit, this.weekly);
  factory Budget.fromMap(String id, Map<String, dynamic> m) => Budget(id, asDouble(m['limit']), m['weekly'] == true);
  Map<String, dynamic> toMap() => {'limit': limit, 'weekly': weekly};
}

class Recurring {
  final String id, title, currency, cat, freq;
  final double amount;
  final bool income;
  final DateTime next;

  /// Day of month the schedule is anchored to, so "31st" doesn't drift to the
  /// 28th forever after passing through February.
  final int anchor;
  const Recurring({required this.id, required this.title, required this.amount, required this.currency, required this.income, required this.cat, required this.freq, required this.next, required this.anchor});
  factory Recurring.fromMap(String id, Map<String, dynamic> m) {
    final next = _dt(m['next']);
    final day = m['day'];
    return Recurring(
        id: id, title: _s(m['title']), amount: asDouble(m['amount']), currency: _s(m['currency'], 'USD'), income: m['income'] == true,
        cat: _s(m['cat'], 'def_other'), freq: _s(m['freq'], 'monthly'), next: next, anchor: day is int && day >= 1 && day <= 31 ? day : next.day);
  }
  Map<String, dynamic> toMap() => {'title': title, 'amount': amount, 'currency': currency, 'income': income, 'cat': cat, 'freq': freq, 'next': Timestamp.fromDate(next), 'day': anchor};

  static int _dim(int y, int m) => DateTime(y, m + 1, 0).day;

  DateTime advance(DateTime d) {
    switch (freq) {
      case 'daily':
        return DateTime(d.year, d.month, d.day + 1, d.hour, d.minute);
      case 'weekly':
        return DateTime(d.year, d.month, d.day + 7, d.hour, d.minute);
      case 'yearly':
        final first = DateTime(d.year + 1, d.month, 1);
        return DateTime(first.year, first.month, min(anchor, _dim(first.year, first.month)), d.hour, d.minute);
      default:
        final first = DateTime(d.year, d.month + 1, 1);
        return DateTime(first.year, first.month, min(anchor, _dim(first.year, first.month)), d.hour, d.minute);
    }
  }
}

class Goal {
  final String id, name;
  final double target, saved;
  const Goal(this.id, this.name, this.target, this.saved);
  factory Goal.fromMap(String id, Map<String, dynamic> m) => Goal(id, _s(m['name']), asDouble(m['target']), asDouble(m['saved']));
  Map<String, dynamic> toMap() => {'name': name, 'target': target, 'saved': saved};
}

/// Asset or liability for net-worth tracking.
class Account {
  final String id, name;
  final double balance;
  final bool liability;
  const Account(this.id, this.name, this.balance, this.liability);
  factory Account.fromMap(String id, Map<String, dynamic> m) => Account(id, _s(m['name']), asDouble(m['balance']), m['liability'] == true);
  Map<String, dynamic> toMap() => {'name': name, 'balance': balance, 'liability': liability};
}

/// Shared-expense group (roommates, trips). Equal split between members.
/// All maths is done in integer cents so balances always sum to exactly zero.
class Group {
  final String id, name;
  final List<String> members;
  final List<Map<String, dynamic>> expenses, settles;
  const Group(this.id, this.name, this.members, this.expenses, this.settles);
  factory Group.fromMap(String id, Map<String, dynamic> m) => Group(id, _s(m['name']), _strs(m['members']), _maps(m['expenses']), _maps(m['settles']));
  Map<String, dynamic> toMap() => {'name': name, 'members': members, 'expenses': expenses, 'settles': settles};

  static int _c(dynamic v) => (asDouble(v) * 100).round();

  Map<String, int> get _cents {
    final b = {for (final m in members) m: 0};
    final n = members.length;
    if (n == 0) return b;
    for (final e in expenses) {
      final total = _c(e['amount']);
      final payer = '${e['paidBy']}';
      b[payer] = (b[payer] ?? 0) + total;
      final share = total ~/ n, rem = total % n;
      for (var i = 0; i < n; i++) {
        b[members[i]] = (b[members[i]] ?? 0) - share - (i < rem ? 1 : 0);
      }
    }
    for (final s in settles) {
      final a = _c(s['amount']);
      final from = '${s['from']}', to = '${s['to']}';
      b[from] = (b[from] ?? 0) + a;
      b[to] = (b[to] ?? 0) - a;
    }
    return b;
  }

  Map<String, double> get balances => _cents.map((k, v) => MapEntry(k, v / 100));

  /// Minimal "who pays whom" list: (debtor, creditor, amount).
  List<(String, String, double)> get debts {
    final b = _cents;
    final deb = b.keys.where((k) => b[k]! < 0).toList()..sort((x, y) => b[x]!.compareTo(b[y]!));
    final cre = b.keys.where((k) => b[k]! > 0).toList()..sort((x, y) => b[y]!.compareTo(b[x]!));
    final out = <(String, String, double)>[];
    var i = 0, j = 0;
    while (i < deb.length && j < cre.length) {
      final a = deb[i], c = cre[j];
      final amt = min(-b[a]!, b[c]!);
      out.add((a, c, amt / 100));
      b[a] = b[a]! + amt;
      b[c] = b[c]! - amt;
      if (b[a] == 0) i++;
      if (b[c] == 0) j++;
    }
    return out;
  }
}
