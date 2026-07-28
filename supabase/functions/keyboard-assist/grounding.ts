import type { NormalizedKeyboardAssistCompilerOutput } from "./normalize.ts";

/// Deliberately absent from the gate below. "改天再約" and "下次帶你去" invent
/// nothing: they point at a future that has not happened, so there is no fact
/// to contradict. Requiring the screenshot to contain the word "下次" before a
/// reply may say it is not a safety property, it is a vocabulary ban — and it
/// is the one that killed three consecutive real screenshots on 2026-07-28,
/// because a batch is exactly three replies and losing one loses all three.
/// A *specific* future is still a fact and stays gated: "下週六" contains 週六,
/// which the weekday pattern picks up.
export const UNGATED_RELATIVE_DATE_TOKENS = [
  "今天",
  "明天",
  "後天",
  "昨天",
  "前天",
  "大前天",
  "大後天",
  "今晚",
  "今早",
  "明早",
  "明晚",
  "今年",
  "明年",
  "去年",
  "本月",
  "這月",
  "下月",
  "上月",
  "這個月",
  "下個月",
  "上個月",
  "本週",
  "這週",
  "下週",
  "上週",
  "本周",
  "這周",
  "下周",
  "上周",
  "週末",
  "周末",
  "下次",
] as const;

function normalizeFactualText(value: string): string {
  return value.normalize("NFKC").replaceAll("臺", "台").toLocaleLowerCase(
    "zh-TW",
  );
}

function compactFactualText(value: string): string {
  return normalizeFactualText(value).replace(/\s+/gu, "");
}

/// Which rule claimed a token. Fixed vocabulary, never text from the image, so
/// it is safe to put in telemetry — and without it a grounding rejection says
/// only "a candidate was ungrounded", which is not enough to tell an invented
/// price from an over-eager regex.
///
/// Five classes, not nine. Place names, venue names, personal names and
/// "上次／還記得" were also gated until 2026-07-28, and between them they caused
/// far more refusals than they prevented harms — a batch is exactly three
/// replies, so one over-eager match takes all three. What remains is the set
/// where an invented value makes the recipient act on something false: a wrong
/// address to visit, a wrong account to contact, a wrong time to show up, a
/// wrong price to bring. Naming the wrong restaurant is embarrassing; it is not
/// that. The whitelists were also structurally unable to work across languages:
/// evidence is matched literally against the model's own transcript, so a Thai
/// screenshot answered in Chinese could never ground a place or a name.
export const FACTUAL_TOKEN_CLASSES = [
  "date",
  "time",
  "number",
  "link",
  "handle",
] as const;

export type FactualTokenClass = typeof FACTUAL_TOKEN_CLASSES[number];

function addMatches(
  tokens: Map<string, FactualTokenClass>,
  value: string,
  pattern: RegExp,
  tokenClass: FactualTokenClass,
  group = 0,
): void {
  for (const match of value.matchAll(pattern)) {
    const token = match[group];
    if (!token) continue;
    const compact = compactFactualText(token);
    if (!tokens.has(compact)) tokens.set(compact, tokenClass);
  }
}

