import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue, Timestamp;
import 'package:flutter/services.dart';
import '../common.dart';

Widget _menu(List<PopupMenuEntry<String>> items, ValueChanged<String> onSelected) =>
    PopupMenuButton<String>(tooltip: 'Options', icon: const Icon(Icons.more_vert_rounded), onSelected: onSelected, itemBuilder: (_) => items);

// ───────────────────────── Budgets ─────────────────────────
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  void _edit(BuildContext context, {Budget? existing}) {
    final s = context.read<AppState>();
    final lim = TextEditingController(text: existing == null ? '' : fmtInput(existing.limit));
    String cat = existing?.id ?? 'all';
    bool weekly = existing?.weekly ?? false;
    String? err;
    showSheet(context, (c) => StatefulBuilder(builder: (c, set) {
          final replaces = existing == null && s.budgets.any((b) => b.id == cat);
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetTitle(existing == null ? 'New budget' : 'Edit budget'),
            DropdownButtonFormField<String>(
              value: cat,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [const DropdownMenuItem(value: 'all', child: Text('All spending')), for (final k in s.cats.where((k) => !k.income && k.parent == null)) DropdownMenuItem(value: k.id, child: Text(k.name))],
              onChanged: existing == null ? (v) => set(() => cat = v ?? 'all') : null,
            ),
            const SizedBox(height: Sp.md),
            TextField(
              controller: lim,
              autofocus: existing != null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,\s]'))],
              onChanged: (_) => set(() => err = null),
              decoration: InputDecoration(labelText: 'Limit (${s.base})'),
            ),
            const SizedBox(height: Sp.md),
            SegmentedButton<bool>(
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: false, label: Text('Monthly')), ButtonSegment(value: true, label: Text('Weekly'))],
              selected: {weekly},
              onSelectionChanged: (v) => set(() => weekly = v.first),
            ),
            if (replaces) Padding(padding: const EdgeInsets.only(top: Sp.md), child: Text('This replaces the existing budget for this category.', style: muted(c))),
            const SizedBox(height: Sp.xl),
            ErrorLine(err),
            PrimaryButton(
              label: 'Save budget',
              expand: true,
              onTap: () {
                final raw = lim.text.trim();
                if (raw.isEmpty) { set(() => err = 'Enter a budget limit'); return; }
                final v = parseAmount(raw);
                if (v == null) { set(() => err = 'Enter a valid number greater than 0'); return; }
                s.put('budgets', cat, Budget(cat, v, weekly).toMap());
                Navigator.pop(c);
              },
            ),
          ]);
        }));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return listPage('Budgets', [
      if (s.budgets.isEmpty) emptyState(context, 'Set a limit per category and get warned\nbefore you overspend.', icon: Icons.speed_rounded),
      for (final b in s.budgets)
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.md),
          child: Builder(builder: (_) {
            final spent = s.spentFor(b), r = b.limit <= 0 ? 0.0 : spent / b.limit;
            final col = r >= 1 ? C.red : r >= .8 ? C.amber : C.green;
            final k = b.id == 'all' ? null : s.cat(b.id);
            return Panel(
              onTap: () => _edit(context, existing: b),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  IconTile(k == null ? Icons.account_balance_wallet_rounded : iconFor(k.icon), k == null ? Theme.of(context).colorScheme.primary : Color(k.color), size: 42),
                  const SizedBox(width: Sp.md),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k?.name ?? 'All spending', maxLines: 1, overflow: TextOverflow.ellipsis, style: bold),
                    Text(b.weekly ? 'Weekly' : 'Monthly', style: muted(context)),
                  ])),
                  Text('${(r * 100).round()}%', style: amountStyle(color: col)),
                  _menu([menuItem('edit', 'Edit', Icons.edit_outlined), menuItem('del', 'Delete', Icons.delete_outline_rounded, danger: true)], (v) async {
                    if (v == 'edit') { _edit(context, existing: b); return; }
                    if (await confirm(context, 'Delete budget?', 'You will no longer get warnings for it.')) s.remove('budgets', b.id);
                  }),
                ]),
                const SizedBox(height: Sp.md),
                Bar(value: r, color: col, height: 10),
                const SizedBox(height: Sp.md),
                Text('${money(spent, s.base)} of ${money(b.limit, s.base)}  ·  ${r >= 1 ? 'Over by ${money(spent - b.limit, s.base)}' : '${money(b.limit - spent, s.base)} left'}', style: muted(context)),
              ]),
            );
          }),
        ),
    ], fab: PrimaryButton(label: 'New budget', icon: Icons.add_rounded, onTap: () => _edit(context)));
  }
}

