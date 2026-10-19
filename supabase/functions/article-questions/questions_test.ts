// Tiny assertions – no remote imports, so tests run offline.
function assert(condition: unknown, message = "assertion failed"): asserts condition {
  if (!condition) throw new Error(message);
}
function assertFalse(condition: unknown, message = "expected false") {
  assert(!condition, message);
}
function assertEquals(actual: unknown, expected: unknown, message = "") {
  const [a, e] = [JSON.stringify(actual), JSON.stringify(expected)];
  assert(a === e, `${message} expected ${e}, got ${a}`);
}
import { claimYear, isValid, labelIdsNeeded, parseGenerated, wikidataQuestions, wrongYears } from "./questions.ts";

// Deterministic "random".
const seq = (...values: number[]) => {
  let i = 0;
  return () => values[i++ % values.length];
};
const time = (t: string, precision = 11) => ({ mainsnak: { datavalue: { value: { time: t, precision } } } });
const item = (id: string) => ({ mainsnak: { datavalue: { value: { id } } } });

Deno.test("validation mirrors create_challenge", () => {
  assert(isValid({ question: "Kolik?", correct: "Dva", wrong: ["Jeden", "Tři"] }));
  assertFalse(isValid({ question: "Kolik?", correct: "Dva", wrong: ["dva", "Tři"] }), "distinct answers");
  assertFalse(isValid({ question: "x".repeat(201), correct: "A", wrong: ["B", "C"] }));
  assertFalse(isValid({ question: "Q", correct: "x".repeat(81), wrong: ["B", "C"] }));
  assertFalse(isValid({ question: "Q", correct: "A", wrong: ["B"] }));
  assertFalse(isValid({ question: " ", correct: "A", wrong: ["B", "C"] }));
});

Deno.test("year claims need year precision and AD dates", () => {
  assertEquals(claimYear({ P575: [time("+1877-08-11T00:00:00Z")] }, "P575"), 1877);
  assertEquals(claimYear({ P575: [time("+1800-00-00T00:00:00Z", 7)] }, "P575"), null, "century precision");
  assertEquals(claimYear({ P575: [time("-0500-00-00T00:00:00Z", 9)] }, "P575"), null, "BC");
  assertEquals(claimYear({}, "P575"), null);
});

Deno.test("wrong years terminate even when the generator repeats", () => {
  const [a, b] = wrongYears(1856, () => 0.5, 2026);
  assert(a !== b && a !== "1856" && b !== "1856");
});

Deno.test("wrong years are distinct, plausible and not in the future", () => {
  for (let i = 0; i < 200; i++) {
    const [a, b] = wrongYears(2020, Math.random, 2026);
    assert(a !== b && a !== "2020" && b !== "2020");
    assert(Number(a) <= 2026 && Number(b) <= 2026 && Number(a) > 0);
  }
});

Deno.test("human gets a birth-year question", () => {
  const claims = { P31: [item("Q5")], P569: [time("+1856-07-10T00:00:00Z")] };
  const [q] = wikidataQuestions("Nikola Tesla", claims, [], {}, seq(0.1, 0.9));
  assertEquals(q.question, "Ve kterém roce se narodil(a) Nikola Tesla?");
  assertEquals(q.correct, "1856");
  assertEquals(q.source, "wikidata");
  assert(isValid(q));
});

Deno.test("place gets a country question with labels", () => {
  const claims = { P31: [item("Q8502")], P17: [item("Q213")], P625: [{}] };
  const { ids, plan } = labelIdsNeeded("Q180", claims, seq(0.05, 0.5));
  assert(ids.includes("Q213"));
  const labels = Object.fromEntries(ids.map((id) => [id, id === "Q213" ? "Česko" : `Země ${id}`]));
  const [q] = wikidataQuestions("Sněžka", claims, plan, labels, Math.random);
  assertEquals(q.question, "Ve které zemi leží Sněžka?");
  assertEquals(q.correct, "Česko");
  assertEquals(q.wrong.length, 2);
  assertFalse(q.wrong.includes("Česko"));
});

Deno.test("border places get no country question", () => {
  const claims = { P17: [item("Q213"), item("Q36")], P625: [{}] };
  assertEquals(labelIdsNeeded("Q180", claims, Math.random).plan, []);
});

Deno.test("states get no inception-year question", () => {
  const claims = { P571: [time("+1958-10-04T00:00:00Z")], P36: [item("Q90")] };
  assertEquals(wikidataQuestions("Francie", claims, [], {}, Math.random), []);
  const landmark = { P571: [time("+1889-03-31T00:00:00Z")] };
  assertEquals(wikidataQuestions("Eiffelova věž", landmark, [], {}, Math.random)[0]?.correct, "1889");
});

Deno.test("a country is not asked where it lies", () => {
  const claims = { P17: [item("Q142")], P625: [{}], P36: [item("Q90")] };
  const { plan } = labelIdsNeeded("Q142", claims, Math.random);
  assertEquals(plan.map((p) => p.kind), ["capital"]);
});

Deno.test("missing labels drop the question instead of showing ids", () => {
  const claims = { P17: [item("Q213")], P625: [{}] };
  const { plan } = labelIdsNeeded("Q1", claims, Math.random);
  assertEquals(wikidataQuestions("X", claims, plan, {}, Math.random), []);
});

Deno.test("generated output is validated and capped", () => {
  const good = { question: "Kolik měsíců má Mars?", correct: "Dva", wrong: ["Jeden", "Žádný"] };
  const parsed = parseGenerated(JSON.stringify([good, { ...good, wrong: ["Dva", "X"] }, good, good, good]));
  assertEquals(parsed.length, 3);
  assert(parsed.every((q) => q.source === "generated"));
  assertEquals(parseGenerated("not json"), []);
  assertEquals(parseGenerated(JSON.stringify({ question: "x" })), []);
});
