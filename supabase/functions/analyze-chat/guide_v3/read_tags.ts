// 第一段（讀局面）的結構化輸出：欄位、json_schema 與逐欄檢查。模型只輸出標記，
// 要不要回、要不要約由 rules.ts 依標記決定（說明書 A4、C 段）。

export const LIGHTS = ["green", "yellow", "red"] as const;
export const HER_MOVES = [
  "生活",
  "情緒",
  "高點",
  "大笑收尾",
  "調侃",
  "試探",
  "認真問",
  "問他的事",
  "問他意見",
  "開窗",
  "煞車",
] as const;
/// v3 A4 的六種，加我們的預設「猶豫」（PR #97 留言第二部分）。
export const INVITE_READINESS = [
  "沒機會",
  "婉拒過",
  "含糊答應",
  "明確答應",
  "她自己提見面",
  "她取消了",
  "猶豫",
] as const;
export const WILLINGNESS = ["high", "medium", "low"] as const;

export interface ReadTags {
  readonly light: typeof LIGHTS[number];
  readonly herMove: typeof HER_MOVES[number];
  readonly herMoodBad: boolean;
  readonly drunkOrLateNight: boolean;
  readonly inviteReadiness: typeof INVITE_READINESS[number];
  readonly cancelHasAlternative: boolean;
  readonly retreating: boolean;
  readonly declinedOrBoundary: boolean;
  readonly explicitRejection: boolean;
  readonly blocked: boolean;
  readonly risk: boolean;
  /// 自傷訊號（Eric 10/16）：有就不出卡，改顯示固定的關心訊息、不扣額度。
  readonly selfHarmSignal: boolean;
  /// 她或他本人未滿 18 歲、或現在還在讀國中或高中（Eric 2026-10-18）：有就不出卡、
  /// 不扣額度，顯示固定說明（課程兩個例外之一）。
  readonly minorSignal: boolean;
  readonly needsHisFacts: boolean;
  readonly identityQuestion: boolean;
  readonly hisStatedFacts: readonly string[];
  readonly hasHisVoiceSample: boolean;
  readonly replyWillingness: typeof WILLINGNESS[number];
  readonly worthyBallCount: number;
  readonly herTurnsPerfunctory: readonly {
    readonly turn: number;
    readonly perfunctory: boolean;
  }[];
  readonly matchedEntries: readonly string[];
  readonly readForUser: string;
  readonly waitFor: string;
}

const BOOL_FIELDS = [
  "herMoodBad",
  "drunkOrLateNight",
  "cancelHasAlternative",
  "retreating",
  "declinedOrBoundary",
  "explicitRejection",
  "blocked",
  "risk",
  "selfHarmSignal",
  "minorSignal",
  "needsHisFacts",
  "identityQuestion",
  "hasHisVoiceSample",
] as const;

/// 第一段的結構化輸出（json_schema）。
export const READ_TAGS_SCHEMA: Record<string, unknown> = {
  type: "object",
  additionalProperties: false,
  required: [
    "light",
    "herMove",
    ...BOOL_FIELDS,
    "inviteReadiness",
    "hisStatedFacts",
    "replyWillingness",
    "worthyBallCount",
    "herTurnsPerfunctory",
    "matchedEntries",
    "readForUser",
    "waitFor",
  ],
  properties: {
    light: { type: "string", enum: [...LIGHTS] },
    herMove: { type: "string", enum: [...HER_MOVES] },
    ...Object.fromEntries(BOOL_FIELDS.map((f) => [f, { type: "boolean" }])),
    inviteReadiness: { type: "string", enum: [...INVITE_READINESS] },
    hisStatedFacts: { type: "array", items: { type: "string" } },
    replyWillingness: { type: "string", enum: [...WILLINGNESS] },
    worthyBallCount: { type: "integer" },
    herTurnsPerfunctory: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["turn", "perfunctory"],
        properties: {
          turn: { type: "integer" },
          perfunctory: { type: "boolean" },
        },
      },
    },
    matchedEntries: { type: "array", items: { type: "string" } },
    readForUser: { type: "string" },
    waitFor: { type: "string" },
  },
};