// ───────────────────────── Goals ─────────────────────────
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  Future<void> _addFunds(BuildContext context, Goal g) async {
    final s = context.read<AppState>();
    final r = await askText(context, 'Add to ${g.name}', [const AskField('Amount', numeric: true, maxLength: 14)]);
    final v = parseAmount(r?.first ?? '');
    if (r == null) return;
    if (v == null) { snack(context, 'Enter a valid amount'); return; }
    s.update('goals', g.id, {'saved': FieldValue.increment(v)});
  }

  Future<void> _editGoal(BuildContext context, Goal g) async {
    final s = context.read<AppState>();
    final r = await askText(context, 'Edit goal', [AskField('Name', initial: g.name), AskField('Target amount', numeric: true, initial: fmtInput(g.target), maxLength: 14)]);
    if (r == null) return;
    final t = parseAmount(r[1]);
    if (t == null) { if (context.mounted) snack(context, 'Enter a valid target'); return; }
    s.update('goals', g.id, {'name': r[0], 'target': t});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return listPage('Savings goals', [
      if (s.goals.isEmpty) emptyState(context, 'Saving for something?\nCreate a goal and track your progress.', icon: Icons.flag_rounded),
      for (final g in s.goals)
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.md),
          child: Panel(
            onTap: () => _addFunds(context, g),
            child: Row(children: [
              SizedBox(
                width: 62, height: 62,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: g.target <= 0 ? 0 : min(1.0, g.saved / g.target)),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => Stack(alignment: Alignment.center, children: [
                    SizedBox(width: 62, height: 62, child: CircularProgressIndicator(value: v, strokeWidth: 6, strokeCap: StrokeCap.round, color: v >= 1 ? C.green : cs.primary, backgroundColor: cs.primary.o(.14))),
                    v >= 1 ? const Icon(Icons.check_rounded, color: C.green) : Text('${(v * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  ]),
                ),
              ),
              const SizedBox(width: Sp.lg),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold),
                const SizedBox(height: Sp.xs),
                Text('${money(g.saved, s.base)} of ${money(g.target, s.base)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted(context)),
                const SizedBox(height: 2),
                Text('Tap to add funds', style: muted(context).copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
              ])),
              _menu([menuItem('add', 'Add funds', Icons.add_circle_outline_rounded), menuItem('edit', 'Edit goal', Icons.edit_outlined), menuItem('del', 'Delete', Icons.delete_outline_rounded, danger: true)], (v) async {
                if (v == 'add') { _addFunds(context, g); }
                else if (v == 'edit') { _editGoal(context, g); }
                else if (await confirm(context, 'Delete goal?', '“${g.name}” and its progress will be removed.')) { s.remove('goals', g.id); }
              }),
            ]),
          ),
        ),
    ], fab: PrimaryButton(label: 'New goal', icon: Icons.add_rounded, onTap: () async {
      final r = await askText(context, 'New savings goal', [const AskField('Name (e.g. New laptop)'), const AskField('Target amount', numeric: true, maxLength: 14), const AskField('Already saved', numeric: true, initial: '0', maxLength: 14)]);
      if (r == null) return;
      final t = parseAmount(r[1]), saved = r[2] == '0' ? 0.0 : parseAmount(r[2]);
      if (t == null || saved == null) { if (context.mounted) snack(context, 'Enter valid amounts'); return; }
      final id = s.newId();
      s.put('goals', id, Goal(id, r[0], t, saved).toMap());
    }));
  }
}

// ───────────────────────── Net worth ─────────────────────────
class NetWorthScreen extends StatelessWidget {
  const NetWorthScreen({super.key});

