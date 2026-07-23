// 教練拆解卡 JSON 解析（純函式、可 deno test）。
// 防御性：去 markdown 圍欄、缺核心欄位丟出、vibe 非法則回退「中性」、長度 clamp。

import {
  rejectL4UnsafeVisibleText,
  rejectVisibleInternalLabelLeak,
  rejectVisibleTemperatureMechanismLeak,
} from "./visible_text_guard.ts";
import type { AppliedHintTurn, PracticeTurn } from "./validate.ts";
import {
  assertPracticeTextGroundedInTurns,
  isGenericPracticeComplimentOrEcho,
  normalizedPracticeText,
  rejectGenericPasteablePracticeText,
  rejectKnownCannedPracticeText,
} from "./practice_visible_quality.ts";
import {
  type PracticeInviteLevel,
  practiceInviteLevelFor,
} from "./practice_invite.ts";
import { toTraditionalChinese } from "./traditional_chinese.ts";
import {
  assertHintFactClaimsSupported,
  buildHintFactContext,
  type HintFactClaim,
} from "./hint_fact_ledger.ts";

export const VIBES = ["暖", "中性", "冷"];
export const DATE_CHANCES = ["low", "medium", "high"];
export const DEBRIEF_QUALITY_SCHEMA_VERSION = "semantic-quality-v2";

export interface GameBreakdown {
  phaseReached: string;
  missedVariable: string;
  failureState: string;
  nextFirstLine: string;
  inviteDirection: string;
}

const GENERATED_DEBRIEF_PROSE_MAX_LENGTH = 120;
const GENERATED_DEBRIEF_LIST_ITEM_MAX_LENGTH = 100;
const GENERATED_GAME_BREAKDOWN_MAX_LENGTH = 140;

/**
 * 單發 tool_use 強制 schema。只管結構（必填鍵＋型別＋寬鬆長度上限）；
 * parseDebriefCard 仍是硬 gate 權威——schema 寬、parser 嚴，衝突以 parser 為準。
 * gameBreakdown（Game 模式必填）與 hidden hintAssessment（有套用 Hint 時必填）
 * 在 schema 層做選填，缺欄由 parser 判敗。
 */
export const DEBRIEF_TOOL_SCHEMA: Readonly<Record<string, unknown>> = {
  type: "object",
  properties: {
    summary: {
      type: "string",
      description: "本場總結，繁體中文",
      maxLength: GENERATED_DEBRIEF_PROSE_MAX_LENGTH,
    },
    strengths: {
      type: "array",
      description: "做得好的點",
      items: {
        type: "string",
        maxLength: GENERATED_DEBRIEF_LIST_ITEM_MAX_LENGTH,
      },
      minItems: 1,
      maxItems: 2,
    },
    watchouts: {
      type: "array",
      description: "要注意的點",
      items: {
        type: "string",
        maxLength: GENERATED_DEBRIEF_LIST_ITEM_MAX_LENGTH,
      },
      minItems: 1,
      maxItems: 2,
    },
    suggestedLine: {
      type: "string",
      description: "下一句可直接貼上的建議訊息",
      maxLength: GENERATED_DEBRIEF_PROSE_MAX_LENGTH,
    },
    vibe: { type: "string", enum: VIBES },
    dateChance: { type: "string", enum: DATE_CHANCES },
    dateChanceReason: {
      type: "string",
      maxLength: GENERATED_DEBRIEF_PROSE_MAX_LENGTH,
    },
    nextInviteMove: {
      type: "string",
      maxLength: GENERATED_DEBRIEF_PROSE_MAX_LENGTH,
    },
    gameBreakdown: {
      type: "object",
      description: "Game 模式拆盤（Game 模式必填）",
      properties: {
        phaseReached: {
          type: "string",
          maxLength: GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        },
        missedVariable: {
          type: "string",
          maxLength: GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        },
        failureState: {
          type: "string",
          maxLength: GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        },
        nextFirstLine: {
          type: "string",
          maxLength: GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        },
        inviteDirection: {
          type: "string",
          maxLength: GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        },
      },
      required: [
        "phaseReached",
        "missedVariable",
        "failureState",
        "nextFirstLine",
        "inviteDirection",
      ],
      additionalProperties: false,
    },
    hintAssessment: {
      type: "object",
      description: "hidden-only：有套用 Hint 時必填，server 會移除",
      properties: {
        verdict: { type: "string", enum: ["preserved", "revised"] },
        revisedEvidenceQuote: { type: ["string", "null"] },
      },
      required: ["verdict", "revisedEvidenceQuote"],
      additionalProperties: false,
    },
  },
  required: [
    "summary",
    "strengths",
    "watchouts",
    "suggestedLine",
    "vibe",
    "dateChance",
    "dateChanceReason",
    "nextInviteMove",
  ],
  additionalProperties: false,
};

/**
 * Game 模式變體：gameBreakdown 升為 schema 必填（eval 第 1 輪 8/20 漏欄）。
 * parser 的 allowGameBreakdown 硬 gate 不變，schema 只是把結構要求前移到生成端。
 */
export const DEBRIEF_TOOL_SCHEMA_GAME: Readonly<Record<string, unknown>> = {
  ...DEBRIEF_TOOL_SCHEMA,
  required: [
    ...(DEBRIEF_TOOL_SCHEMA.required as string[]),
    "gameBreakdown",
  ],
};

/**
 * Hint 套用變體：appliedHintTurns 非空時 hintAssessment 升為 schema 必填。
 * 2026-07-23 真機：hidden 欄位只靠 prompt 教學，Sonnet 首發連兩局整欄漏掉；
 * 同 gameBreakdown 前例，把條件必填前移到生成端 schema。
 */
export function debriefToolSchemaFor(
  opts: { game: boolean; hintApplied: boolean },
): Record<string, unknown> {
  const base = opts.game ? DEBRIEF_TOOL_SCHEMA_GAME : DEBRIEF_TOOL_SCHEMA;
  if (!opts.hintApplied) return base as Record<string, unknown>;
  return {
    ...base,
    required: [...(base.required as string[]), "hintAssessment"],
  };
}

export interface DebriefCard {
  summary: string;
  strengths: string[];
  watchouts: string[];
  suggestedLine: string;
  vibe: string;
  /** 約出來機會：low｜medium｜high。 */
  dateChance: string;
  dateChanceReason: string;
  nextInviteMove: string;
  gameBreakdown: GameBreakdown | null;
}

function latestAssistantText(turns?: PracticeTurn[]): string {
  for (let index = (turns?.length ?? 0) - 1; index >= 0; index--) {
    if (turns?.[index]?.role === "ai") return turns[index].text;
  }
  return "";
}

export function clampStr(v: unknown, max: number): string {
  return typeof v === "string"
    ? toTraditionalChinese(v.trim()).slice(0, max)
    : "";
}

export function clampList(
  v: unknown,
  maxItems: number,
  maxLen: number,
): string[] {
  if (!Array.isArray(v)) return [];
  return v
    .map((x) => clampStr(x, maxLen))
    .filter((x) => x.length > 0)
    .slice(0, maxItems);
}

function generatedVisibleString(
  value: unknown,
  legacyMax: number,
  generatedMax: number,
  enforceGeneratedQuality: boolean,
): string {
  if (typeof value !== "string") return "";
  const trimmed = toTraditionalChinese(value.trim());
  if (enforceGeneratedQuality && trimmed.length > generatedMax) {
    throw new Error("debrief_quality_invalid_overlong");
  }
  return enforceGeneratedQuality ? trimmed : trimmed.slice(0, legacyMax);
}

function generatedVisibleList(
  value: unknown,
  maxItems: number,
  legacyMaxLength: number,
  generatedMaxLength: number,
  enforceGeneratedQuality: boolean,
): string[] {
  if (!Array.isArray(value)) return [];
  if (!enforceGeneratedQuality) {
    return clampList(value, maxItems, legacyMaxLength);
  }
  return value.slice(0, maxItems)
    .map((item) =>
      generatedVisibleString(
        item,
        legacyMaxLength,
        generatedMaxLength,
        enforceGeneratedQuality,
      )
    )
    .filter((item) => item.length > 0);
}

function rejectInternalLabelLeak(value: string) {
  rejectVisibleInternalLabelLeak(value, "debrief_internal_label_leak");
}

function guardVisibleText(value: string): string {
  rejectInternalLabelLeak(value);
  // 批3 P1：debrief prompt 注入 band 詞後，模型可能把溫度內部詞或 1.2 原詞
  // 抄進可見欄位；被拒→handler 重試→band-aware fallback 卡兜底。
  rejectVisibleTemperatureMechanismLeak(value, "debrief_temperature_leak");
  rejectL4UnsafeVisibleText(value, "debrief_l4_unsafe");
  return value;
}

const GAME_BREAKDOWN_FIELDS = [
  "phaseReached",
  "missedVariable",
  "failureState",
  "nextFirstLine",
  "inviteDirection",
] as const;

