# SpendWise - Expense Tracker (Flutter + Firebase)

Offline-first expense tracker with a warm "paper ledger" look (light/dark), animated and touch-friendly.

## Features
**Core:** email/Google/Apple sign-in · PIN + biometric lock · income & expense logging (amount, currency, category, date/time, notes, tags) · dashboard (balance, income vs expenses, daily stats, recent list) · preset + custom categories & subcategories · pie/bar analytics (week/month/year, vs previous period)

**Advanced:** receipt scanning (on-device ML Kit OCR → merchant, total, date) · per-category weekly/monthly budgets with 80%/100% warnings · recurring transactions (auto-posted, idempotent across devices) · multi-currency with live exchange rates (cached offline) · shared expenses & bill splitting with simplified settle-up · CSV/Excel + PDF export · savings goals · net-worth tracker · smart auto-categorisation from notes · search & filters · swipe-to-delete with undo · offline-first via Firestore persistence · dark mode

**Not included (needs a backend):** bank/card sync (Plaid/Yapily - requires server-side token exchange, e.g. Cloud Functions) and push notifications (FCM). Budget alerts are shown in-app.

## Setup
1. Install Flutter (3.29+), then in this folder run `flutter create . --project-name spendwise --org com.example` to generate `android/` and `ios/`. Existing `lib/` and `pubspec.yaml` are kept.
2. Create a Firebase project; enable **Authentication** (Email/Password, Google, Apple) and **Firestore**.
3. `dart pub global activate flutterfire_cli && flutterfire configure` (adds `google-services.json` / `GoogleService-Info.plist`). Make sure the Android Gradle files apply the `com.google.gms.google-services` plugin (flutterfire does this in recent versions). Add your debug SHA-1/SHA-256 in Firebase for Google sign-in (`cd android && ./gradlew signingReport`).
4. **Deploy the new security rules** (they now validate every field): `firebase deploy --only firestore:rules`.
5. Platform config:
   - **Android:** `minSdkVersion 23`; `MainActivity` must extend `FlutterFragmentActivity` (local_auth); manifest: `USE_BIOMETRIC`, `CAMERA`, and on `<application>` set `android:allowBackup="false"` so financial data is never copied into cloud/adb backups.
   - **iOS:** platform `15.5`+; `NSFaceIDUsageDescription`, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` in `Info.plist`; *Sign in with Apple* capability.
6. **App icon:** `dart run flutter_launcher_icons` (reads the `flutter_launcher_icons:` block in `pubspec.yaml`; icon source files are in `assets/icon/`). Prefer to do it by hand? Copy `platform_icons/android/res/*` into `android/app/src/main/res/` and `platform_icons/ios/AppIcon.appiconset` over `ios/Runner/Assets.xcassets/AppIcon.appiconset`. To change the design edit and re-run `python3 tool/make_icon.py`.
7. `flutter pub get && flutter analyze && flutter test && flutter run`

## Testing on your phone
**Android (easiest)**
1. Phone: Settings > About phone > tap *Build number* 7 times > Developer options > enable **USB debugging**.
2. Plug in via USB, accept the "Allow USB debugging" prompt, run `flutter devices` (your phone should be listed).
3. `flutter run` in this folder - the app installs and starts with hot reload.
4. No cable? `flutter build apk --release`, send `build/app/outputs/flutter-apk/app-release.apk` to the phone and open it (allow "install unknown apps"). Release builds need the release SHA-1 added in Firebase for Google sign-in; email sign-in works regardless.
5. Wireless: Developer options > *Wireless debugging* > pair with `adb pair`, then `flutter run`.

**iPhone** needs a Mac with Xcode: `open ios/Runner.xcworkspace`, select your Apple ID team under *Signing*, plug in the phone (trust the computer), then `flutter run`.

**Quick checklist:** sign up > add an expense > swipe it away and tap UNDO > turn on App lock in Settings, background the app and reopen (PIN must appear, even on sub-screens) > try a wrong PIN 5 times (lockout) > airplane mode, add a transaction, reconnect (it syncs).

## What changed in 1.2
- **Nickname at sign-up:** creating an account now asks for a nickname (3-20 characters, **no spaces**). It is shown top-left on Home and can be changed in Profile. The email is shown read-only there and can't be changed.
- **Profile lives in More:** *More > Profile* (the avatar on Home opens it too). It holds avatar, nickname, email, change password and sign out.
- **"Transaction deleted" message:** now disappears by itself after 4 s (newer Flutter keeps snack bars that have an action until swiped away) and floats *above* the Add button. The Add button is a plain overlay instead of a floating-action-button so the message never pushes it around.
- **Much better receipt scanning (OCR):** reads text *with positions*, so "Total:" is matched to its value even when the scanner splits them into separate lines; handles whole-currency amounts like `6,564` (no decimals), `1.234,56`, `৳ 1,250`, `Tk 1250`; tells Total from Subtotal / VAT / Paid / Due / Change / item counts and prefers the value several lines agree on; ignores phone numbers, SKUs and invoice numbers; fixes common OCR slips (`O`/`0`, `l`/`1`); reads dates like `15-10-2026, 07:00 PM`, `05/03/24`, `15 Oct 2026`, `Oct 15, 2026` (with time); picks the shop name from the largest top-of-page text; detects the currency (Taka/Tk/৳ → BDT, $ → USD ...); lets you scan from the camera **or the gallery**. Covered by `test/receipt_test.dart`.
- **Smoother UI:** fonts are loaded before the first frame (no more text re-flowing when a font arrives); *New transaction* focuses the amount only after its slide-in finishes, typing no longer rebuilds the page, the "≈ converted amount"/error line has a reserved height, and category chips are isolated; the tab bar / Add button no longer jump when the Activity search keyboard opens; tab fades are lighter; auth fields reserve space for validation messages.
- **Profile screen:** tap the avatar (top right of Home). Pick an avatar (initial or 12 icon avatars), edit your name, see your email, change password, sign out. The profile card and Sign out were removed from *More*, whose extra bottom space is gone. Name and avatar are now stored per account instead of per device.
- **Change password** (Profile > Security): re-authenticates with the current password, strength meter, "email me a reset link" fallback. Hidden for Google/Apple accounts (they have no SpendWise password).
- **App icon:** coin-with-S mark in the app's green/clay palette, adaptive + monochrome (themed) Android icon and the full iOS set.
- **Filter font:** Week/Month/Year, the Activity filters and the category chips in *New transaction* now use Plus Jakarta Sans. Settings > Appearance > *Filter & category font* lets you switch to DM Sans or **Classic** (the original look). No other text changed.

## What changed in 1.1 (bug fixes & security)
**Security**
- Lock screen is now a layer above the whole navigator - before, sub-screens (Add, Budgets, Settings...) stayed visible while "locked". App-switcher thumbnail is hidden.
- PIN stored as salted, iterated hash (old plain-text PINs migrate automatically); 5 wrong tries trigger an increasing lockout (persisted); disabling/changing the PIN requires the current PIN; PIN entry is confirmed twice and weak PINs rejected; "Forgot PIN" path via sign-out.
- Firestore rules validate type, size and range of every field and deny unknown collections.
- CSV export neutralises formula injection and shares from private cache (old exports are deleted); receipt photos are deleted after OCR.
- Amount input rejects NaN/Infinity/negatives/huge values; text lengths capped; login errors no longer reveal whether an email exists; raw exception text is never shown to users.
**Bugs**
- Swipe-to-delete crashed/misbehaved (used a dead BuildContext); now optimistic with working UNDO.
- Base-currency change converted with the wrong rates when offline and left budgets/goals/net-worth unconverted; now atomic-ish, converts everything or nothing.
- Recurring items were priced before exchange rates loaded, drifted off the 31st, and could resurrect deleted rules; fixed. They also run on app resume.
- Double-tap on Save created duplicates; `1,234.56` / `12,50` amounts were rejected; the receipt scanner crashed without camera permission; invalid receipt dates rolled over silently.
- Month-vs-month insight compared a partial month with a full one; now compares the same point in time. Chart crashed/glitched with zero data.
- Split bills used floating-point (balances could be off by a cent) and concurrent edits overwrote each other; now integer cents + `arrayUnion`. Expenses/groups can be deleted.
- One malformed document no longer wipes a whole list; listener errors are reported instead of silently killing sync; the whole app no longer rebuilds on every Firestore snapshot.
- Keyboard-overflow in bottom sheets, FAB hiding the last list row, crowded icon rows (replaced by tap + overflow menu), Android back button on tabs.
**UI**
- New look: warm paper/ink palette, deep-green hero card, serif display numerals (Fraunces) + Manrope - replaces the violet/cyan gradient look. Consistent 4/8/12/16/24 spacing scale, 44px+ touch targets.
- Motion: staggered entrances, count-up balances, animated progress bars/rings, press-in scale on cards & buttons, tab cross-fade, slide-up Add screen, shake on wrong PIN, interactive pie/bar tooltips.

## Structure
```
lib/main.dart            entry, auth gate, AppLock layer
lib/state.dart           AppState (Firestore listeners, FX, budgets, recurring)
lib/lock_service.dart    hashed PIN, lockout, biometrics
lib/models.dart          Txn, Category, Budget, Recurring, Goal, Account, Group
lib/ui.dart              theme, spacing, animated widgets, dialogs/sheets
lib/widgets.dart         FilterTabs / FilterChoiceChip (filter font), Avatar + avatar options
lib/filter_font.dart     FilterFont enum (Jakarta / DM Sans / Classic)
assets/icon/             app icon sources (full, adaptive foreground, monochrome)
platform_icons/          ready-made Android mipmaps + iOS AppIcon set
tool/make_icon.py        regenerates every icon from code
lib/screens/             auth+lock, home+activity, profile, add (OCR), insights, tools (budgets/goals/...), more (menu/export/settings)
test/logic_test.dart     unit tests (amount parsing, split maths, recurring dates, receipt parsing)
firestore.rules          validated per-user rules
```
Data lives under `users/{uid}/{transactions|categories|budgets|recurring|goals|accounts|groups}`.

> Note: this code was written without a Flutter SDK available, so it has not been compiled. Run `flutter analyze` first; fix any minor version-related warnings and report anything bigger.
