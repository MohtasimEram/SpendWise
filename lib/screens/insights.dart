import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import '../common.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int p = 1, touched = -1; // period: 0 week, 1 month, 2 year

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final n = DateTime.now();
    late DateTime a, b, pa;
    late int buckets;
    late int Function(DateTime) idx;
    late String Function(int) lbl, tip;
    if (p == 0) {
      a = DateTime(n.year, n.month, n.day - (n.weekday - 1)); b = DateTime(a.year, a.month, a.day + 7); pa = DateTime(a.year, a.month, a.day - 7);
      buckets = 7; idx = (d) => d.weekday - 1; lbl = (i) => 'MTWTFSS'[i];
      tip = (i) => DateFormat('EEEE').format(DateTime(a.year, a.month, a.day + i));
    } else if (p == 1) {
      a = DateTime(n.year, n.month); b = DateTime(n.year, n.month + 1); pa = DateTime(n.year, n.month - 1);
      buckets = DateUtils.getDaysInMonth(n.year, n.month); idx = (d) => d.day - 1; lbl = (i) => (i == 0 || (i + 1) % 5 == 0) ? '${i + 1}' : '';
      tip = (i) => '${i + 1} ${DateFormat('MMM').format(a)}';
    } else {
      a = DateTime(n.year); b = DateTime(n.year + 1); pa = DateTime(n.year - 1);
      buckets = 12; idx = (d) => d.month - 1; lbl = (i) => 'JFMAMJJASOND'[i];
      tip = (i) => DateFormat('MMMM').format(DateTime(n.year, i + 1));
    }
    final cur = s.inRange(a, b);
    final exp = s.sum(cur), inc = s.sum(cur, income: true);
    // Fair comparison: previous period up to the same point in time, not the whole previous period.
    final prevEnd = pa.add(n.difference(a));
    final prev = s.sum(s.inRange(pa, prevEnd.isBefore(a) ? prevEnd : a));
    final delta = prev <= 0 ? null : (exp - prev) / prev;
    final byCat = <String, double>{};
    final bars = List.filled(buckets, 0.0);
    for (final t in cur.where((t) => !t.income)) {
      byCat[t.cat] = (byCat[t.cat] ?? 0) + t.base;
      final i = idx(t.date);
      if (i >= 0 && i < buckets) bars[i] += t.base;
    }
    final entries = byCat.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
    final sel = touched >= 0 && touched < entries.length ? touched : -1;
    final maxBar = bars.fold(0.0, max);
    final period = ['week', 'month', 'year'][p];

    return ListView(padding: const EdgeInsets.fromLTRB(Sp.page, Sp.md, Sp.page, Sp.bottom), children: [
      Text('Insights', style: display(32)),
      const SizedBox(height: Sp.lg),
      FilterTabs<int>(
        segments: const [ButtonSegment(value: 0, label: Text('Week')), ButtonSegment(value: 1, label: Text('Month')), ButtonSegment(value: 2, label: Text('Year'))],
        selected: p,
        onChanged: (v) { HapticFeedback.selectionClick(); setState(() { p = v; touched = -1; }); },
      ),
      const SizedBox(height: Sp.lg),
      Row(children: [
        Expanded(child: _Stat('Spent', exp, C.red, s.base)),
        const SizedBox(width: Sp.md),
        Expanded(child: _Stat('Earned', inc, C.green, s.base)),
      ]),
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: delta == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: Sp.md),
                child: Panel(
                  color: (delta > 0 ? C.red : C.green).o(.09),
                  border: false,
                  child: Row(children: [
                    Icon(delta > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: delta > 0 ? C.red : C.green),
                    const SizedBox(width: Sp.md),
                    Expanded(child: Text('${(delta.abs() * 100).round()}% ${delta > 0 ? 'more' : 'less'} spent than at this point last $period', style: bold)),
                  ]),
                ),
              ),
      ),
      const SectionTitle('Spending by category'),
      Panel(
        child: entries.isEmpty
            ? emptyState(context, 'No expenses in this period', icon: Icons.pie_chart_outline_rounded)
            : Column(children: [
                RepaintBoundary(child: SizedBox(
                  height: 220,
                  child: Stack(alignment: Alignment.center, children: [
                    PieChart(PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 68,
                      pieTouchData: PieTouchData(touchCallback: (e, r) {
                        final i = !e.isInterestedForInteractions || r?.touchedSection == null ? -1 : r!.touchedSection!.touchedSectionIndex;
                        if (i != touched) setState(() => touched = i);
                      }),
                      sections: [for (final (i, e) in entries.indexed) PieChartSectionData(value: e.value, color: Color(s.cat(e.key).color), radius: sel == i ? 40 : 30, showTitle: false)],
                    )),
                    IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 56),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(sel >= 0 ? s.cat(entries[sel].key).name : 'Total', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted(context)),
                          const SizedBox(height: 2),
                          FitText(money(sel >= 0 ? entries[sel].value : exp, s.base), maxWidth: 120, align: Alignment.center, style: display(20)),
                        ]),
                      ),
                    ),
                  ]),
                )),
                const SizedBox(height: Sp.md),
                for (final (i, e) in entries.take(6).indexed)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => touched = touched == i ? -1 : i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Sp.sm, horizontal: Sp.xs),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: sel == -1 || sel == i ? 1 : .45,
                        child: Column(children: [
                          Row(children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(s.cat(e.key).color), shape: BoxShape.circle)),
                            const SizedBox(width: Sp.md),
                            Expanded(child: Text(s.cat(e.key).name, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold)),
                            const SizedBox(width: Sp.sm),
                            FitText(money(e.value, s.base), maxWidth: 110, style: amountStyle()),
                            SizedBox(width: 44, child: Text(exp > 0 ? '${(e.value / exp * 100).round()}%' : '', textAlign: TextAlign.right, style: muted(context))),
                          ]),
                          const SizedBox(height: Sp.sm),
                          Bar(value: exp > 0 ? e.value / exp : 0, color: Color(s.cat(e.key).color), height: 6),
                        ]),
                      ),
                    ),
                  ),
              ]),
      ),
      const SectionTitle('Spending trend'),
      Panel(
        padding: const EdgeInsets.fromLTRB(Sp.md, Sp.xl, Sp.md, Sp.md),
        child: SizedBox(
          height: 200,
          child: BarChart(BarChartData(
            maxY: maxBar <= 0 ? 1 : maxBar * 1.2,
            alignment: BarChartAlignment.spaceAround,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => cs.inverseSurface,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, gi, rod, ri) => BarTooltipItem('${tip(group.x)}\n${money(rod.toY, s.base)}', TextStyle(color: cs.onInverseSurface, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: Sp.sm), child: Text(lbl(v.toInt()), style: muted(context))))),
            ),
            barGroups: [
              for (var i = 0; i < buckets; i++)
                BarChartGroupData(x: i, barRods: [BarChartRodData(toY: bars[i], width: buckets > 12 ? 5 : 14, borderRadius: BorderRadius.circular(6), color: bars[i] == maxBar && maxBar > 0 ? cs.primary : cs.primary.o(.45))]),
            ],
          )),
        ),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color, this.cur);
  final String label, cur;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: muted(context)),
          const SizedBox(height: Sp.xs),
          CountUp(value: value, format: (v) => money(v, cur), style: display(24, color: color)),
        ]),
      );
}
