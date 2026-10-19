// Ready-made challenge questions for a Wikipedia article.
//
// POST { "page_id": 771 }  →  { "questions": [{ question, correct, wrong: [a, b], source }] }
//
// 1. Shared cache (public.article_questions) – each article is generated once for everybody.
// 2. Wikidata templates (year of birth/discovery/inception/publication, country, capital).
// 3. Gemini fallback from the article intro when Wikidata gives nothing.
//
// Only signed-in users may call it (verify_jwt is off; the caller is checked here).
// GEMINI_API_KEY (and optional GEMINI_MODEL) live in Supabase secrets, never in the app.
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import {
  geminiPrompt, geminiSchema, labelIdsNeeded, parseGenerated, Question, wikidataQuestions,
} from "./questions.ts";

const USER_AGENT = "Rabbithole/1.0 (Supabase Edge Function; CONTACT_EMAIL@example.com)";
const FRESH_DAYS = 180;
const EMPTY_RETRY_DAYS = 30;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function getJSON(url: string, init: RequestInit = {}) {
  const response = await fetch(url, { ...init, headers: { "User-Agent": USER_AGENT, ...(init.headers ?? {}) } });
  if (!response.ok) throw new Error(`${response.status} ${url.split("?")[0]}`);
  return await response.json();
}

/// Wikidata id, title and plain-text intro of a cs.wikipedia page.
async function pageInfo(pageID: number) {
  const data = await getJSON(
    "https://cs.wikipedia.org/w/api.php?action=query&format=json&formatversion=2" +
      `&prop=pageprops|extracts&ppprop=wikibase_item&exintro=1&explaintext=1&pageids=${pageID}`,
  );
  const page = data?.query?.pages?.[0];
  if (!page || page.missing) return null;
  return { title: page.title as string, qid: page.pageprops?.wikibase_item as string | undefined, intro: (page.extract ?? "") as string };
}

async function fromWikidata(qid: string): Promise<Question[]> {
  const entityData = await getJSON(
    `https://www.wikidata.org/w/api.php?action=wbgetentities&format=json&props=labels|claims&languages=cs&ids=${qid}`,
  );
  const entity = entityData?.entities?.[qid];
  const label = entity?.labels?.cs?.value;
  if (!entity?.claims || !label) return [];

  const { ids, plan } = labelIdsNeeded(qid, entity.claims, Math.random);
  const labels: Record<string, string> = {};
  if (ids.length > 0) {
    const labelData = await getJSON(
      `https://www.wikidata.org/w/api.php?action=wbgetentities&format=json&props=labels&languages=cs&ids=${ids.join("|")}`,
    );
    for (const [id, item] of Object.entries(labelData?.entities ?? {})) {
      // deno-lint-ignore no-explicit-any
      const value = (item as any)?.labels?.cs?.value;
      if (value) labels[id] = value;
    }
  }
  return wikidataQuestions(label, entity.claims, plan, labels, Math.random);
}

async function fromGemini(title: string, intro: string): Promise<Question[]> {
  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key || intro.trim().length < 200) return [];
  const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.1-flash-lite";
  const data = await getJSON(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": key },
      body: JSON.stringify({
        contents: [{ parts: [{ text: geminiPrompt(title, intro) }] }],
        generationConfig: { responseMimeType: "application/json", responseSchema: geminiSchema, temperature: 0.4 },
      }),
    },
  );
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  return parseGenerated(text);
}

export async function generate(pageID: number): Promise<Question[]> {
  const info = await pageInfo(pageID);
  if (!info) return [];
  let questions: Question[] = [];
  if (info.qid) {
    try {
      questions = await fromWikidata(info.qid);
    } catch (error) {
      console.error("wikidata failed", String(error));
    }
  }
  if (questions.length === 0) {
    try {
      questions = await fromGemini(info.title, info.intro);
    } catch (error) {
      console.error("gemini failed", String(error));
    }
  }
  return questions;
}

if (import.meta.main) {
  Deno.serve(async (req) => {
    if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "unauthorized" }, 401);

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user) return json({ error: "unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const pageID = Number(body?.page_id);
    if (!Number.isInteger(pageID) || pageID <= 0) return json({ error: "invalid_page_id" }, 400);

    const { data: cached } = await admin.from("article_questions")
      .select("questions, generated_at").eq("page_id", pageID).maybeSingle();
    if (cached) {
      const ageDays = (Date.now() - new Date(cached.generated_at).getTime()) / 86_400_000;
      const fresh = (cached.questions as Question[]).length > 0 ? ageDays < FRESH_DAYS : ageDays < EMPTY_RETRY_DAYS;
      if (fresh) return json({ questions: cached.questions });
    }

    const questions = await generate(pageID);
    await admin.from("article_questions")
      .upsert({ page_id: pageID, questions, generated_at: new Date().toISOString() });
    return json({ questions });
  });
}