  void _add(BuildContext context) {
    final s = context.read<AppState>();
    final name = TextEditingController(), bal = TextEditingController();
    bool liability = false;
    String? err;
    showSheet(context, (c) => StatefulBuilder(builder: (c, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetTitle('Add account'),
          SegmentedButton<bool>(
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: false, label: Text('Asset'), icon: Icon(Icons.savings_rounded, size: 18)), ButtonSegment(value: true, label: Text('Liability'), icon: Icon(Icons.credit_card_rounded, size: 18))],
            selected: {liability},
            onSelectionChanged: (v) => set(() => liability = v.first),
          ),
          const SizedBox(height: Sp.md),
          TextField(controller: name, maxLength: 60, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: liability ? 'Name (e.g. Credit card)' : 'Name (e.g. Savings)', counterText: '')),
          const SizedBox(height: Sp.md),
          TextField(controller: bal, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => set(() => err = null), decoration: InputDecoration(labelText: liability ? 'Amount owed (${s.base})' : 'Balance (${s.base})')),
          const SizedBox(height: Sp.xl),
          ErrorLine(err),
          PrimaryButton(
            label: 'Add account',
            expand: true,
            onTap: () {
              final v = parseAmount(bal.text, allowNegative: true);
              if (name.text.trim().isEmpty) { set(() => err = 'Give the account a name'); return; }
              if (v == null) { set(() => err = 'Enter a valid amount'); return; }
              final id = s.newId();
              s.put('accounts', id, Account(id, name.text.trim(), v.abs(), liability).toMap());
              Navigator.pop(c);
            },
          ),
        ])));
  }

  Future<void> _editBalance(BuildContext context, Account a) async {
    final s = context.read<AppState>();
    final r = await askText(context, 'Update ${a.name}', [AskField('Balance (${s.base})', numeric: true, initial: fmtInput(a.balance), maxLength: 14)]);
    if (r == null) return;
    final v = parseAmount(r.first, allowNegative: true);
    if (v == null) { if (context.mounted) snack(context, 'Enter a valid amount'); return; }
    s.update('accounts', a.id, {'balance': v.abs()});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final assets = s.accounts.where((a) => !a.liability).fold(0.0, (x, a) => x + a.balance);
    final debts = s.accounts.where((a) => a.liability).fold(0.0, (x, a) => x + a.balance);
    Widget side(String label, double v) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(color: Colors.white.o(.13), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: Colors.white.o(.72), fontSize: 12)),
              const SizedBox(height: 2),
              FitText(money(v, s.base), align: Alignment.centerLeft, maxWidth: 200, style: amountStyle(color: Colors.white)),
            ]),
          ),
        );
    return listPage('Net worth', [
      Panel(
        color: C.brand,
        border: false,
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Net worth', style: TextStyle(color: Colors.white.o(.72), fontWeight: FontWeight.w600)),
          const SizedBox(height: Sp.sm),
          CountUp(value: assets - debts, format: (v) => money(v, s.base), style: display(36, color: Colors.white)),
          const SizedBox(height: Sp.lg),
          Row(children: [side('Assets', assets), const SizedBox(width: Sp.md), side('Liabilities', debts)]),
        ]),
      ),
      const SizedBox(height: Sp.lg),
      if (s.accounts.isEmpty) emptyState(context, 'Add accounts, savings, loans or cards\nto see your full picture.', icon: Icons.account_balance_rounded),
      for (final a in s.accounts)
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.md),
          child: Panel(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
            onTap: () => _editBalance(context, a),
            child: Row(children: [
              IconTile(a.liability ? Icons.credit_card_rounded : Icons.savings_rounded, a.liability ? C.red : C.green, size: 42),
              const SizedBox(width: Sp.md),
              Expanded(child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold)),
              const SizedBox(width: Sp.sm),
              FitText('${a.liability ? '−' : ''}${money(a.balance, s.base)}', maxWidth: 120, style: amountStyle(color: a.liability ? C.red : C.green)),
              _menu([menuItem('edit', 'Update balance', Icons.edit_outlined), menuItem('del', 'Delete', Icons.delete_outline_rounded, danger: true)], (v) async {
                if (v == 'edit') { _editBalance(context, a); }
                else if (await confirm(context, 'Delete account?', '“${a.name}” will be removed from your net worth.')) { s.remove('accounts', a.id); }
              }),
            ]),
          ),
        ),
    ], fab: PrimaryButton(label: 'Add account', icon: Icons.add_rounded, onTap: () => _add(context)));
  }
}

