import { bucketFor, normalize, parseTerms } from "./terms.ts";

function assert(condition: unknown, message = "assertion failed"): asserts condition {
  if (!condition) throw new Error(message);
}
function assertEquals(actual: unknown, expected: unknown) {
  const [a, e] = [JSON.stringify(actual), JSON.stringify(expected)];
  assert(a === e, `expected ${e}, got ${a}`);
}

Deno.test("normalize ignores case, punctuation and spacing, keeps diacritics", () => {
  assertEquals(normalize("  Jak funguje KAPITALISMUS?! "), "jak funguje kapitalismus");
  assertEquals(normalize("Černá díra"), "černá díra");
  assertEquals(normalize("???"), "");
  assert(normalize("x".repeat(500)).length === 200);
});

Deno.test("parseTerms accepts a proper answer", () => {
  assertEquals(parseTerms('{"wikipedia":" Čína ","youtube":"China explained","language":"EN"}'),
    { wikipedia: "Čína", youtube: "China explained", language: "en" });
});

Deno.test("ambiguous or invalid language becomes null", () => {
  assertEquals(parseTerms('{"wikipedia":"Mars","youtube":"Mars","language":""}')?.language, null);
  assertEquals(parseTerms('{"wikipedia":"Mars","youtube":"Mars","language":"english"}')?.language, null);
  assertEquals(parseTerms('{"wikipedia":"Mars","youtube":"Mars"}')?.language, null);
});

Deno.test("parseTerms rejects broken or empty answers", () => {
  assertEquals(parseTerms("nope"), null);
  assertEquals(parseTerms('{"wikipedia":"","youtube":"x"}'), null);
  assertEquals(parseTerms('{"wikipedia":"x"}'), null);
  assertEquals(parseTerms(`{"wikipedia":"${"x".repeat(101)}","youtube":"x"}`), null);
  assertEquals(parseTerms("[1,2]"), null);
});

Deno.test("rate-limit bucket is a stable hash, not the IP", async () => {
  const a = await bucketFor("203.0.113.7");
  assertEquals(a, await bucketFor("203.0.113.7"));
  assert(a !== (await bucketFor("203.0.113.8")));
  assert(!a.includes("203"));
  assertEquals(a.length, 32);
});
