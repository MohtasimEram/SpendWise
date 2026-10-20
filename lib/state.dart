import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'export_util.dart';
import 'filter_font.dart';
import 'lock_service.dart';
import 'models.dart';
import 'ui.dart';

const _defaults = <Category>[
  Category('def_food', 'Food & Dining', 'food', 0xFFE08A3C),
  Category('def_transport', 'Transport', 'transport', 0xFF3E9BC4),
  Category('def_shopping', 'Shopping', 'shopping', 0xFFD9648C),
  Category('def_bills', 'Bills & Utilities', 'bills', 0xFFD4A62A),
  Category('def_health', 'Health', 'health', 0xFFD9574F),
  Category('def_fun', 'Entertainment', 'fun', 0xFF8A6FD1),
  Category('def_edu', 'Education', 'edu', 0xFF2BA39A),
  Category('def_travel', 'Travel', 'travel', 0xFF4F86D9),
  Category('def_home', 'Home & Rent', 'home', 0xFF6B73C9),
  Category('def_sub', 'Subscriptions', 'sub', 0xFFB06BC4),
  Category('def_coffee', 'Coffee', 'coffee', 0xFFB98355, parent: 'def_food'),
  Category('def_other', 'Other', 'other', 0xFF8C93A0),
  Category('def_salary', 'Salary', 'salary', 0xFF2E9E6B, income: true),
  Category('def_freelance', 'Freelance', 'freelance', 0xFF1FA6B8, income: true),
  Category('def_invest', 'Investments', 'invest', 0xFF5AAE45, income: true),
  Category('def_gift', 'Gifts', 'gift', 0xFFD98BB0, income: true),
];

double _r2(double v) => (v * 100).roundToDouble() / 100;

