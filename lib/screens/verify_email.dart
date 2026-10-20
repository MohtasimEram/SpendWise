import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../common.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> with WidgetsBindingObserver {
  bool checking = false;
  bool resending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Periodically check every 4 seconds if the user verified in their browser/email app
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _checkVerified(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkVerified(silent: true);
    }
  }

  Future<void> _checkVerified({bool silent = false}) async {
    if (checking) return;
    if (!silent) setState(() => checking = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.reload();
      if (!mounted) return;
      final updatedUser = FirebaseAuth.instance.currentUser;
      if (updatedUser?.emailVerified == true) {
        context.read<AppState>().refreshUser();
      } else if (!silent) {
        snack(context, 'Your email is not verified yet. Please check your inbox (and spam folder) and click the link.');
      }
    } catch (_) {
      if (!silent && mounted) snack(context, 'Could not check verification. Please try again.');
    } finally {
      if (!silent && mounted) setState(() => checking = false);
    }
  }

  Future<void> _resend() async {
    if (resending) return;
    setState(() => resending = true);
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) snack(context, 'Verification link sent! Check your inbox and spam folder.');
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code == 'too-many-requests') {
          snack(context, 'Please wait a moment before requesting another email.');
        } else {
          snack(context, 'Failed to send email. Please try again later.');
        }
      }
    } catch (_) {
      if (mounted) snack(context, 'Failed to send email. Please try again later.');
    } finally {
      if (mounted) setState(() => resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final email = s.user?.email ?? '';
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Sp.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: cs.primary.o(.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.mark_email_unread_rounded, size: 40, color: cs.primary),
                    ),
                  ),
                  const SizedBox(height: Sp.xl),
                  Text(
                    'Verify your email',
                    textAlign: TextAlign.center,
                    style: display(32),
                  ),
                  const SizedBox(height: Sp.md),
                  Text(
                    'We sent a verification link to:',
                    textAlign: TextAlign.center,
                    style: muted(context).copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: Sp.xs),
                  Text(
                    email,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: Sp.md),
                  Text(
                    'Click the link in the email to activate your account. Once verified, you will be able to enter SpendWise.',
                    textAlign: TextAlign.center,
                    style: muted(context).copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: Sp.xxl),
                  PrimaryButton(
                    label: "I've verified my email",
                    icon: Icons.check_circle_rounded,
                    expand: true,
                    busy: checking,
                    onTap: checking ? null : () => _checkVerified(silent: false),
                  ),
                  const SizedBox(height: Sp.md),
                  OutlinedButton.icon(
                    onPressed: resending ? null : _resend,
                    icon: resending
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded),
                    label: Text(resending ? 'Sending...' : 'Resend email'),
                  ),
                  const SizedBox(height: Sp.lg),
                  TextButton(
                    onPressed: () => s.signOut(),
                    child: const Text('Wrong email? Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