// ───────────────────────── Recurring ─────────────────────────
class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  void _add(BuildContext context) {
    final s = context.read<AppState>();
    final title = TextEditingController(), amt = TextEditingController();
    bool income = false;
    String freq = 'monthly', cur = s.base, cat = 'def_bills';
    final t0 = DateTime.now();
    DateTime start = DateTime(t0.year, t0.month, t0.day);
    String? err;
    showSheet(context, (c) => StatefulBuilder(builder: (c, set) {
          final cats = s.cats.where((k) => k.income == income).toList();
          if (!cats.any((k) => k.id == cat) && cats.isNotEmpty) cat = cats.first.id;
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetTitle('New recurring item'),
            SegmentedButton<bool>(
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: false, label: Text('Expense')), ButtonSegment(value: true, label: Text('Income'))],
              selected: {income},
              onSelectionChanged: (v) => set(() => income = v.first),
            ),
            const SizedBox(height: Sp.md),
            TextField(controller: title, maxLength: 60, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Title (e.g. Netflix, Rent, Salary)', counterText: '')),
            const SizedBox(height: Sp.md),
            Row(children: [
              Expanded(child: TextField(controller: amt, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => set(() => err = null), decoration: const InputDecoration(labelText: 'Amount'))),
              const SizedBox(width: Sp.md),
              SizedBox(
                width: 110,
                child: DropdownButtonFormField<String>(value: cur, isExpanded: true, decoration: const InputDecoration(labelText: 'Currency'), items: [for (final k in {...kCurrencies, s.base}) DropdownMenuItem(value: k, child: Text(k))], onChanged: (v) => set(() => cur = v ?? cur)),
              ),
            ]),
            const SizedBox(height: Sp.md),
            DropdownButtonFormField<String>(value: cat, isExpanded: true, decoration: const InputDecoration(labelText: 'Category'), items: [for (final k in cats) DropdownMenuItem(value: k.id, child: Text(k.name))], onChanged: (v) => set(() => cat = v ?? cat)),
            const SizedBox(height: Sp.md),
            DropdownButtonFormField<String>(
              value: freq,
              decoration: const InputDecoration(labelText: 'Repeats'),
              items: [for (final f in ['daily', 'weekly', 'monthly', 'yearly']) DropdownMenuItem(value: f, child: Text('${f[0].toUpperCase()}${f.substring(1)}'))],
              onChanged: (v) => set(() => freq = v ?? freq),
            ),
            const SizedBox(height: Sp.md),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded),
              label: Text('Starts ${DateFormat('d MMM yyyy').format(start)}'),
              onPressed: () async {
                final d = await showDatePicker(context: c, initialDate: start, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) set(() => start = d);
              },
            ),
            const SizedBox(height: Sp.xl),
            ErrorLine(err),
            PrimaryButton(
              label: 'Save',
              expand: true,
              onTap: () {
                final v = parseAmount(amt.text);
                if (title.text.trim().isEmpty) { set(() => err = 'Give it a title'); return; }
                if (v == null) { set(() => err = 'Enter an amount greater than 0'); return; }
                final id = s.newId();
                s.put('recurring', id, Recurring(id: id, title: title.text.trim(), amount: v, currency: cur, income: income, cat: cat, freq: freq, next: start, anchor: start.day).toMap());
                Navigator.pop(c);
              },
            ),
          ]);
        }));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return listPage('Recurring', [
      if (s.recurring.isEmpty) emptyState(context, 'Rent, subscriptions, salary…\nlog them once, we add them automatically.', icon: Icons.repeat_rounded),
      for (final r in s.recurring)
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.md),
          child: Panel(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
            child: Row(children: [
              IconTile(Icons.repeat_rounded, r.income ? C.green : Theme.of(context).colorScheme.primary, size: 42),
              const SizedBox(width: Sp.md),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold),
                Text('${r.freq[0].toUpperCase()}${r.freq.substring(1)} · next ${DateFormat('d MMM').format(r.next)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted(context)),
              ])),
              const SizedBox(width: Sp.sm),
              FitText('${r.income ? '+' : '−'}${money(r.amount, r.currency)}', maxWidth: 120, style: amountStyle(color: r.income ? C.green : C.red)),
              _menu([menuItem('del', 'Delete', Icons.delete_outline_rounded, danger: true)], (v) async {
                if (await confirm(context, 'Stop this recurring item?', 'Past transactions stay; no new ones will be added.', action: 'Stop')) s.remove('recurring', r.id);
              }),
            ]),
          ),
        ),
    ], fab: PrimaryButton(label: 'New', icon: Icons.add_rounded, onTap: () => _add(context)));
  }
}

