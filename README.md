# Where the Food At

A small personal/family app for keeping a list of restaurants, cafés and bars we've saved, and filtering it
for real situations: "Sunday lunch near Mum's, 8 people, easy parking."

- **Front end:** a single static page ([index.html](index.html)), no build step.
- **Back end:** [Supabase](https://supabase.com) for sign-in (Google or email) and the database.
- **Hosting:** GitHub Pages (or any static host).

## Run it locally

```bash
node serve.js
```

Then open <http://localhost:5500>. With empty values in [config.js](config.js) the app runs in **demo mode**
(sample data, saved in your browser only).

## Set-up

- Supabase project, tables and sign-in: [SUPABASE_SETUP.md](SUPABASE_SETUP.md)
- Database schema: [supabase/schema.sql](supabase/schema.sql) (safe to re-run)
- Scope, decisions and roadmap: [PROJECT_SCOPE.md](PROJECT_SCOPE.md)

## About config.js

`config.js` contains the Supabase **project URL** and **publishable key**. Both are designed to be public;
the database's row-level security rules are what protect the data. Never put the Supabase secret/service-role
key, the Google Places API key or the Google OAuth client secret in this repo. They live in Supabase.
