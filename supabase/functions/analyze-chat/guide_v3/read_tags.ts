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
