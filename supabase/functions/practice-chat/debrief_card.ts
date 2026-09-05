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
  isSalvageableFailureCode,
  normalizedPracticeText,
  rejectGameBreakdownFieldEcho,
  rejectGenericPasteablePracticeText,
  rejectKnownCannedPracticeText,
} from "./practice_visible_quality.ts";
import {
  type PracticeInviteLevel,
  practiceInviteLevelFor,
} from "./practice_invite.ts";
import { toTraditionalChinese } from "../_shared/traditional_chinese.ts";
import { scrubRawImageFilenames } from "./prompt_sanitizer.ts";
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
 * gameBreakdown（Game 模式必填）在 schema 層做選填，缺欄由 parser 判敗；
 * hintAssessment 已退役，僅為相容而保留 optional 定義。
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
      description: "已棄用：server 會直接忽略並移除此欄位，可不填",
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

/** WP3 續聊敘事記憶：`memory_summary` 欄位的資料庫上限（migration 的 CHECK）。 */
export const DEBRIEF_MEMORY_SUMMARY_MAX_CHARS = 1000;

/**
 * WP3：旗標 on 時才掛上去的選填欄位。schema 是 `additionalProperties: false`，
 * 所以旗標關著時模型連這個欄位都看不到（多吐就是違規），開著時它是選填——
 * 缺欄不得讓檢討失敗（parser 端的契約見 `parseDebriefMemorySummary`）。
 */
const MEMORY_SUMMARY_SCHEMA_PROPERTY: Readonly<Record<string, unknown>> = {
  type: "string",
  description:
    "（選填）以第三人稱寫「她記得的事」，供下一場續聊：聊過的話題、他透露的事、她對他的印象、未完的約定。只寫這場真的發生過的事，不得捏造。",
  maxLength: DEBRIEF_MEMORY_SUMMARY_MAX_CHARS,
};

/**
 * hintAssessment 已退役（2026-08-06）：不再必填、server 忽略。schema 保留
 * optional 欄位定義純粹是相容性——舊習慣的模型照填也不會撞
 * additionalProperties: false。
 */
export function debriefToolSchemaFor(
  opts: { game: boolean; memorySummary?: boolean },
): Record<string, unknown> {
  const base =
    (opts.game ? DEBRIEF_TOOL_SCHEMA_GAME : DEBRIEF_TOOL_SCHEMA) as Record<
      string,
      unknown
    >;
  // 旗標 off（省略／false）＝逐位元組回傳既有常數。
  if (opts.memorySummary !== true) return base;
  return {
    ...base,
    properties: {
      ...(base.properties as Record<string, unknown>),
      memorySummary: MEMORY_SUMMARY_SCHEMA_PROPERTY,
    },
  };
}

export type DebriefMemorySummarySkipReason =
  | "missing"
  | "not_string"
  | "too_long";

/**
 * WP3：從檢討的原始輸出撈出選填的 `memorySummary`。
 *
 * **這支永遠不丟例外**——它跑在 `parseDebriefCard` 成功之後，任何形態問題都只
 * 能是「跳過寫入」，不能把一張已經合格的教學卡打回。超長刻意不截斷：截半句的
 * 記憶餵回下一場比沒有記憶更糟，寧可這一場不留。
 */
