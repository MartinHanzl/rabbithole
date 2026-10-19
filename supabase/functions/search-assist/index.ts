// Turns a typed question into search terms for Wikipedia and YouTube using Gemini.
//
// POST { "q": "China" } → { "wikipedia": "Čína", "youtube": "China explained", "language": "en" }
//
// Works without an account (search works without one), so it is protected by a per-IP hourly
// limit (hashed IP) and a shared cache. On any problem it answers 503 and the app falls back
// to its local simplifier. GEMINI_API_KEY / GEMINI_MODEL come from Supabase secrets.
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { bucketFor, normalize, parseTerms, prompt, schema } from "./terms.ts";

const MAX_PER_HOUR = 30;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const query = typeof body?.q === "string" ? body.q.trim() : "";
  const key = normalize(query);
  if (!key) return json({ error: "invalid_query" }, 400);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: cached } = await admin.from("search_terms_cache").select("wikipedia, youtube, language").eq("query", key).maybeSingle();
  if (cached) return json(cached);

  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const { data: allowed } = await admin.rpc("hit_rate_limit", { p_bucket: await bucketFor(ip), p_max_hits: MAX_PER_HOUR });
  if (allowed === false) return json({ error: "rate_limited" }, 429);

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return json({ error: "unavailable" }, 503);
  const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.1-flash-lite";

  try {
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt(query) }] }],
        generationConfig: { responseMimeType: "application/json", responseSchema: schema, temperature: 0.2 },
      }),
    });
    if (!response.ok) return json({ error: "unavailable" }, 503);
    const data = await response.json();
    const terms = parseTerms(data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "");
    if (!terms) return json({ error: "unavailable" }, 503);
    await admin.from("search_terms_cache").upsert({ query: key, ...terms });
    return json(terms);
  } catch (error) {
    console.error("gemini failed", String(error));
    return json({ error: "unavailable" }, 503);
  }
});
