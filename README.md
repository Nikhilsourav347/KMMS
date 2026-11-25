# Unique Knitting Mills

This Flutter app is in local testing mode. It stores data in an app-private database on Android and in IndexedDB on web. Use test credentials. Each installation or browser origin has its own records.

## Getting started

1. Complete onboarding and create the first local Admin account. Save its recovery key.
2. Sign in with **Admin Login**. In **Profile**, add staff accounts and register machines. Save and privately share each new staff member’s recovery key.
3. Sign out and use **Manager Login** to enter daily machine status, schedule machines and record jobs and production. Day and Night are the production shifts. A night entry uses the date its shift starts.
4. Open **Reports** to inspect results. Job-wise and Day-wise PDFs show the relevant order details, total ordered quantity and balance. The Day-wise PDF calculates the balance through the selected date.
5. Use the system back button or the page’s back arrow to return to the dashboard. The web build uses hash routes, so refreshing an internal URL starts at the local login if there is no active session.

Administrators see the same local data on the same installation and have read-only access to status and schedules. Removing a machine archives its registration, which preserves prior records and frees up its machine number for a new registration. Clearing app data, clearing the browser’s site data or uninstalling can remove local records.

## Run and build

Use Flutter 3.38.6 or newer, an Android SDK for Android builds, and Chrome for local web development. On Windows without Developer Mode, set `$env:FLUTTER_WINDOWS = 'false'` first.

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --web-port 8080
flutter run -d <android-device-id>
$env:UKM_TEST_SIGNING = '1'
flutter build apk --release --target-platform android-arm64
flutter build web --release --base-href /KMMS/
```

For Android distribution, unset `UKM_TEST_SIGNING` and configure the company signing key using `android/key.properties.example`. The current web build uses the future GitHub Pages base path. For hosting at the root of a local server, use `--base-href /`. To test on iPhone Safari, serve the web build over HTTPS. Browser storage is specific to that origin.

## Project layout

- `lib/app/` contains startup, dashboard and platform back navigation.
- `lib/core/` contains local credential storage, profiles, operational transactions and Riverpod providers.
- `lib/features/` contains authentication, profiles, machines, scheduling, jobs, production and reporting.
- `test/` contains automated local workflow, navigation, mobile layout and report checks.
- `supabase/` contains previously prepared server migrations. The local app has no Supabase configuration.