/**
 * eval 第 6 輪根因（2026-07-23）：Sonnet 偶發把 tool_use 的巢狀 gameBreakdown
 * 寫成 tool-call 拍平語法——gameBreakdown 變成以 `<parameter name="X">` 開頭的
 * 字串（欄位內容黏在字串裡），其餘欄位逸出到 JSON 頂層。內容其實完整，只是
 * 序列化形態壞掉；prompt 強調必填已證實無效（對症不對藥）。
 *
 * 此 repair 只還原「序列化形態」：逐段抽字串內 `<parameter name="X">` 欄位、
 * 把逸出頂層的欄位搬回巢狀物件並自頂層移除，再交回既有 gate
 * （missing_fields／grounding／詞面守門全不變）。抽完仍缺欄照舊
 * missing_fields reject，絕不填罐頭預設值。
 */
export function repairFlattenedGameBreakdown(
  p: Record<string, unknown>,
): void {
  const raw = p.gameBreakdown;
  if (typeof raw !== "string" || !raw.trimStart().startsWith("<parameter")) {
    return;
  }
  const reparented: Record<string, string> = {};
  // 值取到下一個 <parameter 段落或字串尾；去掉可能的 </parameter> 尾標與空白。
  const segmentRe =
    /<parameter\s+name="([^"]+)"\s*>([\s\S]*?)(?=<parameter\s+name="|$)/g;
  for (const match of raw.matchAll(segmentRe)) {
    const name = match[1];
    if (!(GAME_BREAKDOWN_FIELDS as readonly string[]).includes(name)) continue;
    const value = match[2].replace(/<\/parameter>\s*$/, "").trim();
    if (value.length > 0) reparented[name] = value;
  }
  // 字串裡連一欄都抽不到 → 不是可辨識的拍平形態，不動它，照舊 reject。
  if (Object.keys(reparented).length === 0) return;
  for (const field of GAME_BREAKDOWN_FIELDS) {
    const escaped = p[field];
    if (!(field in reparented) && typeof escaped === "string") {
      reparented[field] = escaped;
    }
    // 逸出頂層的欄位搬回巢狀後移除，避免殘留多餘 key。
    delete p[field];
  }
  p.gameBreakdown = reparented;
}

function parseGameBreakdown(
  value: unknown,
  enforceGeneratedQuality: boolean,
): GameBreakdown {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("debrief_game_breakdown_missing_fields");
  }
  const p = value as Record<string, unknown>;
  const gameBreakdown = {
    phaseReached: guardVisibleText(
      generatedVisibleString(
        p.phaseReached,
        60,
        GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        enforceGeneratedQuality,
      ),
    ),
    missedVariable: guardVisibleText(
      generatedVisibleString(
        p.missedVariable,
        60,
        GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        enforceGeneratedQuality,
      ),
    ),
    failureState: guardVisibleText(
      generatedVisibleString(
        p.failureState,
        60,
        GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        enforceGeneratedQuality,
      ),
    ),
    nextFirstLine: guardVisibleText(
      generatedVisibleString(
        p.nextFirstLine,
        70,
        GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        enforceGeneratedQuality,
      ),
    ),
    inviteDirection: guardVisibleText(
      generatedVisibleString(
        p.inviteDirection,
        60,
        GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        enforceGeneratedQuality,
      ),
    ),
  };
  if (Object.values(gameBreakdown).some((field) => field.length === 0)) {
    throw new Error("debrief_game_breakdown_missing_fields");
  }
  return gameBreakdown;
}

function debriefVisibleFields(card: DebriefCard): string[] {
  return [
    card.summary,
    ...card.strengths,
    ...card.watchouts,
    card.suggestedLine,
    card.dateChanceReason,
    card.nextInviteMove,
    ...(card.gameBreakdown
      ? [
        card.gameBreakdown.phaseReached,
        card.gameBreakdown.missedVariable,
        card.gameBreakdown.failureState,
        card.gameBreakdown.nextFirstLine,
        card.gameBreakdown.inviteDirection,
      ]
      : []),
  ];
}

function hasCompleteHintDecision(hint: AppliedHintTurn): boolean {
  const decision = hint.decision;
  return decision !== undefined &&
    [
      decision.phase,
      decision.targetVariable,
      decision.move,
      decision.inviteRoute,
      decision.rationale,
    ].every((field) => typeof field === "string" && field.trim().length > 0);
}

type HintStrategyRoute = "repair" | "build" | "soft" | "direct";

function authoritativeHintRoute(hint: AppliedHintTurn): HintStrategyRoute {
  const decision = hint.decision!;
  const route = `${decision.inviteRoute} ${decision.move}`.toLowerCase();
  if (/(?:repair|safety|降壓|修復|停止)/u.test(route)) return "repair";
  if (/(?:direct|明確邀約|直接邀約)/u.test(route)) return "direct";
  if (/(?:soft|低壓邀約|試探邀約)/u.test(route)) return "soft";
  return "build";
}

/**
 * Reads explicit strategy claims, not ordinary retrospective prose. Ordering
 * matters: 「先累積投入，等她再接才丟窗口」is a build route even though it
 * mentions a later invitation.
 */
function explicitNarrativeRoute(value: string): HintStrategyRoute | null {
  const text = value.normalize("NFKC").replace(/\s+/gu, "");
  if (
    // 「不要急著邀約」是 build（別急）不是 repair（停止）——急著/趕著/馬上族排除。
    /(?:先|需要|應該|這輪|現在).{0,10}(?:道歉|降壓|修復|修補安全|停下|退開)|(?:停止|不要|不再)(?!急|太快|馬上|趕).{0,8}(?:推進|邀約|打擾)/u
      .test(text)
  ) {
    return "repair";
  }
  if (
    /(?:先|這輪|現在|目前).{0,12}(?:不約|不急著約|別急著約|不硬約|不適合約|鋪墊|累積|建立|延伸|補足|補感受|補投入|熟悉|安全|穩住)|(?:先不要|先別|暫時不要|不要|別|不急著).{0,4}(?:約她|邀她|約對方|邀對方|邀約|問她(?:哪天|何時|什麼時候).{0,6}有空|定.{0,4}時間)|(?:還要|還需|需要)?再.{0,6}(?:累積|建立|延伸|補足|補感受|補投入|穩住)|等.{0,28}(?:再|才).{0,12}(?:約|邀|窗口)|(?:還沒|尚未|未到).{0,10}(?:窗口|時機)|(?:邀約)?窗口(?:還沒|尚未|仍未)(?:開|成熟)|先.{0,28}再.{0,12}(?:約|邀|窗口)|(?:觀察|看)(?:她|對方).{0,20}(?:再|才).{0,12}(?:約|邀|窗口)/u
      .test(text)
  ) {
    return "build";
  }
  if (
    /(?:沒有|沒)(?:做|給|丟|推)?(?:出)?(?:直接|明確)?邀約.{0,10}(?:失誤|錯|問題|可惜)|(?:太被動|偏保守|早該).{0,12}(?:直接)?(?:約|邀約)|(?:現在|這輪|下一句|下一步|接下來|應該|可以|建議|不妨|適合|立刻|趁現在).{0,12}(?:直接|明確)?(?:約她|邀她|約對方|邀對方|問她(?:哪天|何時|什麼時候).{0,6}有空|把.{1,12}收成.{0,4}(?:見面|咖啡|邀約)|去(?:喝咖啡|吃飯|散步|看展|逛街))|(?<!升到)(?<!是否)(?<!考慮)(?<!評估)(?:直接|明確|立刻|趁現在)(?:約|邀約)|(?:約|邀約).{0,8}(?:時機|窗口)(?:已經)?成熟/u
      .test(text)
  ) {
    return "direct";
  }
  if (
    /(?:低壓|試探|模糊|輕量)(?:約|邀約)|(?:丟|開|給).{0,6}(?:低壓|試探|短聚|短咖啡)?窗口|短(?:咖啡|聚).{0,6}(?:邀約|窗口)/u
      .test(text)
  ) {
    return "soft";
  }
  return null;
}

function strategyBearingFields(card: DebriefCard): string[] {
  return [
    card.summary,
    ...card.watchouts,
    card.suggestedLine,
    card.nextInviteMove,
    ...(card.gameBreakdown
      ? [
        card.gameBreakdown.failureState,
        card.gameBreakdown.nextFirstLine,
        card.gameBreakdown.inviteDirection,
      ]
      : []),
  ];
}

function inviteLevelContradicts(
  authoritative: HintStrategyRoute,
  actual: PracticeInviteLevel,
): boolean {
  if (actual === "none") return false;
  if (authoritative === "repair" || authoritative === "build") return true;
  return authoritative === "soft" && actual === "direct";
}

function cardContradictsHintStrategy(
  card: DebriefCard,
  appliedHintTurns: AppliedHintTurn[],
): boolean {
  const latestHint = appliedHintTurns.reduce((latest, hint) =>
    hint.turnIndex >= latest.turnIndex ? hint : latest
  );
  const authoritative = authoritativeHintRoute(latestHint);
  const narrativeRoutes = strategyBearingFields(card)
    .map(explicitNarrativeRoute)
    .filter((route): route is HintStrategyRoute => route !== null);
  if (narrativeRoutes.some((route) => route !== authoritative)) return true;

  const pasteableInviteLevels = [
    practiceInviteLevelFor(card.suggestedLine),
    ...(card.gameBreakdown
      ? [practiceInviteLevelFor(card.gameBreakdown.nextFirstLine)]
      : []),
  ];
  return pasteableInviteLevels.some((level) =>
    inviteLevelContradicts(authoritative, level)
  );
}

