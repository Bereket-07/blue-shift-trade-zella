# ZellaBek — Setup & Deploy Guide

Follow these steps in order. Total time: ~15 minutes.

## Step 1 — Create the database (2 min)

1. Open your Supabase dashboard → your project
2. Left sidebar → **SQL Editor** → **New query**
3. Open the file `supabase-setup.sql` (in this folder), copy ALL of it, paste it in, press **Run**
4. You should see: `Success. No rows returned`

## Step 2 — Deploy the site (3 min)

1. Go to **netlify.com** → sign up free → on the dashboard find **"Deploy manually"** (or drag & drop area under Sites)
2. Drag this whole folder (`zellabek-site`) onto it
3. Netlify gives you a URL like `https://something.netlify.app` — this is your site!
   (You can rename it: Site settings → Change site name → e.g. `zellabek`)

## Step 3 — Tell Supabase your site URL (1 min)

1. Supabase dashboard → **Authentication** → **URL Configuration**
2. Set **Site URL** to your Netlify URL (e.g. `https://zellabek.netlify.app`)
3. Under **Redirect URLs**, add the same URL

Without this step, Google login and email confirmation links will redirect to the wrong place.

## Step 4 — Enable Google login (5 min)

1. Supabase dashboard → **Authentication** → **Sign In / Providers** → **Google** → toggle ON
2. On that panel, copy the **Callback URL** — it looks like:
   `https://gwiwyvaznhmjggsrtstl.supabase.co/auth/v1/callback`
3. Go to **console.cloud.google.com** → APIs & Services → Credentials → your OAuth client:
   - Under **Authorized redirect URIs** → Add → paste the Callback URL from step 2
   - Under **Authorized JavaScript origins** → Add → your Netlify URL
   - Save
4. **IMPORTANT — reset your client secret** (it was shown in a screenshot):
   In the same Google client page click **Reset secret**, copy the NEW secret
5. Back in Supabase's Google provider panel: paste your Google **Client ID** and the NEW **Client secret** → Save
6. Google consent screen: while your app is in "Testing" mode, only test users can log in.
   Google Auth Platform → **Audience** → either add your email under **Test users**, or click **Publish app**

## Step 5 — (Optional) Instant email signup

By default Supabase requires new users to confirm their email.
To skip that: Authentication → Sign In / Providers → **Email** → turn OFF "Confirm email".

## Done!

Open your Netlify URL on any device — phone or PC. Create your account,
import your MT5 statement, and everything (trades, notes, emotions,
screenshots) syncs to your account automatically.

## Security reminders

- If you haven't already: rotate the **secret key** you pasted in chat
  (Supabase → Settings → API Keys → ⋮ next to the secret key → rotate/delete)
- Never share `sb_secret_...` keys or Google client secrets with anyone.
  The `sb_publishable_...` key inside index.html is safe — it's meant to be public.
