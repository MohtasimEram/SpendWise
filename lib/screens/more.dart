import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../common.dart';
import '../export_util.dart';
import 'profile.dart';
import 'tools.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tiles = <(IconData, String, String, Widget)>[
      (Icons.speed_rounded, 'Budgets', '${s.budgets.length} active', const BudgetsScreen()),
      (Icons.flag_rounded, 'Savings goals', '${s.goals.length} goals', const GoalsScreen()),
      (Icons.account_balance_rounded, 'Net worth', '${s.accounts.length} accounts', const NetWorthScreen()),
      (Icons.repeat_rounded, 'Recurring', '${s.recurring.length} rules', const RecurringScreen()),
      (Icons.groups_rounded, 'Split bills', '${s.groups.length} groups', const SplitScreen()),
      (Icons.category_rounded, 'Categories', '${s.cats.length} total', const CategoriesScreen()),
      (Icons.ios_share_rounded, 'Export data', 'CSV · PDF', const ExportScreen()),
      (Icons.settings_rounded, 'Settings', 'Security & theme', const SettingsScreen()),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(Sp.page, Sp.md, Sp.page, Sp.xl), children: [
      Text('More', style: display(32)),
      const SizedBox(height: Sp.lg),
      Reveal(
        child: Panel(
          onTap: () => push(context, const ProfileScreen()),
          child: Row(children: [
            Avatar(id: s.avatarId, name: s.displayName, radius: 24),
            const SizedBox(width: Sp.md),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Profile', style: bold),
              const SizedBox(height: 2),
              Text(s.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted(context)),
            ])),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
      const SizedBox(height: Sp.md),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: Sp.md, crossAxisSpacing: Sp.md, childAspectRatio: 1.25,
        children: [
          for (final (i, t) in tiles.indexed)
            Reveal(
              index: i + 1,
              child: Panel(
                onTap: () => push(context, t.$4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  IconTile(t.$1, cs.primary, size: 42),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold),
                    const SizedBox(height: 2),
                    Text(t.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted(context)),
                  ]),
                ]),
              ),
            ),
        ],
      ),
    ]);
  }
}

// ───────────────────────── Export ─────────────────────────
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});
  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  String? busy;

  /// Spreadsheet apps run text starting with = + - @ as a formula. Prefixing a
  /// quote neutralises "CSV injection" from notes/tags/categories.
  static String _safe(String v) {
    final t = v.trimLeft();
    return t.isNotEmpty && '=+-@\t\r'.contains(t[0]) ? "'$v" : v;
  }

  Rect? _origin() {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _run(String what, Future<void> Function() f) async {
    if (busy != null) return;
    setState(() => busy = what);
    try {
      await cleanTempExports();
      LockService.allowBackgroundFor(const Duration(minutes: 3)); // share sheet backgrounds the app
      await f();
      LockService.allowBackgroundFor(const Duration(seconds: 3));
    } catch (_) {
      if (mounted) snack(context, 'Export failed. Please try again.');
    }
    if (mounted) setState(() => busy = null);
  }

  Future<void> _csv(AppState s) => _run('csv', () async {
        final rows = [
          ['Date', 'Type', 'Category', 'Amount', 'Currency', 'Amount (${s.base})', 'Note', 'Tags'],
          for (final t in s.txns) [DateFormat('yyyy-MM-dd HH:mm').format(t.date), t.income ? 'Income' : 'Expense', _safe(s.cat(t.cat).name), t.amount, t.currency, t.base.toStringAsFixed(2), _safe(t.note), _safe(t.tags.join('|'))],
        ];
        final f = File('${(await getTemporaryDirectory()).path}/spendwise_export_${DateTime.now().millisecondsSinceEpoch}.csv');
        await f.writeAsString('﻿${const ListToCsvConverter().convert(rows)}'); // BOM so Excel reads UTF-8
        await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')], sharePositionOrigin: _origin());
      });

  Future<void> _pdf(AppState s) => _run('pdf', () async {
        pw.ThemeData? theme;
        try {
          theme = pw.ThemeData.withFont(base: await PdfGoogleFonts.notoSansRegular(), bold: await PdfGoogleFonts.notoSansBold());
        } catch (_) {/* offline: fall back to the built-in font */}
        final doc = pw.Document(theme: theme);
        final inc = s.sum(s.txns, income: true), exp = s.sum(s.txns);
        doc.addPage(pw.MultiPage(build: (_) => [
              pw.Header(level: 0, text: 'SpendWise report'),
              pw.Text('Income ${inc.toStringAsFixed(2)} ${s.base}   |   Expenses ${exp.toStringAsFixed(2)} ${s.base}   |   Balance ${(inc - exp).toStringAsFixed(2)} ${s.base}'),
              pw.SizedBox(height: 14),
              pw.TableHelper.fromTextArray(
                headers: ['Date', 'Category', 'Note', 'Amount (${s.base})'],
                data: [for (final t in s.txns) [DateFormat('yyyy-MM-dd').format(t.date), s.cat(t.cat).name, t.note, '${t.income ? '+' : '-'}${t.base.toStringAsFixed(2)}']],
              ),
            ]));
        await Printing.sharePdf(bytes: await doc.save(), filename: 'spendwise_report.pdf');
      });

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    Widget option(IconData i, Color c, String label, String id, VoidCallback go) => Panel(
          onTap: busy == null ? go : null,
          child: Row(children: [
            IconTile(i, c, size: 42),
            const SizedBox(width: Sp.md),
            Expanded(child: Text(label, style: bold)),
            busy == id ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: cs.primary)) : const Icon(Icons.chevron_right_rounded),
          ]),
        );
    return listPage('Export data', [
      Text('Export all ${s.txns.length} transactions for tax reporting or spreadsheet analysis. CSV opens directly in Excel and Google Sheets.', style: muted(context).copyWith(fontSize: 14)),
      const SizedBox(height: Sp.xl),
      option(Icons.table_chart_rounded, C.green, 'Export as CSV / Excel', 'csv', () => _csv(s)),
      const SizedBox(height: Sp.md),
      option(Icons.picture_as_pdf_rounded, C.red, 'Export as PDF report', 'pdf', () => _pdf(s)),
      const SizedBox(height: Sp.lg),
      Text('Exports contain your financial data. Share them only with people and apps you trust.', style: muted(context)),
    ]);
  }
}

