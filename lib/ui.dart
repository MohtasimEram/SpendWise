import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Global keys so state classes can show snackbars / pop routes without a
/// BuildContext (which may already be gone, e.g. after a swipe-to-delete).
final messengerKey = GlobalKey<ScaffoldMessengerState>();
final navKey = GlobalKey<NavigatorState>();

const kMaxAmount = 999999999999999.0; // ~1e15 - supports high-denomination currencies

/// Spacing scale. Everything in the app snaps to these.
class Sp {
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32;
  static const double page = 20; // horizontal screen padding
  static const double bottom = 124; // room for the floating Add button + nav bar
}

class C {
  static const brand = Color(0xFF14503C); // deep green hero surfaces
  static const green = Color(0xFF2E9E6B); // income / positive
  static const red = Color(0xFFD9573B); // expense / negative
  static const amber = Color(0xFFD99A1E);
  static const clay = Color(0xFFC96F4A); // warm accent
}

extension Op on Color {
  Color o(double v) => withAlpha((v * 255).round());
}

const kIcons = <String, IconData>{
  'food': Icons.restaurant_rounded, 'transport': Icons.directions_bus_rounded, 'shopping': Icons.shopping_bag_rounded,
  'bills': Icons.receipt_long_rounded, 'health': Icons.favorite_rounded, 'fun': Icons.movie_rounded, 'edu': Icons.school_rounded,
  'travel': Icons.flight_rounded, 'home': Icons.home_rounded, 'gift': Icons.card_giftcard_rounded, 'salary': Icons.payments_rounded,
  'invest': Icons.trending_up_rounded, 'freelance': Icons.laptop_mac_rounded, 'coffee': Icons.local_cafe_rounded,
  'pets': Icons.pets_rounded, 'fitness': Icons.fitness_center_rounded, 'sub': Icons.subscriptions_rounded, 'other': Icons.category_rounded,
};
IconData iconFor(String key) => kIcons[key] ?? Icons.category_rounded;

const kColors = [0xFF14503C, 0xFF3E9BC4, 0xFF2E9E6B, 0xFFD4A62A, 0xFFE08A3C, 0xFFD9574F, 0xFFD9648C, 0xFF8A6FD1, 0xFF4F86D9, 0xFF8C93A0];
const kCurrencies = ['USD', 'EUR', 'GBP', 'BDT', 'INR', 'JPY', 'AUD', 'CAD', 'SGD', 'AED', 'SAR', 'MYR', 'CNY', 'CHF', 'TRY'];

// ───────────────────────── formatting & parsing ─────────────────────────
final _fmts = <String, NumberFormat>{};
String money(num v, String cur) {
  final f = _fmts.putIfAbsent(cur, () {
    try {
      return NumberFormat.simpleCurrency(name: cur);
    } catch (_) {
      return NumberFormat.currency(name: cur);
    }
  });
  return f.format(v);
}

/// Parses user-typed money: accepts "12", "12.50", "12,50", "1,234.56",
/// "1.234,56". Rejects NaN, Infinity, exponents, zero/negative (unless
/// [allowNegative]) and anything absurdly large. Rounds to cents.
double? parseAmount(String input, {bool allowNegative = false}) {
  // Strip all Unicode whitespace, BOM, zero-width chars, and currency symbols
  // some keyboards inject (e.g. thin space as thousands separator).
  var t = input.trim().replaceAll(RegExp(r'[\s\u00A0\u2007\u200A\u200B\u202F\uFEFF\$€£¥₹₿₺₩₽¢]'), '');
  var neg = false;
  if (allowNegative && t.startsWith('-')) { neg = true; t = t.substring(1); }
  if (t.isEmpty) return null;
  final c = t.lastIndexOf(','), d = t.lastIndexOf('.');
  if (c >= 0 && d >= 0) {
    t = c > d ? t.replaceAll('.', '').replaceAll(',', '.') : t.replaceAll(',', '');
  } else if (c >= 0) {
    final parts = t.split(',');
    t = parts.length == 2 && parts[1].length != 3 ? '${parts[0]}.${parts[1]}' : t.replaceAll(',', '');
  }
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(t)) return null;
  final v = double.tryParse(t);
  if (v == null || !v.isFinite || v > kMaxAmount) return null;
  final r = (v * 100).roundToDouble() / 100;
  if (r == 0 && !allowNegative) return null;
  return neg ? -r : r;
}

