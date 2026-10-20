import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../common.dart';

String _authMessage(FirebaseAuthException e) {
  switch (e.code) {
    // Same message for "no such user" and "wrong password" so the form can't be
    // used to find out which emails have accounts.
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
    case 'invalid-login-credentials':
      return 'Incorrect email or password. If you used Google Sign-In, tap Google or "Forgot password?".';
    case 'invalid-email':
      return 'That email address does not look right.';
    case 'email-already-in-use':
      return 'An account with this email already exists. Try signing in.';
    case 'weak-password':
      return 'Choose a stronger password (at least 8 characters).';
    case 'too-many-requests':
      return 'Too many attempts. Please wait a moment and try again.';
    case 'network-request-failed':
      return 'No internet connection. Check your network and try again.';
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'account-exists-with-different-credential':
      return 'This email is registered with a different sign-in method.';
    default:
      return 'Something went wrong. Please try again.';
  }
}

bool _validEmail(String s) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(s);

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController(), pass = TextEditingController(), nick = TextEditingController();
  bool signup = false, busy = false, hide = true;
  String? emailErr, passErr, nickErr;

  @override
  void dispose() { email.dispose(); pass.dispose(); nick.dispose(); super.dispose(); }

  Future<void> _run(Future<void> Function() f) async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    try {
      await f();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'canceled' && e.code != 'web-context-canceled' && e.code != 'popup-closed-by-user') snack(context, _authMessage(e));
    } on PlatformException catch (e) {
      debugPrint('PlatformException during auth: ${e.code} - ${e.message} - ${e.details}');
      if (e.code == 'sign_in_canceled' || e.code == 'canceled') {
        // User cancelled - do nothing
      } else if (e.code == 'sign_in_failed') {
        snack(context, 'Google Sign-In failed. Please check your internet connection and try again.');
      } else {
        snack(context, 'Sign-in error: ${e.message ?? 'Please try again.'}');
      }
    } catch (e) {
      debugPrint('Auth error: $e');
      snack(context, 'Something went wrong. Please try again.');
    }
    if (mounted) setState(() => busy = false);
  }

  bool _validate({bool needPass = true}) {
    final e = email.text.trim();
    setState(() {
      emailErr = _validEmail(e) ? null : 'Enter a valid email address';
      passErr = !needPass ? null : pass.text.isEmpty ? 'Enter your password' : signup && pass.text.length < 8 ? 'Use at least 8 characters' : null;
      nickErr = signup ? validateNickname(nick.text) : null;
    });
    return emailErr == null && passErr == null && nickErr == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    final a = FirebaseAuth.instance;
    await _run(() async {
      if (signup) {
        final state = context.read<AppState>();
        final cred = await a.createUserWithEmailAndPassword(email: email.text.trim(), password: pass.text);
        if (cred.user != null) {
          await state.setNicknameFor(cred.user!.uid, nick.text.trim());
          try { await cred.user?.sendEmailVerification(); } catch (_) {}
        }
      } else {
        try {
          await a.signInWithEmailAndPassword(email: email.text.trim(), password: pass.text);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'invalid-credential' || e.code == 'wrong-password' || e.code == 'user-not-found' || e.code == 'invalid-login-credentials') {
            List<String> methods = [];
            try {
              methods = await a.fetchSignInMethodsForEmail(email.text.trim());
            } catch (_) {}
            if (methods.contains('google.com') && !methods.contains('password')) {
              if (mounted) _showGoogleLinkedDialog();
              return;
            }
          }
          rethrow;
        }
      }
    });
  }

  void _showGoogleLinkedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Google Account Found'),
        content: const Text(
          'This email is registered with Google Sign-In, so password login is currently inactive.\n\n'
          'You can sign in with Google now, or send a password reset link to reactivate your password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _forgot();
            },
            child: const Text('Reset Password'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _signInWithGoogle();
            },
            child: const Text('Sign in with Google'),
          ),
        ],
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    final a = FirebaseAuth.instance;
    await _run(() async {
      final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
      await googleSignIn.signOut(); // Clear cached account to always show picker
      final gUser = await googleSignIn.signIn();
      if (gUser == null) return; // user cancelled
      final gAuth = await gUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );
      final userCred = await a.signInWithCredential(credential);
      final user = userCred.user;
      if (user != null && pass.text.length >= 8) {
        try {
          await user.linkWithCredential(EmailAuthProvider.credential(email: user.email!, password: pass.text));
        } catch (_) {}
      }
    });
  }

  Future<void> _forgot() async {
    if (!_validate(needPass: false)) return;
    await _run(() async {
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email.text.trim());
      } on FirebaseAuthException catch (e) {
        if (e.code != 'user-not-found') rethrow;
      }
      if (mounted) snack(context, 'If an account exists for that email, a reset link is on its way.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = FirebaseAuth.instance;
    final apple = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(children: [
        Positioned(top: -110, right: -90, child: IgnorePointer(child: CustomPaint(size: const Size(340, 340), painter: _RingsPainter(cs.primary.o(.12))))),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(Sp.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Reveal(child: Align(alignment: Alignment.centerLeft, child: Container(width: 60, height: 60, decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 30)))),
                    const SizedBox(height: Sp.xl),
                    Reveal(
                      index: 1,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Align(key: ValueKey(signup), alignment: Alignment.centerLeft, child: Text(signup ? 'Start your\nledger.' : 'Welcome\nback.', style: display(44))),
                      ),
                    ),
                    const SizedBox(height: Sp.md),
                    Reveal(index: 2, child: Text('Know where your money goes, without the spreadsheet.', style: muted(context).copyWith(fontSize: 15))),
                    const SizedBox(height: 28),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: signup
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: Sp.md),
                              child: TextField(
                                controller: nick, enabled: !busy, maxLength: 20, textInputAction: TextInputAction.next,
                                autocorrect: false, enableSuggestions: false,
                                inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                                onChanged: (_) { if (nickErr != null) setState(() => nickErr = null); },
                                decoration: InputDecoration(labelText: 'Nickname', counterText: '', errorText: nickErr, helperText: nickErr == null ? 'No spaces. Shown on your home screen.' : null, prefixIcon: const Icon(Icons.alternate_email_rounded)),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    Reveal(
                      index: 3,
                      child: TextField(
                        controller: email, enabled: !busy, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email], autocorrect: false, enableSuggestions: false,
                        onChanged: (_) { if (emailErr != null) setState(() => emailErr = null); },
                        decoration: InputDecoration(labelText: 'Email', errorText: emailErr, helperText: ' ', prefixIcon: const Icon(Icons.mail_outline_rounded)),
                      ),
                    ),
                    const SizedBox(height: Sp.md),
                    Reveal(
                      index: 4,
                      child: TextField(
                        controller: pass, enabled: !busy, obscureText: hide, textInputAction: TextInputAction.done, onSubmitted: (_) => _submit(),
                        autofillHints: [signup ? AutofillHints.newPassword : AutofillHints.password], autocorrect: false, enableSuggestions: false,
                        onChanged: (_) { if (passErr != null) setState(() => passErr = null); },
                        decoration: InputDecoration(
                          labelText: 'Password', errorText: passErr, helperText: signup ? 'At least 8 characters' : ' ',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(tooltip: hide ? 'Show password' : 'Hide password', icon: Icon(hide ? Icons.visibility_off_rounded : Icons.visibility_rounded), onPressed: () => setState(() => hide = !hide)),
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: signup
                          ? const SizedBox(height: Sp.lg, width: double.infinity)
                          : Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: busy ? null : _forgot,
                                child: Text('Forgot password?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 13.5)),
                              ),
                            ),
                    ),
                    const SizedBox(height: Sp.sm),
                    Reveal(index: 5, child: PrimaryButton(label: signup ? 'Create account' : 'Sign in', onTap: busy ? null : _submit, busy: busy, expand: true)),
                    const SizedBox(height: Sp.xl),
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: Sp.md), child: Text('or continue with', style: muted(context))),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: Sp.xl),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(onPressed: busy ? null : _signInWithGoogle, icon: const Icon(Icons.g_mobiledata_rounded, size: 30), label: Text('Google', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)))),
                      if (apple) ...[
                        const SizedBox(width: Sp.md),
                        Expanded(child: OutlinedButton.icon(onPressed: busy ? null : () => _run(() async { await a.signInWithProvider(AppleAuthProvider()); }), icon: const Icon(Icons.apple_rounded), label: Text('Apple', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)))),
                      ],
                    ]),
                    const SizedBox(height: Sp.lg),
                    TextButton(
                      onPressed: busy ? null : () => setState(() { signup = !signup; emailErr = null; passErr = null; nickErr = null; }),
                      child: Text(
                        signup ? 'Already have an account? Sign in' : 'New here? Create an account',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = color;
    final c = size.center(Offset.zero);
    for (var i = 1; i <= 5; i++) { canvas.drawCircle(c, size.width / 2 * i / 5, p); }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.color != color;
}

// ───────────────────────── PIN lock ─────────────────────────
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlock});
  final VoidCallback onUnlock;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with SingleTickerProviderStateMixin {
  String pin = '';
  bool wrong = false, checking = false, askOut = false;
  Duration? wait;
  Timer? _tick;
  late final AnimationController shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = context.read<AppState>();
    // If the PIN is gone (e.g. keychain wiped) don't lock the user out of their own data.
    if (!await LockService.hasPin()) {
      await s.setBool('lock', false);
      await s.setBool('bio', false);
      if (mounted) widget.onUnlock();
      return;
    }
    final w = await LockService.lockoutLeft();
    if (!mounted) return;
    if (w != null) { _startCountdown(w); } else if (s.bioOn) { _bio(); }
  }

  @override
  void dispose() { _tick?.cancel(); shake.dispose(); super.dispose(); }

  void _startCountdown(Duration d) {
    _tick?.cancel();
    setState(() => wait = d);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = (wait ?? Duration.zero) - const Duration(seconds: 1);
      if (!mounted) return;
      if (left <= Duration.zero) { t.cancel(); setState(() { wait = null; wrong = false; }); } else { setState(() => wait = left); }
    });
  }

  Future<void> _bio() async { if (await LockService.bio() && mounted) widget.onUnlock(); }

  Future<void> _tap(String d) async {
    if (checking || wait != null || pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() { pin += d; wrong = false; });
    if (pin.length < 4) return;
    checking = true;
    final r = await LockService.check(pin);
    checking = false;
    if (!mounted) return;
    if (r.ok) { widget.onUnlock(); return; }
    HapticFeedback.heavyImpact();
    shake.forward(from: 0);
    setState(() { pin = ''; wrong = true; });
    if (r.wait != null) _startCountdown(r.wait!);
  }

  // The lock layer lives above the Navigator, so dialogs would be hidden behind
  // it - the confirmation is shown inline instead.
  Future<void> _signOut() async {
    final s = context.read<AppState>();
    await LockService.clear();
    await s.setBool('lock', false);
    await s.setBool('bio', false);
    await s.signOut();
  }

  String _fmtWait(Duration d) => d.inMinutes >= 1 ? '${d.inMinutes}m ${d.inSeconds % 60}s' : '${d.inSeconds}s';

  Widget _key(Widget child, VoidCallback? onTap, {bool fill = true}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(Sp.sm),
      child: SizedBox(
        width: 72, height: 72,
        child: Material(
          color: fill && onTap != null ? cs.surface : Colors.transparent,
          shape: CircleBorder(side: fill && onTap != null ? BorderSide(color: cs.onSurface.o(.07)) : BorderSide.none),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Center(child: child)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bio = context.select<AppState, bool>((s) => s.bioOn);
    final cs = Theme.of(context).colorScheme;
    Widget digit(String d) => _key(Text(d, style: display(28, w: FontWeight.w500)), () => _tap(d));
    final msg = wait != null ? 'Too many attempts. Try again in ${_fmtWait(wait!)}' : wrong ? 'Wrong PIN, try again' : 'Enter your PIN';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: Sp.lg),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 60, height: 60, decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.lock_rounded, color: Colors.white, size: 28)),
              const SizedBox(height: Sp.lg),
              AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: Text(msg, key: ValueKey(msg), textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: wrong || wait != null ? C.red : null))),
              const SizedBox(height: Sp.xl),
              AnimatedBuilder(
                animation: shake,
                builder: (_, ch) => Transform.translate(offset: Offset(sin(shake.value * pi * 5) * (1 - shake.value) * 14, 0), child: ch),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < 4; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutBack,
                      margin: const EdgeInsets.symmetric(horizontal: Sp.sm),
                      width: 16, height: 16,
                      transform: Matrix4.diagonal3Values(i < pin.length ? 1.15 : 1, i < pin.length ? 1.15 : 1, 1),
                      transformAlignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: i < pin.length ? (wrong ? C.red : cs.primary) : Colors.transparent, border: Border.all(color: wrong ? C.red : cs.primary, width: 2)),
                    ),
                ]),
              ),
              const SizedBox(height: Sp.xl),
              for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']]) Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) digit(d)]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _key(bio ? Icon(Icons.fingerprint_rounded, size: 32, color: cs.primary) : const SizedBox(), bio ? _bio : null, fill: false),
                digit('0'),
                _key(const Icon(Icons.backspace_outlined), pin.isEmpty ? null : () => setState(() => pin = pin.substring(0, pin.length - 1)), fill: false),
              ]),
              const SizedBox(height: Sp.lg),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: askOut
                    ? Padding(
                        key: const ValueKey('ask'),
                        padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            const Text('Reset your PIN?', style: bold),
                            const SizedBox(height: Sp.sm),
                            Text('The only way is to sign out. Your data stays safe in your account - sign back in and set a new PIN.', style: muted(context)),
                            const SizedBox(height: Sp.lg),
                            Row(children: [
                              Expanded(child: OutlinedButton(onPressed: () => setState(() => askOut = false), child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)))),
                              const SizedBox(width: Sp.md),
                              Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: C.red, foregroundColor: Colors.white), onPressed: _signOut, child: Text('Sign out', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)))),
                            ]),
                          ])),
                        ),
                      )
                    : TextButton(key: const ValueKey('forgot'), onPressed: () => setState(() => askOut = true), child: Text('Forgot PIN?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 13.5))),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
