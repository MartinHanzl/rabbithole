// Pure question logic: Wikidata templates, validation of generated questions.
// No I/O here – covered by questions_test.ts.

export type Source = "wikidata" | "generated";

export interface Question {
  question: string;
  correct: string;
  wrong: [string, string];
  source: Source;
}

export const MAX_QUESTION = 200;
export const MAX_ANSWER = 80;

/// Same rules as create_challenge(): non-blank, within limits, three distinct answers.
export function isValid(q: { question?: unknown; correct?: unknown; wrong?: unknown }): boolean {
  if (typeof q.question !== "string" || typeof q.correct !== "string" || !Array.isArray(q.wrong)) return false;
  if (q.wrong.length !== 2 || !q.wrong.every((w) => typeof w === "string")) return false;
  const question = q.question.trim();
  const answers = [q.correct, ...(q.wrong as string[])].map((a) => a.trim());
  if (question.length < 1 || question.length > MAX_QUESTION) return false;
  if (answers.some((a) => a.length < 1 || a.length > MAX_ANSWER)) return false;
  return new Set(answers.map((a) => a.toLowerCase())).size === 3;
}

export function normalize(q: Question): Question {
  return {
    question: q.question.trim(),
    correct: q.correct.trim(),
    wrong: [q.wrong[0].trim(), q.wrong[1].trim()],
    source: q.source,
  };
}

/// Parses Gemini's JSON output, keeping only valid questions (max 3).
export function parseGenerated(text: string): Question[] {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    return [];
  }
  if (!Array.isArray(data)) return [];
  return data
    .filter((item) => item && typeof item === "object" && isValid(item))
    .map((item) => normalize({ ...(item as Question), source: "generated" }))
    .slice(0, 3);
}

// ---------------------------------------------------------------------------
// Wikidata
// ---------------------------------------------------------------------------

// deno-lint-ignore no-explicit-any
type Claims = Record<string, any[]>;

export const HUMAN = "Q5";
/// Distractor pools (Wikidata ids); labels are fetched in Czech.
export const COUNTRIES = ["Q213", "Q183", "Q142", "Q38", "Q29", "Q36", "Q40", "Q28", "Q214", "Q145",
  "Q30", "Q148", "Q17", "Q159", "Q155", "Q668", "Q408", "Q16", "Q96", "Q79"];
export const CAPITALS = ["Q1085", "Q64", "Q90", "Q220", "Q2807", "Q270", "Q1741", "Q1781", "Q1780",
  "Q84", "Q61", "Q956", "Q1490", "Q649"];

/// Year of the first time claim with at least year precision, or null.
export function claimYear(claims: Claims, property: string): number | null {
  for (const claim of claims[property] ?? []) {
    const value = claim?.mainsnak?.datavalue?.value;
    if (!value?.time || (value.precision ?? 0) < 9) continue;
    const match = /^([+-])(\d+)-/.exec(value.time);
    if (!match || match[1] === "-") continue;
    const year = Number(match[2]);
    if (year > 0) return year;
  }
  return null;
}

export function claimItem(claims: Claims, property: string): string | null {
  for (const claim of claims[property] ?? []) {
    const id = claim?.mainsnak?.datavalue?.value?.id;
    if (typeof id === "string") return id;
  }
  return null;
}

/// Two plausible wrong years, different from each other and from `year`, not in the future.
/// Bounded: falls back to fixed offsets if the random draws keep colliding.
export function wrongYears(year: number, random: () => number, now = new Date().getFullYear()): [string, string] {
  const picked = new Set<number>();
  const acceptable = (candidate: number) => candidate > 0 && candidate <= now && candidate !== year;
  for (let attempt = 0; attempt < 50 && picked.size < 2; attempt++) {
    const offset = 3 + Math.floor(random() * 38); // 3–40 years
    const candidate = random() < 0.5 ? year - offset : year + offset;
    if (acceptable(candidate)) picked.add(candidate);
  }
  for (const offset of [-7, 11, -15, 19, -23, 31]) {
    if (picked.size >= 2) break;
    if (acceptable(year + offset)) picked.add(year + offset);
  }
  const [a, b] = [...picked];
  return [String(a), String(b)];
}

function pickTwo(pool: string[], exclude: string, random: () => number): [string, string] | null {
  const candidates = pool.filter((id) => id !== exclude);
  if (candidates.length < 2) return null;
  const first = candidates.splice(Math.floor(random() * candidates.length), 1)[0];
  const second = candidates[Math.floor(random() * candidates.length)];
  return [first, second];
}

