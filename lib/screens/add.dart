import 'dart:io';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../common.dart';
import '../receipt_parser.dart';

const _kw = {
  'def_coffee': ['coffee', 'starbucks', 'latte', 'cafe'],
  'def_food': ['food', 'lunch', 'dinner', 'breakfast', 'pizza', 'burger', 'restaurant', 'grocery', 'kfc'],
  'def_transport': ['uber', 'pathao', 'taxi', 'bus', 'fuel', 'petrol', 'metro', 'ride', 'rickshaw'],
  'def_sub': ['netflix', 'spotify', 'subscription', 'youtube', 'icloud'],
  'def_bills': ['bill', 'electric', 'internet', 'wifi', 'gas', 'water', 'rent'],
  'def_health': ['pharmacy', 'doctor', 'medicine', 'hospital', 'clinic'],
  'def_shopping': ['amazon', 'shop', 'mall', 'clothes', 'daraz', 'gadget', 'electronic', 'mobile', 'laptop', 'mouse', 'keyboard', 'headphone', 'charger', 'store', 'mart', 'fashion', 'apparel'],
  'def_edu': ['book', 'course', 'tuition', 'udemy', 'exam'],
};

/// Lightweight rule-based auto-categorisation from a note / merchant.
String? guessCat(String text) {
  final t = text.toLowerCase();
  for (final e in _kw.entries) { if (e.value.any(t.contains)) return e.key; }
  return null;
}

/// Kept for compatibility with older callers/tests; the real work is in receipt_parser.dart.
ReceiptData parseReceipt(String text) => parseReceiptText(text);

class AddTxnScreen extends StatefulWidget {
  const AddTxnScreen({super.key, this.edit});
  final Txn? edit;
  @override
  State<AddTxnScreen> createState() => _AddTxnScreenState();
}

/// Layout notes (smoothness):
///  * The amount field is focused only AFTER the slide-in transition has finished -
///    opening the keyboard mid-transition re-laid out the page every frame.
///  * Amount, currency and category live in ValueNotifiers consumed by small
///    widgets, so typing never rebuilds the whole page.
///  * The hint line under the amount has a fixed height, so "≈ 12.30 USD" or an
///    error message appearing can no longer push everything below it down.
class _AddTxnScreenState extends State<AddTxnScreen> {
  final amt = TextEditingController(), note = TextEditingController(), tags = TextEditingController();
  final amtFocus = FocusNode();
  final amtErr = ValueNotifier<String?>(null);
  final catN = ValueNotifier<String>('def_food');
  final curN = ValueNotifier<String>('USD');
  bool income = false, manualCat = false, scanning = false, ready = false, saving = false;
  String _id = '';
  DateTime date = DateTime.now();
  Animation<double>? _routeAnim;
  AnimationStatusListener? _routeListener;

