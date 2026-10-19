# Privacy policy website

`index.html` is a single self-contained page (no external files), ready to host.

## Before publishing
1. Replace `agamcoder@gmail.com` (2 places in `index.html`) with a real, monitored email.
2. If you add Google Play Games sign-in, update the text first: it will then use the internet and process your Play Games player ID, and the Play Console Data safety form must match.

## Host it free on GitHub Pages (about 2 minutes)
1. Create a public GitHub repo, e.g. `inktide-privacy`.
2. Upload `index.html` to the repo root.
3. Repo **Settings > Pages > Build and deployment**: Source = *Deploy from a branch*, Branch = `main`, folder = `/ (root)`. Save.
4. After a minute your URL is `https://<your-github-username>.github.io/inktide-privacy/`.
5. Open it in a private browser window to confirm it loads without login.
6. Paste that URL into **Play Console > App content > Privacy policy**.

Alternatives: Netlify Drop (drag the folder onto app.netlify.com/drop) or Cloudflare Pages. The page must be public, an HTML page (not a PDF), and not geo-blocked.
