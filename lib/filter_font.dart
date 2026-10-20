import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typeface used ONLY by the filter / sort buttons (Week · Month · Year,
/// All · Expenses · Income) and the category chips in "New transaction".
/// Everything else in the app keeps its original fonts.
///
/// [classic] is the original look (the platform default font) - pick it in
/// Settings > Appearance to revert.
enum FilterFont {
  jakarta('Plus Jakarta Sans', 'Jakarta'),
  dmSans('DM Sans', 'DM Sans'),
  classic('Classic (original)', 'Classic');

  const FilterFont(this.label, this.short);
  final String label, short;

  TextStyle style({double size = 14, FontWeight weight = FontWeight.w700, Color? color}) => switch (this) {
        FilterFont.jakarta => GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: weight, color: color),
        FilterFont.dmSans => GoogleFonts.dmSans(fontSize: size, fontWeight: weight, color: color),
        // Exactly what the app used before: no family, just size + weight.
        FilterFont.classic => TextStyle(fontSize: size, fontWeight: weight, color: color),
      };

  static FilterFont parse(String? name) => FilterFont.values.firstWhere((f) => f.name == name, orElse: () => FilterFont.jakarta);

  /// Downloads (first run) / loads the font files before they are needed so
  /// text never swaps from a fallback font to the real one mid-screen.
  Future<void> preload() async {
    if (this == classic) return;
    try {
      await GoogleFonts.pendingFonts([style(weight: FontWeight.w600), style(weight: FontWeight.w700)]).timeout(const Duration(seconds: 4));
    } catch (_) {/* offline: falls back gracefully */}
  }
}