// ───────────────────────── Bill splitting ─────────────────────────
class SplitScreen extends StatelessWidget {
  const SplitScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return listPage('Split bills', [
      if (s.groups.isEmpty) emptyState(context, 'Create a group for roommates, trips or dinners\nand see who owes whom.', icon: Icons.groups_rounded),
      for (final g in s.groups)
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.md),
          child: Panel(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
            onTap: () => push(context, GroupScreen(id: g.id)),
            child: Row(children: [
              IconTile(Icons.groups_rounded, Theme.of(context).colorScheme.primary, size: 42),
              const SizedBox(width: Sp.md),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold),
                Text(g.members.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: muted(context)),
              ])),
              const SizedBox(width: Sp.sm),
              Text(g.debts.isEmpty ? 'Settled' : '${g.debts.length} to settle', style: TextStyle(color: g.debts.isEmpty ? C.green : C.amber, fontWeight: FontWeight.w700, fontSize: 13)),
              _menu([menuItem('del', 'Delete group', Icons.delete_outline_rounded, danger: true)], (v) async {
                if (await confirm(context, 'Delete group?', '“${g.name}” and all its shared expenses will be removed.')) s.remove('groups', g.id);
              }),
            ]),
          ),
        ),
    ], fab: PrimaryButton(label: 'New group', icon: Icons.add_rounded, onTap: () async {
      final r = await askText(context, 'New group', [const AskField('Group name', maxLength: 60), const AskField('Members (comma separated, include you)', maxLength: 200)]);
      if (r == null) return;
      final m = r[1].split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).map((e) => e.length > 30 ? e.substring(0, 30) : e).toSet().take(20).toList();
      if (m.length < 2) { if (context.mounted) snack(context, 'Add at least two different members, separated by commas'); return; }
      final id = s.newId();
      s.put('groups', id, Group(id, r[0], m, [], []).toMap());
    }));
  }
}