/**
 * 明確指涉「使用者這句回覆/提示句」的詞面（2026-07-23 契約收斂）。
 * 排除她方所有格（她的回覆/對方的回答＝在講對方的訊息）；bare「回答」
 * 不收（「她只回答飲食內容」的回答是動詞）。
 */
const HINT_REPLY_REFERENCE_PATTERN =
  /(?:照提示|照貼|提示那句|原本提示|hint|你的回覆|你的提問|你的問法|你這句|你這一?問|這句|剛才那句|剛剛那句|這個回應|這個回答|這樣回|這樣問|(?<!(?:她|對方)的)(?:回覆|訊息|提問)|(?<!(?:她|對方)的)這個(?:問法|問題|提問)|(?<!(?:她|對方)的)這一問)/iu;

/** 施事毀局句：把/讓＋毀局動詞，把責任歸給使用者送出的那句（＝Hint 句）。 */
const AGENTIVE_HINT_KILL_PATTERN =
  /(?:把|讓).{0,12}(?:聊死|停住|停掉|斷|句點|關上|冷場)/u;

const PRESERVED_HINT_CRITIQUE_PATTERN =
  /(?:只(?:回|問|停)|只是.{0,8}(?:禮貌|收尾|附和)|禮貌收尾|停在|沒給球|沒有給.{0,8}(?:球|接球|空間)|球(?:沒有|沒)丟回|(?:沒有|沒)丟回|沒有接|沒接住|很難繼續|查戶口|盤問|偏保守|太保守|太客套|客套|無效|扣分|沒留(?:接點|鉤子)|沒有留(?:接點|鉤子|回應空間)|沒有把話題往前帶|回覆收得太乾淨|互動斷在這裡|像把門關上|收得太死|沒有延伸|缺少鉤子|少了.{0,8}(?:鉤子|接點|溫度|生活感|畫面)|缺乏.{0,8}(?:鉤子|接點|溫度|生活感|畫面)|(?:容易)?冷場|(?:讓人)?接不下去|敷衍|平庸|話題.{0,4}句點|像句點|封閉話題|讓對話停住|把.{0,10}話題聊死|沒有讓對話延續|太乾|收尾感太重|對話沒有出口|沒有留下下一球|很難接下去)/u;

type PreservedHintCritiqueMatch = {
  index: number;
  text: string;
};

function preservedHintCritiqueMatches(
  compact: string,
): PreservedHintCritiqueMatch[] {
  const globalPattern = new RegExp(
    PRESERVED_HINT_CRITIQUE_PATTERN.source,
    `${PRESERVED_HINT_CRITIQUE_PATTERN.flags}g`,
  );
  return [...compact.matchAll(globalPattern)].map((match) => ({
    index: match.index,
    text: match[0],
  }));
}

function lastPatternIndex(text: string, pattern: RegExp): number {
  let latest = -1;
  for (const match of text.matchAll(pattern)) {
    if (match.index !== undefined) latest = match.index;
  }
  return latest;
}

function lastPartnerSubjectIndex(text: string): number {
  return lastPatternIndex(
    text,
    /(?:^|[，,:：；;]|但|不過|可是|然而|(?:做)?後|目前|這輪|從|結果|最後|當下|現在)(?:目前|最後|後來|仍然|只|現在|這次)?(?:她|對方)/gu,
  );
}

function hasPartnerRecipientReference(value: string): boolean {
  const compact = normalizedPracticeText(value);
  return /(?:她|對方)(?:收到|看到|讀到|接到|面對)(?:的)?(?:這句|回覆|訊息)/u
    .test(compact);
}

function partnerPerceptionTargetsUserReply(value: string): boolean {
  const compact = normalizedPracticeText(value);
  return /(?:^|[，,:：；;]|但|不過|可是|然而|結果|最後|當下|現在)(?:她|對方).{0,8}(?:覺得|認為|感覺|說|表示).{0,8}(?:你的回覆|你這句|這個回應|這個回答|這句|回覆|回答|訊息)/u
    .test(compact);
}

function hasPartnerSubject(value: string): boolean {
  return value.split(/[。！？；;，,:：\n]+/u).some((clause) =>
    !hasPartnerRecipientReference(clause) &&
    !partnerPerceptionTargetsUserReply(clause) &&
    lastPartnerSubjectIndex(normalizedPracticeText(clause)) >= 0
  );
}

function critiqueClearlyTargetsPartner(
  compact: string,
  criticalIndex: number,
): boolean {
  const prefix = compact.slice(0, criticalIndex);
  if (hasPartnerRecipientReference(prefix)) return false;
  if (partnerPerceptionTargetsUserReply(prefix)) return false;
  if (
    /(?:她|對方)(?:看完|讀完|收到後|看到後).{0,6}(?:覺得|認為|感覺)/u
      .test(prefix)
  ) {
    return false;
  }
  if (
    /(?:她|對方).{0,12}(?:對|看到|收到|讀到|接到)(?:了)?你的回覆(?:後)?.{0,8}(?:覺得|認為|感覺|嫌|評為)/u
      .test(prefix)
  ) {
    return false;
  }
  if (
    /(?:她|對方).{0,8}(?:對|看到|收到|讀到|接到)(?:了)?你的回覆(?:後)?/u
      .test(prefix)
  ) {
    return true;
  }
  const partnerSubjectIndex = lastPartnerSubjectIndex(prefix);
  const userOrHintIndex = lastPatternIndex(
    prefix,
    /(?:照提示|照貼|提示那句|原本提示|提示|hint|你的回覆|你這句|你剛才|你剛剛|你後來|使用者|這個回應|剛才那句|剛剛那句|你)/giu,
  );
  return partnerSubjectIndex > userOrHintIndex;
}

function critiqueIsNegatedPraise(
  compact: string,
  criticalIndex: number,
): boolean {
  const prefix = compact.slice(0, criticalIndex);
  return /(?:(?:沒有|沒|不會|不是|不像|並非|避免|不算).{0,5}|(?:不只|不僅)(?:是)?.{0,8}|不)$/u
    .test(prefix);
}

function critiqueClearlyTargetsAnotherUserTurn(
  clause: string,
  turns: PracticeTurn[] | undefined,
  appliedHintTurns: AppliedHintTurn[],
): boolean {
  const compact = normalizedPracticeText(clause);
  if (/(?:照提示|照貼|提示那句|hint)/iu.test(compact)) return false;
  if (
    /(?:提示前|照貼前|前一(?:句|輪|則)|上一(?:句|輪|則)|前面那句|第[一二三四五六七八九十\d]+句)/u
      .test(compact)
  ) {
    return true;
  }
  const latestHintIndex = Math.max(
    ...appliedHintTurns.map((hint) => hint.turnIndex),
  );
  const laterUserTurns = (turns ?? []).filter((turn, index) =>
    index > latestHintIndex && turn.role === "user"
  );
  if (laterUserTurns.length === 0) return false;
  if (/(?:你後來|後來你|下一輪你|提示後你又)/u.test(compact)) return true;
  return laterUserTurns.some((turn) => {
    const laterText = normalizedPracticeText(turn.text);
    return laterText.length >= 2 && compact.includes(laterText);
  });
}

function hasForwardCoachingScope(value: string): boolean {
  const compact = normalizedPracticeText(value);
  return /^(?:下一步|下次|接下來|之後|後續|先|接著|等她|延續|沿著|順著|可以|建議|不妨|記得)/u
    .test(
      compact,
    ) ||
    /(?:可以再|可再|還能再|再補|再加|先(?:觀察|等|延續|補|聊|接|看)|(?:邀約)?窗口(?:還沒|尚未|仍未)(?:開|成熟).{0,10}(?:繼續|先|再)(?:累積|延續|建立|多聊))/u
      .test(compact);
}

function debriefAnalyticalFields(card: DebriefCard): string[] {
  return [
    card.summary,
    ...card.strengths,
    ...card.watchouts,
    card.dateChanceReason,
    card.nextInviteMove,
    ...(card.gameBreakdown
      ? [
        card.gameBreakdown.phaseReached,
        card.gameBreakdown.missedVariable,
        card.gameBreakdown.failureState,
        card.gameBreakdown.inviteDirection,
      ]
      : []),
  ];
}

function isVagueDebriefTopicAction(value: string): boolean {
  const compact = normalizedPracticeText(value);
  const hasThinForwardAction =
    /(?:下一步|下次|接下來|之後|後續|接著|繼續|可以|建議|不妨).{0,8}(?:問|聊|延伸|接住|接)|^(?:接著|繼續|再)(?:問|聊|延伸|接住|接)/u
      .test(compact);
  const hasConcreteMethodOrTarget =
    /(?:哪|什麼|怎麼|為什麼|最常|偏好|感受|原因|畫面|時間|時段|哪一|哪裡|幾|自己的|交換|回呼|選擇|如果|等她|看她|再看|因為|別|不要|避免|改成|換成|一句|一個|二選一|生活習慣)/u
      .test(compact);
  return hasThinForwardAction && !hasConcreteMethodOrTarget &&
    compact.length <= 24;
}

function isGenericDebriefDateReason(value: string): boolean {
  const compact = normalizedPracticeText(value);
  const onlyRestatesSharing =
    /^(?:她|對方)(?:願意|有)?(?:說|分享|聊)(?:了)?(?:自己)?(?:住)?[\p{Script=Han}a-z0-9]{1,28}$/u
      .test(compact);
  const explainsReadiness =
    /(?:但|不過|所以|而且|同時|開玩笑|回問|窗口|時間|時段|見面|邀|投入|拒絕|冷|短|主動|延伸|接球|多聊)/u
      .test(compact);
  return onlyRestatesSharing && !explainsReadiness;
}

