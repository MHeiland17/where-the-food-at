# Supabase setup — Where The Food At

About 15 minutes. Everything here is on Supabase's free plan.

## 1. Create the project
1. Sign in at <https://supabase.com/dashboard> and click **New project**.
2. Name it `where-the-food-at`, set a strong **database password** (store it in your password manager;
   the app never needs it), and pick the region closest to you (e.g. **Sydney** for Australia).
3. Wait a minute or two for it to finish provisioning.

## 2. Create the tables and security rules
1. Go to **SQL Editor → New query**.
2. Paste the whole of [`supabase/schema.sql`](supabase/schema.sql) and click **Run**.
3. Check **Table Editor**: you should see `workspaces`, `workspace_members` and `places`, each marked
   **RLS enabled**.

The script also adds a trigger, so every new user automatically gets their own workspace ("My places").

## 3. Configure sign-in
Go to **Authentication → Sign In / Providers** (the menu name varies slightly between dashboard versions):

- **Email** provider: enabled (the default).
- **Confirm email:** leave **on** (recommended). You'll click a link in an email once per account.
  Supabase's built-in email sender is rate-limited to a few emails an hour, which is fine for 2 people.

Then **Authentication → URL Configuration**:
- **Site URL:** `http://localhost:5500` for now. This is where confirmation links send you.
- **Redirect URLs:** add `http://localhost:5500/**`.
- When you host the app later (Netlify / Vercel / Cloudflare Pages), add that URL too and make it the
  Site URL.

## 4. Connect the app
1. Go to **Project Settings → API** (or **Connect**).
2. Copy the **Project URL** and the **publishable key** (`sb_publishable_…`). On older projects it's called
   the **anon public** key; either works.
3. Paste them into [`config.js`](config.js):
   ```js
   window.WTFA_CONFIG = {
     supabaseUrl: "https://abcdefgh.supabase.co",
     supabaseKey: "sb_publishable_…",
   };
   ```

> The publishable/anon key is **meant** to be in the browser. Row-level security is what protects the data.
> **Never** put the `service_role` / secret key in `config.js`.

## 5. Run it and create your account
```bash
node serve.js
```
Open <http://localhost:5500>, choose **Create account**, confirm via the email, then sign in.

## 6. Add the second family member (shared list)
1. They open the app and create their own account (step 5). They get an empty workspace of their own.
2. In **SQL Editor**, run this with both email addresses filled in:
   ```sql
   insert into public.workspace_members (workspace_id, user_id, role)
   select w.id, member.id, 'editor'
   from public.workspaces w
   join auth.users owner  on owner.id = w.created_by
   join auth.users member on member.email = 'THEIR_EMAIL_HERE'
   where owner.email = 'YOUR_EMAIL_HERE'
     and w.name = 'My places';
   ```
3. They reload the app and pick your list from the workspace menu in the top bar. The app remembers the
   choice.

## 7. Lock down sign-ups
Once both accounts exist: **Authentication → Sign In / Providers → turn off "Allow new users to sign up"**.
Nobody else can create an account, even if they find the URL.

## 8. Google Places search (fill in a new entry from Google)
Needs the Google Cloud set-up (Places API (New) enabled, a key restricted to it) and the key stored as the
Supabase secret `GOOGLE_PLACES_KEY` (**Edge Functions → Secrets**).

1. **Database:** run [`supabase/002_google_search.sql`](supabase/002_google_search.sql) in the **SQL Editor**.
   It adds `google_place_id` / `snapshot_at` to `places` and the daily usage counter.
2. **Server function:** **Edge Functions → Deploy a new function → Via Editor**.
   - Name it exactly `places`.
   - Replace the sample code with the contents of
     [`supabase/functions/places/index.ts`](supabase/functions/places/index.ts) → **Deploy function**.
   - Open the function → **Details** (or **Settings**) → turn **Verify JWT / Enforce JWT verification**
     **off** → save. The function checks the signed-in user itself.

   Command-line alternative (from the project folder):
   ```bash
   npx supabase login
   npx supabase functions deploy places --project-ref dijpdzeswufcyqsatdut --no-verify-jwt --use-api
   ```
3. **Try it:** sign in → **Add a place** → type a name → **Search** → pick a result → **Fill in details**.

Daily caps live in the function (`DAILY_LIMITS`: 200 searches, 50 fill-ins). If the app is ever served
from a new address, add it to `ALLOWED_ORIGINS` at the top of the function and redeploy.

## Good to know
- **Free projects pause after ~7 days with no activity.** Unpause from the dashboard with one click.
  Your data is kept.
- **Forgot your password:** use **Authentication → Users → … → Send password recovery** in the dashboard
  (the app has no reset screen yet).
- **Backups:** the free plan has no point-in-time restore. Occasionally export `places` as CSV from
  **Table Editor** if you want a copy.