class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key, required this.id});
  final String id;

  void _addExpense(BuildContext context, Group g) {
    final s = context.read<AppState>();
    final title = TextEditingController(), amt = TextEditingController();
    String paid = g.members.first;
    String? err;
    showSheet(context, (c) => StatefulBuilder(builder: (c, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetTitle('Shared expense'),
          TextField(controller: title, maxLength: 60, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'What for?', counterText: '')),
          const SizedBox(height: Sp.md),
          TextField(controller: amt, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => set(() => err = null), decoration: InputDecoration(labelText: 'Amount (${s.base})')),
          const SizedBox(height: Sp.md),
          DropdownButtonFormField<String>(value: paid, isExpanded: true, decoration: const InputDecoration(labelText: 'Paid by'), items: [for (final m in g.members) DropdownMenuItem(value: m, child: Text(m))], onChanged: (v) => set(() => paid = v ?? paid)),
          const SizedBox(height: Sp.xl),
          ErrorLine(err),
          PrimaryButton(
            label: 'Split equally',
            expand: true,
            onTap: () {
              final v = parseAmount(amt.text);
              if (title.text.trim().isEmpty) { set(() => err = 'What was it for?'); return; }
              if (v == null) { set(() => err = 'Enter an amount greater than 0'); return; }
              // arrayUnion = safe even if someone else adds an expense at the same moment.
              s.update('groups', g.id, {'expenses': FieldValue.arrayUnion([{'title': title.text.trim(), 'amount': v, 'paidBy': paid, 'date': DateTime.now().millisecondsSinceEpoch}])});
              Navigator.pop(c);
            },
          ),
        ])));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final g = s.groups.where((x) => x.id == id).firstOrNull;
    if (g == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final bal = g.balances;
    return listPage(g.name, [
      Text('Who owes whom', style: display(20)),
      const SizedBox(height: Sp.md),
      if (g.debts.isEmpty) const Panel(child: Row(children: [Icon(Icons.check_circle_rounded, color: C.green), SizedBox(width: Sp.md), Text('All settled up', style: bold)])),
      for (final d in g.debts)
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.md),
          child: Panel(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.sm, Sp.sm),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${d.$1} owes ${d.$2}', maxLines: 2, overflow: TextOverflow.ellipsis, style: bold),
                const SizedBox(height: 2),
                Text(money(d.$3, s.base), style: amountStyle(color: C.amber)),
              ])),
              const SizedBox(width: Sp.sm),
              TextButton(
                onPressed: () async {
                  if (!await confirm(context, 'Mark as paid?', '${d.$1} paid ${d.$2} ${money(d.$3, s.base)}.', action: 'Settle', danger: false)) return;
                  s.update('groups', g.id, {'settles': FieldValue.arrayUnion([{'from': d.$1, 'to': d.$2, 'amount': d.$3, 'date': DateTime.now().millisecondsSinceEpoch}])});
                },
                child: const Text('Settle'),
              ),
            ]),
          ),
        ),
      const SectionTitle('Balances'),
      Panel(
        child: Column(children: [
          for (final (i, m) in g.members.indexed) ...[
            if (i > 0) const Divider(height: Sp.xl),
            Row(children: [
              Expanded(child: Text(m, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold)),
              const SizedBox(width: Sp.md),
              Builder(builder: (_) {
                final v = bal[m] ?? 0;
                return Text(v.abs() < .005 ? 'even' : '${v > 0 ? 'gets back ' : 'owes '}${money(v.abs(), s.base)}', style: TextStyle(fontWeight: FontWeight.w700, color: v.abs() < .005 ? null : v > 0 ? C.green : C.red));
              }),
            ]),
          ],
        ]),
      ),
      const SectionTitle('Expenses'),
      if (g.expenses.isEmpty) emptyState(context, 'No shared expenses yet.', icon: Icons.receipt_long_rounded),
      for (final (i, e) in g.expenses.indexed.toList().reversed)
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.md),
          child: Panel(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.sm, Sp.md),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: bold),
                Text('Paid by ${e['paidBy']} · split ${g.members.length} ways', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted(context)),
              ])),
              const SizedBox(width: Sp.sm),
              FitText(money(asDouble(e['amount']), s.base), maxWidth: 110, style: amountStyle()),
              _menu([menuItem('del', 'Delete expense', Icons.delete_outline_rounded, danger: true)], (v) async {
                if (!await confirm(context, 'Delete expense?', '“${e['title']}” will be removed and balances recalculated.')) return;
                final next = [...g.expenses]..removeAt(i);
                s.update('groups', g.id, {'expenses': next});
              }),
            ]),
          ),
        ),
    ], fab: PrimaryButton(label: 'Add expense', icon: Icons.add_rounded, onTap: () => _addExpense(context, g)));
  }
}

