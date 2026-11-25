# Unique Knitting Mills

Unique Knitting Mills uses Supabase for staff authentication and shared operational records. Follow the [Supabase setup guide](docs/supabase-setup.md) to configure a build.

## Getting started

Open the [GitHub Pages app](https://nikhilsourav347.github.io/KMMS/) in Safari or Chrome.

1. Sign in with the work account provided by your administrator. Select the login matching your staff role.
2. In the Admin **Profile**, add staff accounts and register each machine with its machine number and DIA. Machine type and other specifications are optional.
3. Sign out and use **Manager Login**. Use the ON/OFF cards for daily machine status and the monthly calendar to confirm a booking or make a scheduled machine available again. Day and Night are the production shifts. A night entry uses the date its shift starts.
4. Open **Reports** to inspect results. Job-wise and Day-wise PDFs show the relevant order details, total ordered quantity and balance. The Day-wise PDF calculates the balance through the selected date.
5. Use the system back button or the page’s back arrow to return to the dashboard. Refreshing the browser verifies the stored Supabase session.

Administrators have read-only access to status and schedules. Removing a machine archives its registration, preserves prior records, and frees up its machine number for a new registration.

## Run and build

Use Flutter 3.38.6 or newer, an Android SDK for Android builds, and Chrome for local web development. On Windows without Developer Mode, set `$env:FLUTTER_WINDOWS = 'false'` first.

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --web-port 8080 --dart-define-from-file=config.local.json
flutter run -d <android-device-id> --dart-define-from-file=config.local.json
$env:UKM_TEST_SIGNING = '1'
flutter build apk --release --target-platform android-arm64 --dart-define-from-file=config.local.json
flutter build web --release --base-href /KMMS/ --pwa-strategy=none --dart-define-from-file=config.local.json
```

For Android distribution, unset `UKM_TEST_SIGNING` and configure the company signing key using `android/key.properties.example`. For hosting the web build at the root of a local server, use `--base-href /`.

GitHub Actions builds and deploys the site on pushes to `main`. Run **Deploy Flutter to GitHub Pages** from the Actions tab to redeploy manually.

## Project layout

- `lib/app/` contains startup, dashboard and platform back navigation.
- `lib/core/` contains Supabase sessions, profile verification, operational data access and Riverpod providers.
- `lib/features/` contains authentication, profiles, machines, scheduling, jobs, production and reporting.
- `test/` contains automated local workflow, navigation, mobile layout and report checks.
- `supabase/` contains cloud schema migrations, database tests, and the staff provisioning function.
