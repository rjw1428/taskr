/**
 * Pure-logic tests for the Gemini callable. Run with:
 *   npm run build && node --test lib/gemini.test.js
 */
import {test} from "node:test";
import * as assert from "node:assert";

import {
  MAX_PROMPT_CHARS,
  buildGeminiRequest,
  extractGeminiText,
  isGeminiKind,
  validateGeminiInput,
} from "./gemini.logic";

test("accepts the known kinds only", () => {
  assert.ok(isGeminiKind("coach"));
  assert.ok(isGeminiKind("goalPlan"));
  assert.ok(!isGeminiKind("toString"));
  assert.ok(!isGeminiKind("constructor"));
  assert.ok(!isGeminiKind(""));
  assert.ok(!isGeminiKind(undefined));
});

test("validates the payload shape", () => {
  assert.deepStrictEqual(validateGeminiInput({kind: "coach", prompt: "hi"}), {ok: true, kind: "coach", prompt: "hi"});
  assert.strictEqual(validateGeminiInput(null).ok, false);
  assert.strictEqual(validateGeminiInput("x").ok, false);
  assert.strictEqual(validateGeminiInput({kind: "nope", prompt: "hi"}).ok, false);
  assert.strictEqual(validateGeminiInput({kind: "coach"}).ok, false);
  assert.strictEqual(validateGeminiInput({kind: "coach", prompt: "   "}).ok, false);
  assert.strictEqual(validateGeminiInput({kind: "coach", prompt: "x".repeat(MAX_PROMPT_CHARS + 1)}).ok, false);
});

test("builds the coach request without a generation config", () => {
  const req = buildGeminiRequest("coach", "How did I do?") as any;
  assert.match(req.system_instruction.parts[0].text, /personal coach/);
  assert.deepStrictEqual(req.contents, [{role: "user", parts: [{text: "How did I do?"}]}]);
  assert.strictEqual(req.generationConfig, undefined);
});

test("builds the goal plan request as JSON output", () => {
  const req = buildGeminiRequest("goalPlan", "Goal: Run more") as any;
  assert.match(req.system_instruction.parts[0].text, /personal development coach/);
  assert.deepStrictEqual(req.generationConfig, {responseMimeType: "application/json"});
});

test("extracts and trims the first candidate text", () => {
  const body = {candidates: [{content: {parts: [{text: "  Great work  "}]}}]};
  assert.strictEqual(extractGeminiText(body), "Great work");
  assert.strictEqual(extractGeminiText({}), "");
  assert.strictEqual(extractGeminiText({candidates: []}), "");
  assert.strictEqual(extractGeminiText({candidates: [{content: {parts: []}}]}), "");
  assert.strictEqual(extractGeminiText({candidates: [{content: {parts: [{text: 7}]}}]}), "");
  assert.strictEqual(extractGeminiText(null), "");
  assert.strictEqual(extractGeminiText("str"), "");
});