function assertGeneratedDebriefFieldSubstance(card: DebriefCard): void {
  const summary = normalizedPracticeText(card.summary);
  if (
    /(?:這個)?(?:話題|資訊)(?:有)?(?:接到|聊到|回應到|延伸到)$/u.test(
      summary,
    )
  ) {
    throw new Error("debrief_quality_invalid_summary_substance");
  }

  for (const strength of card.strengths) {
    const compact = normalizedPracticeText(strength);
    const onlyRestatesAcknowledge = /(?:接到|接住|承接|回應)/u.test(compact) &&
      !/(?:讓|所以|因此|沒有|避免|變成|延伸|分享自己|提問|問句|畫面|幽默|選擇|具體|降低|保留|回呼|交換|自己的)/u
        .test(compact);
    if (onlyRestatesAcknowledge) {
      throw new Error("debrief_quality_invalid_strength_substance");
    }
  }

  for (const watchout of card.watchouts) {
    if (isVagueDebriefTopicAction(watchout)) {
      throw new Error("debrief_quality_invalid_watchout_substance");
    }
  }

  if (isGenericPracticeComplimentOrEcho(card.suggestedLine)) {
    throw new Error("debrief_quality_invalid_suggested_line");
  }
  if (isGenericDebriefDateReason(card.dateChanceReason)) {
    throw new Error("debrief_quality_invalid_date_reason_substance");
  }
  if (isVagueDebriefTopicAction(card.nextInviteMove)) {
    throw new Error("debrief_quality_invalid_next_move_substance");
  }
}

function partnerTurnContainsInviteEvidence(value: string): boolean {
  const compact = normalizedPracticeText(value);
  return practiceInviteLevelFor(value) !== "none" ||
    /(?:約|邀)[妳你]|要不要.{0,8}一起|(?:跟|和)[妳你].{0,10}(?:見面|碰面|喝咖啡|吃飯|散步|看展|逛街)/u
      .test(compact) ||
    // 她自報空檔（我這週六下午剛好有空）＝主動釋出時間窗口
    // （2026-07-23 gd1 eval：卡片寫「她釋出時間窗口」被誤殺）。
    /我.{0,10}(?:有空|沒事|有時間|都可以|沒排)/u.test(compact) ||
    // 她拍板確認（下午可以欸，那說好了）＝接受/敲定邀約
    // （2026-07-23 gd5 eval 同型誤殺）。
    /(?:說好了|說定|一言為定|成交)/u.test(compact) ||
    // 可以後接「再看/先休息/睡」等後續動作＝保留不是拍板（Codex 首審 P2-4）。
    /(?:週[一二三四五六日末]|星期[一二三四五六日天]|禮拜[一二三四五六日天]|明天|後天|下午|晚上|早上)[^，,。！？!?；;]{0,4}(?:可以|沒問題|ok|行)(?!再|先|睡|休|等|忙|慢|考慮|想|看)/iu
      .test(compact);
}

// 逐子句判定：跨子句黏連（「先聊她的感受，累積默契後再提邀約」的她與邀約
// 分屬不同子句、不同主詞）曾整批誤殺（2026-07-23 真機 debrief eval）。
function claimsPartnerInitiatedInvite(value: string): boolean {
  return value.split(/[，,。！？!?；;\n]+/u).some((clause) =>
    clauseClaimsPartnerInitiatedInvite(clause)
  );
}

function clauseClaimsPartnerInitiatedInvite(value: string): boolean {
  const compact = normalizedPracticeText(value);
  if (
    /(?:還沒|尚未|沒有|沒|未|不).{0,24}(?:見面|碰面|邀約|約|邀)/u.test(
      compact,
    )
  ) {
    return false;
  }
  // 「等她主動釋出時間再考慮邀約」「觀察她是否會問你」「累積到她主動釋出
  // 線索再考慮邀約」＝未來條件教學句，不是「她邀約過」宣稱
  // （2026-07-23 真機 debrief eval FP 家族）。
  if (
    /(?:等|等到|看|觀察|如果|假如|若|要是|直到|累積到)(?:她|對方)(?:是否|會不會|有沒有)?.{0,20}(?:主動|願意|想|提|問|回|開口)/u
      .test(compact)
  ) {
    return false;
  }
  if (
    /(?:她|對方).{0,20}主動.{0,16}再(?:考慮|談|提|評估|看|開|邀|約)/u
      .test(compact)
  ) {
    return false;
  }
  // 動詞與邀約詞之間隔著「窗口/機會/時機」＝機會描述或教練指令句（如「順著她給的窗口直接邀約」），非「她邀約過」宣稱
  return /(?:她|對方).{0,28}(?:主動(?:提(?:了|出)?|說|問|給|丟|發出)?|(?:提(?:了|出)?|說想|說要|問|給|丟|發出|表示想|想|要|願意))(?:(?!窗口|機會|時機|的).){0,12}(?:見面|碰面|邀約|約你|邀你)/u
    .test(compact) ||
    // 「邀約窗口/機會/時機」是機會描述不是「她發出過邀約」的宣稱，不觸發本 gate
    /(?:她|對方)的.{0,10}(?:邀約(?!窗口|機會|時機)|見面提議|約見)/u.test(compact);
}

function assertNoInventedPartnerInitiative(
  card: DebriefCard,
  turns: PracticeTurn[] | undefined,
): void {
  if (!debriefVisibleFields(card).some(claimsPartnerInitiatedInvite)) return;
  const hasPartnerInviteEvidence = (turns ?? []).some((turn) =>
    turn.role === "ai" && partnerTurnContainsInviteEvidence(turn.text)
  );
  if (!hasPartnerInviteEvidence) {
    throw new Error("debrief_quality_invalid_partner_initiative");
  }
}

function assertGeneratedDebriefFieldRoles(card: DebriefCard): void {
  const summary = normalizedPracticeText(card.summary);
  if (
    !/(?:你|使用者|她|對方|雙方|提示|回覆|這句|話題|梗).{0,18}(?:接|回|問|提|說|分享|延伸|交換|照|聊|停|投入|開玩笑|升溫|降溫)|(?:這輪|本輪|對話|互動).{0,24}(?:接|回|問|提|說|分享|延伸|交換|照|聊|投入|開玩笑|升溫|降溫)|(?:接|回|問|提|說|分享|延伸|交換|照|聊|停|投入).{0,18}(?:她|對方|話題|梗|提示|回覆)/u
      .test(summary)
  ) {
    throw new Error("debrief_quality_invalid_summary_role");
  }

  for (const strength of card.strengths) {
    if (
      !/(?:你|使用者|回覆|這句|提示|有照|有接|接住|承接|延伸|分享|提問|問句|把.{0,12}變成|梗有延續)/u
        .test(normalizedPracticeText(strength))
    ) {
      throw new Error("debrief_quality_invalid_strength_role");
    }
  }

  for (const watchout of card.watchouts) {
    if (
      !/(?:下一步|下次|接下來|可以|建議|不妨|記得|先|再|少|多留|多放|補|問|分享|延伸|接|回|改|換|等|別|不要)/u
        .test(normalizedPracticeText(watchout)) ||
      /^(?:可以|建議|不妨)?(?:增加|加強|提升)(?:一點)?(?:投入感|生活感|互動感|熟悉感)[。！]?$/u
        .test(normalizedPracticeText(watchout))
    ) {
      throw new Error("debrief_quality_invalid_watchout_role");
    }
  }

  const dateReason = normalizedPracticeText(card.dateChanceReason);
  if (
    !/(?:她|對方).{0,20}(?:回|問|提|說|分享|延伸|接|開玩笑|主動|願意|拒絕|冷|短)|雙方.{0,16}(?:提|聊|分享|交換)|(?:尚未|還沒|還沒有|沒有|未見|仍未).{0,12}(?:窗口|見面|時間|意願|投入|訊號)|(?:窗口|時間|意願|投入).{0,10}(?:出現|明確|不足|不夠|未開|沒開|還沒開|尚未成熟)/u
      .test(dateReason)
  ) {
    throw new Error("debrief_quality_invalid_date_reason_role");
  }

  const nextMove = normalizedPracticeText(card.nextInviteMove);
  if (
    /^(?:先)?(?:累積|建立)(?:一點|更多)?(?:熟悉感|投入感|生活感)?(?:，|再)?(?:再)?找(?:自然)?(?:邀約)?窗口[。！]?$/u
      .test(nextMove) ||
    /^(?:先)?聊.{1,12}(?:，|再)+(?:再)?找(?:自然)?(?:邀約)?窗口[。！]?$/u
      .test(nextMove) ||
    !/(?:問|分享|交換|延伸|接|回|補|改|換|等|看|丟|約|邀|收成|保留|玩|聊)/u
      .test(nextMove)
  ) {
    throw new Error("debrief_quality_invalid_next_move_role");
  }

  const game = card.gameBreakdown;
  if (!game) return;
  if (
    !/(?:階段|開場|熟悉|測試|升溫|邀約|投入|窗口|進度|進到|仍在|已到|到達)/u
      .test(normalizedPracticeText(game.phaseReached))
  ) {
    throw new Error("debrief_quality_invalid_game_phase_role");
  }
  if (
    !/(?:缺|少|不足|不夠|還沒|尚未|未能|沒有|目標|投入|感受|畫面|接點|窗口)/u
      .test(normalizedPracticeText(game.missedVariable))
  ) {
    throw new Error("debrief_quality_invalid_game_variable_role");
  }
  const failure = normalizedPracticeText(game.failureState);
  if (
    /^(?:話題|互動|對話)?.{0,12}(?:目前)?(?:有點)?卡住[。！]?$/u.test(
      failure,
    ) ||
    !/(?:停|卡|斷|冷|硬|表面|問答|失速|無法|沒|未|不足|太|偏|風險|句點|聊死|難接)/u
      .test(failure)
  ) {
    throw new Error("debrief_quality_invalid_game_failure_role");
  }
  const inviteDirection = normalizedPracticeText(game.inviteDirection);
  if (
    /^(?:先)?聊.{1,12}(?:，|再)+(?:再)?找(?:自然)?(?:邀約)?窗口[。！]?$/u
      .test(inviteDirection) ||
    !/(?:問她|分享|交換|延伸|接|補|換|等她|看她|丟|約|邀|收成|保留|玩)/u
      .test(inviteDirection)
  ) {
    throw new Error("debrief_quality_invalid_game_invite_role");
  }
}