/// Plain editable text for an amount (no trailing ".0", no exponent).
String fmtInput(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

// ───────────────────────── typography ─────────────────────────
TextStyle muted(BuildContext c) => TextStyle(fontSize: 12.5, height: 1.3, color: Theme.of(c).colorScheme.onSurface.o(.58));
const bold = TextStyle(fontWeight: FontWeight.w700, fontSize: 15);

/// Serif display face used for titles and big numbers - gives the app a
/// ledger / editorial feel instead of the usual all-sans fintech look.
TextStyle display(double size, {Color? color, FontWeight w = FontWeight.w600}) =>
    GoogleFonts.fraunces(fontSize: size, fontWeight: w, color: color, height: 1.1, letterSpacing: -size * 0.015);

const _tab = [FontFeature.tabularFigures()];
TextStyle amountStyle({double size = 15, FontWeight w = FontWeight.w800, Color? color}) => TextStyle(fontSize: size, fontWeight: w, color: color, fontFeatures: _tab);

// ───────────────────────── theme ─────────────────────────
ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? const Color(0xFF11130F) : const Color(0xFFF5F1EA);
  final surface = dark ? const Color(0xFF1A1D17) : Colors.white;
  final field = dark ? const Color(0xFF252922) : const Color(0xFFEFEAE0);
  final ink = dark ? const Color(0xFFF1EDE4) : const Color(0xFF1B1A17);
  final primary = dark ? const Color(0xFF5DBE92) : C.brand;
  final scheme = ColorScheme.fromSeed(seedColor: C.brand, brightness: b).copyWith(
    primary: primary,
    onPrimary: dark ? const Color(0xFF06241A) : Colors.white,
    secondary: C.clay,
    surface: surface,
    onSurface: ink,
    error: C.red,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: surface,
    surfaceContainerLow: surface,
    surfaceContainer: surface,
    surfaceContainerHigh: surface,
    surfaceContainerHighest: field,
  );
  final base = ThemeData(brightness: b, colorScheme: scheme, useMaterial3: true, scaffoldBackgroundColor: bg);
  final shape16 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return base.copyWith(
    textTheme: GoogleFonts.manropeTextTheme(base.textTheme).apply(bodyColor: ink, displayColor: ink),
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, centerTitle: false, surfaceTintColor: Colors.transparent,
      titleTextStyle: display(24, color: ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: primary, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: C.red, width: 1.2)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: C.red, width: 1.6)),
      labelStyle: TextStyle(color: ink.o(.6)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface, indicatorColor: primary.o(.16), height: 70, elevation: 0, surfaceTintColor: Colors.transparent,
      labelTextStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent, showDragHandle: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(64, 50), shape: shape16, textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 50), shape: shape16, side: BorderSide(color: ink.o(.16)), textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 44), padding: const EdgeInsets.symmetric(horizontal: 14), shape: shape16, textStyle: const TextStyle(fontWeight: FontWeight.w700))),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(44, 44))),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(), side: BorderSide(color: ink.o(.12)), showCheckmark: false,
      backgroundColor: Colors.transparent, selectedColor: primary.o(.16),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(shape16),
        side: WidgetStatePropertyAll(BorderSide(color: ink.o(.14))),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary.o(.16) : Colors.transparent),
        foregroundColor: WidgetStatePropertyAll(ink),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12)),
    popupMenuTheme: PopupMenuThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), color: surface, surfaceTintColor: Colors.transparent),
    dividerTheme: DividerThemeData(color: ink.o(.08), thickness: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.onPrimary : ink.o(.55)),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : field),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}

// ───────────────────────── interaction primitives ─────────────────────────

/// Surface card. When tappable it gets an ink ripple *and* a subtle press-in
/// scale, so every card feels physical.
class Panel extends StatefulWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(Sp.lg), this.onTap, this.onLongPress, this.color, this.radius = 22, this.border = true});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap, onLongPress;
  final Color? color;
  final double radius;
  final bool border;
  @override
  State<Panel> createState() => _PanelState();
}

