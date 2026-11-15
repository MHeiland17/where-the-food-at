# Where The Food At — Project Scope

_Last updated: 2026-11-15_

A personal / family app (1–2 users) for keeping a list of restaurants and cafés **we have saved**, and quickly
filtering it for a real situation:

> "Sunday lunch near Mum's place, 8 people, needs easy parking."

---

## 0. Current approach: Pass 1, lightweight manual entry (decided 2026-11-15)

**No Google APIs yet.** Pass 1 is deliberately small:

- **Supabase** for login (email + password) and the database. See [SUPABASE_SETUP.md](SUPABASE_SETUP.md) and
  [supabase/schema.sql](supabase/schema.sql).
- **Everything is entered by hand:** name, address (street / suburb / postcode / state), phone, website, meals,
  opening hours per day, max group size, price, booking method, link and notes, delivery, takeaway,
  public rating, our rating, parking ease and notes, tags, notes.
- **Filters on all of those fields.** The area search matches **postcode → suburb → street** as text on the
  saved address fields.
- **List view only.** No map yet, because a map needs coordinates.
- **One HTML file** ([index.html](index.html)) + [config.js](config.js). Run it locally with `node serve.js`.
  With no config it runs in **demo mode** (data stays in the browser).

**Pass 2 candidates** (pick when Pass 1 feels limiting):
1. Map view + radius search: geocode the typed address to lat/lng on save (OpenStreetMap Nominatim is free
   but rate-limited, or Google Geocoding), then Leaflet or Google Maps.
2. Prefill from Google Places (sections 3–5 below describe that design).
3. "Discover nearby" when nothing saved matches.
4. Busy-periods grid.

Sections 1–11 below are the **fuller Google-backed design**, kept for reference.

---

## 1. Goals and non-goals

### In scope (MVP)
- A saved list of places, viewable as a **map** and as a **list**.
- **Location search** by postcode, suburb or street address, with a radius.
- **Search Google** for places and **save** one (details are prefilled), or **add a custom place** by hand.
- **Personal fields** on each saved place (see section 4).
- **Filters:** location/radius, day + time, meal (breakfast / brunch / lunch / dinner), group size, price,
  booking, delivery, public rating, our rating, parking.
- **Booking indicator** that surfaces the phone number when there is no online booking.
- Both users share **one list** (one shared workspace).

### Later (post-MVP), in priority order
1. **"Discover nearby" fallback**: when no saved place matches, search Google around the address.
2. **Busy periods**: a grid we fill in ourselves (day × time → quiet / normal / busy).
3. Thumbnails from **our own uploaded photos**.
4. Invite UI for workspaces (MVP adds the second user by hand).

### Explicitly out of scope (scope-creep guard)
- Google Place Photos (cost; revisit only if really missed).
- Live "how busy" data from third parties (BestTime, Foursquare popularity).
- Traffic data for parking.
- Public users, sign-up flows, multiple workspaces per user.
- Native iOS / Android apps (a phone-installable web app, a PWA, is enough).

---

## 2. Tech choices

| Layer | Choice | Why |
|---|---|---|
| App | Responsive web app, installable on a phone (PWA), e.g. Next.js or SvelteKit | One codebase for phone and laptop |
| Map | Google Maps JavaScript API | Google's terms require Google data to be shown on a Google map |
| Location search | Google Places Autocomplete (New) + Geocoding | Strong coverage of Australian postcodes and suburbs |
| Place data | Google Places API (New): Text Search, Place Details | Fields match our filters almost 1:1 |
| Login + database | Supabase (Postgres + Auth, Google sign-in or magic link) | Free plan is plenty for 2 users |
| API key protection | Supabase Edge Function (server-side proxy) | Keeps the Google key off the client; enforces field masks |
| Hosting | Vercel / Netlify / Cloudflare Pages free plan | — |

---

## 3. Google Places: field tiers and cost

Google bills each request at the **most expensive tier of any field you ask for** (via the "field mask").
Each tier (SKU) has its **own free monthly allowance**. Verify current numbers at
<https://developers.google.com/maps/billing-and-pricing/pricing>.

| Tier | Example fields | Free / month (approx.) |
|---|---|---|
| Essentials | place ID, address, location, types | ~10,000 |
| Pro | display name, business status, Google Maps link, primary type | ~5,000 |
| Enterprise | rating, rating count, price level, opening hours, phone, website | ~1,000 |
| Enterprise + Atmosphere | serves breakfast/lunch/dinner, delivery, takeout, reservable, good for groups, parking options | ~1,000 |

**What this means for us:** the fields we care about are **not** in the cheapest tier, but they are **still
free up to ~1,000 calls a month**. One Place Details call returns every field we ask for and is billed once,
at the top tier. With snapshots (section 5) and 1–2 users, we expect **~20–100 calls a month, so $0**.

### Cost rules
- Always send a **minimal field mask**. Never use `*`.
- **Search results list:** request Pro fields only (name, location, address, type). Fetch the full
  Enterprise + Atmosphere details **only when a place is opened or saved**.
- Set **daily quotas and a budget alert** in Google Cloud before going live. A billing card is required even
  when usage stays within the free allowance.
- No Place Photos in the MVP.

---

## 4. Data: where each field comes from

