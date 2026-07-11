import type { PracticeTurn } from "./validate.ts";

const KNOWN_CANNED_SIGNATURES = [
  "妳剛說的那個點",
  "你剛說的那個點",
  "妳剛剛說的那個點",
  "你剛剛說的那個點",
  "我先分享我的版本再聽妳的",
  "我先分享我的版本再聽你的",
  "我先說我的版本再聽妳的",
  "我先說我的版本再聽你的",
  "目前比較像穩住話題",
  "還沒看到足夠投入或明確窗口",
  "先補感受與投入再接低壓邀約窗口",
  "提示偏保守",
];

const GENERIC_META_SIGNATURES = [
  "先接住她",
  "先接住對方",
  "分享你的版本",
  "分享自己的版本",
  "再聽她的",
  "再聽對方的",
];

const COMMON_EVIDENCE_FRAGMENTS = new Set([
  "妳好",
  "你好",
  "我很",
  "你很",
  "妳很",
  "她很",
  "這個",
  "那個",
  "可以",
  "就是",
  "因為",
  "所以",
  "但是",
  "今天",
  "現在",
  "剛剛",
  "真的",
  "有點",
  "感覺",
  "想要",
  "什麼",
  "怎麼",
  "為什",
  "妳說",
  "你說",
  "我說",
  "她說",
  "這句",
  "那句",
  "妳的",
  "你的",
  "我的",
  "她的",
  "我還",
  "還在",
  "我在",
  "你在",
  "妳在",
  "她在",
  "我有",
  "你有",
  "妳有",
  "她有",
  "也有",
  "不會",
  "不是",
  "不要",
  "先不",
  "一下",
  "一點",
  "一個",
  "這樣",
  "那樣",
  "這麼",
  "那麼",
]);

function compact(value: string): string {
  return value
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\s\p{P}\p{S}]/gu, "");
}

export function rejectKnownCannedPracticeText(
  value: string,
  errorCode: string,
): void {
  const normalized = compact(value);
  if (
    KNOWN_CANNED_SIGNATURES.some((signature) =>
      normalized.includes(compact(signature))
    )
  ) {
    throw new Error(errorCode);
  }
}

export function rejectGenericPasteablePracticeText(
  value: string,
  errorCode: string,
): void {
  rejectKnownCannedPracticeText(value, errorCode);
  const normalized = compact(value);
  if (
    normalized.length < 6 ||
    GENERIC_META_SIGNATURES.some((signature) =>
      normalized === compact(signature) ||
      normalized === `${compact(signature)}。`
    )
  ) {
    throw new Error(errorCode);
  }
}

function evidenceFragments(value: string): Set<string> {
  const normalized = compact(value);
  const result = new Set<string>();
  // Very short replies are common in real chats. Their whole token is the only
  // honest lexical anchor; treating them as "no evidence" would let generic
  // canned copy pass. Emoji/punctuation-only turns remain ungroundable and are
  // failed closed by assertPracticeTextGroundedInTurns.
  if (normalized.length > 0 && normalized.length < 4) {
    result.add(normalized);
    return result;
  }
  // English replies are valid conversation evidence too. Keeping their word
  // tokens closes the old fail-open where Okay/Thanks/haha produced no
  // fragments and let generic Chinese copy pass automatically.
  if (!/\p{Script=Han}/u.test(normalized)) {
    for (
      const token of value.normalize("NFKC").toLowerCase().match(
        /[a-z0-9]{2,}/gu,
      ) ?? []
    ) {
      result.add(token);
    }
    return result;
  }
  if (normalized.length < 4) {
    return result;
  }
  for (const width of [4, 3, 2]) {
    if (normalized.length < width) continue;
    for (let index = 0; index <= normalized.length - width; index++) {
      const fragment = normalized.slice(index, index + width);
      if (COMMON_EVIDENCE_FRAGMENTS.has(fragment)) continue;
      if (/^[我你妳她他它這那的是了嗎呢吧啊喔哦欸啦]+$/u.test(fragment)) {
        continue;
      }
      result.add(fragment);
    }
  }
  return result;
}

/**
 * Generated coaching must visibly touch the supplied conversation rather than
 * pass a generic relationship template. This is deliberately lexical and
 * conservative: the prompt already asks the model to reuse a concrete detail,
 * and a failed check simply moves to the generated Claude repair path.
 */
export function assertPracticeTextGroundedInTurns(opts: {
  visibleText: string;
  turns?: PracticeTurn[];
  latestOnly?: boolean;
  errorCode: string;
}): void {
  if (!opts.turns || opts.turns.length === 0) return;
  const evidenceTurns = opts.latestOnly
    ? [...opts.turns].reverse().filter((turn) => turn.role === "ai").slice(0, 1)
    : opts.turns.slice(-8);
  const fragments = new Set<string>();
  for (const turn of evidenceTurns) {
    for (const fragment of evidenceFragments(turn.text)) {
      fragments.add(fragment);
    }
  }
  if (fragments.size === 0) {
    if (
      opts.latestOnly === true &&
      evidenceTurns.some((turn) => turn.text.trim().length > 0) &&
      evidenceTurns.every((turn) => compact(turn.text).length === 0)
    ) {
      throw new Error(opts.errorCode);
    }
    return;
  }
  const visible = compact(opts.visibleText);
  if (![...fragments].some((fragment) => visible.includes(fragment))) {
    throw new Error(opts.errorCode);
  }
}

export function normalizedPracticeText(value: string): string {
  return compact(value);
}