// ───────────────────────── Categories ─────────────────────────
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  void _add(BuildContext context) {
    final s = context.read<AppState>();
    final name = TextEditingController();
    bool income = false;
    String icon = 'other';
    int color = kColors[1];
    String? parent, err;
    showSheet(context, (c) => StatefulBuilder(builder: (c, set) {
          final cs = Theme.of(c).colorScheme;
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetTitle('New category'),
            TextField(controller: name, maxLength: 30, textCapitalization: TextCapitalization.sentences, onChanged: (_) => set(() => err = null), decoration: const InputDecoration(labelText: 'Name', counterText: '')),
            const SizedBox(height: Sp.md),
            SegmentedButton<bool>(
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: false, label: Text('Expense')), ButtonSegment(value: true, label: Text('Income'))],
              selected: {income},
              onSelectionChanged: (v) => set(() { income = v.first; parent = null; }),
            ),
            const SizedBox(height: Sp.md),
            DropdownButtonFormField<String?>(
              value: parent,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Subcategory of (optional)'),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('None - top level')), for (final k in s.cats.where((k) => k.income == income && k.parent == null)) DropdownMenuItem<String?>(value: k.id, child: Text(k.name))],
              onChanged: (v) => set(() => parent = v),
            ),
            const SizedBox(height: Sp.lg),
            Text('Icon', style: muted(c).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: Sp.sm),
            Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
              for (final e in kIcons.entries)
                Semantics(
                  label: e.key,
                  selected: icon == e.key,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => set(() => icon = e.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 46, height: 46,
                      decoration: BoxDecoration(color: icon == e.key ? cs.primary.o(.16) : Colors.transparent, borderRadius: BorderRadius.circular(14), border: Border.all(color: icon == e.key ? cs.primary : cs.onSurface.o(.12), width: icon == e.key ? 1.6 : 1)),
                      child: Icon(e.value, size: 22, color: icon == e.key ? cs.primary : null),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: Sp.lg),
            Text('Colour', style: muted(c).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: Sp.sm),
            Wrap(spacing: Sp.md, runSpacing: Sp.md, children: [
              for (final k in kColors)
                Semantics(
                  button: true,
                  selected: color == k,
                  label: 'Colour',
                  child: InkResponse(
                    onTap: () => set(() => color = k),
                    radius: 26,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: Color(k), shape: BoxShape.circle, border: Border.all(color: color == k ? cs.onSurface : Colors.transparent, width: 3)),
                      child: color == k ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: Sp.xl),
            ErrorLine(err),
            PrimaryButton(
              label: 'Create',
              expand: true,
              onTap: () {
                if (name.text.trim().isEmpty) { set(() => err = 'Give the category a name'); return; }
                final id = s.newId();
                s.put('categories', id, Category(id, name.text.trim(), icon, color, income: income, parent: parent).toMap());
                Navigator.pop(c);
              },
            ),
          ]);
        }));
  }

  Future<void> _delete(BuildContext context, Category k) async {
    final s = context.read<AppState>();
    final kids = s.cats.where((c) => c.parent == k.id).toList();
    final ok = await confirm(context, 'Delete “${k.name}”?', kids.isEmpty ? 'Existing transactions move to “Other”.' : 'Its subcategories become top-level categories, and existing transactions move to “Other”.');
    if (!ok) return;
    for (final c in kids) { s.update('categories', c.id, {'parent': null}); }
    if (s.budgets.any((b) => b.id == k.id)) s.remove('budgets', k.id);
    s.remove('categories', k.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    Widget row(Category k) => Padding(
          padding: EdgeInsets.only(bottom: Sp.sm, left: k.parent == null ? 0 : Sp.xl),
          child: Panel(
            padding: EdgeInsets.fromLTRB(Sp.md, Sp.sm, k.id.startsWith('def_') ? Sp.md : Sp.xs, Sp.sm),
            child: Row(children: [
              IconTile(iconFor(k.icon), Color(k.color), size: 38),
              const SizedBox(width: Sp.md),
              Expanded(child: Text(k.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold)),
              if (!k.id.startsWith('def_')) IconButton(tooltip: 'Delete category', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _delete(context, k)),
            ]),
          ),
        );
    List<Widget> section(String t, bool inc) {
      final tops = s.cats.where((k) => k.income == inc && k.parent == null);
      final tops2 = tops.map((k) => k.id).toSet();
      // Subcategories whose parent is missing are still shown (never lose data from view).
      final orphans = s.cats.where((k) => k.income == inc && k.parent != null && !tops2.contains(k.parent));
      return [SectionTitle(t), for (final k in tops) ...[row(k), for (final c in s.cats.where((c) => c.parent == k.id)) row(c)], for (final k in orphans) row(k)];
    }

    return listPage('Categories', [...section('Expenses', false), ...section('Income', true)], fab: PrimaryButton(label: 'New', icon: Icons.add_rounded, onTap: () => _add(context)));
  }
}