// ───────────────────────── Settings ─────────────────────────
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static bool _weak(String p) => RegExp(r'^(\d)\1{3}$').hasMatch(p) || p == '1234' || p == '4321' || p == '0123';

  Future<String?> _newPin(BuildContext context) async {
    const f = AskField('PIN', numeric: true, obscure: true, maxLength: 4, digitsOnly: true);
    final a = await askText(context, 'Set a 4-digit PIN', [f]);
    if (a == null || !context.mounted) return null;
    if (a[0].length != 4) { snack(context, 'PIN must be exactly 4 digits'); return null; }
    if (_weak(a[0])) { snack(context, 'Too easy to guess - avoid 1234 or repeated digits'); return null; }
    final b = await askText(context, 'Confirm your PIN', [f]);
    if (b == null || !context.mounted) return null;
    if (a[0] != b[0]) { snack(context, 'PINs did not match'); return null; }
    return a[0];
  }

  /// Asks for the current PIN before a security-sensitive change.
  Future<bool> _verify(BuildContext context) async {
    final r = await askText(context, 'Enter your current PIN', [const AskField('PIN', numeric: true, obscure: true, maxLength: 4, digitsOnly: true)], action: 'Continue');
    if (r == null) return false;
    final res = await LockService.check(r[0]);
    if (res.ok) return true;
    if (context.mounted) snack(context, res.wait != null ? 'Too many attempts. Try again in ${res.wait!.inSeconds}s.' : 'Wrong PIN');
    return false;
  }

  Future<void> _changeCurrency(BuildContext context, AppState s, String v) async {
    if (!await confirm(context, 'Switch to $v?', 'All your amounts, budgets, goals and balances will be converted at today\'s exchange rate. This needs an internet connection the first time.', action: 'Convert', danger: false)) return;
    final ok = await s.changeBase(v);
    if (context.mounted) snack(context, ok ? 'Base currency is now $v' : 'Could not get exchange rates. Check your connection and try again.');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return listPage('Settings', [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Base currency', style: bold)),
            DropdownButton<String>(
              value: s.base,
              underline: const SizedBox(),
              borderRadius: BorderRadius.circular(16),
              items: [for (final c in {...kCurrencies, s.base}) DropdownMenuItem(value: c, child: Text(c, style: bold))],
              onChanged: (v) { if (v != null && v != s.base) _changeCurrency(context, s, v); },
            ),
          ]),
          const Divider(height: Sp.xxl),
          const Text('Appearance', style: bold),
          const SizedBox(height: Sp.md),
          SegmentedButton<int>(
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: 1, label: Text('Light')), ButtonSegment(value: 2, label: Text('Dark')), ButtonSegment(value: 0, label: Text('System'))],
            selected: {s.themeIdx},
            onSelectionChanged: (v) => s.setTheme(v.first),
          ),
        ]),
      ),
      const SizedBox(height: Sp.md),
      Panel(
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs),
        child: Column(children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Sp.md),
            title: const Text('App lock (PIN)', style: bold),
            subtitle: const Text('Ask for a PIN when you open the app'),
            value: s.lockOn,
            onChanged: (v) async {
              if (v) {
                final pin = await _newPin(context);
                if (pin == null) return;
                await LockService.setPin(pin);
                await s.setBool('lock', true);
              } else {
                if (!await _verify(context)) return;
                await LockService.clear();
                await s.setBool('lock', false);
                await s.setBool('bio', false);
              }
            },
          ),
          if (s.lockOn) ...[
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Sp.md),
              title: const Text('Biometric unlock', style: bold),
              subtitle: const Text('Face ID / fingerprint'),
              value: s.bioOn,
              onChanged: (v) async {
                if (v && !(await LockService.bioAvailable())) { if (context.mounted) snack(context, 'No biometrics set up on this device'); return; }
                if (v && !(await LockService.bio())) return;
                await s.setBool('bio', v);
              },
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Sp.md),
              title: const Text('Change PIN', style: bold),
              trailing: const Icon(Icons.chevron_right_rounded),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onTap: () async {
                if (!await _verify(context) || !context.mounted) return;
                final pin = await _newPin(context);
                if (pin != null) { await LockService.setPin(pin); if (context.mounted) snack(context, 'PIN updated'); }
              },
            ),
          ],
        ]),
      ),
      const SizedBox(height: Sp.xl),
      Center(child: Text('SpendWise 1.2.0', style: muted(context).copyWith(color: cs.onSurface.o(.4)))),
    ]);
  }
}
