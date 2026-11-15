// Where The Food At — `places` Edge Function
//
// Keeps the Google Places API key on the server and exposes two actions to signed-in users:
//   { action: "search",  query: "golden lantern", near?: "Box Hill 3128 VIC" }  → { places: [...] }
//   { action: "details", id: "ChIJ..." }                                         → { place: {...} }
//
// Secrets it needs (Supabase → Edge Functions → Secrets):
//   GOOGLE_PLACES_KEY   your Places API (New) key
// Provided automatically by Supabase:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Deploy with JWT verification OFF (this function checks the signed-in user itself):
//   npx supabase functions deploy places --project-ref <ref> --no-verify-jwt --use-api

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const GOOGLE_KEY = Deno.env.get("GOOGLE_PLACES_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Where the app is allowed to call this from.
const ALLOWED_ORIGINS = [
  "http://localhost:5500",
  "https://mheiland17.github.io",
];

// The app's own daily caps (on top of anything set in Google Cloud).
const DAILY_LIMITS: Record<string, number> = { search: 200, details: 50 };

// Only ask Google for what we use: the search list is cheap, details are fetched after the user confirms.
const SEARCH_FIELDS = ["places.id", "places.displayName", "places.formattedAddress", "places.primaryType"].join(",");
const DETAIL_FIELDS = [
  "id", "displayName", "formattedAddress", "addressComponents", "primaryType", "types",
  "nationalPhoneNumber", "websiteUri", "regularOpeningHours",
  "priceLevel", "rating", "userRatingCount",
  "servesBreakfast", "servesBrunch", "servesLunch", "servesDinner",
  "servesBeer", "servesWine", "servesCocktails", "servesDessert", "servesVegetarianFood",
  "delivery", "takeout", "dineIn", "reservable", "goodForGroups", "parkingOptions",
].join(",");

const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

function corsHeaders(origin: string): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0],
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function reply(body: unknown, status: number, origin: string): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
  });
}

async function google(url: string, init: RequestInit, fieldMask: string) {
  const res = await fetch(url, {
    ...init,
    headers: {
      ...(init.headers ?? {}),
      "X-Goog-Api-Key": GOOGLE_KEY,
      "X-Goog-FieldMask": fieldMask,
    },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const message = data?.error?.message ?? `Google returned ${res.status}`;
    throw new Error(message);
  }
  return data;
}

Deno.serve(async (req) => {
  const origin = req.headers.get("Origin") ?? "";
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(origin) });
  if (req.method !== "POST") return reply({ error: "Method not allowed." }, 405, origin);
  if (!GOOGLE_KEY) return reply({ error: "Search isn't set up: the GOOGLE_PLACES_KEY secret is missing." }, 500, origin);

  // 1. Only signed-in users of this app.
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth, error: authError } = await admin.auth.getUser(token);
  if (authError || !auth?.user) return reply({ error: "Please sign in again." }, 401, origin);

  // 2. Validate the request.
  let body: { action?: string; query?: string; near?: string; id?: string };
  try {
    body = await req.json();
  } catch {
    return reply({ error: "Bad request." }, 400, origin);
  }
  const action = body.action ?? "";
  if (!(action in DAILY_LIMITS)) return reply({ error: "Unknown action." }, 400, origin);

  const query = String(body.query ?? "").trim().slice(0, 120);
  const near = String(body.near ?? "").trim().slice(0, 80);
  const id = String(body.id ?? "").trim();
  if (action === "search" && query.length < 2) return reply({ error: "Type at least 2 letters of the name." }, 400, origin);
  if (action === "details" && !/^[A-Za-z0-9_-]{10,300}$/.test(id)) return reply({ error: "That place ID doesn't look right." }, 400, origin);

  // 3. Daily cap.
  const { data: underLimit, error: usageError } = await admin.rpc("bump_places_usage", {
    p_kind: action,
    p_limit: DAILY_LIMITS[action],
  });
  if (usageError) return reply({ error: `Usage check failed: ${usageError.message}` }, 500, origin);
  if (!underLimit) {
    return reply({ error: `Today's limit of ${DAILY_LIMITS[action]} ${action === "search" ? "searches" : "fill-ins"} has been reached. It resets tomorrow.` }, 429, origin);
  }

  // 4. Ask Google.
  try {
    if (action === "search") {
      const data = await google(
        "https://places.googleapis.com/v1/places:searchText",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            textQuery: near ? `${query} ${near}` : query,
            regionCode: "AU",
            languageCode: "en",
            pageSize: 8,
          }),
        },
        SEARCH_FIELDS,
      );
      return reply({ places: data.places ?? [] }, 200, origin);
    }

    const data = await google(
      `https://places.googleapis.com/v1/places/${encodeURIComponent(id)}?languageCode=en&regionCode=AU`,
      { method: "GET" },
      DETAIL_FIELDS,
    );
    return reply({ place: data }, 200, origin);
  } catch (err) {
    return reply({ error: `Google: ${(err as Error).message}` }, 502, origin);
  }
});
