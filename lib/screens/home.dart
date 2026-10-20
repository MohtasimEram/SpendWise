import 'dart:math';
import '../common.dart';
import 'add.dart';
import 'insights.dart';
import 'more.dart';
import 'profile.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with SingleTickerProviderStateMixin {
  int i = 0;
  late final AnimationController fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 200), value: 1);
  late final Animation<double> curved = CurvedAnimation(parent: fade, curve: Curves.easeOutCubic);

  @override
  void dispose() { fade.dispose(); super.dispose(); }

  void _go(int v) {
    if (v == i) return;
    setState(() => i = v);
    fade.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [HomeScreen(onSeeAll: () => _go(1)), const ActivityScreen(), const InsightsScreen(), const MoreScreen()];
    // Each tab paints in its own layer so a fade or a chart animation in one never repaints the others.
    final isolated = [for (final p in pages) RepaintBoundary(child: p)];
    final showAdd = i != 3;
    return PopScope(
      canPop: i == 0,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _go(0); },
      child: Scaffold(
        // The Add button and tab bar must not jump up with the keyboard when searching in Activity.
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          bottom: false,
          child: Stack(children: [
            Positioned.fill(
              child: FadeTransition(
                opacity: curved,
                child: IndexedStack(index: i, children: isolated),
              ),
            ),
            // Plain overlay instead of a FloatingActionButton: snack bars (e.g. "Transaction deleted")
            // then float above it instead of the Scaffold shoving the button around.
            Positioned(
              right: Sp.page,
              bottom: Sp.lg,
              child: AnimatedSlide(
                offset: showAdd ? Offset.zero : const Offset(0, 1.6),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: showAdd ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(ignoring: !showAdd, child: PrimaryButton(label: 'Add', icon: Icons.add_rounded, onTap: () => Navigator.push(context, slideUpRoute(const AddTxnScreen())))),
                ),
              ),
            ),
          ]),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: _go,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Activity'),
            NavigationDestination(icon: Icon(Icons.pie_chart_outline_rounded), selectedIcon: Icon(Icons.pie_chart_rounded), label: 'Insights'),
            NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'More'),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onSeeAll});
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final n = DateTime.now();
    final month = s.inRange(s.monthStart, DateTime(n.year, n.month + 1));
    final inc = s.sum(month, income: true), exp = s.sum(month);
    final balance = s.sum(s.txns, income: true) - s.sum(s.txns);
    final today = s.sum(s.inRange(DateTime(n.year, n.month, n.day), DateTime(n.year, n.month, n.day + 1)));
    final shown = s.displayName; // the nickname chosen at sign-up
    final hello = switch (n.hour) {
      >= 0 && < 5 => 'Late night 🌙',
      >= 5 && < 12 => 'Good morning ☀️',
      >= 12 && < 17 => 'Good afternoon 🌤️',
      >= 17 && < 22 => 'Good evening 🌆',
      _ => 'Good night 🌙',
    };
    final overall = s.budgets.where((b) => b.id == 'all' && !b.weekly && b.limit > 0).firstOrNull;
    final alerts = [for (final b in s.budgets) if (b.limit > 0 && s.spentFor(b) / b.limit >= .8) (b, s.spentFor(b))];
    final spendAlert = s.spendingAlert;

    return ListView(padding: const EdgeInsets.fromLTRB(Sp.page, Sp.md, Sp.page, Sp.bottom), children: [
      Reveal(
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => push(context, const ProfileScreen()),
              behavior: HitTestBehavior.opaque,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hello, style: muted(context).copyWith(fontSize: 14)),
                const SizedBox(height: Sp.xs),
                Text(shown.isNotEmpty ? shown : 'Welcome', maxLines: 1, overflow: TextOverflow.ellipsis, style: display(30)),
              ]),
            ),
          ),
          const SizedBox(width: Sp.md),
          Semantics(
            button: true,
            label: 'Open profile',
            child: GestureDetector(
              onTap: () => push(context, const ProfileScreen()),
              child: Avatar(id: s.avatarId, name: shown, radius: 23),
            ),
          ),
        ]),
      ),
      const SizedBox(height: Sp.xl),
      Reveal(
        index: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Container(
            color: C.brand,
            padding: const EdgeInsets.all(22),
            child: Stack(children: [
              Positioned(right: -70, top: -70, child: Container(width: 190, height: 190, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.o(.09), width: 1.5)))),
              Positioned(right: -30, top: -30, child: Container(width: 110, height: 110, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.o(.09), width: 1.5)))),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Total balance', style: TextStyle(color: Colors.white.o(.72), fontWeight: FontWeight.w600)),
                const SizedBox(height: Sp.sm),
                CountUp(value: balance, format: (v) => money(v, s.base), style: display(40, color: Colors.white)),
                const SizedBox(height: Sp.xl),
                Row(children: [
                  Expanded(child: _Pill(Icons.south_west_rounded, 'Income', money(inc, s.base))),
                  const SizedBox(width: Sp.md),
                  Expanded(child: _Pill(Icons.north_east_rounded, 'Spent', money(exp, s.base))),
                ]),
                if (overall != null) ...[
                  const SizedBox(height: Sp.xl),
                  Row(children: [
                    Expanded(child: Text(exp >= overall.limit ? 'Over this month\'s budget by ${money(exp - overall.limit, s.base)}' : '${money(overall.limit - exp, s.base)} left this month', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                    const SizedBox(width: Sp.sm),
                    Text('${min(999, (exp / overall.limit * 100).round())}%', style: TextStyle(color: Colors.white.o(.8), fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: Sp.sm),
                  Bar(value: exp / overall.limit, color: exp >= overall.limit ? const Color(0xFFFF9C86) : Colors.white, height: 8),
                ],
              ]),
            ]),
          ),
        ),
      ),
      const SizedBox(height: Sp.md),
      Reveal(
        index: 2,
        child: Row(children: [
          Expanded(child: _Stat('Spent today', money(today, s.base), Icons.today_rounded)),
          const SizedBox(width: Sp.md),
          Expanded(child: _Stat('Daily average', money(exp / n.day, s.base), Icons.show_chart_rounded)),
        ]),
      ),
      for (final (i, a) in alerts.indexed)
        Padding(
          padding: const EdgeInsets.only(top: Sp.md),
          child: Reveal(
            index: 3 + i,
            child: Panel(
              padding: const EdgeInsets.all(Sp.lg),
              color: (a.$2 >= a.$1.limit ? C.red : C.amber).o(.1),
              border: false,
              child: Row(children: [
                Icon(a.$2 >= a.$1.limit ? Icons.error_rounded : Icons.warning_amber_rounded, color: a.$2 >= a.$1.limit ? C.red : C.amber),
                const SizedBox(width: Sp.md),
                Expanded(child: Text('${a.$1.id == 'all' ? 'Overall' : s.cat(a.$1.id).name} budget: ${(a.$2 / a.$1.limit * 100).round()}% used', style: bold)),
              ]),
            ),
          ),
        ),
      if (spendAlert != null)
        Padding(
          padding: const EdgeInsets.only(top: Sp.md),
          child: Reveal(
            index: 3 + alerts.length,
            child: Panel(
              padding: const EdgeInsets.all(Sp.lg),
              color: (exp >= inc ? C.red : C.amber).o(.1),
              border: false,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(exp >= inc ? Icons.trending_up_rounded : Icons.warning_amber_rounded, color: exp >= inc ? C.red : C.amber),
                const SizedBox(width: Sp.md),
                Expanded(child: Text(spendAlert, style: bold)),
              ]),
            ),
          ),
        ),
      SectionTitle('Recent transactions', action: s.txns.isEmpty ? null : 'See all', onAction: onSeeAll),
      if (s.txns.isEmpty) emptyState(context, 'No transactions yet.\nTap “Add” to log your first one.', icon: Icons.receipt_long_rounded),
      for (final (i, t) in s.txns.take(8).indexed) Reveal(key: ValueKey('hr_${t.id}'), index: 4 + i, child: TxnTile(t, key: ValueKey('h_${t.id}'))),
    ]);
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
        decoration: BoxDecoration(color: Colors.white.o(.13), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: Sp.sm),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: Colors.white.o(.72), fontSize: 12)),
            const SizedBox(height: 2),
            FitText(value, align: Alignment.centerLeft, maxWidth: 200, style: amountStyle(color: Colors.white)),
          ])),
        ]),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.all(Sp.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary), const SizedBox(width: Sp.sm), Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted(context)))]),
          const SizedBox(height: Sp.sm),
          FitText(value, align: Alignment.centerLeft, maxWidth: 200, style: amountStyle(size: 19)),
        ]),
      );
}

