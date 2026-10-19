# Privacy policy website (Vercel)

`index.html` is a single self-contained page (no external files, no scripts), with `vercel.json` for headers and clean URLs. The folder is ready to deploy as a static Vercel project.

## Before publishing
1. Confirm the contact email in `index.html` (currently agamcoder@gmail.com).
2. If you add Google Play Games sign-in or other data collection, update the text first. The Play Console Data safety form must match.

## Deploy on Vercel (about 3 minutes)
1. Go to vercel.com/new and import the GitHub repo `agamsiingh/InkTide-Territory-Dash`.
2. Set **Root Directory** to `store/privacy-site`.
3. Framework preset: **Other**. Leave Build Command and Output Directory empty.
4. Click **Deploy**. Your URL is `https://<project-name>.vercel.app/`.
5. Open it in a private browser window to confirm it loads without login.
6. Paste that URL into **Play Console > App content > Privacy policy**.

Vercel CLI alternative: `cd store/privacy-site && npx vercel --prod`, then log in when asked.

The page must be public, an HTML page (not a PDF), and not geo-blocked.