class _PanelState extends State<Panel> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = BorderRadius.circular(widget.radius);
    final tappable = widget.onTap != null || widget.onLongPress != null;
    return AnimatedScale(
      scale: down ? .975 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: DecoratedBox(
        decoration: BoxDecoration(color: widget.color ?? cs.surface, borderRadius: r, border: widget.border ? Border.all(color: cs.onSurface.o(.07)) : null),
        child: Material(
          color: Colors.transparent,
          borderRadius: r,
          clipBehavior: tappable ? Clip.antiAlias : Clip.none,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onHighlightChanged: tappable ? (v) => setState(() => down = v) : null,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Primary call-to-action. Solid brand colour (no gradient), press-in scale,
/// haptic tick and a built-in busy state.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({super.key, required this.label, this.icon, required this.onTap, this.busy = false, this.expand = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool busy, expand;
  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onTap != null && !widget.busy;
    final bg = widget.onTap == null ? cs.onSurface.o(.14) : cs.primary;
    final fg = widget.onTap == null ? cs.onSurface.o(.4) : cs.onPrimary;
    final r = BorderRadius.circular(18);
    final btn = AnimatedScale(
      scale: down ? .96 : 1,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      child: DecoratedBox(
        decoration: BoxDecoration(color: bg, borderRadius: r, boxShadow: enabled ? [BoxShadow(color: bg.o(.30), blurRadius: 16, offset: const Offset(0, 6))] : null),
        child: Material(
          color: Colors.transparent,
          borderRadius: r,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () { HapticFeedback.lightImpact(); widget.onTap!(); } : null,
            onHighlightChanged: (v) => setState(() => down = v),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 54, minWidth: 54),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                child: Row(mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: widget.busy
                        ? SizedBox(key: const ValueKey('busy'), width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
                        : widget.icon != null ? Icon(widget.icon, key: const ValueKey('icon'), color: fg, size: 22) : const SizedBox.shrink(key: ValueKey('none')),
                  ),
                  if (widget.busy || widget.icon != null) const SizedBox(width: Sp.sm),
                  Flexible(child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(color: fg, fontWeight: FontWeight.w800, fontSize: 16))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    return widget.expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Fade + rise entrance, staggered by [index]. Only plays once per element.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;
  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> a = CurvedAnimation(parent: c, curve: Curves.easeOutCubic);
  Timer? t;
  @override
  void initState() {
    super.initState();
    t = Timer(Duration(milliseconds: 40 * widget.index.clamp(0, 10)), () { if (mounted) c.forward(); });
  }

  @override
  void dispose() { t?.cancel(); c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(a),
          child: widget.child,
        ),
      );
}

/// Number that counts up/down to its value.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.format, this.style});
  final double value;
  final String Function(double) format;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text(format(v), maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      );
}

/// Progress bar that animates to its value.
class Bar extends StatelessWidget {
  const Bar({super.key, required this.value, required this.color, this.height = 8});
  final double value, height;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final v = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: color.o(.16),
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: v),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, x, __) => FractionallySizedBox(widthFactor: x, child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)))),
        ),
      ),
    );
  }
}

/// Right-aligned text that shrinks instead of overflowing.
class FitText extends StatelessWidget {
  const FitText(this.text, {super.key, this.style, this.maxWidth = 150, this.align = Alignment.centerRight});
  final String text;
  final TextStyle? style;
  final double maxWidth;
  final Alignment align;
  @override
  Widget build(BuildContext context) => ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: FittedBox(fit: BoxFit.scaleDown, alignment: align, child: Text(text, maxLines: 1, style: style)));
}

/// Rounded tinted square holding an icon (category / feature marker).
class IconTile extends StatelessWidget {
  const IconTile(this.icon, this.color, {super.key, this.size = 46});
  final IconData icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: color.o(.15), borderRadius: BorderRadius.circular(size * .34)),
        child: Icon(icon, color: color, size: size * .5),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, Sp.xl, 0, Sp.sm),
        child: Row(children: [
          Expanded(child: Text(text, style: display(20))),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

Widget emptyState(BuildContext c, String text, {IconData icon = Icons.inbox_rounded}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: Sp.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 64, height: 64, decoration: BoxDecoration(color: Theme.of(c).colorScheme.primary.o(.1), shape: BoxShape.circle), child: Icon(icon, size: 28, color: Theme.of(c).colorScheme.primary)),
          const SizedBox(height: Sp.lg),
          Text(text, textAlign: TextAlign.center, style: muted(c).copyWith(fontSize: 14)),
        ],
      ),
    );

/// Standard scrolling page with a floating action. Rows enter with a stagger.
Widget listPage(String title, List<Widget> kids, {Widget? fab}) => Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: fab,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.page, Sp.sm, Sp.page, Sp.bottom),
        children: [for (final (i, k) in kids.indexed) Reveal(index: i, child: k)],
      ),
    );

PopupMenuItem<String> menuItem(String value, String label, IconData icon, {bool danger = false}) => PopupMenuItem(
      value: value,
      height: 48,
      child: Row(children: [Icon(icon, size: 20, color: danger ? C.red : null), const SizedBox(width: Sp.md), Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: danger ? C.red : null))]),
    );

