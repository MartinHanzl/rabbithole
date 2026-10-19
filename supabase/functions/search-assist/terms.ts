// Pure helpers for search-assist – covered by terms_test.ts.

export interface Terms {
  wikipedia: string;
  youtube: string;
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
  const { wikipedia, youtube } = data as Record<string, unknown>;
  if (typeof wikipedia !== "string" || typeof youtube !== "string") return null;
  const terms = { wikipedia: wikipedia.trim(), youtube: youtube.trim() };
  if (!terms.wikipedia || !terms.youtube || terms.wikipedia.length > MAX_TERM || terms.youtube.length > MAX_TERM) {
    return null;
  }
  return terms;
}

export function prompt(query: string): string {
  return [
    "Uživatel české vzdělávací aplikace napsal do vyhledávání dotaz. Převeď ho na hledané výrazy.",
    "- \"wikipedia\": 1–4 klíčová slova pro vyhledávání na české Wikipedii (podstatná jména v 1. pádě, bez tazacích slov), např. „jak funguje kapitalismus“ → „kapitalismus“.",
    "- \"youtube\": krátký přirozený dotaz pro YouTube v češtině, který najde srozumitelné vysvětlující video.",
    "Pokud dotaz není otázka, vrať ho téměř beze změny. Vrať pouze JSON {\"wikipedia\": string, \"youtube\": string}.",
    "",
    `Dotaz: ${query.slice(0, MAX_QUERY)}`,
  ].join("\n");
}

export const schema = {
  type: "OBJECT",
  properties: { wikipedia: { type: "STRING" }, youtube: { type: "STRING" } },
  required: ["wikipedia", "youtube"],
};

/// Privacy: rate-limit buckets store a hash, never the IP itself.
export async function bucketFor(ip: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`search-assist:${ip}`));
  return [...new Uint8Array(digest)].slice(0, 16).map((b) => b.toString(16).padStart(2, "0")).join("");
}