  @override
  void dispose() {
    if (_routeListener != null) _routeAnim?.removeStatusListener(_routeListener!);
    amt.dispose(); note.dispose(); tags.dispose(); amtFocus.dispose();
    amtErr.dispose(); catN.dispose(); curN.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ready) return;
    ready = true;
    final s = context.read<AppState>();
    curN.value = s.base;
    final e = widget.edit;
    _id = e?.id ?? s.newId(); // fixed up-front: a double-tap on Save can never create two rows
    if (e != null) {
      income = e.income; curN.value = e.currency; catN.value = e.cat; date = e.date;
      amt.text = fmtInput(e.amount); note.text = e.note; tags.text = e.tags.join(', ');
      manualCat = true;
    } else {
      _focusAfterTransition();
    }
  }

  void _focusAfterTransition() {
    final a = ModalRoute.of(context)?.animation;
    if (a == null || a.isCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) amtFocus.requestFocus(); });
      return;
    }
    _routeAnim = a;
    _routeListener = (st) {
      if (st != AnimationStatus.completed) return;
      a.removeStatusListener(_routeListener!);
      _routeListener = null;
      if (mounted) amtFocus.requestFocus();
    };
    a.addStatusListener(_routeListener!);
  }

  void _setIncome(bool v) {
    if (v == income) return;
    HapticFeedback.selectionClick();
    final s = context.read<AppState>();
    setState(() => income = v);
    manualCat = false;
    final first = s.cats.where((c) => c.income == v).firstOrNull;
    if (first != null) catN.value = first.id;
  }

  Future<void> _scan() async {
    final src = await showSheet<ImageSource>(
      context,
      (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetTitle('Scan a receipt'),
        Panel(onTap: () => Navigator.pop(c, ImageSource.camera), child: const Row(children: [Icon(Icons.photo_camera_rounded), SizedBox(width: Sp.md), Expanded(child: Text('Take a photo', style: bold))])),
        const SizedBox(height: Sp.md),
        Panel(onTap: () => Navigator.pop(c, ImageSource.gallery), child: const Row(children: [Icon(Icons.photo_library_rounded), SizedBox(width: Sp.md), Expanded(child: Text('Choose from gallery', style: bold))])),
        const SizedBox(height: Sp.md),
        Text('Tip: lay the receipt flat, fill the frame and avoid shadows. Photos of invoices, till slips and screenshots all work.', style: muted(c)),
      ]),
    );
    if (src == null || !mounted) return;
    setState(() => scanning = true);
    final rec = TextRecognizer(script: TextRecognitionScript.latin);
    XFile? x;
    try {
      LockService.allowBackgroundFor(const Duration(minutes: 3)); // the camera backgrounds the app - don't lock on return
      x = await ImagePicker().pickImage(source: src, imageQuality: 92, maxWidth: 3000);
      LockService.allowBackgroundFor(const Duration(seconds: 3));
      if (x == null) return;
      final res = await rec.processImage(InputImage.fromFilePath(x.path));
      // Use word positions so "Total:" and its value are matched even when OCR splits them into separate lines.
      final lines = [for (final b in res.blocks) for (final l in b.lines) OcrLine(l.text, l.boundingBox)];
      final r = lines.isEmpty ? parseReceiptText(res.text) : parseReceiptLines(lines);
      if (!mounted) return;
      setState(() {
        income = false;
        final d = r.date;
        if (d != null) date = r.dateHasTime ? d : DateTime(d.year, d.month, d.day, date.hour, date.minute);
      });
      manualCat = false;
      if (r.currency != null && kCurrencies.contains(r.currency)) curN.value = r.currency!;
      if (r.total != null) { amt.text = fmtInput(r.total!); amtErr.value = null; }
      final m = r.merchant;
      if (m != null && m.isNotEmpty) {
        note.text = m.length > 60 ? m.substring(0, 60) : m;
        final g = guessCat(m);
        if (g != null) catN.value = g;
      }
      final found = [if (m != null && m.isNotEmpty) m, if (r.total != null) money(r.total!, curN.value), if (r.date != null) DateFormat('d MMM yyyy').format(r.date!)];
      snack(context, r.total == null ? 'Could not find a total on that receipt - please enter the amount.' : r.confident ? 'Scanned: ${found.join(' · ')}' : 'Scanned (best guess for the amount): ${found.join(' · ')} - please check it.');
    } on PlatformException {
      if (mounted) snack(context, 'Camera or gallery unavailable. Check that SpendWise has permission.');
    } catch (_) {
      if (mounted) snack(context, 'Scan failed. Try again with better light or a flatter receipt.');
    } finally {
      await rec.close();
      // The receipt photo is sensitive - don't leave it in the cache.
      if (x != null) { try { await File(x.path).delete(); } catch (_) {} }
      if (mounted) setState(() => scanning = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(date));
    if (!mounted) return;
    setState(() => date = DateTime(d.year, d.month, d.day, t?.hour ?? date.hour, t?.minute ?? date.minute));
  }

  Future<void> _delete() async {
    final e = widget.edit!;
    if (!await confirm(context, 'Delete transaction?', 'This will remove it from your history.')) return;
    if (!mounted) return;
    final s = context.read<AppState>();
    s.removeTxn(e.id);
    Navigator.pop(context);
    showUndoSnack('Transaction deleted', () => s.saveTxn(e));
  }

  void _save() {
    if (saving) return;
    final v = parseAmount(amt.text);
    if (v == null) { amtErr.value = 'Enter an amount greater than 0'; return; }
    final s = context.read<AppState>();
    final e = widget.edit;
    final cur = curN.value;
    final keepBase = e != null && e.currency == cur && e.amount == v;
    if (!keepBase && !s.canConvert(cur)) {
      amtErr.value = 'No exchange rate for $cur yet. Go online once, or pick ${s.base}.';
      return;
    }
    var cat = catN.value;
    final valid = s.cats.where((c) => c.income == income).toList();
    if (valid.isNotEmpty && !valid.any((c) => c.id == cat)) cat = valid.first.id;
    saving = true;
    final tagList = tags.text.split(',').map((t) => t.trim().replaceFirst(RegExp(r'^#+'), '')).where((t) => t.isNotEmpty).map((t) => t.length > 24 ? t.substring(0, 24) : t).toSet().take(10).toList();
    final t = Txn(id: _id, amount: v, currency: cur, base: keepBase ? e!.base : s.toBase(v, cur), income: income, cat: cat, date: date, note: note.text.trim(), tags: tagList);
    final warn = e == null && !income ? s.budgetWarning(t) : null;
    final incWarn = e == null && !income ? s.incomeWarning(t) : null;
    s.saveTxn(t);
    HapticFeedback.mediumImpact();
    Navigator.pop(context);
    final allWarns = [if (warn != null) warn, if (incWarn != null) incWarn];
    if (allWarns.isNotEmpty) messengerKey.currentState?..clearSnackBars()..showSnackBar(SnackBar(content: Text(allWarns.join('\n')), backgroundColor: C.amber, showCloseIcon: true, duration: const Duration(seconds: 5)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.edit == null ? 'New transaction' : 'Edit transaction'),
        actions: [
          IconButton(tooltip: 'Scan receipt', onPressed: scanning ? null : _scan, icon: scanning ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.document_scanner_rounded)),
          if (widget.edit != null) IconButton(tooltip: 'Delete', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded, color: C.red)),
          const SizedBox(width: Sp.xs),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(Sp.page, Sp.sm, Sp.page, 40),
        children: [
          SegmentedButton<bool>(
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: false, label: Text('Expense'), icon: Icon(Icons.north_east_rounded, size: 18)), ButtonSegment(value: true, label: Text('Income'), icon: Icon(Icons.south_west_rounded, size: 18))],
            selected: {income},
            onSelectionChanged: (v) => _setIncome(v.first),
          ),
          const SizedBox(height: Sp.xl),
          _AmountCard(amt: amt, focus: amtFocus, err: amtErr, cur: curN),
          const SectionTitle('Category'),
          RepaintBoundary(child: _CategoryPicker(income: income, selected: catN, onPick: (id) { catN.value = id; manualCat = true; })),
          const SizedBox(height: Sp.xl),
          TextField(
            controller: note,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            onChanged: (v) { if (!manualCat && !income) { final g = guessCat(v); if (g != null && g != catN.value) catN.value = g; } },
            decoration: const InputDecoration(labelText: 'Note (e.g. Dinner with Sarah)', counterText: '', prefixIcon: Icon(Icons.notes_rounded)),
          ),
          const SizedBox(height: Sp.md),
          TextField(controller: tags, maxLength: 120, decoration: const InputDecoration(labelText: 'Tags (comma separated)', counterText: '', prefixIcon: Icon(Icons.tag_rounded))),
          const SizedBox(height: Sp.md),
          Panel(
            onTap: _pickDate,
            child: Row(children: [
              Icon(Icons.event_rounded, color: cs.primary),
              const SizedBox(width: Sp.md),
              Expanded(child: Text(DateFormat('EEE, d MMM yyyy · h:mm a').format(date), style: bold)),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
          const SizedBox(height: Sp.xxl),
          PrimaryButton(label: 'Save transaction', icon: Icons.check_rounded, expand: true, onTap: _save),
        ],
      ),
    );
  }
}