class TxnTile extends StatelessWidget {
  const TxnTile(this.t, {super.key});
  final Txn t;
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final c = s.cat(t.cat), col = Color(c.color);
    final title = t.note.isEmpty ? c.name : t.note;
    return Dismissible(
      key: ValueKey('d_${t.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Sp.xl),
        margin: const EdgeInsets.only(bottom: Sp.md),
        decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(22)),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) {
        s.removeTxn(t.id);
        showUndoSnack('Transaction deleted', () => s.saveTxn(t));
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: Sp.md),
        child: Panel(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
          onTap: () => push(context, AddTxnScreen(edit: t)),
          child: Row(children: [
            IconTile(iconFor(c.icon), col),
            const SizedBox(width: Sp.md),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold),
              const SizedBox(height: 2),
              Text('${c.name} · ${DateFormat('d MMM, h:mm a').format(t.date)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted(context)),
            ])),
            const SizedBox(width: Sp.md),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              FitText('${t.income ? '+' : '−'}${money(t.base, s.base)}', maxWidth: 124, style: amountStyle(color: t.income ? C.green : C.red)),
              if (t.currency != s.base) ...[const SizedBox(height: 2), FitText(money(t.amount, t.currency), maxWidth: 124, style: muted(context))],
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Day {
  _Day(this.label, this.spent);
  final String label;
  final double spent;
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final search = TextEditingController();
  String q = '';
  int f = 0; // 0 all, 1 expense, 2 income

  @override
  void dispose() { search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final needle = q.trim().toLowerCase();
    final list = s.txns.where((t) {
      if (f == 1 && t.income || f == 2 && !t.income) return false;
      if (needle.isEmpty) return true;
      return '${t.note} ${t.tags.join(' ')} ${s.cat(t.cat).name}'.toLowerCase().contains(needle);
    }).toList();

    final spentByDay = <String, double>{};
    for (final t in list) {
      if (t.income) continue;
      final k = DateFormat('yyyyMMdd').format(t.date);
      spentByDay[k] = (spentByDay[k] ?? 0) + t.base;
    }
    final items = <Object>[];
    String? last;
    for (final t in list) {
      final k = DateFormat('yyyyMMdd').format(t.date);
      if (k != last) { items.add(_Day(DateFormat('EEEE, d MMM').format(t.date), spentByDay[k] ?? 0)); last = k; }
      items.add(t);
    }

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Sp.page, Sp.md, Sp.page, 0),
          sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Activity', style: display(32)),
              const SizedBox(height: Sp.lg),
              TextField(
                controller: search,
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => q = v),
                decoration: InputDecoration(
                  hintText: 'Search notes, tags, categories',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: q.isEmpty ? null : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded), onPressed: () { search.clear(); setState(() => q = ''); }),
                ),
              ),
              const SizedBox(height: Sp.md),
              Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [for (final (i, l) in ['All', 'Expenses', 'Income'].indexed) FilterChoiceChip(label: l, selected: f == i, onSelected: () => setState(() => f = i))]),
              const SizedBox(height: Sp.sm),
            ]),
          ),
        ),
        if (list.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 60),
                child: emptyState(context, q.isEmpty ? 'Nothing here yet.' : 'No matches for “$q”.', icon: Icons.search_off_rounded),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.bottom),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (c, i) {
                  final it = items[i];
                  if (it is _Day) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(4, Sp.lg, 4, Sp.sm),
                      child: Row(children: [
                        Expanded(child: Text(it.label, style: muted(c).copyWith(fontWeight: FontWeight.w700))),
                      if (it.spent > 0) Text('−${money(it.spent, s.base)}', style: muted(c)),
                      ]),
                    );
                  }
                  final t = it as Txn;
                  return TxnTile(t, key: ValueKey('a_${t.id}'));
                },
                childCount: items.length,
              ),
            ),
          ),
      ],
    );
  }
}