| Filter / field | Prefilled from Google (snapshot) | Our own field (overrides Google) |
|---|---|---|
| Location | `location`, `formattedAddress` | — |
| Price | `priceLevel`, `priceRange` | `price_override` (1–4) |
| Opening hours, days | `regularOpeningHours` | — |
| Meal badges | `servesBreakfast`, `servesBrunch`, `servesLunch`, `servesDinner` | can be edited |
| Group size | `goodForGroups` | `max_group_size` (number) |
| Booking | `reservable`, `websiteUri`, `nationalPhoneNumber` | `booking_notes` |
| Delivery | `delivery`, `takeout`, `dineIn` | — |
| Rating | `rating`, `userRatingCount` | `our_rating` (1–5) |
| Parking | `parkingOptions` (patchy coverage) | `parking_ease` (1–3), `parking_notes` |
| Busy periods (later) | — | `busy_grid` |
| Notes | — | `notes` |

### Booking indicator
1. Our `booking_notes` exist → show them (always win).
2. `reservable` and a website → **"Book online"**.
3. Not reservable or unknown, but a phone number → **"No online booking · Call 03 xxxx xxxx"** (tap to call).
4. Neither → **"Walk-in / unknown"**.

### Custom places
Entered by hand. The address is geocoded once to get map coordinates. Every field is our own, and there is no
Google place ID.

---

## 5. Snapshot policy (decision)

**Decision:** when a place is saved, store a **snapshot** of its Google details, so viewing and filtering the
list costs **zero** API calls.

- Each saved place stores `google_snapshot` (JSON) and `snapshot_at`.
- The UI shows **"Details as of <date>"**, with a **Refresh** button on each place.
- **Auto-refresh** snapshots older than **30 days** when a place is opened (keeps opening hours and phone
  numbers reasonably current).
- **Terms note:** Google's terms allow storing **place IDs permanently** and **coordinates for up to 30 days**,
  but generally not other place content. Snapshots are a deliberate choice for a **private, 1–2 person app**.
  If the app ever becomes public, switch to "store the ID, fetch fresh details for candidates near the search
  point".

---

## 6. Data model (Supabase / Postgres)

```
users                (managed by Supabase Auth)

workspaces           id, name, created_at
workspace_members    workspace_id, user_id, role            -- MVP: one workspace, both users in it

saved_places         id, workspace_id, added_by, created_at
                     source              'google' | 'custom'
                     google_place_id     nullable
                     name, address, lat, lng
                     google_snapshot     jsonb, nullable
                     snapshot_at         timestamptz, nullable
                     -- our own fields
                     price_override      smallint, nullable
                     max_group_size      smallint, nullable
                     our_rating          smallint, nullable
                     parking_ease        smallint, nullable    -- 1 hard, 2 ok, 3 easy
                     parking_notes       text
                     booking_notes       text
                     notes               text
                     meal_overrides      jsonb, nullable
                     busy_grid           jsonb, nullable       -- post-MVP
```

Row-level security: a user can read and write only the `saved_places` rows of workspaces they belong to.

---

## 7. Key flows

### Save a place
1. Search a name or area → results list or map (Pro fields only).
2. Tap a result → Place Details (Enterprise + Atmosphere field mask) → prefilled form.
3. Add our own fields → **Save** (snapshot stored).

### "Lunch near Mum's" (the main use case)
1. Enter an address (autocomplete) → a point on the map, plus a radius.
2. Set day + time, group size and minimum parking ease (plus any other filters).
3. Filter the saved places **locally** (no API calls):
   - within the radius (stored lat/lng)
   - open at that day and time (`regularOpeningHours`)
   - meal badge matches
   - `max_group_size` ≥ N, or `goodForGroups` if we haven't set one
   - parking ease meets the minimum
4. Show the results on the map and the list with badges: Open · Lunch · $$ · ★4.4 / ours ★5 · Call to book ·
   Parking: easy.
5. **No matches** (post-MVP): a **"Discover nearby"** button runs one Nearby Search with Pro fields only, and
   each result has a **Save** button.

---

## 8. Cost estimate (1–2 users)

| Service | Expected usage / month | Expected cost |
|---|---|---|
| Maps JS (map loads) | < 500 | $0 |
| Autocomplete / Geocoding | < 500 | $0 |
| Place Details (save + refresh) | ~20–100 | $0 |
| Text / Nearby Search (Pro fields) | < 300 | $0 |
| Supabase free plan | tiny | $0 (pauses after 7 days of no activity) |
| Hosting free plan | tiny | $0 |

---

## 9. Build phases

**Phase 1 (MVP)**
- [ ] Supabase project, auth, schema, RLS; add both users to one workspace
- [ ] Edge Function proxy for Google with fixed field masks
- [ ] Google Cloud quotas and budget alert
- [ ] Location search (postcode, suburb, street) plus radius
- [ ] Map + list views of saved places, kept in sync
- [ ] Search Google → place details → save with snapshot
- [ ] Add a custom place
- [ ] Edit our own fields
- [ ] Filters (section 7) plus the booking indicator
- [ ] "Details as of" date, Refresh button, 30-day auto-refresh

**Phase 2**
- [ ] "Discover nearby" fallback
- [ ] Busy-periods grid (entered by us)
- [ ] Optional photo uploads to Supabase storage

---

## 10. Decisions log

| Date | Decision |
|---|---|
| 2026-11-15 | Saved-list app for personal / family use (1–2 users), not a general discovery app |
| 2026-11-15 | Google Places API (New) + Google Maps; Supabase for auth and database |
| 2026-11-15 | Snapshot Google details on save; manual refresh plus 30-day auto-refresh |
| 2026-11-15 | No Google Place Photos in the MVP |
| 2026-11-15 | Busy periods are post-MVP and entered by us |
| 2026-11-15 | Region assumed to be Australia (postcodes, suburbs) |

## 11. Open questions
- Framework choice (Next.js vs. SvelteKit).
- Default search radius (2 km? 5 km?).
- Is the Supabase free-plan pause after 7 days of no activity acceptable, or pay $25/month?
