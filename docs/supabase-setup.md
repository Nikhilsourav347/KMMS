# Connect Unique Knitting Mills to Supabase

The current app requires Supabase and internet access for staff sign-in and shared records. Older offline installations keep their operational data on their original device or browser. Cloud staff accounts are provisioned separately.

## Set up the project in the Supabase Dashboard

1. In the [Supabase Dashboard](https://supabase.com/dashboard/projects), choose **New project**. Select your organization, name the project **Unique Knitting Mills**, choose a region near your staff and store the generated database password privately.
2. Go to **SQL Editor → New query**. Run the migrations below one at a time, in order, by copying the full contents of each file into a new query. Continue after each query succeeds. Migration 003 enables the Cron extension and schedules the shift rollover. If your project requires the extension to be enabled first, use **Database → Extensions → pg_cron** before retrying that file.

   - [001 · Schema and access policies](../supabase/migrations/202611250001_schema.sql)
   - [002 · Database operations](../supabase/migrations/202611250002_operations.sql)
   - [003 · Reporting and shift rollover](../supabase/migrations/202611250003_reporting_cron.sql)
   - [004 · Production sheet](../supabase/migrations/202611250004_production_sheet.sql)
   - [005 · Current app operations](../supabase/migrations/202611250005_current_app.sql)
3. Under **Authentication**, enable the **Email** provider, disable **Allow new users to sign up**, and set the minimum password length to **12**. In **URL Configuration**, use `https://nikhilsourav347.github.io/KMMS/` as the **Site URL** for this deployment.
4. In **Authentication → Users**, choose **Add user → Create new user**. Enter the first administrator’s actual work email and strong password and select **Auto Confirm User**. Copy the user’s UUID from the Users list. In **SQL Editor**, paste the query below, replace both placeholders, and run it.

   ```sql
   insert into public.profiles (id, full_name, role)
   values ('FIRST_ADMIN_USER_UUID'::uuid, 'First Admin Name', 'admin');
   ```

5. Under **Edge Functions → Deploy a new function → Via Editor**, name the function `ukm-create-account`, replace the editor contents with [the repository’s function](../supabase/functions/ukm-create-account/index.ts) and deploy. In that function’s **Details** tab, turn off the legacy JWT verification toggle. The function validates the signed-in user with Supabase Auth and verifies their active Admin role before creating any account. Supabase supplies the privileged key through the function’s environment. [Dashboard deployment](https://supabase.com/docs/guides/functions/quickstart-dashboard) · [JWT verification settings](https://supabase.com/kb/troubleshooting/edge-function-401-error-response)
6. Under **Authentication → Email Templates → Reset Password**, paste the [recovery email template](../supabase/templates/recovery.html). The template includes a reset link and a one-time code. Set the Site URL to the app root, ending with a slash. Configure **Authentication → SMTP Settings** to deliver recovery and email-change messages to staff outside the project team. [Email templates](https://supabase.com/docs/guides/auth/auth-email-templates) · [Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp)
7. Open **Connect** or **Settings → API Keys** and copy the **Project URL** and **Publishable key** (`sb_publishable_…`). These two values go into the Flutter build. Keep the database password, secret key, and service-role key private. [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys)

## Verify cloud mode before switching GitHub Pages

Create `config.local.json` in the repository root. Git ignores this file. Fill in the two client values.

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT_REF.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_REPLACE_ME"
}
```

```powershell
flutter pub get
flutter run -d chrome --dart-define-from-file=config.local.json
```

- Sign in with **Admin Login**. In **Profile**, edit the starter machine registrations to add the actual numbers and DIAs, and archive unused starter registrations. Create a test Manager using **Add Manager**.
- In a second browser profile or Android test build, sign in with **Manager Login**. Update one machine’s ON/OFF status, book and cancel a calendar date, create a job with DIA 24 and a custom design, and enter distinct Day and Night quantities. Verify that Admin can see the entries and reports, and that the Manager cannot manage staff or machine registrations.
- Reset the test Manager’s password through **Forgot password** and sign in with the new one. Once finished, disable the test Manager in **Profile**.

## Deploy the cloud build

- **GitHub Pages.** In the repository, open **Settings → Secrets and variables → Actions → Variables**. Set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. Push to `main` or run `gh workflow run deploy-pages.yml --ref main`. Confirm the workflow succeeds and open the app in Safari or Chrome. Pages uses the `/KMMS/` base path and publishes a fresh asset URL for each commit.
- **Android.** Configure the same signing key as the existing release. Use the next unused 1.x version and build number for distribution, then build with `flutter build apk --release --target-platform android-arm64 --dart-define-from-file=config.local.json`. Verify it on the Android test phone before uploading it to GitHub Releases.