function isOneOf<T extends string>(
  value: unknown,
  options: readonly T[],
): value is T {
  return typeof value === "string" && (options as readonly string[]).includes(
    value,
  );
}

/// 兩段式實驗（開關 ANALYZE_GUIDE_V3_TWO_STAGE，Eric 2026-10-19 兩段式實驗）才多要的標記：
/// 只放排卡用得到的（情侶、撒嬌示愛、開心分享不排帶張力或多一張共鳴，值得接的句子分給各張卡）。
/// 開關沒開時 schema 與檢查都不碰這幾欄。
/// 「問他」是第 2 輪加的（Bruce 10/19 盲選理由）：每張卡都要先回她直接問他、要他看法的那句，
/// 第 1 輪讀局面把這種句子有時標情感、有時標其他，排卡找不出來。
export const WORTHY_LINE_KINDS = [
  "問他",
  "情感",
  "照片或貼圖",
  "其他",
] as const;
/// 甜話短回（開關 ANALYZE_GUIDE_V3_SWEET_SHORT；Codex 主審第 1 輪 P2）開時才多的一種：她這一則本身在對他撒嬌或示愛。「情感」
/// 也包含難過、生氣、痛（「腿好痛」），不能拿來認甜話，所以由讀局面逐則標。開關沒開時讀局面的提示詞、schema 與檢查都不認
/// 這一種（WORTHY_LINE_KINDS 不變）。
export const SWEET_LINE_KIND = "撒嬌";
export const WORTHY_LINE_KINDS_SWEET = [
  "問他",
  SWEET_LINE_KIND,
  "情感",
  "照片或貼圖",
  "其他",
] as const;
export type WorthyLineKind = typeof WORTHY_LINE_KINDS_SWEET[number];

export interface WorthyLine {
  /// 她最新這一輪的第幾則（1 起算，照讀局面對話稿上的編號）。
  readonly line: number;
  readonly label: string;
  readonly kind: WorthyLineKind;
}

export interface TwoStageTags {
  readonly establishedCouple: boolean;
  readonly herAffection: boolean;
  readonly herHappyShare: boolean;
  readonly worthyLines: readonly WorthyLine[];
}

const TWO_STAGE_BOOL_FIELDS = [
  "establishedCouple",
  "herAffection",
  "herHappyShare",
] as const;

/// 兩段式的讀局面 schema：今天的全部欄位，再加上面四欄（都必填）。
export const READ_TAGS_SCHEMA_TWO_STAGE: Record<string, unknown> = {
  ...READ_TAGS_SCHEMA,
  required: [
    ...(READ_TAGS_SCHEMA.required as readonly string[]),
    ...TWO_STAGE_BOOL_FIELDS,
    "worthyLines",
  ],
  properties: {
    ...(READ_TAGS_SCHEMA.properties as Record<string, unknown>),
    ...Object.fromEntries(
      TWO_STAGE_BOOL_FIELDS.map((f) => [f, { type: "boolean" }]),
    ),
    worthyLines: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["line", "label", "kind"],
        properties: {
          line: { type: "integer" },
          label: { type: "string" },
          kind: { type: "string", enum: [...WORTHY_LINE_KINDS] },
        },
      },
    },
  },
};

/// 甜話短回開時的兩段式 schema：只有 worthyLines 的 kind 多「撒嬌」，其他欄位與順序都跟 READ_TAGS_SCHEMA_TWO_STAGE 一樣。
export const READ_TAGS_SCHEMA_TWO_STAGE_SWEET: Record<string, unknown> =
  withWorthyKinds(READ_TAGS_SCHEMA_TWO_STAGE, WORTHY_LINE_KINDS_SWEET);

