# Where the Food At — notes for AI assistants

- **Before any UI change, read [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)** and follow it: use the `:root` tokens in
  `index.html` (no raw pixel heights/gaps), wrap side-by-side fields in `.row`, keep controls on one line on the same
  height token, and follow the autofill rules for place fields. Run its checklist before finishing.
- The app is a single static page: `index.html` + `config.js`. Run locally with `node serve.js` (port 5500).
  Append `?demo` to the URL to test without touching real data.
- Supabase: schema in `supabase/schema.sql` (re-runnable), Google Places proxy in `supabase/functions/places`.
  Secrets (Google key, OAuth secret, Supabase secret key) never go in the repo.
- Live site: GitHub Pages from `main` at https://mheiland17.github.io/where-the-food-at/.
