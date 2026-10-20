import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../common.dart';

/// Profile: avatar, name, email, security (change password) and sign out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController nameC;
  bool saving = false;
  String? nickErr;

  @override
  void initState() {
    super.initState();
    nameC = TextEditingController(text: context.read<AppState>().displayName);
  }

  @override
  void dispose() { nameC.dispose(); super.dispose(); }

  Future<void> _saveName(AppState s) async {
    final v = nameC.text.trim();
    if (saving || v == s.displayName) return;
    final err = validateNickname(v);
    if (err != null) { setState(() => nickErr = err); return; }
    FocusScope.of(context).unfocus();
    setState(() { saving = true; nickErr = null; });
    await s.setDisplayName(v);
    if (!mounted) return;
    setState(() => saving = false);
    snack(context, 'Nickname updated');
  }

  Future<void> _changePassword() async {
    final done = await showSheet<bool>(context, (c) => const _ChangePasswordSheet());
    if (done == true && mounted) snack(context, 'Password updated');
  }

  Future<void> _setPassword() async {
    final done = await showSheet<bool>(context, (c) => const _SetPasswordSheet());
    if (done == true && mounted) snack(context, 'Password set! You can now sign in with either your password or Google.');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final shown = s.displayName;
    final changed = nameC.text.trim() != s.displayName;
    final provider = s.user?.providerData.map((p) => p.providerId).firstWhere((id) => id != 'firebase', orElse: () => '') ?? '';
    final social = provider == 'google.com' ? 'Google' : provider == 'apple.com' ? 'Apple' : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(Sp.page, Sp.sm, Sp.page, Sp.xxl),
        children: [
          Reveal(
            child: Column(children: [
              Avatar(id: s.avatarId, name: shown, radius: 54),
              const SizedBox(height: Sp.lg),
              Text(shown.isEmpty ? 'Your profile' : shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(28)),
              const SizedBox(height: Sp.xs),
              Text(s.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted(context).copyWith(fontSize: 14)),
            ]),
          ),
          const SectionTitle('Choose your avatar'),
          Reveal(
            index: 1,
            child: Panel(
              padding: const EdgeInsets.all(Sp.lg),
              child: Wrap(spacing: Sp.md, runSpacing: Sp.md, children: [
                _AvatarChoice(selected: s.avatarId == kInitialAvatar || !kAvatars.any((a) => a.id == s.avatarId), tooltip: 'Initial', onTap: () => s.setAvatar(kInitialAvatar), child: Avatar(id: kInitialAvatar, name: shown, radius: 26)),
                for (final a in kAvatars)
                  _AvatarChoice(selected: s.avatarId == a.id, tooltip: a.label, onTap: () => s.setAvatar(a.id), child: Avatar(id: a.id, name: shown, radius: 26)),
              ]),
            ),
          ),
          const SectionTitle('Account'),
          Reveal(
            index: 2,
            child: Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: nameC,
                  maxLength: 20,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))], // nicknames never contain spaces
                  onChanged: (_) => setState(() => nickErr = null),
                  onSubmitted: (_) => _saveName(s),
                  decoration: InputDecoration(
                    labelText: 'Nickname', counterText: '', errorText: nickErr, helperText: nickErr == null ? 'No spaces. Shown on your home screen.' : null,
                    prefixIcon: const Icon(Icons.alternate_email_rounded),
                    suffixIcon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: changed
                          ? IconButton(key: const ValueKey('save'), tooltip: 'Save nickname', icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)) : Icon(Icons.check_circle_rounded, color: cs.primary), onPressed: () => _saveName(s))
                          : const SizedBox(key: ValueKey('none'), width: 48),
                    ),
                  ),
                ),
                const SizedBox(height: Sp.md),
                TextFormField(
                  initialValue: s.email,
                  readOnly: true,
                  enableInteractiveSelection: true,
                  style: TextStyle(color: cs.onSurface.o(.75)),
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.mail_outline_rounded),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: C.green.o(.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: C.green.o(.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_rounded, size: 14, color: C.green),
                                SizedBox(width: 4),
                                Text('Verified', style: TextStyle(color: C.green, fontSize: 11.5, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Sp.sm),
                Text('Your email is tied to your account and can\'t be changed.', style: muted(context)),
              ]),
            ),
          ),
          const SectionTitle('Security'),
          Reveal(
            index: 3,
            child: s.hasPassword
                ? Panel(
                    onTap: _changePassword,
                    child: Row(children: [
                      IconTile(Icons.password_rounded, cs.primary, size: 42),
                      const SizedBox(width: Sp.md),
                      const Expanded(child: Text('Change password', style: bold)),
                      const Icon(Icons.chevron_right_rounded),
                    ]),
                  )
                : Panel(
                    onTap: _setPassword,
                    child: Row(children: [
                      IconTile(Icons.lock_reset_rounded, cs.primary, size: 42),
                      const SizedBox(width: Sp.md),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Set a password', style: bold),
                          const SizedBox(height: 2),
                          Text('Add a password to sign in with either your email & password or $social.', style: muted(context).copyWith(fontSize: 13)),
                        ]),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ]),
                  ),
          ),
          const SizedBox(height: Sp.xl),
          Reveal(
            index: 4,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: C.red.o(.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.logout_rounded, color: C.red),
              label: Text('Sign out', style: s.filterFont.style(color: C.red, size: 15, weight: FontWeight.w700)),
              onPressed: () async {
                if (await confirm(context, 'Sign out?', 'You can sign back in any time - your data stays in your account.', action: 'Sign out')) s.signOut();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({required this.selected, required this.onTap, required this.child, required this.tooltip});
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String tooltip;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        child: AnimatedScale(
          scale: selected ? 1.06 : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? cs.primary : Colors.transparent, width: 2.5)),
            child: child,
          ),
        ),
      ),
    );
  }
}

