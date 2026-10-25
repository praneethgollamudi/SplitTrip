# SplitTrip — shared Supabase/Vercel starter

A static mobile-friendly web app with Supabase Auth (email magic link), trip creation and invite codes, member-only RLS, shared expenses and splits, and Realtime refreshes.

## 1. Configure Supabase

1. Open your Supabase project and choose **SQL Editor → New query**.
2. Paste all of `supabase/schema.sql` and run it.
3. In **Project Settings → API** (sometimes labelled Data API / API Keys), copy the Project URL and the publishable/anon key. Do not use the `service_role` or secret key in browser code.
4. Edit `index.html`; replace `YOUR_SUPABASE_PROJECT_URL` and `YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY`.
5. In **Authentication → URL Configuration**, add your eventual Vercel URL to Site URL and Redirect URLs. During local testing add `http://localhost:5173/**` (or your local server origin) as a redirect URL.
6. In **Authentication → Providers → Email**, configure email OTP/magic links. For reliable delivery beyond testing, configure SMTP in Supabase.

## 2. Deploy to Vercel

This is a static site; no build step is required.

1. Create a private GitHub repository named `splittrip`.
2. Upload `index.html`, `README.md`, and the `supabase/` directory to its root.
3. In Vercel choose **Add New → Project**, import that repository.
4. Framework preset: **Other**. Build command: leave empty. Output directory: `.` (the repository root). Deploy.
5. Copy the generated `https://….vercel.app` URL. In Supabase **Authentication → URL Configuration**, set Site URL to that URL and add it to Redirect URLs.
6. Open the URL, sign in with your email magic link, create a trip, and share the invite code. Each teammate signs in individually and joins with the code.

## 3. Local test (optional)

From this folder run `python3 -m http.server 5173` and open `http://localhost:5173`. Configure that origin in Supabase Auth Redirect URLs. (Opening `index.html` directly as a `file://` URL is not recommended for auth redirects.)

## Security notes / limitations

- Never expose the Supabase `service_role` or secret key in the browser or GitHub.
- RLS is enabled for all application tables. Trip creation and joining use narrowly scoped `SECURITY DEFINER` RPCs; all other reads/writes require membership.
- Invite codes are bearer invitations: anyone who gets one can join. Share privately and rotate/revoke codes before using for sensitive groups. This starter does not yet include code expiration, rate limits, owner-driven invite revocation, or per-user display-name editing.
- The browser performs expense creation and split insertion as two requests; if the second request fails, it attempts to delete the expense. For stronger atomicity, replace this with a single database RPC that inserts expense + shares in one transaction.
- Realtime subscription status is displayed, but reconnect/error UX can be improved. Settlement recommendations are informational only; no payments are initiated.
- Before production use, review RLS policies with test accounts, enable appropriate Supabase Auth protections, configure backups, and test concurrent edits.
