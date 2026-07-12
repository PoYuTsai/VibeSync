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

// These are semantic skeletons rather than exact canned sentences. Providers
// often hide the same empty acknowledgement behind a topic slot, a discourse
// particle (「啦／耶」), or a near-synonym (「也常這樣／跟妳一樣」).
// A concrete continuation does not match because every skeleton is anchored at
// the end of the visible line.
const SLOT_PREFIX = ".*";
const GENERIC_PARTICLE = "(?:啦|耶|啊|喔|哦|欸|齁)?";
const GENERIC_ACK =
  `(?:我)?(?:(?:懂|了解|明白|知道)(?:了)?${GENERIC_PARTICLE}|(?:有)?(?:收到|接到|接住)(?:了)?${GENERIC_PARTICLE}|(?:能理解|有共鳴|有感|get到(?:了)?)${GENERIC_PARTICLE})`;
const GENERIC_SELF_LEAD =
  "(?:(?:其實|大概|好像)?我|我(?:其實|大概|好像)?|(?:其實|大概|好像))?";
const GENERIC_SELF_SIMILARITY =
  `${GENERIC_SELF_LEAD}(?:也(?:是(?:這樣)?|有過|遇(?:過|到過)|常(?:常)?(?:會)?(?:這樣|遇到|碰到)|會(?:這樣)?|差不多|一樣)|跟[妳你她他](?:一樣|差不多))${GENERIC_PARTICLE}`;
const GENERIC_RETURN_PROMPT =
  "(?:再聊聊[妳你]的|(?:那)?[妳你](?:呢|勒|咧)|換[妳你](?:呢|勒|咧)?|[妳你]也(?:是|會)嗎)?";
const GENERIC_HANDOFF =
  "(?:換我(?:來)?(?:說說|講講|聊聊|說一點|講一點|分享|分享一下|(?:說|講|聊)我的)|我(?:來|也來)(?:說說|講講|聊聊|分享|分享一下|(?:說|講|聊)我的)|再(?:換|讓)我(?:說說|講講|聊聊|分享|分享一下)|(?:輪到|該)我(?:說|講|聊)(?:了)?|輪我(?:了|(?:說|講|聊)(?:了)?))";
const GENERIC_HANDOFF_TAIL = "(?:再聽[妳你]的|再聊聊[妳你]的|[妳你]呢)?";

const SLOT_FILLED_CANNED_PATTERNS = [
  new RegExp(
    `^${SLOT_PREFIX}${GENERIC_SELF_SIMILARITY}${GENERIC_RETURN_PROMPT}$`,
    "u",
  ),
  new RegExp(
    `^${SLOT_PREFIX}(?:這個點|這件事|這句|這段)(?:${GENERIC_ACK}|(?:我)?(?:先記住|記住了))(?:${GENERIC_RETURN_PROMPT}|${GENERIC_HANDOFF}${GENERIC_HANDOFF_TAIL})$`,
    "u",
  ),
  new RegExp(
    `^${SLOT_PREFIX}${GENERIC_ACK}${GENERIC_HANDOFF}${GENERIC_HANDOFF_TAIL}$`,
    "u",
  ),
];

const GENERIC_PRAISE_TAIL =
  /(?:聽起來|感覺|看起來)?(?:很|蠻|滿|挺|有點)?(?:舒服|真實|有意思|有趣|有生活感|有感覺|特別|不錯|很好|很棒|很讚|可以)(?:耶|啦|啊|喔|哦|欸|齁)?$/u;
const GENERIC_PRAISE_HANDOFF =
  /(?:聽起來|感覺|看起來)?(?:很|蠻|滿|挺|有點)?(?:舒服|真實|有意思|有趣|有生活感|有感覺|特別|不錯|很好|很棒|很讚|可以)(?:[妳你])?(?:可以|願意|想|要不要)?(?:再|繼續)?(?:多)?(?:說|分享|聊|講)(?:一點|一些|一下|更多|下去)?(?:嗎|呢|嘛)?$/u;
// A negated acknowledgement ("沒記住"／"不懂") is a substantive admission, not a
// generic "收到／了解了" echo, so the tail must not fire when negated.
const GENERIC_ECHO_TAIL =
  /(?<![沒不未別])(?:收到|記住(?:了)?|聽到(?:了)?|懂(?:了)?|了解(?:了)?|明白(?:了)?|有接到(?:了)?|有接住(?:了)?)(?:耶|啦|啊|喔|哦|欸|齁)?$/u;
// The negation may sit further left than one char ("沒有記住"、"沒聽懂"), which a
// single-char lookbehind cannot see, so this guard runs before the echo tail.
const NEGATED_ACK_TAIL =
  /[沒不未別](?:有)?[聽記看搞弄]?(?:收到|記住|聽到|聽懂|懂|了解|明白|接到|接住)(?:了)?(?:耶|啦|啊|喔|哦|欸|齁)?$/u;

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

/**
 * Detects a grounded topic slot wrapped in praise or acknowledgement but with
 * no stance, scene, choice, or concrete next move. Grounding is deliberately
 * checked elsewhere; repeating one transcript noun must not make this useful.
 */
export function isGenericPracticeComplimentOrEcho(value: string): boolean {
  const normalized = compact(value);
  return GENERIC_PRAISE_TAIL.test(normalized) ||
    GENERIC_PRAISE_HANDOFF.test(normalized) ||
    (!NEGATED_ACK_TAIL.test(normalized) && GENERIC_ECHO_TAIL.test(normalized));
}

function groundingCompact(value: string): string {
  return compact(value)
    .replace(/(?:發|送|寄|丟|轉)(?=給)/gu, "傳")
    .replace(/那家店/gu, "那間店")
    .replace(/這家店/gu, "這間店");
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
    SLOT_FILLED_CANNED_PATTERNS.some((pattern) => pattern.test(normalized)) ||
    GENERIC_META_SIGNATURES.some((signature) =>
      normalized === compact(signature) ||
      normalized === `${compact(signature)}。`
    )
  ) {
    throw new Error(errorCode);
  }
}

function evidenceFragments(value: string): Set<string> {
  const normalized = groundingCompact(value);
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
  const visible = groundingCompact(opts.visibleText);
  if (![...fragments].some((fragment) => visible.includes(fragment))) {
    throw new Error(opts.errorCode);
  }
}

export function normalizedPracticeText(value: string): string {
  return compact(value);
}