function hasNegativeReplyEvaluation(value: string): boolean {
  // 引號內是引述（多半是對方原話），不是拆解卡自己的評價。
  const compact = normalizedPracticeText(
    value.replace(/「[^」]*」|『[^』]*』/gu, ""),
  )
    .replace(
      /(?:沒有|沒|不會|並不|不)(?:造成|帶來|顯得|讓她感到|給她|連續)?(?:太)?(?:加壓|壓力|壓迫|逼迫|逼人|急|用力|突兀|冒進|油膩|刻意|硬推|硬聊|盤問|查戶口|追問|轟炸)/gu,
      "",
    )
    .replace(
      /(?:沒有|沒|不會|不是|並非)(?:(?:不夠|缺少|欠缺|不足|少了|缺乏)(?:生活感|溫度|鉤子|接點|畫面|具體|有趣|自然|承接|投入|誠意|真誠)|(?:太|過於|偏|顯得|略嫌)?(?:單薄|客套|平淡|乾|冷|硬|制式|普通|尷尬|無聊|敷衍|平庸)|(?:容易)?冷場|(?:讓人)?接不下去)/gu,
      "",
    )
    // 路線進度陳述（還沒有往邀約方向推進）不是對回覆品質的負評。
    .replace(
      /(?:還沒|尚未|仍未)(?:有)?(?:往|向)?.{0,10}(?:推進|升溫|邀約|見面|窗口)/gu,
      "",
    );
  const target = compact.match(/(?:這句|回覆|訊息|回答)/u);
  const tail = target?.index === undefined
    ? compact
    : compact.slice(target.index + target[0].length);
  if (/(?:不夠|缺少|欠缺|不足|沒有).{1,12}/u.test(tail)) return true;
  if (
    /(?:少了|缺乏).{1,12}|(?:容易)?冷場|(?:讓人)?接不下去|(?:顯得)?敷衍|(?:略嫌)?平庸/u
      .test(tail)
  ) {
    return true;
  }
  if (/(?:像|像是)(?:客服|罐頭|機器|公關|面試|句點|制式)/u.test(tail)) {
    return true;
  }
  if (/(?:很|有點)(?:無聊|平淡|乾|冷|硬|制式|普通|尷尬)/u.test(tail)) {
    return true;
  }
  return /(?:太|過於|偏)(?!好|自然|順|有趣|生動|舒服|真誠|具體|剛好).{1,8}/u
    .test(tail);
}

function hintCreditHasUnscopedAdversative(value: string): boolean {
  const compact = normalizedPracticeText(value);
  const creditPattern =
    /(?:(?:有|已)(?:照|採用|使用)提示|照著提示|照提示|照貼提示|提示那句)/gu;
  for (const credit of compact.matchAll(creditPattern)) {
    const remainder = compact.slice(credit.index + credit[0].length);
    for (
      const adversative of remainder.matchAll(
        /(?:但|不過|可是|然而|卻|只是|唯獨)/gu,
      )
    ) {
      if (
        adversative[0] === "只是" &&
        remainder[adversative.index - 1] === "不"
      ) {
        continue;
      }
      const tail = remainder.slice(adversative.index + adversative[0].length);
      const targetsOtherUserTurn =
        /(?:提示前|照貼前|前一(?:句|輪|則)|上一(?:句|輪|則)|前面那句|你後來|後來你|下一輪你|提示後你又)/u
          .test(tail);
      const isForwardCoaching = hasForwardCoachingScope(tail) &&
        !/(?:照提示|照貼|提示那句|原本提示|hint)/iu.test(tail);
      if (hasPartnerSubject(tail) || targetsOtherUserTurn || isForwardCoaching) {
        continue;
      }
      // 契約收斂（2026-07-23 真機 debrief 全滅）：轉折尾只有「詞表批評」或
      // 「明確指涉回覆＋負評」才算翻案；進度/路線/她方觀察等回顧（還沒往
      // 邀約方向推進、後續沒有新的反問）一律放行——allowlist 措辭窮舉已被
      // 真 API eval 證明收斂不了，改 kill-list。
      // 「但整場仍停在資訊交換階段」＝進度陳述非批 Hint（停在/卡在＋
      // 資訊交換/階段族收口）。
      const progressState =
        /(?:停在|卡在|停留在).{0,10}(?:資訊交換|一問一答|資訊|表面|階段|熟悉|認識|鋪墊)/u
          .test(tail);
      const critiqued = !progressState &&
        preservedHintCritiqueMatches(tail).some((match) =>
          !critiqueIsNegatedPraise(tail, match.index)
        );
      if (critiqued) return true;
      if (
        HINT_REPLY_REFERENCE_PATTERN.test(tail) &&
        hasNegativeReplyEvaluation(tail)
      ) {
        return true;
      }
    }
  }
  return false;
}

function hasDateOutcomeScope(value: string): boolean {
  const compact = normalizedPracticeText(value);
  if (
    hasPartnerSubject(value) ||
    /(?:目前|這輪|現階段|現在|尚未|還沒|未見|仍未).{0,18}(?:窗口|邀約|見面|投入|回覆|互動|時間|意願)/u
      .test(compact) ||
    /(?:邀約)?窗口(?:尚未|還沒|仍未)(?:出現|開|成熟)/u.test(compact)
  ) {
    return true;
  }
  if (
    /(?:你的回覆|你這句|這句|這個回應)/u.test(compact) &&
    /(?:自然|接住|延續|舒服|有來有往|順|輕鬆|有畫面|有互動|有承接|沒有加壓|不會太急|沒有太用力|不突兀)/u
      .test(compact) &&
    !hasNegativeReplyEvaluation(value)
  ) {
    return true;
  }
  return !/(?:照提示|照貼|提示那句|原本提示|hint|你的回覆|你這句|這句|剛才那句|剛剛那句|這個回應)/iu
    .test(compact);
}

function hasGamePhaseScope(value: string): boolean {
  const compact = normalizedPracticeText(value);
  return hasPartnerSubject(value) ||
    /(?:階段|開場|建立熟悉|熟悉建立|測試|升溫|邀約|投入|窗口|進度|進到|仍在|已到|到達|stage|phase)/iu
      .test(compact);
}

function isObjectiveGameOutcome(value: string): boolean {
  const compact = normalizedPracticeText(value);
  if (
    /(?:照提示|照貼|提示那句|原本提示|hint|你的回覆|你這句|這句|剛才那句|剛剛那句|這個回應)/iu
      .test(compact)
  ) {
    return false;
  }
  return /^(?!把|讓)(?:[\p{Script=Han}A-Za-z0-9·・]{0,10})?(?:話題|互動|對話|節奏)(?:(?:沒有|沒|尚未|還沒|未能|仍未)(?:延伸|繼續|往前|往深處走|升溫|展開|推進|打開|接下去)|(?:停住|中斷|停在表面))(?:了)?$/u
    .test(compact);
}

