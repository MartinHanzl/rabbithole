// Pure helpers for search-assist – covered by terms_test.ts.

export interface Terms {
  wikipedia: string;
  youtube: string;
  /// ISO 639-1 language of the query, null when ambiguous.
  language: string | null;
}

export const MAX_QUERY = 200;
export const MAX_TERM = 100;

/// Cache key: lowercase, letters and digits only, single spaces.
export function normalize(query: string): string {
  return query.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean).join(" ").slice(0, MAX_QUERY);
}

/// Validates Gemini's JSON answer; null when unusable.
export function parseTerms(text: string): Terms | null {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    return null;
  }
  if (!data || typeof data !== "object") return null;
  const { wikipedia, youtube, language } = data as Record<string, unknown>;
  if (typeof wikipedia !== "string" || typeof youtube !== "string") return null;
  const code = typeof language === "string" ? language.trim().toLowerCase() : "";
  const terms = { wikipedia: wikipedia.trim(), youtube: youtube.trim(), language: /^[a-z]{2}$/.test(code) ? code : null };
  if (!terms.wikipedia || !terms.youtube || terms.wikipedia.length > MAX_TERM || terms.youtube.length > MAX_TERM) {
    return null;
  }
  return terms;
}

export function prompt(query: string): string {
  return [
    "Uživatel české vzdělávací aplikace napsal do vyhledávání dotaz. Převeď ho na hledané výrazy.",
    "- \"wikipedia\": 1–4 klíčová slova V ČEŠTINĚ pro českou Wikipedii (podstatná jména v 1. pádě, bez tazacích slov); dotaz v jiném jazyce přelož, např. „jak funguje kapitalismus“ → „kapitalismus“, „China“ → „Čína“.",
    "- \"youtube\": krátký přirozený dotaz pro YouTube VE STEJNÉM JAZYCE, v jakém je dotaz napsaný, který najde srozumitelné vysvětlující video. NEPŘEKLÁDEJ ho: „jak funguje kapitalismus“ → „jak funguje kapitalismus“, „China“ → „China explained“. Zachovej téma dotazu a nezužuj ho (ne „history of China“).",
    "- \"language\": dvoupísmenný kód ISO 639-1 jazyka dotazu (cs, en, de…); pokud jde o slovo, které je stejné ve více jazycích (např. „Mars“), vrať prázdný řetězec.",
    "Vrať pouze JSON {\"wikipedia\": string, \"youtube\": string, \"language\": string}.",
    "",
    `Dotaz: ${query.slice(0, MAX_QUERY)}`,
  ].join("\n");
}

export const schema = {
  type: "OBJECT",
  properties: { wikipedia: { type: "STRING" }, youtube: { type: "STRING" }, language: { type: "STRING" } },
  required: ["wikipedia", "youtube", "language"],
};

/// Privacy: rate-limit buckets store a hash, never the IP itself.
export async function bucketFor(ip: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`search-assist:${ip}`));
  return [...new Uint8Array(digest)].slice(0, 16).map((b) => b.toString(16).padStart(2, "0")).join("");
}
