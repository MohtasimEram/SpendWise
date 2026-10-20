import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// PIN + biometric app lock.
///
/// * The PIN is never stored: only a salted, iterated SHA-256 hash lives in the
///   platform keystore / keychain.
/// * Wrong attempts are counted and punished with an increasing delay
///   (persisted, so restarting the app does not reset it).
/// * Legacy plain-text PINs written by v1.0 are migrated on first successful use.
class LockService {
  static const _s = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static final _auth = LocalAuthentication();
  static const _iterations = 20000;

  // ---- grace window for system pickers (camera / share sheet) ----
  static DateTime? _bypassUntil;

  /// Call right before launching a system UI that backgrounds the app, so it
  /// does not trigger the lock when the user comes back.
  static void allowBackgroundFor(Duration d) => _bypassUntil = DateTime.now().add(d);

  /// True (once) if the app was backgrounded on purpose a moment ago.
  static bool consumeBypass() {
    final u = _bypassUntil;
    _bypassUntil = null;
    return u != null && DateTime.now().isBefore(u);
  }

  // ---- hashing ----
  static List<int> _hash(String pin, List<int> salt) {
    final p = utf8.encode(pin);
    var h = sha256.convert([...salt, ...p]).bytes;
    for (var i = 0; i < _iterations; i++) {
      h = sha256.convert([...h, ...salt, ...p]).bytes;
    }
    return h;
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) { r |= a[i] ^ b[i]; }
    return r == 0;
  }

  static Future<bool> hasPin() async => (await _s.read(key: 'pin')) != null;

  static Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    await _s.write(key: 'pin', value: 'v1:${base64Url.encode(salt)}:${base64Url.encode(_hash(pin, salt))}');
    await _resetFails();
  }

  static Future<void> clear() async {
    await _s.delete(key: 'pin');
    await _resetFails();
  }

  // ---- attempts / lockout ----
  static Future<void> _resetFails() async {
    await _s.delete(key: 'pin_fails');
    await _s.delete(key: 'pin_until');
  }

  /// Remaining lockout time, or null when attempts are allowed.
  static Future<Duration?> lockoutLeft() async {
    final u = int.tryParse(await _s.read(key: 'pin_until') ?? '');
    if (u == null) return null;
    final left = DateTime.fromMillisecondsSinceEpoch(u).difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  /// Checks a PIN. [wait] is set when the user is (now) locked out.
  static Future<({bool ok, Duration? wait})> check(String pin) async {
    final wait = await lockoutLeft();
    if (wait != null) return (ok: false, wait: wait);
    final stored = await _s.read(key: 'pin');
    var ok = false;
    if (stored != null) {
      if (stored.startsWith('v1:')) {
        final parts = stored.split(':');
        if (parts.length == 3) {
          try {
            ok = _same(_hash(pin, base64Url.decode(parts[1])), base64Url.decode(parts[2]));
          } catch (_) {
            ok = false;
          }
        }
      } else if (_same(utf8.encode(stored), utf8.encode(pin))) {
        ok = true;
        await setPin(pin); // migrate legacy plain-text PIN
      }
    }
    if (ok) {
      await _resetFails();
      return (ok: true, wait: null);
    }
    final fails = (int.tryParse(await _s.read(key: 'pin_fails') ?? '') ?? 0) + 1;
    await _s.write(key: 'pin_fails', value: '$fails');
    if (fails >= 5) {
      final secs = min(30 * pow(2, fails - 5).toInt(), 900);
      final until = DateTime.now().add(Duration(seconds: secs));
      await _s.write(key: 'pin_until', value: '${until.millisecondsSinceEpoch}');
      return (ok: false, wait: Duration(seconds: secs));
    }
    return (ok: false, wait: null);
  }

  // ---- biometrics ----
  static Future<bool> bioAvailable() async {
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> bio() async {
    try {
      allowBackgroundFor(const Duration(seconds: 30));
      return await _auth.authenticate(localizedReason: 'Unlock SpendWise', options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true));
    } catch (_) {
      return false;
    } finally {
      allowBackgroundFor(const Duration(seconds: 2));
    }
  }
}
