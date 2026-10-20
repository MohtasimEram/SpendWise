<div align="center">

  <h1>💰 SpendWise</h1>
  <p><strong>A Modern, Offline-First Personal Finance & Expense Tracker built with Flutter & Firebase</strong></p>

  <p>
    <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" /></a>
    <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" /></a>
    <a href="https://firebase.google.com"><img src="https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" alt="Firebase" /></a>
    <a href="https://www.android.com"><img src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android" /></a>
    <img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="License" />
  </p>

  <p><em>Know where your money goes — without the spreadsheet.</em></p>

</div>

---

## 🌟 Overview

**SpendWise** is a full-featured, privacy-focused personal finance manager designed with a warm "paper ledger" aesthetic. It combines intuitive day-to-day transaction tracking with advanced features like on-device receipt scanning (OCR), smart multi-currency conversion, real-time budgeting alerts, shared bill splitting, and biometric security.

Built with an **offline-first** architecture powered by Cloud Firestore persistence, SpendWise works flawlessly with or without an active internet connection.

---

## ✨ Key Features

### 📊 1. Effortless Expense & Income Tracking
- **Quick Logging:** Record income and expenses in seconds with custom categories, tags, notes, dates, and payment accounts.
- **Smart Categorization:** Automatically predicts the right category based on your transaction notes.
- **Swipe Actions:** Intuitive swipe-to-delete with instant Undo capability.
- **Activity & Search:** Powerful search across notes, tags, and categories with filter chips and clean empty states.

### 📸 2. On-Device Receipt Scanner (ML Kit OCR)
- Scan paper receipts using your phone's camera or pick an image from your gallery.
- Extracts merchant/shop names, transaction dates, tax/VAT, and totals automatically.
- Detects currencies (USD, BDT, EUR, GBP, etc.) and handles various number formats (`1,250.00`, `1.250,00`, `৳ 1250`).
- Runs completely on-device for maximum speed and privacy (receipt images are immediately cleaned up after scanning).

### 🎯 3. Smart Budgeting & Goal Tracking
- **Category & Monthly Budgets:** Set spending limits per category or across your entire month.
- **Real-Time Warning Alerts:** Visual indicators warn you when you reach **80%** (amber) and **100%+** (red) of your budget.
- **Savings Goals:** Track progress toward specific savings milestones with target amounts and deadlines.

### 📈 4. Visual Insights & Analytics
- Dynamic breakdowns comparing weekly, monthly, and yearly cash flow.
- Interactive donut and bar charts showing where your money actually goes.
- Trend comparisons against previous time periods to spot spending habits.

### 👥 5. Shared Expenses & Group Bill Splitting
- Split shared dinners, apartment rent, or road trips with friends and roommates.
- Computes optimal settlement amounts so everyone knows who owes whom with minimal transactions.

### 🔄 6. Recurring Transactions & Multi-Currency
- **Automated Bills:** Set up salary, rent, and subscriptions once — SpendWise logs them automatically.
- **Multi-Currency Engine:** Seamlessly converts international amounts using live exchange rates, cached offline.

### 🔒 7. Enterprise Security & Privacy
- **Authentication:** Dual support for **Google Sign-In (OAuth 2.0)** and **Email & Password** with an enforced email verification gate.
- **App Lock:** Protect your financial privacy with Biometric Authentication (Fingerprint / Face ID) or custom secure PIN.
- **Anti-Snooping:** Automatically blurs app contents in the OS recent apps / app-switcher view.

---

## 🛠️ Technology Stack

| Layer | Technology |
|---|---|
| **Framework** | [Flutter](https://flutter.dev) (v3.29+) |
| **Language** | [Dart](https://dart.dev) |
| **Backend & Database** | [Google Firebase](https://firebase.google.com) (Authentication & Cloud Firestore) |
| **Machine Learning** | Google ML Kit Text Recognition (On-device OCR) |
| **State Management** | Provider & ChangeNotifier (Reactive, clean separation of concerns) |
| **Security & Biometrics** | `local_auth`, Salted PBKDF2 PIN hashing |
| **Charts & Typography** | Custom Canvas Painters, Google Fonts (Manrope, Fraunces, Plus Jakarta Sans) |

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) installed (version 3.24 or higher recommended).
- [Android Studio](https://developer.android.com/studio) or VS Code with Flutter extension.
- A physical Android device or an Android Emulator (API 34/35 recommended).

### Installation & Run

1. **Clone the repository:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/SpendWise.git
   cd SpendWise
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase:**
   - Create a project on the [Firebase Console](https://console.firebase.google.com/).
   - Enable **Authentication** (Email/Password & Google Sign-In) and **Cloud Firestore**.
   - Download your `google-services.json` and place it in `android/app/google-services.json`.
   - Add your debug SHA-1 fingerprint to your Firebase Android app settings.

4. **Run the app:**
   ```bash
   flutter run
   ```

5. **Build Release APK:**
   ```bash
   flutter build apk --release
   ```
   The compiled APK will be generated at:
   `build/app/outputs/flutter-apk/app-release.apk`

---

## 📁 Project Structure

```text
lib/
├── main.dart             # App entrypoint, AuthGate, theme, and app lifecycle lock
├── common.dart           # Reusable design tokens, spacing, colors, and helpers
├── state.dart            # Central AppState (Firestore sync, transactions, budgets, rates)
├── models.dart           # Data models (Txn, Category, Budget, Goal, Group, Account)
├── ui.dart               # Core design system components (Buttons, Panels, Empty states)
├── receipt_parser.dart   # On-device ML Kit OCR parser for receipt scanning
├── lock_service.dart     # PIN security & biometric lock management
└── screens/
    ├── home.dart         # Home overview, recent transactions & Activity screen
    ├── add.dart          # Transaction creation, editing & camera receipt scan
    ├── insights.dart     # Analytics, charts, and monthly spending breakdown
    ├── tools.dart        # Budgets, Goals, Accounts, Recurring & Groups
    ├── profile.dart      # User profile, verified status, nickname, password setup
    ├── auth.dart         # Login & Sign-up (Google OAuth & Email/Password)
    └── verify_email.dart # Email verification gatekeeper screen
```

---

## 🛡️ Security & Privacy

- **Zero Third-Party Trackers:** No telemetry, ad networks, or analytical trackers.
- **Local Cache First:** Offline data stays securely stored in device sandbox storage.
- **Strict Firestore Rules:** Cloud data is locked strictly to `request.auth.uid == userId`, ensuring users can never read or write another user's financial logs.

---