export function parseDebriefMemorySummary(
  raw: string,
): { summary: string; skipped: null } | {
  summary: null;
  skipped: DebriefMemorySummarySkipReason;
} {
  let value: unknown;
  try {
    const parsed = JSON.parse(extractJsonObject(raw));
    if (typeof parsed !== "object" || parsed === null) {
      return { summary: null, skipped: "missing" };
    }
    value = (parsed as Record<string, unknown>).memorySummary;
  } catch {
    return { summary: null, skipped: "missing" };
  }
  if (value === undefined || value === null) {
    return { summary: null, skipped: "missing" };
  }
  if (typeof value !== "string") {
    return { summary: null, skipped: "not_string" };
  }
  // 與 `relationship_thread.ts` 的 `str()` 同一套正規化：檔名不得外洩進下一場
  // 的 prompt，空白壓成單一空格。
  const normalized = toTraditionalChinese(
    scrubRawImageFilenames(value).trim().replace(/\s+/gu, " "),
  );
  if (normalized.length === 0) return { summary: null, skipped: "missing" };
  if (normalized.length > DEBRIEF_MEMORY_SUMMARY_MAX_CHARS) {
    return { summary: null, skipped: "too_long" };
  }
  return { summary: normalized, skipped: null };
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

/**
 * salvage 時超長改成切到上限而不是丟整張卡。用 module-scope 旗標而不是把參數
 * 穿過 11 個呼叫點：parseDebriefCard 全程同步、沒有 await，JS 單執行緒下不可能
 * 有第二個 parse 交錯進來。進出一律成對（try/finally）。
 */
let degradeOverlongDuringParse = false;

function generatedVisibleString(
  value: unknown,
  legacyMax: number,
  generatedMax: number,
  enforceGeneratedQuality: boolean,
): string {
  if (typeof value !== "string") return "";
  const trimmed = toTraditionalChinese(value.trim());
  if (
    enforceGeneratedQuality && trimmed.length > generatedMax &&
    !degradeOverlongDuringParse
  ) {
    throw new Error("debrief_quality_invalid_overlong");
  }
  return enforceGeneratedQuality
    ? trimmed.slice(0, generatedMax)
    : trimmed.slice(0, legacyMax);
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

/**
 * 第二刀（2026-08-24）守門情境。沿用 degradeOverlongDuringParse 的
 * module-scope 旗標模式：parse 全程同步、單執行緒，try/finally 成對進出。
 */
let guardSpicyAllowed = false;
let guardTranscript = "";

function rejectInternalLabelLeak(value: string) {
  rejectVisibleInternalLabelLeak(value, "debrief_internal_label_leak", {
    transcript: guardTranscript,
  });
}

/**
 * strict＝照唸句欄（suggestedLine/nextFirstLine）：同意權類永遠攔、尺度類
 * 按熱度；analysis＝點評欄：尺度類只攔教唆形（案例表 B 組）。
 */
function guardVisibleText(
  value: string,
  fieldClass: "strict" | "analysis" = "strict",
): string {
  rejectInternalLabelLeak(value);
  // 批3 P1：debrief prompt 注入 band 詞後，模型可能把溫度內部詞或 1.2 原詞
  // 抄進可見欄位；被拒→handler 重試→band-aware fallback 卡兜底。
  rejectVisibleTemperatureMechanismLeak(value, "debrief_temperature_leak");
  rejectL4UnsafeVisibleText(value, "debrief_l4_unsafe", {
    fieldClass,
    spicyAllowed: guardSpicyAllowed,
  });
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
  degradeStructuralDefects: boolean,
  turns: PracticeTurn[] | undefined,
): GameBreakdown | null {
  // 模型有時把 null 寫成字串 "null"（2026-08-06 撈 ai_logs 實例）。那是序列化
  // 瑕疵不是內容瑕疵，跟真的 null 一樣處理。
  const normalized = typeof value === "string" &&
      ["null", "none", ""].includes(value.trim().toLowerCase())
    ? null
    : value;
  if (
    typeof normalized !== "object" || normalized === null ||
    Array.isArray(normalized)
  ) {
    // salvage 降級：拆盤是**可選**區塊，丟掉它比丟掉整張使用者看得到的卡好。
    if (degradeStructuralDefects) return null;
    throw new Error("debrief_game_breakdown_missing_fields");
  }
  const value_ = normalized;
  const p = value_ as Record<string, unknown>;
  const gameBreakdown = {
    phaseReached: guardVisibleText(
      generatedVisibleString(
        p.phaseReached,
        60,
        GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        enforceGeneratedQuality,
      ),
      "analysis",
    ),
    missedVariable: guardVisibleText(
      generatedVisibleString(
        p.missedVariable,
        60,
        GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        enforceGeneratedQuality,
      ),
      "analysis",
    ),
    failureState: guardVisibleText(
      generatedVisibleString(
        p.failureState,
        60,
        GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        enforceGeneratedQuality,
      ),
      "analysis",
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
    if (degradeStructuralDefects) return null;
    throw new Error("debrief_game_breakdown_missing_fields");
  }
  if (enforceGeneratedQuality) {
    try {
      rejectGameBreakdownFieldEcho(
        gameBreakdown,
        turns,
        "debrief_game_breakdown_field_echo",
      );
    } catch (error) {
      // 拆盤是可選區塊：salvage 端丟掉這塊比丟掉整張使用者看得到的卡好
      // （同一套降級路徑，見上面「缺欄位」分支）；前兩發仍照擋逼重生成。
      if (degradeStructuralDefects) return null;
      throw error;
    }
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

// ── Hint 路線一致性（finding-only）────────────────────────────────
// hintAssessment 記帳契約退役後，server-authoritative 路線（build 不升約、
// soft 不升 direct、repair 不邊修邊約）不再有否決權，但矛盾仍要看得見：
// 降為 finding 記進 telemetry（Codex 2026-08-06 審查：prompt 有規則、
// 守門全刪＝觀測盲區）。
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
    /(?:沒有|沒)(?:做|給|丟|推)?(?:出)?(?:直接|明確)?邀約.{0,10}(?:失誤|錯|問題|可惜)|(?:太被動|偏保守|早該).{0,12}(?:直接)?(?:約|邀約)|(?:現在|這輪|下一句|下一步|接下來|應該|可以|建議|不妨|適合|立刻|趁現在).{0,12}(?:直接|明確)?(?:約她|邀她|約對方|邀對方|問她(?:哪天|何時|什麼時候).{0,6}有空|把.{1,12}收成.{0,4}(?:見面|咖啡|邀約)|去(?:喝咖啡|吃飯|散步|看展|逛街))|(?<!升到)(?<!是否)(?<!考慮)(?<!評估)(?:直接|明確|立刻|趁現在)(?:約|邀約)(?![，,]?會(?!(?:(?![。！？!?]).)*(?:但|不過)(?:(?![。！？!?]).){0,10}(?:值得|該試|可以試|不妨))(?:(?![。！？!?]).){0,12}(?:只想|壓力|反感|嚇|唐突|冒進|扣分|反效果|翻車|界線|防備|距離感|保持距離|拉開距離|退|被拒|打槍|句點|不夠|不太|不舒服|不自在|太快|太急|太衝|踩|錯))|(?:約|邀約).{0,8}(?:時機|窗口)(?:已經)?成熟/u
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
  if (authoritative === "repair") return true;
  // round14 gd6：build 提示是「該輪先鋪墊」；她接住後 debrief 建議下一句
  // 走低壓軟邀約（改天…如何）是局勢推進的前瞻指引，不是翻案說提示錯。
  // build 下只有 direct（具體時間地點的硬邀約）才算與提示策略矛盾；
  // repair 局任何邀約照舊全擋。
  if (authoritative === "build") return actual === "direct";
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
  // 2026-07-24 Mabel FP：repair 提示被照做後，拆解卡的前瞻指引自然轉入
  // 鋪墊敘事（先別約、累積安全感）——與「修復」同向，是局勢推進不是翻案。
  // repair 局的 soft/direct 敘事與任何可貼邀約句（下方 invite level）照舊全擋。
  const narrativeContradicts = narrativeRoutes.some((route) => {
    if (route === authoritative) return false;
    if (authoritative === "repair" && route === "build") return false;
    return true;
  });
  if (narrativeContradicts) return true;

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

// 逐子句判定（Codex 四審 P2）：保留句 bail 只吃自己那個子句，
// 「下午可以再看看吧，我週六有空」後半的真空檔仍要收。
function partnerTurnContainsInviteEvidence(value: string): boolean {
  return value.split(/[，,。！？!?；;\n]+/u).some((clause) =>
    partnerClauseContainsInviteEvidence(clause)
  );
}

function partnerClauseContainsInviteEvidence(value: string): boolean {
  const compact = normalizedPracticeText(value);
  if (compact.length === 0) return false;
  // 硬拍板（約妳/說好了）最優先——「可以欸，那說好了」不受保留句 bail 影響。
  if (
    /(?:約|邀)[妳你]|(?:說好了|說定|一言為定|成交)/u.test(compact)
  ) {
    return true;
  }
  // 保留句（可以(的話/欸/喔/吧)…再看看/再說）＝deliberation 不是拍板，
  // 先於時間 pattern 與 classifier 判掉（Codex 三審 P2：語氣詞插入會讓
  // lookahead 失效、時間 pattern 先放行）。
  if (
    /(?:可以|行|沒問題)(?:的話)?(?:欸|喔|啊|吧)?再(?:看|想|說|喬|確認|討論)/u
      .test(compact)
  ) {
    return false;
  }
  return /要不要.{0,8}一起|(?:跟|和)[妳你].{0,10}(?:見面|碰面|喝咖啡|吃飯|散步|看展|逛街)/u
    .test(compact) ||
    // 她自報空檔（我這週六下午剛好有空）＝主動釋出時間窗口
    // （2026-07-23 gd1 eval：卡片寫「她釋出時間窗口」被誤殺）。
    /我.{0,10}(?:有空|沒事|有時間|都可以|沒排)/u.test(compact) ||
    // 可以後接「再看/先休息」等後續動作＝保留不是拍板（Codex 首審 P2-4）。
    /(?:週[一二三四五六日末]|星期[一二三四五六日天]|禮拜[一二三四五六日天]|明天|後天|下午|晚上|早上)[^，,。！？!?；;]{0,4}(?:可以|沒問題|ok|行)(?!再|先|睡|休|等|忙|慢|考慮|想|看)/iu
      .test(compact) ||
    practiceInviteLevelFor(value) !== "none";
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
  // 「才能/才會…見面」＝門檻條件段：她還沒邀約，是在講需要什麼條件才會
  // 考慮（「她需要更多安定感才能考慮見面」，2026-07-24 Mabel FP）。只剔除
  // 該段本身，其餘內容照跑真宣稱偵測——門檻敘事＋既成邀約宣稱的混合句
  // （「…才願意見面而昨天已主動約你」）不得被整句吞掉（Codex R2）。
  const withoutThreshold = compact.replace(
    /(?:才能|才會|才可能|才願意).{0,10}?(?:見面|碰面|邀約|約|邀)/gu,
    "",
  );
  // 動詞與邀約詞之間隔著「窗口/機會/時機」＝機會描述或教練指令句（如「順著她給的窗口直接邀約」），非「她邀約過」宣稱
  return /(?:她|對方).{0,28}(?:主動(?:提(?:了|出)?|說|問|給|丟|發出)?|(?:提(?:了|出)?|說想|說要|問|給|丟|發出|表示想|想|(?<!需)要|願意))(?:(?!窗口|機會|時機|的).){0,12}(?:見面|碰面|邀約|約你|邀你)/u
    .test(withoutThreshold) ||
    // 「邀約窗口/機會/時機」是機會描述不是「她發出過邀約」的宣稱，不觸發本 gate
    /(?:她|對方)的.{0,10}(?:邀約(?!窗口|機會|時機)|見面提議|約見)/u.test(
      withoutThreshold,
    );
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

/**
 * 守門嚴重度分級（2026-08-06 Eric 拍板，root-cause 修）：
 *
 * - 紅線（罐頭句在這裡；露骨／內部洩漏／溫度洩漏在 guardVisibleText）＝
 *   否決權，任何一發踩到都打回。名單與 salvage 黑名單
 *   （NEVER_SALVAGEABLE_FAILURE_CODE_PARTS）同一套，刻意講得完。
 * - 其餘全是「偏好門」：ai_logs 21 天實證它們殺掉的候選卡內容都是好的
 *   （短對話下 grounding 結構性不可能過、hint 記帳欄瑕疵陪葬整張好卡），
 *   而被殺後端出的 salvage/修補模板卡品質遠低於被丟棄的模型卡。偏好門
 *   一律降級成 telemetry finding：卡照端出去，違規碼記進 onQualityFinding
 *   給 handler 觀測（finding 率長期偏高＝該回頭修 prompt 或門本身）。
 *
 * Game 拆盤字面複製同一句籠統話的檢查在 parseGameBreakdown 內做（跟缺欄位
 * 同一套 degrade/throw 階梯）——那是模型空轉的結構性瑕疵，重生成有救，
 * 維持前兩發照擋。
 */
function assertGeneratedDebriefQuality(
  card: DebriefCard,
  opts: {
    turns?: PracticeTurn[];
    appliedHintTurns?: AppliedHintTurn[];
    sharedFactualEvidence?: string[];
    partnerFactualEvidence?: string[];
    trustedFactClaims?: HintFactClaim[];
    salvagePass?: boolean;
    onQualityFinding?: (code: string) => void;
  },
): void {
  const visibleFields = debriefVisibleFields(card);
  for (const field of visibleFields) {
    rejectKnownCannedPracticeText(field, "debrief_canned_visible_text");
  }
  // salvage pass 只查紅線：候選先前已在正式發收過一次 finding，不重複記。
  if (opts.salvagePass === true) return;

  // 偏好門：丟出的錯誤碼原樣轉成 finding，不否決。
  const soft = (gate: () => void) => {
    try {
      gate();
    } catch (error) {
      opts.onQualityFinding?.(
        error instanceof Error && error.message
          ? error.message
          : "debrief_quality_finding_unknown",
      );
    }
  };

  soft(() => assertNoInventedPartnerInitiative(card, opts.turns));
  soft(() => assertGeneratedDebriefFieldSubstance(card));
  soft(() =>
    rejectGenericPasteablePracticeText(
      card.suggestedLine,
      "debrief_quality_invalid_suggested_line",
    )
  );
  if (card.gameBreakdown) {
    const nextFirstLine = card.gameBreakdown.nextFirstLine;
    soft(() =>
      rejectGenericPasteablePracticeText(
        nextFirstLine,
        "debrief_quality_invalid_next_first_line",
      )
    );
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
    soft(() =>
      assertHintFactClaimsSupported({
        text: pasteableText,
        field: "reply",
        context: factContext,
        errorCode: "debrief_quality_invalid_unsupported_detail",
      })
    );
  }
  for (const analyticalText of debriefAnalyticalFields(card)) {
    soft(() =>
      assertHintFactClaimsSupported({
        text: analyticalText,
        field: "coaching",
        context: factContext,
        errorCode: "debrief_quality_invalid_unsupported_detail",
      })
    );
  }
  const metaPasteablePattern =
    /(?:先接住(?:她|對方)|補(?:上|一點)?感受|低壓邀約|邀約窗口|分享(?:你的|自己的)版本|再聽(?:她|對方)的|(?:可以|不妨|試著|記得)(?:先)?(?:說|回|傳|問)(?:她)?[：:]|下次(?:可以|試著|記得)(?:先)?(?:說|問|回))/u;
  if (
    metaPasteablePattern.test(card.suggestedLine) ||
    (card.gameBreakdown &&
      metaPasteablePattern.test(card.gameBreakdown.nextFirstLine))
  ) {
    opts.onQualityFinding?.("debrief_quality_invalid_meta_line");
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
      opts.onQualityFinding?.("debrief_quality_invalid_repeated_hint");
      break;
    }
  }
  if (appliedHints.some((hint) => hint.exact)) {
    const accountability = `${card.summary}\n${card.strengths.join("\n")}`;
    if (
      !/(?:有|已)(?:照|採用|使用)提示|照著提示|提示那句/u.test(accountability)
    ) {
      opts.onQualityFinding?.("debrief_quality_invalid_hint_accountability");
    }
  }
  // Hint 路線一致性（finding-only）：卡的策略敘事/可貼句與 server decision
  // 的路線矛盾（如 repair 局建議直接約）要看得見，但不否決。
  if (
    appliedHints.length > 0 &&
    appliedHints.every(hasCompleteHintDecision) &&
    cardContradictsHintStrategy(card, appliedHints)
  ) {
    opts.onQualityFinding?.("debrief_quality_hint_strategy_contradiction");
  }

  soft(() => assertGeneratedDebriefFieldRoles(card));

  // 貼句欄是「下次可傳的第一句」，不必逐字複讀最新句；引用整場任何具體
  // 細節都算有憑有據（latestOnly 舊制 2026-07-23 判定表 8/11 誤殺）。
  // 短對話（如「嗨」開局）下好建議必然引入逐字稿外的新內容，這道門結構性
  // 不可能過——正是它連殺兩發把使用者推進 salvage（2026-08-05 三連 503），
  // 故降為 finding。分析欄位（summary/strengths…）是後設評語，n-gram 接地
  // 天生不適用（判定表 20/20 全誤殺），連 finding 都不記。
  soft(() =>
    assertPracticeTextGroundedInTurns({
      visibleText: card.suggestedLine,
      turns: opts.turns,
      errorCode: "debrief_quality_invalid_suggested_line_not_grounded",
    })
  );
  if (card.gameBreakdown) {
    const nextFirstLine = card.gameBreakdown.nextFirstLine;
    soft(() =>
      assertPracticeTextGroundedInTurns({
        visibleText: nextFirstLine,
        turns: opts.turns,
        errorCode: "debrief_quality_invalid_game_breakdown_not_grounded",
      })
    );
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
    /**
     * 偏好門（grounding／主觀 rubric／fact ledger／hint 重複…）不再否決，
     * 違規碼經這裡回報給呼叫端做 telemetry（見 assertGeneratedDebriefQuality）。
     */
    onQualityFinding?: (code: string) => void;
    /**
     * 只有 salvage pass 可以開。乙類（結構／格式）缺陷改成修補或降級：超長切到
     * 上限、vibe/dateChance 落安全預設、Game 拆盤這個**可選**區塊殘缺就丟掉那
     * 一塊而不是丟整張卡（2026-08-06 W3）。
     *
     * 前兩發刻意不開：留給 retry 產出完整卡的機會。
     */
    degradeStructuralDefects?: boolean;
    /**
     * salvage pass 的總開關（2026-08-06 Eric 拍板把白名單翻成黑名單）。開了就
     * 等於宣告「不端出去使用者就拿到 503」，此時紅線（露骨／內部洩漏／溫度
     * 洩漏／罐頭）以外的 gate 一律讓路，包含捏造事實。前兩發完全不受影響。
     */
    salvagePass?: boolean;
    /**
     * 第二刀 B6：建議句欄的尺度類熱度門。呼叫端用本場 FSM 的
     * spicyLevel === "L3" 計算；省略＝低熱（現行行為）。
     */
    spicyAllowed?: boolean;
  } = {},
): DebriefCard {
  if (opts.salvagePass === true) {
    degradeOverlongDuringParse = true;
  }
  guardSpicyAllowed = opts.spicyAllowed === true;
  // 第二刀 A 組原話豁免：代號詞出現在本局對話原文就可引用。
  guardTranscript = (opts.turns ?? []).map((turn) => turn.text).join("\n");
  try {
    return parseDebriefCardInner(raw, opts);
  } finally {
    degradeOverlongDuringParse = false;
    guardSpicyAllowed = false;
    guardTranscript = "";
  }
}

function parseDebriefCardInner(
  raw: string,
  opts: Parameters<typeof parseDebriefCard>[1] & object,
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
    "analysis",
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
  ).map((item) => guardVisibleText(item, "analysis"));
  const watchouts = generatedVisibleList(
    p.watchouts,
    2,
    40,
    GENERATED_DEBRIEF_LIST_ITEM_MAX_LENGTH,
    enforceGeneratedQuality,
  ).map((item) => guardVisibleText(item, "analysis"));
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
    "analysis",
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
  // 核心欄位缺席不在降級範圍（W3 乙類），salvage 也照擋——殘缺卡寧可換下一張
  // 候選或 503，也不端出空區塊（Codex 2026-08-06 審查修補：舊碼 salvagePass
  // 會繞過這段，跟 W3 測試宣稱的保證矛盾）。
  if (opts.requireCompleteCard === true) {
    if (
      strengths.length === 0 || watchouts.length === 0 ||
      dateChanceReason.length === 0 || nextInviteMove.length === 0
    ) {
      throw new Error("debrief_missing_fields");
    }
    // salvage 降級：列舉外的 vibe/dateChance 上面已經算好安全預設值了，為了一個
    // 標籤把整張卡丟掉是純虧（2026-08-06 W3 乙類）。
    if (opts.degradeStructuralDefects !== true) {
      if (!VIBES.includes(vibeRaw)) {
        throw new Error("debrief_invalid_vibe");
      }
      if (!DATE_CHANCES.includes(dateChanceRaw)) {
        throw new Error("debrief_invalid_date_chance");
      }
    }
  }

  const card: DebriefCard = {
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
      ? parseGameBreakdown(
        p.gameBreakdown,
        enforceGeneratedQuality,
        opts.degradeStructuralDefects === true,
        opts.turns,
      )
      : null,
  };
  // hintAssessment 隱藏記帳契約已整條退役（2026-08-06 root-cause 修）：它是
  // 使用者永遠看不到的 meta 欄位，21 天 ai_logs 裡它的一致性檢查殺掉的都是
  // 可見內容正常的好卡，修補路徑（repairPreservedHintCritiqueCard）產出的
  // 模板空話卡品質更差。模型仍可能照舊填 p.hintAssessment，parser 直接忽略；
  // 提示問責改由 prompt 引導＋finding 觀測（hint_accountability）。
  if (opts.enforceGeneratedQuality === true) {
    assertGeneratedDebriefQuality(card, opts);
  }
  return card;
}

/**
 * Salvage pass：兩發（Sonnet→Haiku）都被打回時，從候選原文裡搶救一張可以
 * 端出的卡，而不是讓使用者拿到 503（2026-08-05 Eric 拍板的產品不變量：
 * hint/debrief × 新手/一般/Game 正常一定要有輸出）。
 *
 * 偏好門降級成 finding 後，會走到這裡的只剩結構性失敗（缺欄位／壞 JSON／
 * 拆盤殘缺）與紅線。紅線（黑名單）不可救；結構性缺陷降級（超長切上限、
 * vibe/dateChance 落安全預設、殘缺拆盤丟掉該可選區塊），救不起來才回
 * null（→ 503）。候選順序＝attemptFailures 順序（主模型在前）。
 */
export function salvageDebriefCandidate(opts: {
  failures: readonly { model: string; code?: string; raw?: string }[];
  parseOptions: Parameters<typeof parseDebriefCard>[1];
}): { card: DebriefCard; model: string } | null {
  for (const failure of opts.failures) {
    if (typeof failure.raw !== "string" || failure.raw.length === 0) continue;
    if (!isSalvageableFailureCode(failure.code)) continue;
    try {
      const card = parseDebriefCard(failure.raw, {
        ...opts.parseOptions,
        degradeStructuralDefects: true,
        salvagePass: true,
      });
      return { card, model: failure.model };
    } catch {
      continue; // 這張救不了（踩到紅線或格式壞掉），換下一張
    }
  }
  return null;
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
