# LifeBase

Your calendar, to-dos, money, home, career and health in one private place.
LifeBase is a web app you install from a link. There's no App Store and no account,
and **your data never leaves your device**.

## Install it

**iPhone / iPad:** open the link in **Safari** → tap **Share** → **Add to Home Screen**.

**Mac:** open the link in **Safari** → **File › Add to Dock**.
(Chrome: ⋮ menu → **Cast, save and share › Install page as app**.)

**Android / Windows:** open the link in Chrome → ⋮ menu → **Install app**.

It opens full-screen like any other app and works offline.

## Your data is yours

- Everything you enter is stored **only in this browser on this device**. Nobody else
  can see it, including whoever runs this copy of LifeBase.
- Your phone and your laptop each keep their **own** copy; they don't sync.
  To move data between them, use **Profile › Backup & restore**: download a backup on
  one device and restore it on the other.
- **Back up regularly.** Clearing your browser's website data, or deleting the app,
  erases your LifeBase data. LifeBase reminds you when a backup is overdue.
- Files you attach to documents (insurance cards, deeds) stay on the device and
  aren't included in backups. Keep the originals.
- **Community** (optional) is the one part that uses an account (email and password).
  Only what you post (wins, comments, challenge totals, shared expenses) and your
  display name and email are stored, on the host's Supabase database, and only
  members of groups you join can see your posts. You can delete all of it from
  **Profile › Delete my Community data**.
- If AI features are on, the text of an AI request (for example, a quick-add note,
  or your question plus a summary of your LifeBase data for **Ask**) is sent to
  Anthropic's API through this app's AI proxy to get an answer. The proxy keeps
  only a monthly request count per device, not the content.

## Getting started

Open the app and follow **Get LifeBase set up** on Home. It walks you through
accounts, bills, your home, insurance and the rest, and disappears once you're done.

---

## For the person hosting this copy

### 1. Put the app online (free, GitHub Pages)

1. Create a GitHub repo (for example `lifebase`) and push these files to it.
2. In the repo: **Settings › Pages › Build and deployment**: Source *Deploy from a branch*,
   branch `main`, folder `/ (root)`. Save.
3. After a minute it's live at `https://<your-username>.github.io/lifebase/`.
   Send that link to friends.

### 2. Turn on AI features (optional)

AI powers quick add, Ask, step-by-step guides and checkup advice. It needs an
Anthropic API key, kept on a tiny proxy so it's never exposed in the app, with a
monthly cap per person and overall.

1. Get an API key at <https://console.anthropic.com> and **set a monthly spend
   limit there too** (Settings › Limits). That's your final safety net.
2. Install Node.js, then in the `worker` folder:
   ```sh
   npx wrangler login
   npx wrangler kv namespace create USAGE      # paste the id into wrangler.toml
   npx wrangler secret put ANTHROPIC_API_KEY   # paste your key when asked
   ```
3. In `worker/wrangler.toml`, set `ALLOWED_ORIGINS` to your Pages address
   (for example `https://<your-username>.github.io`) and adjust the limits:
   `MONTHLY_LIMIT` is requests per person per month, `GLOBAL_MONTHLY_LIMIT` is
   the ceiling across everyone.
4. Deploy: `npx wrangler deploy`. It prints a URL like
   `https://lifebase-ai.<you>.workers.dev`.
5. Put that URL in `config.js` (`aiEndpoint: '...'`), commit and push.

The per-person limit uses an anonymous device id, so a determined person could
get around it. The overall limit and your Console spend limit are what actually
protect your bill.

### 3. Turn on Community (optional)

Community gives friends accounts (email + password), private groups joined with an
invite code, a feed for wins, workout challenges with a leaderboard, and shared
costs that work out who owes whom.

1. Create a free project at <https://supabase.com>. Use a strong password and turn on
   two-factor login for your Supabase account: it protects everyone's posts.
2. **SQL Editor › New query**: paste all of `supabase/schema.sql` and **Run**. This
   creates the tables and the access rules (each person only sees groups they're in,
   and only changes what they created).
3. **Authentication › Providers › Email**: keep Email on. Choose whether new accounts
   must confirm their email ("Confirm email"). Leaving it on stops typos and fake
   sign-ups; turning it off lets friends start immediately.
   In the same Email settings, set **Minimum password length** to 10.
4. **Authentication › URL Configuration**: set **Site URL** to your app's address
   (for example `https://<you>.github.io/lifebase/`) and add it to **Redirect URLs**,
   so password-reset emails come back to the app.
5. **Project Settings › API**: copy the **Project URL** and the **anon public** key
   into `config.js` (`supabaseUrl`, `supabaseAnonKey`). Commit and push.

**Your responsibilities as host:** keep your Supabase login secure; if someone asks,
delete their account under **Authentication › Users** (the app already lets them
delete their posts and data themselves); and don't share the `service_role` key
with anyone or put it in the app.

The access rules are tested: `supabase/tests/rls.test.mjs` runs them against a
local Postgres (`npm i @electric-sql/pglite && node supabase/tests/rls.test.mjs`).

### 4. Updating the app

The app is one file: `src/lifebase.html`. Edit it, then run

```sh
python3 build.py
```

which regenerates `index.html` and `sw.js`. Commit and push; installed copies pick
up the update the next time they're opened online.

### 5. Moving your own data in

If you've been using LifeBase inside Claude: open it there, go to
**Profile › Backup & restore › Download backup**, then in the installed app
**Profile › Backup & restore › Restore from backup**.

### Files

| Path | What it is |
|---|---|
| `src/lifebase.html` | The app (single file; also runs inside Claude as an artifact) |
| `build.py` | Builds `index.html` + `sw.js` from the source |
| `index.html`, `sw.js` | Generated: the installable app and its offline cache |
| `config.js` | Your settings (AI proxy URL) |
| `manifest.webmanifest`, `icons/` | App name and icons for Home Screen / Dock |
| `worker/` | The optional AI proxy (Cloudflare Worker) |
| `supabase/schema.sql` | Community database and access rules |
| `supabase/tests/` | Automated test of the access rules |