/// schema 的 worthyLines.kind 換一份可以填的種類（其他照原樣，key 的順序不變）。
function withWorthyKinds(
  schema: Record<string, unknown>,
  kinds: readonly string[],
): Record<string, unknown> {
  // deno-lint-ignore no-explicit-any
  const properties = schema.properties as Record<string, any>;
  const worthy = properties.worthyLines;
  return {
    ...schema,
    properties: {
      ...properties,
      worthyLines: {
        ...worthy,
        items: {
          ...worthy.items,
          properties: {
            ...worthy.items.properties,
            kind: { type: "string", enum: [...kinds] },
          },
        },
      },
    },
  };
}

/// 兩段式多要的四欄逐欄檢查，壞了回 null（跟 parseReadTags 一樣記成讀局面失敗）。編號在不在
/// 她最新這一輪的範圍內，交給排卡（rules.ts assignAnswers）處理，這裡只看型別。
/// sweetShort（甜話短回開、兩段式也開）：kind 多認「撒嬌」；沒給或 false 跟今天一樣，標了撒嬌就算讀局面失敗。
export function parseTwoStageTags(
  value: unknown,
  options: { readonly sweetShort?: boolean } = {},
): TwoStageTags | null {
  const kinds: readonly WorthyLineKind[] = options.sweetShort
    ? WORTHY_LINE_KINDS_SWEET
    : WORTHY_LINE_KINDS;
  // deno-lint-ignore no-explicit-any
  const v = value as any;
  if (!v || typeof v !== "object") return null;
  for (const f of TWO_STAGE_BOOL_FIELDS) {
    if (typeof v[f] !== "boolean") return null;
  }
  if (
    !Array.isArray(v.worthyLines) ||
    !v.worthyLines.every((w: unknown) =>
      // deno-lint-ignore no-explicit-any
      Number.isInteger((w as any)?.line) &&
      // deno-lint-ignore no-explicit-any
      typeof (w as any)?.label === "string" &&
      // deno-lint-ignore no-explicit-any
      isOneOf((w as any)?.kind, kinds)
    )
  ) return null;
  return {
    establishedCouple: v.establishedCouple,
    herAffection: v.herAffection,
    herHappyShare: v.herHappyShare,
    worthyLines: v.worthyLines.map((w: WorthyLine) => ({
      line: w.line,
      label: w.label,
      kind: w.kind,
    })),
  };
}

/// 結構化輸出照理不會壞；還是逐欄檢查，壞了回 null（記成讀局面失敗）。
export function parseReadTags(value: unknown): ReadTags | null {
  // deno-lint-ignore no-explicit-any
  const v = value as any;
  if (!v || typeof v !== "object") return null;
  if (!isOneOf(v.light, LIGHTS) || !isOneOf(v.herMove, HER_MOVES)) return null;
  if (!isOneOf(v.inviteReadiness, INVITE_READINESS)) return null;
  if (!isOneOf(v.replyWillingness, WILLINGNESS)) return null;
  for (const f of BOOL_FIELDS) if (typeof v[f] !== "boolean") return null;
  const strings = (x: unknown) =>
    Array.isArray(x) && x.every((s) => typeof s === "string");
  if (!strings(v.hisStatedFacts) || !strings(v.matchedEntries)) return null;
  if (!Number.isInteger(v.worthyBallCount) || v.worthyBallCount < 0) {
    return null;
  }
  if (
    !Array.isArray(v.herTurnsPerfunctory) ||
    !v.herTurnsPerfunctory.every((t: unknown) =>
      // deno-lint-ignore no-explicit-any
      Number.isInteger((t as any)?.turn) &&
      // deno-lint-ignore no-explicit-any
      typeof (t as any)?.perfunctory === "boolean"
    )
  ) return null;
  if (typeof v.readForUser !== "string" || typeof v.waitFor !== "string") {
    return null;
  }
  return v as ReadTags;
}