/// Single source of truth. Firestore snapshot listeners keep it in sync;
/// Firestore's local cache makes the whole app work offline and sync later.
///
/// NOTE: writes are intentionally NOT awaited - offline, a write's future
/// only completes once the server acknowledges it. Failures are surfaced
/// through [_err] instead.
class AppState extends ChangeNotifier {
  AppState(this.prefs) {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_attach, onError: (Object _) {
      authReady = true;
      notifyListeners();
    });
  }
  final SharedPreferences prefs;
  StreamSubscription<User?>? _authSub;
  User? user;
  bool authReady = false;
  List<Txn> txns = [];
  List<Category> cats = [];
  List<Budget> budgets = [];
  List<Recurring> recurring = [];
  List<Goal> goals = [];
  List<Account> accounts = [];
  List<Group> groups = [];
  Map<String, double> rates = {};
  final _subs = <StreamSubscription>[];
  final _loaded = <String>{};
  Map<String, Category> _catMap = {};
  bool _seeded = false, _ratesLoading = false;
  DateTime? _lastErr;

  @override
  void dispose() {
    _authSub?.cancel();
    for (final s in _subs) { s.cancel(); }
    super.dispose();
  }

  // ---- preferences ----
  String get base => prefs.getString('base') ?? 'USD';
  int get themeIdx => (prefs.getInt('theme') ?? 0).clamp(0, 2);
  ThemeMode get themeMode => ThemeMode.values[themeIdx];
  bool get lockOn => prefs.getBool('lock') ?? false;
  bool get bioOn => prefs.getBool('bio') ?? false;
  String get email => user?.email ?? '';
  Future<void> setBool(String k, bool v) async { await prefs.setBool(k, v); notifyListeners(); }
  Future<void> setTheme(int i) async { await prefs.setInt('theme', i); notifyListeners(); }
  // Profile prefs are keyed by user id so two accounts on one device never share a name/avatar.
  String get _uidKey => user?.uid ?? '';
  /// The nickname: stored one, else first word of the provider name, else the email prefix. Never contains spaces.
  String get displayName {
    final stored = sanitizeNick((prefs.getString('user_display_name_$_uidKey') ?? '').trim());
    if (stored.isNotEmpty) return stored;
    final fromProvider = sanitizeNick((user?.displayName ?? '').trim().split(RegExp(r'\s+')).first);
    if (fromProvider.isNotEmpty) return fromProvider;
    return sanitizeNick((user?.email ?? '').split('@').first);
  }
  String get avatarId => prefs.getString('avatar_$_uidKey') ?? 'initial';
  Future<void> setAvatar(String id) async { await prefs.setString('avatar_$_uidKey', id); notifyListeners(); }
  /// True when the account signs in with email + password (so a password can be changed in-app).
  bool get hasPassword => user?.providerData.any((p) => p.providerId == 'password') ?? false;

  void refreshUser() {
    user = FirebaseAuth.instance.currentUser;
    notifyListeners();
  }

  FilterFont get filterFont => FilterFont.parse(prefs.getString('filter_font'));
  Future<void> setFilterFont(FilterFont f) async {
    await f.preload(); // load first, so the switch never flashes a fallback font
    await prefs.setString('filter_font', f.name);
    notifyListeners();
  }

  /// Used right after sign-up, before [user] has been attached to this state.
  Future<void> setNicknameFor(String uid, String nick) async {
    final clean = sanitizeNick(nick.trim());
    await prefs.setString('user_display_name_$uid', clean);
    try { await FirebaseAuth.instance.currentUser?.updateDisplayName(clean); } catch (_) {}
    notifyListeners();
  }

  Future<void> setDisplayName(String n) async {
    final clean = sanitizeNick(n.trim());
    await prefs.setString('user_display_name_$_uidKey', clean);
    try { await user?.updateDisplayName(clean); } catch (_) {}
    notifyListeners();
  }

  // ---- session / sync ----
  void _attach(User? u) {
    final same = authReady && u?.uid == user?.uid;
    authReady = true;
    user = u;
    // One-time migration of the old device-wide display name to the signed-in account.
    final legacy = prefs.getString('user_display_name');
    if (u != null && legacy != null) {
      if (prefs.getString('user_display_name_${u.uid}') == null) prefs.setString('user_display_name_${u.uid}', legacy);
      prefs.remove('user_display_name');
    }
    if (same) { notifyListeners(); return; }
    for (final s in _subs) { s.cancel(); }
    _subs.clear();
    _loaded.clear();
    _seeded = false;
    txns = []; cats = []; budgets = []; recurring = []; goals = []; accounts = []; groups = [];
    _catMap = {};
    notifyListeners();
    if (u == null) return;
    _listen<Txn>('transactions', Txn.fromMap, (l) { l.sort((a, b) => b.date.compareTo(a.date)); txns = l; runRecurring(); });
    _listen<Category>('categories', Category.fromMap, (l) {
      cats = l;
      _catMap = {for (final c in l) c.id: c};
      if (l.isEmpty && !_seeded) { _seeded = true; _seed(); }
    });
    _listen<Budget>('budgets', Budget.fromMap, (l) => budgets = l);
    _listen<Recurring>('recurring', Recurring.fromMap, (l) { recurring = l; runRecurring(); });
    _listen<Goal>('goals', Goal.fromMap, (l) => goals = l);
    _listen<Account>('accounts', Account.fromMap, (l) => accounts = l);
    _listen<Group>('groups', Group.fromMap, (l) => groups = l);
    loadRates();
  }

  /// Called when the app returns to the foreground.
  void onResume() {
    if (user == null) return;
    loadRates();
    runRecurring();
  }

  Future<void> signOut() async {
    navKey.currentState?.popUntil((r) => r.isFirst);
    await cleanTempExports();
    await FirebaseAuth.instance.signOut();
  }

  CollectionReference<Map<String, dynamic>> _col(String n) => FirebaseFirestore.instance.collection('users').doc(user!.uid).collection(n);

  void _listen<T>(String c, T Function(String, Map<String, dynamic>) f, void Function(List<T>) set) {
    _subs.add(_col(c).snapshots().listen((s) {
      final out = <T>[];
      for (final d in s.docs) {
        try { out.add(f(d.id, d.data())); } catch (_) {/* skip a malformed document instead of losing the whole list */}
      }
      _loaded.add(c);
      set(out);
      notifyListeners();
    }, onError: (Object e) => _err(e)));
  }

  void _err(Object e) {
    debugPrint('SpendWise sync error: $e');
    final now = DateTime.now();
    if (_lastErr != null && now.difference(_lastErr!) < const Duration(seconds: 6)) return;
    _lastErr = now;
    final denied = e is FirebaseException && e.code == 'permission-denied';
    messengerKey.currentState?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(denied ? 'The server rejected that change. Please check the values and try again.' : "Sync problem. Your changes are saved on this device and will retry when you're online."),
    ));
  }

  void put(String c, String id, Map<String, dynamic> m) {
    if (user == null) return;
    _col(c).doc(id).set(m).catchError((Object e) { _err(e); });
  }

  /// Merge fields into an existing doc. Unlike [put] this never re-creates a
  /// document that was deleted in the meantime (e.g. on another device).
  void update(String c, String id, Map<String, dynamic> m) {
    if (user == null) return;
    _col(c).doc(id).update(m).catchError((Object e) { _err(e); });
  }

  void remove(String c, String id) {
    if (user == null) return;
    _col(c).doc(id).delete().catchError((Object e) { _err(e); });
  }

  // Transactions are updated optimistically so list animations (Dismissible)
  // see the change in the same frame instead of waiting for the snapshot.
  void saveTxn(Txn t) {
    txns = [...txns.where((x) => x.id != t.id), t]..sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    put('transactions', t.id, t.toMap());
  }

  void removeTxn(String id) {
    txns = txns.where((t) => t.id != id).toList();
    notifyListeners();
    remove('transactions', id);
  }

  String newId() => const Uuid().v4();
  void _seed() { for (final c in _defaults) { put('categories', c.id, c.toMap()); } } // deterministic ids => idempotent

  // ---- multi-currency ----
  bool canConvert(String cur) => cur == base || (rates[cur] ?? 0) > 0;
  double toBase(double a, String cur) => cur == base || (rates[cur] ?? 0) <= 0 ? a : _r2(a / rates[cur]!);

  Map<String, double> _parse(dynamic m) {
    final out = <String, double>{};
    if (m is Map) {
      m.forEach((k, v) {
        if (k is String && v is num && v.isFinite && v > 0) out[k] = v.toDouble();
      });
    }
    return out;
  }

  Map<String, double>? _cached(String b) {
    final s = prefs.getString('rates_$b');
    if (s == null) return null;
    try {
      final m = _parse(jsonDecode(s));
      return m.isEmpty ? null : m;
    } catch (_) {
      return null;
    }
  }

  /// Network first, cached copy as fallback. Returns null if neither exists.
  Future<Map<String, double>?> _fetchRates(String b) async {
    try {
      final r = await http.get(Uri.https('open.er-api.com', '/v6/latest/$b')).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        if (j is Map && j['result'] == 'success') {
          final m = _parse(j['rates']);
          if ((m[b] ?? 0) > 0) {
            await prefs.setString('rates_$b', jsonEncode(m));
            await prefs.setInt('rates_at_$b', DateTime.now().millisecondsSinceEpoch);
            return m;
          }
        }
      }
    } catch (_) {/* offline: fall through to cache */}
    return _cached(b);
  }

  Future<void> loadRates({bool force = false}) async {
    if (_ratesLoading) return;
    _ratesLoading = true;
    final b = base;
    try {
      final c = _cached(b);
      if (c != null) { rates = c; notifyListeners(); }
      final age = DateTime.now().millisecondsSinceEpoch - (prefs.getInt('rates_at_$b') ?? 0);
      if (c == null || force || age > const Duration(hours: 6).inMilliseconds) {
        final r = await _fetchRates(b);
        if (r != null && b == base) rates = r;
      }
    } finally {
      _ratesLoading = false;
    }
    notifyListeners();
    runRecurring();
  }

  /// Switches the base currency and converts every stored amount that is
  /// expressed in it (reports, budgets, goals, net worth, shared expenses).
  /// Returns false (and changes nothing) if no exchange rate is available.
  Future<bool> changeBase(String nb) async {
    final old = base;
    if (nb == old) return true;
    final r = await _fetchRates(nb);
    final k = r?[old];
    if (r == null || k == null || k <= 0) return false;
    final f = 1 / k;
    double cv(double v) => _r2(v * f);
    Map<String, dynamic> scale(Map<String, dynamic> e) => {...e, 'amount': cv(asDouble(e['amount']))};

    final ops = <void Function(WriteBatch)>[];
    for (final t in txns) {
      final nbv = t.currency == nb ? t.amount : (r[t.currency] ?? 0) > 0 ? _r2(t.amount / r[t.currency]!) : cv(t.base);
      ops.add((b) => b.update(_col('transactions').doc(t.id), {'base': nbv}));
    }
    for (final x in budgets) { ops.add((b) => b.update(_col('budgets').doc(x.id), {'limit': cv(x.limit)})); }
    for (final x in goals) { ops.add((b) => b.update(_col('goals').doc(x.id), {'target': cv(x.target), 'saved': cv(x.saved)})); }
    for (final x in accounts) { ops.add((b) => b.update(_col('accounts').doc(x.id), {'balance': cv(x.balance)})); }
    for (final x in groups) { ops.add((b) => b.update(_col('groups').doc(x.id), {'expenses': x.expenses.map(scale).toList(), 'settles': x.settles.map(scale).toList()})); }

    for (var i = 0; i < ops.length; i += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final op in ops.skip(i).take(400)) { op(batch); }
      batch.commit().catchError((Object e) { _err(e); });
    }
    await prefs.setString('base', nb);
    rates = r;
    notifyListeners();
    return true;
  }

  // ---- derived data ----
  DateTime get monthStart => DateTime(DateTime.now().year, DateTime.now().month);
  List<Txn> inRange(DateTime a, DateTime b) => txns.where((t) => !t.date.isBefore(a) && t.date.isBefore(b)).toList();
  double sum(Iterable<Txn> l, {bool income = false}) => l.where((t) => t.income == income).fold(0.0, (s, t) => s + t.base);
  Category cat(String id) => _catMap[id] ?? Category.other;

  double spentFor(Budget b) {
    final n = DateTime.now();
    final DateTime from, to;
    if (b.weekly) {
      from = DateTime(n.year, n.month, n.day - (n.weekday - 1));
      to = DateTime(from.year, from.month, from.day + 7);
    } else {
      from = monthStart;
      to = DateTime(n.year, n.month + 1);
    }
    return sum(txns.where((t) => !t.income && !t.date.isBefore(from) && t.date.isBefore(to) && (b.id == 'all' || t.cat == b.id || cat(t.cat).parent == b.id)));
  }

  String? budgetWarning(Txn t) {
    for (final b in budgets) {
      if (b.limit <= 0) continue;
      if (b.id != 'all' && b.id != t.cat && cat(t.cat).parent != b.id) continue;
      final before = spentFor(b), after = before + t.base, name = b.id == 'all' ? 'overall' : cat(b.id).name;
      if (after >= b.limit) return 'Over budget: your $name limit has been exceeded';
      if (after >= b.limit * .8 && before < b.limit * .8) return 'Heads up: 80% of your $name budget is used';
    }
    return null;
  }

  /// Returns a spending-vs-income alert for the current month, or null if
  /// spending is within a safe range. Thresholds: 80 %, 100 %, 150 %.
  String? get spendingAlert {
    final n = DateTime.now();
    final month = inRange(monthStart, DateTime(n.year, n.month + 1));
    final inc = sum(month, income: true);
    final exp = sum(month);
    if (inc <= 0) return null; // no income logged this month - skip
    final ratio = exp / inc;
    if (ratio >= 1.5) return 'You\'ve spent ${(ratio * 100).round()}% of your monthly income \u2014 significantly over budget!';
    if (ratio >= 1.0) return 'Your spending has exceeded your income this month by ${money(exp - inc, base)}.';
    if (ratio >= 0.8) return 'You\'ve used ${(ratio * 100).round()}% of this month\'s income. Consider slowing down.';
    return null;
  }

  /// Returns a warning when a new expense transaction would push spending
  /// past the user's income for this month.
  String? incomeWarning(Txn t) {
    if (t.income) return null;
    final n = DateTime.now();
    final month = inRange(monthStart, DateTime(n.year, n.month + 1));
    final inc = sum(month, income: true);
    if (inc <= 0) return null;
    final before = sum(month);
    final after = before + t.base;
    if (after >= inc && before < inc) return 'This transaction will push your spending past your monthly income.';
    if (after >= inc * 0.8 && before < inc * 0.8) return 'You are approaching your monthly income limit.';
    return null;
  }

  // ---- recurring transactions ----
  /// Posts every due occurrence. Transaction ids are derived from the rule id
  /// and the date, so running this on several devices never duplicates.
  void runRecurring() {
    if (user == null || !_loaded.containsAll(const ['transactions', 'recurring'])) return;
    final now = DateTime.now();
    final have = {for (final t in txns) t.id};
    for (final r in recurring) {
      if (r.amount <= 0 || !canConvert(r.currency)) continue; // wait until we can price it correctly
      var d = r.next, n = 0;
      while (!d.isAfter(now) && n < 60) {
        final id = '${r.id}_${DateFormat('yyyyMMdd').format(d)}';
        if (have.add(id)) {
          saveTxn(Txn(id: id, amount: r.amount, currency: r.currency, base: toBase(r.amount, r.currency), income: r.income, cat: r.cat, date: d, note: r.title, tags: const ['recurring']));
        }
        d = r.advance(d);
        n++;
      }
      if (n > 0) update('recurring', r.id, {'next': Timestamp.fromDate(d)});
    }
  }
}