// ───────────────────────── routes, dialogs, sheets ─────────────────────────
/// Nickname rules: 3-20 characters, letters/numbers/_ . - and NO spaces.
String? validateNickname(String v) {
  if (v.trim().isEmpty) return 'Choose a nickname';
  if (RegExp(r'\s').hasMatch(v.trim())) return 'No spaces allowed';
  final t = v.trim();
  if (t.length < 3) return 'Use at least 3 characters';
  if (t.length > 20) return 'Use at most 20 characters';
  if (!RegExp(r'^[\p{L}\p{N}_.\-]+$', unicode: true).hasMatch(t)) return 'Use letters, numbers, _ . or -';
  return null;
}

/// Removes everything a nickname may not contain (spaces, symbols).
String sanitizeNick(String v) => v.replaceAll(RegExp(r'[^\p{L}\p{N}_.\-]', unicode: true), '');

/// "X deleted - UNDO" message. Floats at the bottom of the screen.
void showUndoSnack(String message, VoidCallback onUndo) {
  messengerKey.currentState
    ?..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 4),
      persist: false,
      action: SnackBarAction(label: 'UNDO', onPressed: onUndo),
    ));
}

void snack(BuildContext c, String m) {
  messengerKey.currentState
    ?..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(m)));
}

Route<T> slideUpRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) {
        final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(opacity: curved, child: SlideTransition(position: Tween(begin: const Offset(0, .08), end: Offset.zero).animate(curved), child: child));
      },
    );

Future<T?> push<T>(BuildContext c, Widget page) => Navigator.of(c).push<T>(MaterialPageRoute(builder: (_) => page));

Future<bool> confirm(BuildContext c, String title, String body, {String action = 'Delete', bool danger = true}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        ),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: C.red, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(d, true),
          child: Text(action, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return r == true;
}

Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(Sp.page, Sp.xs, Sp.page, Sp.xl), child: builder(c)),
      ),
    );

class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: Sp.lg), child: Text(text, style: display(24)));
}

/// Inline validation message for sheets (snackbars would be hidden behind them).
class ErrorLine extends StatelessWidget {
  const ErrorLine(this.text, {super.key});
  final String? text;
  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: text == null
            ? const SizedBox(width: double.infinity)
            : Padding(padding: const EdgeInsets.only(bottom: Sp.md), child: Row(children: [const Icon(Icons.error_outline_rounded, size: 18, color: C.red), const SizedBox(width: Sp.sm), Expanded(child: Text(text!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w600, fontSize: 13)))])),
      );
}

class AskField {
  const AskField(this.label, {this.numeric = false, this.initial = '', this.obscure = false, this.maxLength = 40, this.digitsOnly = false});
  final String label, initial;
  final bool numeric, obscure, digitsOnly;
  final int maxLength;
}

/// Small prompt with one or more text fields. Returns trimmed values, or null
/// if cancelled. Save stays disabled until every field has content.
Future<List<String>?> askText(BuildContext ctx, String title, List<AskField> fields, {String action = 'Save', String? hint}) =>
    showDialog<List<String>>(context: ctx, builder: (d) => _AskDialog(title: title, fields: fields, action: action, hint: hint));

class _AskDialog extends StatefulWidget {
  const _AskDialog({required this.title, required this.fields, required this.action, this.hint});
  final String title, action;
  final String? hint;
  final List<AskField> fields;
  @override
  State<_AskDialog> createState() => _AskDialogState();
}

class _AskDialogState extends State<_AskDialog> {
  late final cs = [for (final f in widget.fields) TextEditingController(text: f.initial)];
  bool get valid => cs.every((c) => c.text.trim().isNotEmpty);
  @override
  void dispose() { for (final c in cs) { c.dispose(); } super.dispose(); }
  void _submit() { if (valid) Navigator.pop(context, cs.map((c) => c.text.trim()).toList()); }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.hint != null) Padding(padding: const EdgeInsets.only(bottom: Sp.md), child: Text(widget.hint!, style: muted(context).copyWith(fontSize: 13.5))),
            for (var i = 0; i < widget.fields.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : Sp.md),
                child: TextField(
                  controller: cs[i],
                  obscureText: widget.fields[i].obscure,
                  autofocus: i == 0,
                  maxLength: widget.fields[i].maxLength,
                  textInputAction: i == widget.fields.length - 1 ? TextInputAction.done : TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                  keyboardType: widget.fields[i].numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                  inputFormatters: widget.fields[i].digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
                  decoration: InputDecoration(labelText: widget.fields[i].label, counterText: ''),
                ),
              ),
          ]),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            onPressed: valid ? _submit : null,
            child: Text(widget.action, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
        ],
      );
}