function preservedCardCritiquesExactHint(
  card: DebriefCard,
  appliedHintTurns: AppliedHintTurn[],
  turns?: PracticeTurn[],
): boolean {
  if (!appliedHintTurns.some((hint) => hint.exact)) return false;
  if (
    [card.summary, ...card.strengths].some(
      hintCreditHasUnscopedAdversative,
    )
  ) {
    return true;
  }
  if (!hasDateOutcomeScope(card.dateChanceReason)) return true;
  if (
    card.gameBreakdown && !hasGamePhaseScope(card.gameBreakdown.phaseReached)
  ) {
    return true;
  }
  // 契約收斂（2026-07-23 真機 debrief 全滅）：unscoped 批評預設不再視為批
  // Hint——真 API eval 證明「安全措辭 allowlist」對模型輸出多樣性收斂不了
  // （六張好卡 0% 過關）。改 kill-list：只有(1)明確指涉這句/回覆/提示、
  // (2)整句引用 Hint 原文、(3)施事毀局句（把話題聊死）、(4)短裸評價
  // （太平淡/只停在禮貌收尾＝對回覆的隱式判詞）才算翻案。
  // 卡文已過 guardVisibleText 繁化（准→準），引用比對兩側都先繁化。
  const exactHintQuotes = appliedHintTurns
    .filter((hint) => hint.exact)
    .map((hint) => normalizedPracticeText(toTraditionalChinese(hint.sentText)))
    .filter((quote) => quote.length >= 6);
  const critiqueFields: Array<{
    value: string;
    allowObjectiveGameOutcome?: boolean;
  }> = [
    { value: card.summary },
    ...card.strengths.map((value) => ({ value })),
    ...card.watchouts.map((value) => ({ value })),
    { value: card.dateChanceReason },
    { value: card.nextInviteMove },
    ...(card.gameBreakdown
      ? [
        { value: card.gameBreakdown.phaseReached },
        {
          value: card.gameBreakdown.missedVariable,
          allowObjectiveGameOutcome: true,
        },
        {
          value: card.gameBreakdown.failureState,
          allowObjectiveGameOutcome: true,
        },
      ]
      : []),
  ];
  for (const { value: field, allowObjectiveGameOutcome } of critiqueFields) {
    if (allowObjectiveGameOutcome && isObjectiveGameOutcome(field)) continue;
    for (const clause of field.split(/[。！？；;\n]+/u)) {
      const compact = normalizedPracticeText(clause);
      if (compact.length === 0) continue;
      const critiques = preservedHintCritiqueMatches(compact).filter((match) =>
        !critiqueIsNegatedPraise(compact, match.index)
      );
      const replyReferenced = HINT_REPLY_REFERENCE_PATTERN.test(compact) ||
        exactHintQuotes.some((quote) =>
          normalizedPracticeText(toTraditionalChinese(clause)).includes(quote)
        );
      const agentive = AGENTIVE_HINT_KILL_PATTERN.test(compact);
      if (!replyReferenced && !agentive) {
        // 短裸評價（太平淡/賴床這輪只停在禮貌收尾）＝對回覆的隱式判詞；
        // 有主詞（你的生活樣本還沒有出現）/前瞻/指涉他句的回顧一律放行。
        if (
          compact.length <= 12 &&
          (critiques.length > 0 || hasNegativeReplyEvaluation(clause)) &&
          !/(?:你|妳)/u.test(compact) &&
          !hasPartnerSubject(clause) &&
          !hasForwardCoachingScope(clause) &&
          !critiqueClearlyTargetsAnotherUserTurn(clause, turns, appliedHintTurns)
        ) {
          return true;
        }
        continue;
      }
      const forwardInstruction =
        /^(?:下一步|下次|接下來|之後)/u.test(compact) &&
        !/(?:照提示|照貼|提示那句|原本提示|剛才那句|hint)/iu.test(compact);
      if (
        forwardInstruction ||
        critiqueClearlyTargetsAnotherUserTurn(clause, turns, appliedHintTurns)
      ) {
        continue;
      }
      for (const critical of critiques) {
        if (critiqueClearlyTargetsPartner(compact, critical.index)) continue;
        // 「照提示延伸，但整場仍停在資訊交換階段」＝進度陳述；停在/卡在
        // 收在進度名詞上不算批 Hint（收尾在禮貌收尾/句點等判詞仍殺）。
        if (
          /^(?:停在|卡在|停留在)/u.test(critical.text) &&
          /(?:停在|卡在|停留在).{0,10}(?:資訊交換|一問一答|資訊|表面|階段|熟悉|認識|鋪墊)/u
            .test(compact)
        ) {
          continue;
        }
        return true;
      }
      // negEval 只在子句真的點名回覆（這句/回覆…）時才算翻案；只因提及
      // 「照提示」就咬「缺乏下一步鋪墊」這類進度負評是誤殺。
      if (
        /(?:這句|你的回覆|這個回應|這個回答|這樣回|剛才那句|剛剛那句|(?<!(?:她|對方)的)(?:回覆|回答|訊息))/u
          .test(compact) &&
        hasNegativeReplyEvaluation(clause) && !hasPartnerSubject(clause)
      ) {
        return true;
      }
    }
  }
  return false;
}

function isPreservedHiddenHintAssessment(value: unknown): boolean {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }
  const assessment = value as Record<string, unknown>;
  return assessment.verdict === "preserved" &&
    assessment.revisedEvidenceQuote === null;
}

