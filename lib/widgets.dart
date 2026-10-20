import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'filter_font.dart';
import 'state.dart';
import 'ui.dart';

// ───────────────────────── filter font widgets ─────────────────────────

/// Segmented filter (Week / Month / Year, ...) that follows the user's
/// "filter font" setting. Use it wherever a segmented sort/filter is needed.
class FilterTabs<T> extends StatelessWidget {
  const FilterTabs({super.key, required this.segments, required this.selected, required this.onChanged});
  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) {
    final font = context.select<AppState, FilterFont>((s) => s.filterFont);
    return SegmentedButton<T>(
      expandedInsets: EdgeInsets.zero,
      showSelectedIcon: false,
      segments: segments,
      selected: {selected},
      onSelectionChanged: (v) => onChanged(v.first),
      style: ButtonStyle(textStyle: WidgetStatePropertyAll(font.style(size: 14, weight: FontWeight.w700))),
    );
  }
}

/// Choice chip that follows the user's "filter font" setting
/// (Activity filters, category chips in "New transaction").
class FilterChoiceChip extends StatelessWidget {
  const FilterChoiceChip({super.key, required this.label, required this.selected, required this.onSelected, this.avatar});
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Widget? avatar;
  @override
  Widget build(BuildContext context) {
    final font = context.select<AppState, FilterFont>((s) => s.filterFont);
    return ChoiceChip(
      avatar: avatar,
      label: Text(label, style: font.style(size: 13.5, weight: FontWeight.w600)),
      labelStyle: font.style(size: 13.5, weight: FontWeight.w600),
      selected: selected,
      onSelected: (_) { HapticFeedback.selectionClick(); onSelected(); },
    );
  }
}

// ───────────────────────── avatars ─────────────────────────

class AvatarOption {
  const AvatarOption(this.id, this.icon, this.color, this.label);
  final String id, label;
  final IconData icon;
  final Color color;
}

const kAvatars = <AvatarOption>[
  AvatarOption('man_1', Icons.face_6_rounded, Color(0xFF3E9BC4), 'Alex'),
  AvatarOption('woman_1', Icons.face_3_rounded, Color(0xFFD9648C), 'Maya'),
  AvatarOption('man_2', Icons.face_rounded, Color(0xFF2E9E6B), 'Sam'),
  AvatarOption('woman_2', Icons.face_4_rounded, Color(0xFFE08A3C), 'Zara'),
  AvatarOption('person_1', Icons.person_rounded, Color(0xFF8A6FD1), 'Taylor'),
  AvatarOption('elder', Icons.face_5_rounded, Color(0xFFB98355), 'Morgan'),
  AvatarOption('woman_3', Icons.face_2_rounded, Color(0xFFD9574F), 'Elena'),
  AvatarOption('pro', Icons.badge_rounded, Color(0xFF4F86D9), 'Jordan'),
  AvatarOption('smile', Icons.sentiment_satisfied_alt_rounded, Color(0xFF2BA39A), 'Sunny'),
  AvatarOption('student', Icons.school_rounded, Color(0xFFD4A62A), 'Student'),
  AvatarOption('creator', Icons.palette_rounded, Color(0xFFC96F4A), 'Creative'),
  AvatarOption('engineer', Icons.engineering_rounded, Color(0xFF5DBE92), 'Builder'),
];

const kInitialAvatar = 'initial';

/// Profile picture: the user's initial by default, or one of [kAvatars].
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.id, required this.name, this.radius = 23});
  final String id, name;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final opt = kAvatars.where((a) => a.id == id).firstOrNull;
    final letter = name.trim().isEmpty ? '' : name.trim()[0].toUpperCase();
    final Widget face = opt == null
        ? CircleAvatar(
            key: ValueKey('initial-$letter'),
            radius: radius,
            backgroundColor: cs.primary.o(.14),
            child: letter.isNotEmpty ? Text(letter, style: display(radius * .87, color: cs.primary)) : Icon(Icons.person_rounded, color: cs.primary, size: radius * 1.1),
          )
        : CircleAvatar(key: ValueKey(opt.id), radius: radius, backgroundColor: opt.color, child: Icon(opt.icon, color: Colors.white, size: radius * 1.05));
    return SizedBox(width: radius * 2, height: radius * 2, child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: face));
  }
}
