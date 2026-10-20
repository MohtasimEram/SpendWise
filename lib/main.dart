import 'dart:ui' show PlatformDispatcher;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'common.dart';
import 'screens/auth.dart';
import 'screens/home.dart';
import 'screens/verify_email.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never let a stray async error take the whole app down.
  PlatformDispatcher.instance.onError = (e, st) {
    debugPrint('Unhandled error: $e\n$st');
    return true;
  };
  SharedPreferences? prefs;
  Object? bootError;
  try {
    await Firebase.initializeApp();
    // Offline-first: reads/writes hit the local cache and sync when online.
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: 100 * 1024 * 1024);
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    bootError = e;
  }
  if (prefs == null) {
    runApp(SetupErrorApp(error: '$bootError'));
    return;
  }
  await _preloadFonts(prefs!);
  runApp(ChangeNotifierProvider(create: (_) => AppState(prefs!), child: const SpendWiseApp()));
}

/// Loads every typeface before the first frame. Without this, google_fonts
/// fetches them lazily and text visibly re-flows ("jumps") when each font
/// arrives. Files are cached on disk, so this is instant after the first run.
Future<void> _preloadFonts(SharedPreferences prefs) async {
  try {
    await GoogleFonts.pendingFonts([
      GoogleFonts.manropeTextTheme(),
      GoogleFonts.fraunces(fontWeight: FontWeight.w500),
      GoogleFonts.fraunces(fontWeight: FontWeight.w600),
    ]).timeout(const Duration(seconds: 4));
  } catch (_) {/* offline on the very first launch: system fonts are used until they are cached */}
  await FilterFont.parse(prefs.getString('filter_font')).preload();
}

/// Shown instead of a white crash screen when Firebase is not configured yet.
class SetupErrorApp extends StatelessWidget {
  const SetupErrorApp({super.key, required this.error});
  final String error;
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Sp.xl),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.cloud_off_rounded, size: 40, color: C.red),
                const SizedBox(height: Sp.lg),
                Text('SpendWise could not start', style: display(28)),
                const SizedBox(height: Sp.md),
                const Text('Firebase is not configured for this build. Add google-services.json (Android) or GoogleService-Info.plist (iOS) and rebuild - see the README for the exact steps.'),
                const SizedBox(height: Sp.lg),
                Text(error, maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ]),
            ),
          ),
        ),
      );
}

class SpendWiseApp extends StatelessWidget {
  const SpendWiseApp({super.key});
  @override
  Widget build(BuildContext context) {
    // Only rebuild the whole app when the theme actually changes - not on every Firestore snapshot.
    final mode = context.select<AppState, ThemeMode>((s) => s.themeMode);
    return MaterialApp(
      title: 'SpendWise',
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      scaffoldMessengerKey: messengerKey,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      builder: (context, child) => AppLock(child: child ?? const SizedBox.shrink()),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.authReady) return const _Splash();
    final u = s.user;
    if (u == null) return const AuthScreen();
    if (!u.emailVerified) return const VerifyEmailScreen();
    return const Shell();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Container(width: 72, height: 72, decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 34))));
}

/// Lock layer that sits ABOVE the Navigator, so pushed screens (Add, Settings,
/// Budgets ...) can never be seen while locked. It also hides the app contents
/// in the OS app-switcher thumbnail.
class AppLock extends StatefulWidget {
  const AppLock({super.key, required this.child});
  final Widget child;
  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  bool locked = true, covered = false, wasAway = false;
  String? uid;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    switch (s) {
      case AppLifecycleState.inactive:
        setState(() => covered = true);
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        wasAway = true;
        setState(() => covered = true);
      case AppLifecycleState.resumed:
        if (wasAway && !LockService.consumeBypass()) locked = true;
        wasAway = false;
        setState(() => covered = false);
        context.read<AppState>().onResume();
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only rebuild when the session or lock setting changes - not on every Firestore snapshot.
    final (curUid, lockOn) = context.select<AppState, (String?, bool)>((s) => (s.user?.uid, s.lockOn));
    if (curUid != uid) { uid = curUid; locked = true; } // new session => lock again
    final active = curUid != null && lockOn;
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      Positioned.fill(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: active && locked
              ? LockScreen(key: const ValueKey('lock'), onUnlock: () => setState(() => locked = false))
              : active && covered
                  ? const _PrivacyCover(key: ValueKey('cover'))
                  : const SizedBox.shrink(key: ValueKey('open')),
        ),
      ),
    ]);
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover({super.key});
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(child: Container(width: 72, height: 72, decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.lock_rounded, color: Colors.white, size: 32))),
      );
}