function compactDebriefQuote(value: string, maxChars = 18): string {
  const normalized = value
    .normalize("NFKC")
    .replace(/\s+/gu, " ")
    .replace(/[「」"']/gu, "")
    .trim();
  const chars = [...normalized];
  if (chars.length <= maxChars) return normalized;
  return `${chars.slice(0, maxChars).join("")}…`;
}

function assistantTextNearHint(
  turns: PracticeTurn[] | undefined,
  hintTurnIndex: number,
  direction: "before" | "after",
): string {
  if (!turns || turns.length === 0) return "";
  if (direction === "after") {
    for (let index = hintTurnIndex + 1; index < turns.length; index++) {
      if (turns[index]?.role === "ai") return turns[index].text;
    }
    return "";
  }
  for (let index = hintTurnIndex - 1; index >= 0; index--) {
    if (turns[index]?.role === "ai") return turns[index].text;
  }
  return "";
}

function cardVisiblyReversesPreservedHint(card: DebriefCard): boolean {
  const visible = normalizedPracticeText(debriefVisibleFields(card).join("\n"));
  return /(?:提示|hint).{0,16}(?:錯|不對|不該|太急|偏保守|無效|不好|不合適|不適合|有問題|失準|誤判)/iu
    .test(visible);
}

function preservedHintTopicLabel(value: string): string {
  const normalized = normalizedPracticeText(value);
  if (
    /(?:咖啡|口袋名單|裝潢|氣味|香味|單品|黑咖啡|拿鐵|美式)/u.test(normalized)
  ) {
    return "咖啡偏好";
  }
  if (/(?:追什麼劇|什麼劇|追劇|好看嗎|片單|懸疑|推薦)/u.test(normalized)) {
    return "追劇片單";
  }
  if (/(?:作息|時差|長班|上班|飛久|飛回來|飛回|抗戰)/u.test(normalized)) {
    return "時差狀態";
  }
  if (/(?:賴床|開機|睡醒|醒了)/u.test(normalized)) {
    return "開機狀態";
  }
  return "她剛丟回來的話題";
}

function preservedHintRepairNextLine(anchor: string, context = anchor): string {
  const normalized = normalizedPracticeText(`${anchor}\n${context}`);
  if (
    /(?:黑咖啡|單品|美式|拿鐵|咖啡|口袋名單|裝潢|氣味|香味)/u.test(normalized)
  ) {
    return "妳剛說咖啡偏好，清爽感跟香氣妳最在意哪一個？";
  }
  if (/(?:追什麼劇|什麼劇|追劇|好看嗎|片單|懸疑)/u.test(normalized)) {
    return `我昨晚追到停不下來；你飛久都怎麼撐過時差？`;
  }
  if (/(?:作息|時差|長班|上班|飛久|飛回來)/u.test(normalized)) {
    return "飛回來還在抗戰時差，妳都怎麼拉回來？";
  }
  if (/(?:賴床|開機|睡醒|醒了)/u.test(normalized)) {
    return "那我先陪妳用低速模式聊，等妳慢慢開機。";
  }
  return "剛剛這個點我有接到，妳比較想先聊哪一段？";
}

function repairPreservedHintCritiqueCard(
  card: DebriefCard,
  appliedHintTurns: AppliedHintTurn[],
  turns?: PracticeTurn[],
): DebriefCard {
  const latestHint = appliedHintTurns.reduce((latest, hint) =>
    hint.turnIndex >= latest.turnIndex ? hint : latest
  );
  const afterText = assistantTextNearHint(turns, latestHint.turnIndex, "after");
  const afterQuote = compactDebriefQuote(afterText);
  if (!afterQuote) return card;
  const beforeQuote = compactDebriefQuote(
    assistantTextNearHint(turns, latestHint.turnIndex, "before"),
  );
  const anchor = afterQuote || beforeQuote || "這個話題";
  const topic = preservedHintTopicLabel(`${afterText}\n${beforeQuote}`);
  const setup = beforeQuote || anchor;

  const summary = guardVisibleText(
    afterQuote
      ? `你有照提示做，她也願意延續${topic}。`
      : "你有照提示做，這輪先保留低壓節奏。",
  );
  const strengths = [
    guardVisibleText(`你先接住${topic}，沒有急著推進。`),
  ];
  const watchouts = [
    guardVisibleText(`下一步別只追問，多補一點你對${topic}的生活感。`),
  ];
  const suggestedLine = guardVisibleText(
    preservedHintRepairNextLine(anchor, afterText),
  );
  const dateChanceReason = guardVisibleText(
    afterQuote ? `她願意延續${topic}和你來回。` : "她願意延續話題和你來回。",
  );
  const nextInviteMove = guardVisibleText(
    `先接${topic}，再補一點你的生活畫面。`,
  );
  const gameBreakdown = card.gameBreakdown
    ? {
      ...card.gameBreakdown,
      phaseReached: guardVisibleText(`熟悉進度仍在延續${topic}。`),
      missedVariable: guardVisibleText(
        `下一步缺的是你對${topic}的生活畫面。`,
      ),
      failureState: guardVisibleText(
        `她仍停在低壓延續${topic}的節奏。`,
      ),
      nextFirstLine: suggestedLine,
      inviteDirection: guardVisibleText(
        `先補你對${topic}的生活畫面，保留低壓節奏。`,
      ),
    }
    : null;
  return {
    ...card,
    summary,
    strengths,
    watchouts,
    suggestedLine,
    dateChanceReason,
    nextInviteMove,
    gameBreakdown,
  };
}

function unansweredQuestionRepairLine(turns?: PracticeTurn[]): string | null {
  const latest = latestAssistantText(turns);
  const normalized = normalizedPracticeText(latest);
  if (!normalized) return null;
  if (
    /(?:追哪一部|哪一部|追什麼劇|什麼劇|有推薦|推薦嗎|片單)/u.test(normalized)
  ) {
    return "我先不爆雷，妳片單想補輕鬆還是燒腦的？";
  }
  if (/(?:哪區|哪一區|哪家|哪間|店名|咖啡店|口袋名單)/u.test(normalized)) {
    return "我先不亂猜店名，妳口袋名單通常看哪區？";
  }
  if (/(?:哪裡|哪邊|地點|地址|路名|哪條路|哪一帶)/u.test(normalized)) {
    return "我先不亂猜地點，妳說的是哪一帶？";
  }
  return null;
}

function isGroundedInLatestAssistant(
  value: string,
  turns?: PracticeTurn[],
): boolean {
  try {
    assertPracticeTextGroundedInTurns({
      visibleText: value,
      turns,
      latestOnly: true,
      errorCode: "debrief_quality_invalid_suggested_line_not_grounded",
    });
    return true;
  } catch (error) {
    if (
      error instanceof Error &&
      error.message === "debrief_quality_invalid_suggested_line_not_grounded"
    ) {
      return false;
    }
    throw error;
  }
}

function repairUngroundedUnansweredQuestionLine(
  card: DebriefCard,
  turns?: PracticeTurn[],
): DebriefCard {
  const repairLine = unansweredQuestionRepairLine(turns);
  if (!repairLine) return card;
  const shouldRepairSuggested = !isGroundedInLatestAssistant(
    card.suggestedLine,
    turns,
  );
  const shouldRepairGameLine = card.gameBreakdown !== null &&
    !isGroundedInLatestAssistant(card.gameBreakdown.nextFirstLine, turns);
  if (!shouldRepairSuggested && !shouldRepairGameLine) return card;

  const guardedLine = guardVisibleText(repairLine);
  return {
    ...card,
    suggestedLine: shouldRepairSuggested ? guardedLine : card.suggestedLine,
    gameBreakdown: card.gameBreakdown
      ? {
        ...card.gameBreakdown,
        nextFirstLine: shouldRepairGameLine
          ? guardedLine
          : card.gameBreakdown.nextFirstLine,
      }
      : null,
  };
}

/**
 * Hidden continuity contract. Debrief may revise a Hint only when it points to
 * an exact assistant reply that happened after that Hint was sent. The hidden
 * assessment is validated and then deliberately omitted from DebriefCard.
 */
function assertHintAssessment(opts: {
  value: unknown;
  card: DebriefCard;
  turns?: PracticeTurn[];
  appliedHintTurns: AppliedHintTurn[];
  skipVisibleConsistency?: boolean;
}): void {
  if (!opts.appliedHintTurns.every(hasCompleteHintDecision)) {
    throw new Error("debrief_hint_decision_missing");
  }
  if (
    typeof opts.value !== "object" || opts.value === null ||
    Array.isArray(opts.value)
  ) {
    throw new Error("debrief_hint_assessment_missing");
  }
  const assessment = opts.value as Record<string, unknown>;
  const keys = Object.keys(assessment).sort();
  if (
    keys.length !== 2 ||
    keys[0] !== "revisedEvidenceQuote" ||
    keys[1] !== "verdict"
  ) {
    throw new Error("debrief_hint_assessment_invalid");
  }
  const verdict = assessment.verdict;
  if (verdict !== "preserved" && verdict !== "revised") {
    throw new Error("debrief_hint_assessment_invalid");
  }
  const quote = assessment.revisedEvidenceQuote;
  const visibleText = debriefVisibleFields(opts.card).join("\n");
  const visiblyReversesHint =
    /(?:提示|建議)(?:(?:本身|內容|那句|其實|真的|確實|有點|完全|根本|實在|太|很|偏|是)){0,3}(?:錯|不對|不該|太急|偏保守|無效|不好|不合適|不適合|有問題|失準|誤判)/u
      .test(normalizedPracticeText(visibleText));
  const strategyContradictsHint = cardContradictsHintStrategy(
    opts.card,
    opts.appliedHintTurns,
  );
  if (
    opts.skipVisibleConsistency !== true &&
    (visiblyReversesHint || strategyContradictsHint) && verdict !== "revised"
  ) {
    throw new Error("debrief_hint_assessment_revision_required");
  }
  if (verdict === "preserved") {
    if (quote !== null) {
      // schema 升必填後模型偏好填「她的原句」而非 null（2026-07-23 eval）：
      // 引句逐字出自 ai turn＝無害佐證，hidden 欄位 server 會移除，照收；
      // 其餘非 null 引句仍屬 preserved 矛盾照殺。
      const quoteText = typeof quote === "string"
        ? normalizedPracticeText(toTraditionalChinese(quote))
        : "";
      const benignEvidence = quoteText.length > 0 &&
        (opts.turns ?? []).some((turn) =>
          turn.role === "ai" &&
          normalizedPracticeText(toTraditionalChinese(turn.text)).includes(
            quoteText,
          )
        );
      if (!benignEvidence) throw new Error("debrief_hint_assessment_invalid");
    }
    if (
      opts.skipVisibleConsistency !== true &&
      preservedCardCritiquesExactHint(
        opts.card,
        opts.appliedHintTurns,
        opts.turns,
      )
    ) {
      throw new Error("debrief_hint_assessment_revision_required");
    }
    return;
  }
  if (
    typeof quote !== "string" || quote.trim().length === 0 || quote.length > 120
  ) {
    throw new Error("debrief_hint_assessment_evidence_invalid");
  }
  const exactQuote = quote.trim();
  const latestHintTurnIndex = Math.max(
    ...opts.appliedHintTurns.map((hint) => hint.turnIndex),
  );
  const laterAssistantEvidence = (opts.turns ?? []).some((turn, index) =>
    index > latestHintTurnIndex && turn.role === "ai" &&
    turn.text.includes(exactQuote)
  );
  if (!laterAssistantEvidence) {
    throw new Error("debrief_hint_assessment_evidence_invalid");
  }
  if (
    !normalizedPracticeText(toTraditionalChinese(visibleText)).includes(
      normalizedPracticeText(toTraditionalChinese(exactQuote)),
    )
  ) {
    throw new Error("debrief_hint_assessment_evidence_not_visible");
  }
}

function assertGeneratedDebriefQuality(
  card: DebriefCard,
  opts: {
    turns?: PracticeTurn[];
    appliedHintTurns?: AppliedHintTurn[];
    sharedFactualEvidence?: string[];
    partnerFactualEvidence?: string[];
    trustedFactClaims?: HintFactClaim[];
    relaxSubjectiveQualityRubrics?: boolean;
  },
): void {
  const relaxSubjective = opts.relaxSubjectiveQualityRubrics === true;
  const visibleFields = debriefVisibleFields(card);
  for (const field of visibleFields) {
    rejectKnownCannedPracticeText(field, "debrief_canned_visible_text");
  }
  assertNoInventedPartnerInitiative(card, opts.turns);
  if (!relaxSubjective) {
    assertGeneratedDebriefFieldSubstance(card);
    rejectGenericPasteablePracticeText(
      card.suggestedLine,
      "debrief_quality_invalid_suggested_line",
    );
    if (card.gameBreakdown) {
      rejectGenericPasteablePracticeText(
        card.gameBreakdown.nextFirstLine,
        "debrief_quality_invalid_next_first_line",
      );
    }
  }
  const factContext = buildHintFactContext({
    turns: opts.turns,
    sharedFactualEvidence: opts.sharedFactualEvidence,
    partnerFactualEvidence: opts.partnerFactualEvidence,
    trustedFactClaims: opts.trustedFactClaims,
  });
  for (
    const pasteableText of [
      card.suggestedLine,
      ...(card.gameBreakdown ? [card.gameBreakdown.nextFirstLine] : []),
    ]
  ) {
    assertHintFactClaimsSupported({
      text: pasteableText,
      field: "reply",
      context: factContext,
      errorCode: "debrief_quality_invalid_unsupported_detail",
    });
  }
  for (const analyticalText of debriefAnalyticalFields(card)) {
    assertHintFactClaimsSupported({
      text: analyticalText,
      field: "coaching",
      context: factContext,
      errorCode: "debrief_quality_invalid_unsupported_detail",
    });
  }
  const metaPasteablePattern =
    /(?:先接住(?:她|對方)|補(?:上|一點)?感受|低壓邀約|邀約窗口|分享(?:你的|自己的)版本|再聽(?:她|對方)的|(?:可以|不妨|試著|記得)(?:先)?(?:說|回|傳|問)(?:她)?[：:]|下次(?:可以|試著|記得)(?:先)?(?:說|問|回))/u;
  if (
    metaPasteablePattern.test(card.suggestedLine) ||
    (card.gameBreakdown &&
      metaPasteablePattern.test(card.gameBreakdown.nextFirstLine))
  ) {
    throw new Error("debrief_quality_invalid_meta_line");
  }

  const appliedHints = opts.appliedHintTurns ?? [];
  const suggestion = normalizedPracticeText(
    toTraditionalChinese(card.suggestedLine),
  );
  for (const hint of appliedHints) {
    if (
      suggestion === normalizedPracticeText(
          toTraditionalChinese(hint.originalHintText),
        ) ||
      suggestion === normalizedPracticeText(
          toTraditionalChinese(hint.sentText),
        )
    ) {
      throw new Error("debrief_quality_invalid_repeated_hint");
    }
  }
  if (!relaxSubjective && appliedHints.some((hint) => hint.exact)) {
    const accountability = `${card.summary}\n${card.strengths.join("\n")}`;
    if (
      !/(?:有|已)(?:照|採用|使用)提示|照著提示|提示那句/u.test(accountability)
    ) {
      throw new Error("debrief_quality_invalid_hint_accountability");
    }
  }

  if (!relaxSubjective) {
    assertGeneratedDebriefFieldRoles(card);
  }

  // 貼句欄是「下次可傳的第一句」，不必逐字複讀最新句；引用整場任何具體
  // 細節都算有憑有據（latestOnly 舊制 2026-07-23 判定表 8/11 誤殺）。
  assertPracticeTextGroundedInTurns({
    visibleText: card.suggestedLine,
    turns: opts.turns,
    errorCode: "debrief_quality_invalid_suggested_line_not_grounded",
  });
  // 分析欄位（summary/strengths/watchouts…）是後設評語（投入度/單向/缺自
  // 揭），詞面 n-gram 接地檢查天生不適用（判定表 20/20 全誤殺）——捏造防線
  // 由 fact ledger（assertHintFactClaimsSupported）與罐頭簽名檢查負責，
  // 這裡不再做詞面 grounding。gameBreakdown 同理只查可貼的 nextFirstLine。
  if (card.gameBreakdown) {
    assertPracticeTextGroundedInTurns({
      visibleText: card.gameBreakdown.nextFirstLine,
      turns: opts.turns,
      errorCode: "debrief_quality_invalid_game_breakdown_not_grounded",
    });
  }
}

function extractJsonObject(raw: string): string {
  const fenced = raw
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  const start = fenced.indexOf("{");
  const end = fenced.lastIndexOf("}");
  if (start >= 0 && end > start) {
    return fenced.slice(start, end + 1).trim();
  }
  return fenced;
}

export function parseDebriefCard(
  raw: string,
  opts: {
    allowGameBreakdown?: boolean;
    requireCompleteCard?: boolean;
    turns?: PracticeTurn[];
    appliedHintTurns?: AppliedHintTurn[];
    sharedFactualEvidence?: string[];
    partnerFactualEvidence?: string[];
    trustedFactClaims?: HintFactClaim[];
    enforceGeneratedQuality?: boolean;
    repairPreservedHintCritique?: boolean;
    /**
     * 單發管線 profile（2026-07-23 eval 第 1 輪校正）：放行 reviewer 時代主觀
     * rubric（substance／role／partner_initiative／hint_accountability／
     * generic-pasteable）；canned、事實接地（unsupported_detail＋grounding）、
     * 守門詞表、breakdown 完整性一律照擋。
     */
    relaxSubjectiveQualityRubrics?: boolean;
  } = {},
): DebriefCard {
  const cleaned = extractJsonObject(raw);
  let parsed: unknown;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    // 同 hint parseObject：截斷/壞 JSON 收斂成機器碼供 telemetry 分類。
    throw new Error("debrief_json_parse_failed");
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("debrief_not_object");
  }
  const p = parsed as Record<string, unknown>;
  // 拍平形態 repair 必須在 parseGameBreakdown 之前；只救序列化形態，
  // 之後所有 gate（missing_fields／grounding／詞面）照原路走。
  if (opts.allowGameBreakdown === true) {
    repairFlattenedGameBreakdown(p);
  }
  const enforceGeneratedQuality = opts.enforceGeneratedQuality === true;
  const summary = guardVisibleText(
    generatedVisibleString(
      p.summary,
      60,
      GENERATED_DEBRIEF_PROSE_MAX_LENGTH,
      enforceGeneratedQuality,
    ),
  );
  const suggestedLine = guardVisibleText(
    generatedVisibleString(
      p.suggestedLine,
      60,
      GENERATED_DEBRIEF_PROSE_MAX_LENGTH,
      enforceGeneratedQuality,
    ),
  );
  if (summary.length === 0 || suggestedLine.length === 0) {
    throw new Error("debrief_missing_fields");
  }
  const strengths = generatedVisibleList(
    p.strengths,
    2,
    40,
    GENERATED_DEBRIEF_LIST_ITEM_MAX_LENGTH,
    enforceGeneratedQuality,
  ).map((item) => guardVisibleText(item));
  const watchouts = generatedVisibleList(
    p.watchouts,
    2,
    40,
    GENERATED_DEBRIEF_LIST_ITEM_MAX_LENGTH,
    enforceGeneratedQuality,
  ).map((item) => guardVisibleText(item));
  const vibeRaw = clampStr(p.vibe, 4);
  const vibe = VIBES.includes(vibeRaw) ? vibeRaw : "中性";

  // 約出來機會：合法值直接採用；非法/缺值時，有理由文字才 fallback medium，否則 low
  // （沒理由還說 medium 會誤導，往保守方向）。向後相容：舊卡缺這些欄位 → low + 空字串。
  const dateChanceRaw = clampStr(p.dateChance, 8).toLowerCase();
  const dateChanceReason = guardVisibleText(
    generatedVisibleString(
      p.dateChanceReason,
      60,
      GENERATED_DEBRIEF_PROSE_MAX_LENGTH,
      enforceGeneratedQuality,
    ),
  );
  const nextInviteMove = guardVisibleText(
    generatedVisibleString(
      p.nextInviteMove,
      60,
      GENERATED_DEBRIEF_PROSE_MAX_LENGTH,
      enforceGeneratedQuality,
    ),
  );
  const dateChance = DATE_CHANCES.includes(dateChanceRaw)
    ? dateChanceRaw
    : (dateChanceReason.length > 0 ? "medium" : "low");

  // Handler 的正式生成路徑採完整契約；寬鬆模式只留給舊快照/純 parser 相容。
  // 缺欄位交給第二次修復型生成，避免 UI 把殘缺卡誤認為模型成功。
  if (opts.requireCompleteCard === true) {
    if (
      strengths.length === 0 || watchouts.length === 0 ||
      dateChanceReason.length === 0 || nextInviteMove.length === 0
    ) {
      throw new Error("debrief_missing_fields");
    }
    if (!VIBES.includes(vibeRaw)) {
      throw new Error("debrief_invalid_vibe");
    }
    if (!DATE_CHANCES.includes(dateChanceRaw)) {
      throw new Error("debrief_invalid_date_chance");
    }
  }

  let card: DebriefCard = {
    summary,
    strengths,
    watchouts,
    suggestedLine,
    vibe,
    dateChance,
    dateChanceReason,
    nextInviteMove,
    // handler 僅在 Game mode 傳 true；Game 卡少任何拆盤欄位都視為格式失敗，
    // 交由既有 retry/fallback 路徑處理，避免殘缺拆盤被當成成功。
    gameBreakdown: opts.allowGameBreakdown === true
      ? parseGameBreakdown(p.gameBreakdown, enforceGeneratedQuality)
      : null,
  };
  const appliedHintTurns = opts.appliedHintTurns ?? [];
  const hiddenHintAssessment = appliedHintTurns.length > 0 &&
      opts.repairPreservedHintCritique === true &&
      (typeof p.hintAssessment !== "object" || p.hintAssessment === null ||
        Array.isArray(p.hintAssessment))
    ? { verdict: "preserved", revisedEvidenceQuote: null }
    : p.hintAssessment;
  if (
    appliedHintTurns.length > 0 &&
    opts.repairPreservedHintCritique === true &&
    isPreservedHiddenHintAssessment(hiddenHintAssessment) &&
    (cardVisiblyReversesPreservedHint(card) ||
      preservedCardCritiquesExactHint(card, appliedHintTurns, opts.turns) ||
      (appliedHintTurns.every(hasCompleteHintDecision) &&
        cardContradictsHintStrategy(card, appliedHintTurns)))
  ) {
    card = repairPreservedHintCritiqueCard(
      card,
      appliedHintTurns,
      opts.turns,
    );
  }
  if (appliedHintTurns.length > 0) {
    assertHintAssessment({
      value: hiddenHintAssessment,
      card,
      turns: opts.turns,
      appliedHintTurns,
      skipVisibleConsistency: false,
    });
  }
  if (opts.enforceGeneratedQuality === true) {
    card = repairUngroundedUnansweredQuestionLine(card, opts.turns);
    assertGeneratedDebriefQuality(card, opts);
  }
  return card;
}

/** Strictly extracts the provider object for the semantic review hand-off. */
export function parseDebriefCandidateObject(
  raw: string,
): Record<string, unknown> {
  const parsed = JSON.parse(extractJsonObject(raw));
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("debrief_not_object");
  }
  return parsed as Record<string, unknown>;
}