int _score(String p) {
  var n = 0;
  if (p.length >= 8) n++;
  if (p.length >= 12) n++;
  if (RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p)) n++;
  if (RegExp(r'\d').hasMatch(p) && RegExp(r'[^A-Za-z0-9]').hasMatch(p)) n++;
  return n;
}

String _msg(FirebaseAuthException e) => switch (e.code) {
      'wrong-password' || 'invalid-credential' || 'invalid-login-credentials' => 'Your current password is incorrect.',
      'weak-password' => 'Choose a stronger password (at least 8 characters).',
      'too-many-requests' => 'Too many attempts. Please wait a moment and try again.',
      'network-request-failed' => 'No internet connection. Check your network and try again.',
      'requires-recent-login' => 'For your security, sign out and sign in again, then retry.',
      'user-disabled' => 'This account has been disabled.',
      _ => 'Could not update the password. Please try again.',
    };

// ───────────────────────── change password ─────────────────────────
class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();
  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final cur = TextEditingController(), nw = TextEditingController(), cf = TextEditingController();
  bool busy = false, hide = true;
  String? err;

  @override
  void dispose() { cur.dispose(); nw.dispose(); cf.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (busy) return;
    final u = FirebaseAuth.instance.currentUser;
    String? problem;
    if (u == null || u.email == null) {
      problem = 'You are signed out. Please sign in again.';
    } else if (cur.text.isEmpty) {
      problem = 'Enter your current password.';
    } else if (nw.text.length < 8) {
      problem = 'Use at least 8 characters for the new password.';
    } else if (nw.text == cur.text) {
      problem = 'The new password must be different from the current one.';
    } else if (nw.text != cf.text) {
      problem = 'The new passwords do not match.';
    }
    if (problem != null) { setState(() => err = problem); return; }
    FocusScope.of(context).unfocus();
    setState(() { busy = true; err = null; });
    try {
      // Re-authenticate first: Firebase requires a recent login to change a password.
      await u!.reauthenticateWithCredential(EmailAuthProvider.credential(email: u.email!, password: cur.text));
      await u.updatePassword(nw.text);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { busy = false; err = _msg(e); });
    } catch (_) {
      if (mounted) setState(() { busy = false; err = 'Something went wrong. Please try again.'; });
    }
  }

  Future<void> _forgot() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;
    try { await FirebaseAuth.instance.sendPasswordResetEmail(email: email); } catch (_) {/* same message either way */}
    if (mounted) snack(context, 'If your account allows it, a reset link is on its way to $email.');
  }

  @override
  Widget build(BuildContext context) {
    final sc = _score(nw.text);
    final col = sc <= 1 ? C.red : sc == 2 ? C.amber : C.green;
    InputDecoration dec(String l, {bool eye = false}) => InputDecoration(
          labelText: l, prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: eye ? IconButton(tooltip: hide ? 'Show passwords' : 'Hide passwords', icon: Icon(hide ? Icons.visibility_off_rounded : Icons.visibility_rounded), onPressed: () => setState(() => hide = !hide)) : null,
        );
    return AutofillGroup(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetTitle('Change password'),
        TextField(controller: cur, obscureText: hide, enabled: !busy, textInputAction: TextInputAction.next, autofillHints: const [AutofillHints.password], decoration: dec('Current password', eye: true), onChanged: (_) { if (err != null) setState(() => err = null); }),
        const SizedBox(height: Sp.md),
        TextField(controller: nw, obscureText: hide, enabled: !busy, textInputAction: TextInputAction.next, autofillHints: const [AutofillHints.newPassword], decoration: dec('New password'), onChanged: (_) => setState(() => err = null)),
        const SizedBox(height: Sp.sm),
        SizedBox(
          height: 34,
          child: nw.text.isEmpty
              ? Align(alignment: Alignment.centerLeft, child: Text('At least 8 characters. Mix letters, numbers and symbols.', style: muted(context)))
              : Row(children: [Expanded(child: Bar(value: sc / 4, color: col, height: 6)), const SizedBox(width: Sp.md), Text(sc <= 1 ? 'Weak' : sc == 2 ? 'Okay' : 'Strong', style: TextStyle(color: col, fontWeight: FontWeight.w700, fontSize: 13))]),
        ),
        TextField(controller: cf, obscureText: hide, enabled: !busy, textInputAction: TextInputAction.done, autofillHints: const [AutofillHints.newPassword], onSubmitted: (_) => _submit(), decoration: dec('Confirm new password'), onChanged: (_) { if (err != null) setState(() => err = null); }),
        const SizedBox(height: Sp.md),
        ErrorLine(err),
        PrimaryButton(label: 'Update password', icon: Icons.check_rounded, expand: true, busy: busy, onTap: busy ? null : _submit),
        TextButton(onPressed: busy ? null : _forgot, child: const Text('Forgot current password? Email me a reset link')),
      ]),
    );
  }
}