/// Big amount input + currency picker + a fixed-height hint line.
class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.amt, required this.focus, required this.err, required this.cur});
  final TextEditingController amt;
  final FocusNode focus;
  final ValueNotifier<String?> err;
  final ValueNotifier<String> cur;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = context.read<AppState>();
    context.select<AppState, Object>((s) => s.rates); // rebuild when exchange rates arrive
    final base = context.select<AppState, String>((s) => s.base);
    final amtColor = Theme.of(context).brightness == Brightness.dark ? Colors.white : cs.onSurface;
    return Panel(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 12, Sp.md, 10),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: amt,
              focusNode: focus,
              onChanged: (_) { if (err.value != null) err.value = null; },
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(14)],
              style: display(38, color: amtColor),
              cursorColor: amtColor,
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: display(38, color: amtColor.o(.28)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: Sp.sm),
          ValueListenableBuilder<String>(
            valueListenable: cur,
            builder: (_, c, __) => PopupMenuButton<String>(
              tooltip: 'Currency',
              onSelected: (v) { cur.value = v; err.value = null; },
              itemBuilder: (_) => [for (final x in {...kCurrencies, base, c}) PopupMenuItem(value: x, child: Text(x, style: bold))],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
                decoration: BoxDecoration(color: cs.primary.o(.12), borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Text(c, style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary)), Icon(Icons.expand_more_rounded, size: 20, color: cs.primary)]),
              ),
            ),
          ),
        ]),
        ListenableBuilder(
          listenable: Listenable.merge([amt, err, cur]),
          builder: (_, __) {
            final e = err.value, typed = parseAmount(amt.text), c = cur.value;
            final text = e ?? (c != base && typed != null && s.canConvert(c) ? '≈ ${money(s.toBase(typed, c), base)}' : null);
            if (text == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: e != null ? const TextStyle(color: C.red, fontWeight: FontWeight.w600, fontSize: 13) : muted(context)),
              ),
            );
          },
        ),
      ]),
    );
  }
}

/// Category chips. Rebuilds only when the category list, the income/expense
/// toggle or the selection changes.
class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.income, required this.selected, required this.onPick});
  final bool income;
  final ValueNotifier<String> selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final cats = context.select<AppState, List<Category>>((s) => s.cats);
    final byId = {for (final c in cats) c.id: c};
    final list = cats.where((c) => c.income == income).toList();
    if (list.isEmpty) return const SizedBox(height: 56, child: Center(child: CircularProgressIndicator()));
    return ValueListenableBuilder<String>(
      valueListenable: selected,
      builder: (_, sel, __) => Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
        for (final c in list)
          FilterChoiceChip(
            key: ValueKey(c.id),
            avatar: Icon(iconFor(c.icon), size: 18, color: Color(c.color)),
            label: c.parent == null ? c.name : '${byId[c.parent]?.name ?? 'Other'} › ${c.name}',
            selected: sel == c.id,
            onSelected: () => onPick(c.id),
          ),
      ]),
    );
  }
}