function factualTokens(value: string): Map<string, FactualTokenClass> {
  const tokens = new Map<string, FactualTokenClass>();
  const normalized = normalizeFactualText(value);

  addMatches(
    tokens,
    normalized,
    /\d{1,4}\s*(?:[./-]|年)\s*\d{1,2}(?:\s*(?:[./-]|月)\s*\d{1,2}\s*(?:日|號)?)?/gu,
    "date",
  );
  addMatches(
    tokens,
    normalized,
    /\d{1,2}\s*月\s*\d{1,2}\s*(?:日|號)?/gu,
    "date",
  );
  addMatches(
    tokens,
    normalized,
    /[一二三四五六七八九十廿卅]{1,4}月[一二三四五六七八九十廿卅]{1,4}(?:日|號)/gu,
    "date",
  );
  addMatches(
    tokens,
    normalized,
    /(?:星期|禮拜|週|周)[一二三四五六日天]/gu,
    "date",
  );
  addMatches(tokens, normalized, /\d{1,2}\s*[:：]\s*\d{2}/gu, "time");
  addMatches(
    tokens,
    normalized,
    /(?:凌晨|早上|上午|中午|下午|傍晚|晚上)\s*(?:\d{1,2}|[一二三四五六七八九十]{1,3})\s*(?:點|時)(?:半|[一二三四五六七八九十\d]{1,3}分)?/gu,
    "time",
  );
  // A bare clock time is as much of an appointment as 下午三點 is. It used to be
  // caught only because every digit was, so it has to be named now that they
  // are not.
  addMatches(
    tokens,
    normalized,
    /\d{1,2}\s*(?:點|時)(?:半|\s*\d{1,2}\s*分)?/gu,
    "time",
  );
  // Refusing every digit cost far more ordinary replies than it caught claims:
  // one candidate writing 那 4 道菜 instead of 那幾道菜 killed all three lines.
  // Money is the part worth keeping — an invented price is a claim the user
  // sends to a real person. A count is not, and dates and times are gated above.
  addMatches(
    tokens,
    normalized,
    /(?:nt\$|\$)\s*\d+(?:[.,]\d+)*|\d+(?:[.,]\d+)*\s*(?:元|塊)/gu,
    "number",
  );
  addMatches(
    tokens,
    normalized,
    /(?:https?:\/\/|www\.)[^\s<>"'，。！？、]+/gu,
    "link",
  );
  addMatches(tokens, normalized, /@[a-z0-9_.-]+/gu, "handle");

  return tokens;
}

/// The class of the first token the evidence cannot account for, or null when
/// everything the text asserts is on screen.
export function ungroundedFactualTokenClass(
  generated: string,
  evidence: string,
): FactualTokenClass | null {
  const compactEvidence = compactFactualText(evidence);
  for (const [token, tokenClass] of factualTokens(generated)) {
    if (!compactEvidence.includes(token)) return tokenClass;
  }
  return null;
}

export function hasOnlyGroundedFactualTokens(
  generated: string,
  evidence: string,
): boolean {
  return ungroundedFactualTokenClass(generated, evidence) === null;
}

/// Which part of the compiler output failed grounding. The three fields are not
/// equally dangerous: `cue` and `uncertainty` are commentary we render, while a
/// candidate is text the user is about to send to a real person. Naming the
/// field is what lets the pipeline drop the former and still refuse the latter.
export type KeyboardAssistGroundingFailure =
  | "cue"
  | "uncertainty"
  | "candidate";

export function keyboardAssistCompilerGroundingFailure(
  value: NormalizedKeyboardAssistCompilerOutput,
): KeyboardAssistGroundingFailure | null {
  const allVisibleMessages = value.messages.map((message) => message.text).join(
    "\n",
  );
  if (!hasOnlyGroundedFactualTokens(value.cue, allVisibleMessages)) {
    return "cue";
  }
  if (
    value.uncertainty !== null &&
    !hasOnlyGroundedFactualTokens(value.uncertainty, allVisibleMessages)
  ) {
    return "uncertainty";
  }
  return value.candidates.every((candidate) =>
      isGroundedKeyboardAssistCandidate(candidate, value)
    )
    ? null
    : "candidate";
}

export function isGroundedKeyboardAssistCandidate(
  candidate: NormalizedKeyboardAssistCompilerOutput["candidates"][number],
  value: NormalizedKeyboardAssistCompilerOutput,
): boolean {
  const messagesByIndex = new Map(
    value.messages.map((message) => [message.index, message.text]),
  );
  const allVisibleMessages = value.messages.map((message) => message.text).join(
    "\n",
  );
  if (
    candidate.evidenceIndices.length < 1 ||
    candidate.evidenceIndices.some((index) => !messagesByIndex.has(index))
  ) return false;
  return hasOnlyGroundedFactualTokens(candidate.text, allVisibleMessages);
}

/// Why the batch is about to be refused, at the granularity telemetry can
/// carry. `citation` means the candidate pointed at a message index that does
/// not exist, which is a different bug from asserting a fact off screen.
export function ungroundedCandidateTokenClass(
  value: NormalizedKeyboardAssistCompilerOutput,
): FactualTokenClass | "citation" | null {
  const messagesByIndex = new Set(
    value.messages.map((message) => message.index),
  );
  const allVisibleMessages = value.messages.map((message) => message.text).join(
    "\n",
  );
  for (const candidate of value.candidates) {
    if (
      candidate.evidenceIndices.length < 1 ||
      candidate.evidenceIndices.some((index) => !messagesByIndex.has(index))
    ) return "citation";
    const tokenClass = ungroundedFactualTokenClass(
      candidate.text,
      allVisibleMessages,
    );
    if (tokenClass !== null) return tokenClass;
  }
  return null;
}

export function isGroundedKeyboardAssistCompilerOutput(
  value: NormalizedKeyboardAssistCompilerOutput,
): boolean {
  const messagesByIndex = new Map(
    value.messages.map((message) => [message.index, message.text]),
  );
  const allVisibleMessages = value.messages.map((message) => message.text).join(
    "\n",
  );
  if (
    !hasOnlyGroundedFactualTokens(value.cue, allVisibleMessages) ||
    value.uncertainty !== null &&
      !hasOnlyGroundedFactualTokens(value.uncertainty, allVisibleMessages)
  ) return false;

  return value.candidates.every((candidate) => {
    // The citation contract still has to hold: a candidate must point at real
    // messages. But the safety property is "no fact from outside this
    // screenshot", so the tokens are checked against everything visible rather
    // than only the messages this candidate happened to cite. Checking against
    // the citation alone rejects an ordinary reply that answers the newest
    // message using a date agreed three messages earlier — a real conversation
    // spreads its facts around, and that rejection is a hard failure the user
    // can only escape by giving up.
    if (
      candidate.evidenceIndices.length < 1 ||
      candidate.evidenceIndices.some((index) => !messagesByIndex.has(index))
    ) return false;
    return hasOnlyGroundedFactualTokens(candidate.text, allVisibleMessages);
  });
}