/// Ids whose Czech labels are needed to render the templates for an entity.
export function labelIdsNeeded(entityId: string, claims: Claims, random: () => number): { ids: string[]; plan: Plan[] } {
  const plan: Plan[] = [];
  const country = claimItem(claims, "P17");
  // Places with coordinates "lie" in a country – but a country doesn't lie in itself, and
  // border places (several P17 values, e.g. Sněžka: Česko + Polsko) would make a distractor correct.
  const countryCount = new Set((claims["P17"] ?? []).map((c) => c?.mainsnak?.datavalue?.value?.id)).size;
  if (country && country !== entityId && countryCount === 1 && (claims["P625"]?.length ?? 0) > 0) {
    const wrong = pickTwo(COUNTRIES, country, random);
    if (wrong) plan.push({ kind: "country", correct: country, wrong });
  }
  const capital = claimItem(claims, "P36");
  if (capital) {
    const wrong = pickTwo(CAPITALS, capital, random);
    if (wrong) plan.push({ kind: "capital", correct: capital, wrong });
  }
  return { ids: [...new Set(plan.flatMap((p) => [p.correct, ...p.wrong]))], plan };
}

export interface Plan {
  kind: "country" | "capital";
  correct: string;
  wrong: [string, string];
}

/// Builds template questions. `labels` maps Wikidata ids to Czech labels.
export function wikidataQuestions(
  entityLabel: string,
  claims: Claims,
  plan: Plan[],
  labels: Record<string, string>,
  random: () => number,
): Question[] {
  const questions: Question[] = [];
  const isHuman = (claims["P31"] ?? []).some((c) => c?.mainsnak?.datavalue?.value?.id === HUMAN);
  // States carry the date of their current constitution as inception (France: 1958) – misleading.
  const isState = (claims["P36"]?.length ?? 0) > 0;

  const yearTemplates: [string, (label: string) => string][] = isHuman
    ? [["P569", (l) => `Ve kterém roce se narodil(a) ${l}?`]]
    : [
      ["P575", (l) => `Ve kterém roce se datuje objev: ${l}?`],
      ["P577", (l) => `Ve kterém roce vyšlo dílo ${l}?`],
      ...(isState ? [] : [["P571", (l: string) => `Ve kterém roce se datuje vznik: ${l}?`] as [string, (label: string) => string]]),
    ];
  for (const [property, template] of yearTemplates) {
    const year = claimYear(claims, property);
    if (year === null) continue;
    questions.push({ question: template(entityLabel), correct: String(year), wrong: wrongYears(year, random), source: "wikidata" });
    break; // one year question is enough
  }

  for (const item of plan) {
    const correct = labels[item.correct];
    const wrong = item.wrong.map((id) => labels[id]);
    if (!correct || wrong.some((w) => !w)) continue;
    const question = item.kind === "country"
      ? `Ve které zemi leží ${entityLabel}?`
      : `Jaké je hlavní město země ${entityLabel}?`;
    questions.push({ question, correct, wrong: [wrong[0], wrong[1]], source: "wikidata" });
  }

  return questions.filter(isValid).map(normalize);
}

// ---------------------------------------------------------------------------
// Gemini prompt
// ---------------------------------------------------------------------------

export function geminiPrompt(title: string, intro: string): string {
  return [
    "Jsi autor přátelských kvízových otázek pro aplikaci, kde si přátelé posílají články z Wikipedie.",
    `Na základě POUZE níže uvedeného úvodu článku „${title}“ vytvoř 3 otázky v češtině.`,
    "Každá otázka má jednu jednoznačně správnou odpověď (přímo z textu) a dvě věrohodné, ale jasně špatné odpovědi.",
    `Otázka max. ${MAX_QUESTION} znaků, každá odpověď max. ${MAX_ANSWER} znaků. Žádné chytáky, žádné odpovědi typu „všechny výše uvedené“.`,
    "Vrať pouze JSON pole objektů {\"question\": string, \"correct\": string, \"wrong\": [string, string]}.",
    "",
    "Úvod článku:",
    intro.slice(0, 4000),
  ].join("\n");
}

export const geminiSchema = {
  type: "ARRAY",
  items: {
    type: "OBJECT",
    properties: {
      question: { type: "STRING" },
      correct: { type: "STRING" },
      wrong: { type: "ARRAY", items: { type: "STRING" } },
    },
    required: ["question", "correct", "wrong"],
  },
};