class _SetPasswordSheet extends StatefulWidget {
  const _SetPasswordSheet();
  @override
  State<_SetPasswordSheet> createState() => _SetPasswordSheetState();
}

class _SetPasswordSheetState extends State<_SetPasswordSheet> {
  final nw = TextEditingController(), cf = TextEditingController();
  bool hide = true, busy = false;
  String? err;

  @override
  void dispose() { nw.dispose(); cf.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || busy) return;
    String? problem;
    if (nw.text.length < 8) {
      problem = 'Use at least 8 characters.';
    } else if (nw.text != cf.text) {
      problem = 'The passwords do not match.';
    }
    if (problem != null) { setState(() => err = problem); return; }
    FocusScope.of(context).unfocus();
    setState(() { busy = true; err = null; });
    try {
      final cred = EmailAuthProvider.credential(email: u.email!, password: nw.text);
      try {
        await u.linkWithCredential(cred);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'provider-already-linked') {
          await u.updatePassword(nw.text);
        } else {
          rethrow;
        }
      }
      await u.reload();
      if (mounted) {
        context.read<AppState>().refreshUser();
        HapticFeedback.mediumImpact();
        Navigator.pop(context, true);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { busy = false; err = _msg(e); });
    } catch (_) {
      if (mounted) setState(() { busy = false; err = 'Something went wrong. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = _score(nw.text);
    final col = sc <= 1 ? C.red : sc == 2 ? C.amber : C.green;
    InputDecoration dec(String l, {bool eye = false}) => InputDecoration(
          labelText: l, prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: eye ? IconButton(tooltip: hide ? 'Show passwords' : 'Hide passwords', icon: Icon(hide ? Icons.visibility_off_rounded : Icons.visibility_rounded), onPressed: () => setState(() => hide = !hide)) : null,
        );
    return AutofillGroup(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetTitle('Set account password'),
        Text('Add a password to your account so you can log in with either your password or Google.', style: muted(context).copyWith(fontSize: 13.5)),
        const SizedBox(height: Sp.lg),
        TextField(controller: nw, obscureText: hide, enabled: !busy, textInputAction: TextInputAction.next, autofillHints: const [AutofillHints.newPassword], decoration: dec('Password', eye: true), onChanged: (_) => setState(() => err = null)),
        const SizedBox(height: Sp.sm),
        SizedBox(
          height: 34,
          child: nw.text.isEmpty
              ? Align(alignment: Alignment.centerLeft, child: Text('At least 8 characters. Mix letters, numbers and symbols.', style: muted(context)))
              : Row(children: [Expanded(child: Bar(value: sc / 4, color: col, height: 6)), const SizedBox(width: Sp.md), Text(sc <= 1 ? 'Weak' : sc == 2 ? 'Okay' : 'Strong', style: TextStyle(color: col, fontWeight: FontWeight.w700, fontSize: 13))]),
        ),
        TextField(controller: cf, obscureText: hide, enabled: !busy, textInputAction: TextInputAction.done, autofillHints: const [AutofillHints.newPassword], onSubmitted: (_) => _submit(), decoration: dec('Confirm password'), onChanged: (_) { if (err != null) setState(() => err = null); }),
        const SizedBox(height: Sp.md),
        ErrorLine(err),
        PrimaryButton(label: 'Set password', icon: Icons.check_rounded, expand: true, busy: busy, onTap: busy ? null : _submit),
      ]),
    );
  }
}

