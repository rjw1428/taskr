/**
 * Pure logic for the `callGemini` callable.
 *
 * The app never talks to Gemini directly: the API key lives only in a function
 * secret. Every prompt kind the app may ask for is enumerated here with its
 * system instruction and generation config, so a caller can choose *what* to
 * ask but not *how* the model is instructed. Imports nothing so the tests run
 * as plain node.
 */

export type GeminiKind = "coach" | "goalPlan";

export const GEMINI_MODEL_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";

/** Hard cap on prompt length: a coaching prompt is a few hundred chars. */
export const MAX_PROMPT_CHARS = 8000;

interface KindSpec {
  systemInstruction: string;
  generationConfig?: Record<string, unknown>;
}

const KINDS: Record<GeminiKind, KindSpec> = {
  coach: {
    systemInstruction:
      "You are a personal coach, helping this person grow and become better. " +
      "A user is keeping track of their tasks in order to help manage, schedule, and complete these tasks. " +
      "You should provide substantial praise when all tasks are complete. " +
      "You should provide either a strategy to improve when there are tasks still left, a motivational quote, " +
      "or encouragement to complete the last remaining tasks if they seem achievable.",
  },
  goalPlan: {
    systemInstruction:
      "You are a personal development coach. Given a user's goal, generate a list of concrete, actionable " +
      "tasks for the coming week. Each task should be specific and achievable in a single session. " +
      "Return ONLY a JSON array of objects with these fields: " +
      "\"title\" (string, concise task name), " +
      "\"description\" (string, brief details on what to do), " +
      "\"dayOffset\" (int, 0=Monday through 6=Sunday, which day of the week to schedule this task), " +
      "\"effort\" (string, one of \"low\", \"medium\", \"high\"). " +
      "Do not include any text outside the JSON array.",
    generationConfig: {responseMimeType: "application/json"},
  },
};

export function isGeminiKind(value: unknown): value is GeminiKind {
  return typeof value === "string" && Object.prototype.hasOwnProperty.call(KINDS, value);
}

/**
 * Checks the callable payload. Returns the validated fields or the reason it
 * was rejected, so the caller can map that onto an HttpsError.
 */
export function validateGeminiInput(
  data: unknown
): {ok: true; kind: GeminiKind; prompt: string} | {ok: false; reason: string} {
  if (!data || typeof data !== "object") return {ok: false, reason: "payload must be an object"};
  const {kind, prompt} = data as {kind?: unknown; prompt?: unknown};
  if (!isGeminiKind(kind)) return {ok: false, reason: `unknown kind: ${String(kind)}`};
  if (typeof prompt !== "string" || prompt.trim().length === 0) {
    return {ok: false, reason: "prompt must be a non-empty string"};
  }
  if (prompt.length > MAX_PROMPT_CHARS) return {ok: false, reason: "prompt too long"};
  return {ok: true, kind, prompt};
}

/** The generateContent request body for a kind and prompt. */
export function buildGeminiRequest(kind: GeminiKind, prompt: string): Record<string, unknown> {
  const spec = KINDS[kind];
  return {
    system_instruction: {parts: [{text: spec.systemInstruction}]},
    contents: [{role: "user", parts: [{text: prompt}]}],
    ...(spec.generationConfig ? {generationConfig: spec.generationConfig} : {}),
  };
}

/** The first candidate's text, trimmed, or "" when the shape is unexpected. */
export function extractGeminiText(response: unknown): string {
  if (!response || typeof response !== "object") return "";
  const candidates = (response as {candidates?: unknown}).candidates;
  if (!Array.isArray(candidates) || candidates.length === 0) return "";
  const parts = candidates[0]?.content?.parts;
  if (!Array.isArray(parts) || parts.length === 0) return "";
  const text = parts[0]?.text;
  return typeof text === "string" ? text.trim() : "";
}
