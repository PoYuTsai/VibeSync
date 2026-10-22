// 兩段式實驗（ANALYZE_GUIDE_V3_TWO_STAGE）與關係訊號（ANALYZE_GUIDE_V3_RELATION）四種開關組合的
// 共用情境（Eric 2026-10-20 兩邊都上線）：同一段對話、同一份假讀局面、假寫卡與假說明，跑正式的
// handleGuideV3Stream，收集事件、送給模型的請求、扣費、落帳與 log，再算成一個 sha256。
// handle 由呼叫端傳進來：測試傳這一版的，對照值是拿同一個情境跑 main 6ef72aff 與兩段式 c8f64dfe 的
// 原始快照算出來的（不連網、不呼叫模型）。給 flag_matrix_test.ts 用；入口不載入，不隨函式部署。
// 甜話短回另有一段交往中的情境（FLAG_MATRIX_SWEET_*，句子全新），用 options.messages 與 readText 換上。
import type { AnalysisStreamRun } from "../stream_run_store.ts";
import { GUIDE_V3_VERSION } from "./guide_text.ts";
import type { GuideV3StreamDeps } from "./stream_flow.ts";

export const FLAG_MATRIX_T0 = Date.parse("2026-10-20T00:00:00.000Z");

export interface FlagCombo {
  readonly twoStage: boolean;
  readonly relation: boolean;
  /// 口吻與斷句交給程式（ANALYZE_GUIDE_V3_TYPING_STYLE，Bruce 2026-10-20 改法 3）；沒給當關。
  readonly typingStyle?: boolean;
  /// 寫卡第 4 輪（Bruce 2026-10-20）：短版稱讚、帶張力改寫法；沒給當關。
  readonly shortPraise?: boolean;
  readonly tensionStyle?: boolean;
  /// 「這題」「滿→蠻」交給程式（ANALYZE_GUIDE_V3_PHRASE_TIDY，Bruce 2026-10-20 PR #97）；沒給當關。
  readonly phraseTidy?: boolean;
  /// 甜話短回（ANALYZE_GUIDE_V3_SWEET_SHORT，Eric 2026-10-22「照預設」）；沒給當關。
  readonly sweetShort?: boolean;
}

/// 她傳照片、貼圖又問他（第 2 輪的形狀）；訊息裡不放「只」，繁體轉換的修正不影響比對。
export const FLAG_MATRIX_MESSAGES: readonly {
  isFromMe: boolean;
  content: string;
}[] = [
  { isFromMe: true, content: "聚餐好玩嗎" },
  { isFromMe: false, content: "超好玩 主管請客" },
  { isFromMe: false, content: "[兩張照片：同事合照、一桌火鍋]" },
  { isFromMe: false, content: "[貼圖：小熊比愛心]" },
  { isFromMe: false, content: "晚點回去給你看影片" },
  { isFromMe: false, content: "你覺得我今天好看嗎" },
];

export const FLAG_MATRIX_TAGS: Record<string, unknown> = {
  light: "green",
  herMove: "問他意見",
  herMoodBad: false,
  drunkOrLateNight: false,
  inviteReadiness: "沒機會",
  cancelHasAlternative: false,
  retreating: false,
  declinedOrBoundary: false,
  explicitRejection: false,
  blocked: false,
  risk: false,
  selfHarmSignal: false,
  minorSignal: false,
  needsHisFacts: false,
  identityQuestion: false,
  hisStatedFacts: [],
  hasHisVoiceSample: true,
  replyWillingness: "high",
  worthyBallCount: 3,
  herTurnsPerfunctory: [{ turn: 2, perfunctory: false }],
  matchedEntries: ["B44", "B22"],
  readForUser: "她在分享聚餐的開心，最後問你她今天好不好看。",
  waitFor: "",
};

/// 兩段式多要的四欄。
export const FLAG_MATRIX_TWO_STAGE_FIELDS: Record<string, unknown> = {
  establishedCouple: false,
  herAffection: true,
  herHappyShare: true,
  worthyLines: [
    { line: 1, label: "主管請客", kind: "情感" },
    { line: 2, label: "照片", kind: "照片或貼圖" },
    { line: 3, label: "愛心貼圖", kind: "情感" },
    { line: 4, label: "晚點給他看影片", kind: "其他" },
    { line: 5, label: "問他好不好看", kind: "問他" },
  ],
};

/// 關係訊號多要的三欄。
export const FLAG_MATRIX_RELATION_FIELDS: Record<string, unknown> = {
  gameStage: "premise",
  heatScore: 82,
  dimensions: {
    engagement: 85,
    topicDepth: 60,
    replyWillingness: 88,
    emotionalConnection: 74,
  },
};

/// 讀局面回的 JSON：照這個組合的 schema 該有的欄位（兩段式四欄在前、關係三欄在最後）。
export function flagMatrixReadText(combo: FlagCombo): string {
  return JSON.stringify({
    ...FLAG_MATRIX_TAGS,
    ...(combo.twoStage ? FLAG_MATRIX_TWO_STAGE_FIELDS : {}),
    ...(combo.relation ? FLAG_MATRIX_RELATION_FIELDS : {}),
  });
}

// ── 甜話短回（ANALYZE_GUIDE_V3_SWEET_SHORT，Eric 2026-10-22「照預設」）的情境：已經在交往，她最新這一輪先撒嬌一句很短的
// 甜話、再說腳痛（Bruce 2026-10-22 試的形狀，句子全新）。他傳過兩則，排卡第一張是推進（種子）。

export const FLAG_MATRIX_SWEET_MESSAGES: readonly {
  isFromMe: boolean;
  content: string;
}[] = [
  { isFromMe: true, content: "今天還好嗎" },
  { isFromMe: false, content: "還行 剛開完會" },
  { isFromMe: true, content: "辛苦了 晚點打給你" },
  { isFromMe: false, content: "只想要你哄❤️" },
  { isFromMe: false, content: "今天穿新鞋走了好多路 腳底好痛" },
];

/// 同一段對話但她最新這一輪只有那句甜話（走少出幾張的路）。
export const FLAG_MATRIX_SWEET_ONLY_MESSAGES = FLAG_MATRIX_SWEET_MESSAGES.slice(
  0,
  4,
);

export const FLAG_MATRIX_SWEET_TAGS: Record<string, unknown> = {
  ...FLAG_MATRIX_TAGS,
  herMove: "生活",
  worthyBallCount: 2,
  matchedEntries: [],
  readForUser: "你們在交往，她跟你撒嬌，也說今天走路走到腳底痛。",
};

export const FLAG_MATRIX_SWEET_TWO_STAGE_FIELDS: Record<string, unknown> = {
  establishedCouple: true,
  herAffection: true,
  herHappyShare: false,
  worthyLines: [
    { line: 1, label: "撒嬌要他哄", kind: "情感" },
    { line: 2, label: "腳底痛", kind: "其他" },
  ],
};

/// 甜話情境的讀局面 JSON（跟 flagMatrixReadText 一樣照組合給欄位）；over 蓋過讀局面的欄位（她只傳那句甜話、她沒撒嬌、
/// 那則變長這些對照用）。
export function flagMatrixSweetReadText(
  combo: FlagCombo,
  over: Record<string, unknown> = {},
): string {
  return JSON.stringify({
    ...FLAG_MATRIX_SWEET_TAGS,
    ...(combo.twoStage ? FLAG_MATRIX_SWEET_TWO_STAGE_FIELDS : {}),
    ...(combo.relation ? FLAG_MATRIX_RELATION_FIELDS : {}),
    ...over,
  });
}

/// 寫卡：規格要幾張就回幾張。
export function flagMatrixCards(user: string): string[] {
  const n = Number(user.match(/一共 (\d+) 張/)?.[1] ?? 0);
  return Array.from({ length: n }, (_, i) =>
    JSON.stringify({
      card: i + 1,
      messages: [`好看啊，第 ${i + 1} 張`],
      hasInventedDetail: false,
    }) + "\n");
}

/// 說明：寫好的卡有幾張就回幾段（照使用者訊息裡的「### 第 N 張」）。
export function flagMatrixExplain(user: string): string {
  const slots = [...user.matchAll(/^### 第 (\d+) 張$/gmu)].map((m) =>
    Number(m[1])
  );
  return JSON.stringify({
    explanations: slots.map((card) => ({
      card,
      text: `第 ${card} 張先回她問的那句，你們聊得下去。`,
    })),
  });
}

async function* stream(parts: readonly string[]): AsyncGenerator<string> {
  for (const part of parts) yield part;
}

type Handle = (deps: GuideV3StreamDeps) => Promise<Response>;

export interface FlagMatrixOptions {
  /// 換掉讀局面回的 JSON（哨兵測試用）。
  readonly readText?: string;
  /// 換掉寫卡的輸出（哨兵測試用）。
  readonly writeParts?: (user: string) => string[];
  /// 換掉說明的輸出（哨兵測試用）。
  readonly explainText?: (user: string) => string;
  /// 換掉對話（甜話短回的情境用）；沒給是 FLAG_MATRIX_MESSAGES。
  readonly messages?: readonly { isFromMe: boolean; content: string }[];
}

/// 跑一次，送出的、存的、記的都收進 outcome（JSON 化，跟資料庫存的一樣丟掉 undefined）。
export async function runFlagMatrix(
  handle: Handle,
  combo: FlagCombo,
  options: FlagMatrixOptions = {},
): Promise<Record<string, unknown>> {
  const T0 = FLAG_MATRIX_T0;
  const calls: string[] = [];
  const charges: unknown[] = [];
  const logs: unknown[] = [];
  const requests: Record<string, unknown> = {};
  let markDone: unknown = null;
  let run: AnalysisStreamRun = {
    id: "matrix-run",
    user_id: "matrix-user",
    conversation_hash: "matrix-hash",
    status: "pending",
    selected_style: null,
    decision_kind: null,
    card_task: null,
    recommendation_json: null,
    final_result_json: null,
    charged_at: null,
    last_error_code: null,
    retry_count: 0,
    request_context: { guideVersion: GUIDE_V3_VERSION },
    created_at: new Date(T0).toISOString(),
    expires_at: new Date(T0 + 30 * 60_000).toISOString(),
  };
  const deps = {
    store: {
      getRun: () => Promise.resolve(run),
      createPendingRun: () => {
        calls.push("createPendingRun");
        return Promise.resolve(run);
      },
      chargeRunV3: (input: { decisionKind: string; cardTask: string }) => {
        calls.push(`charge:${input.decisionKind}:${input.cardTask}`);
        charges.push(input);
        run = {
          ...run,
          status: "charged",
          charged_at: new Date(T0).toISOString(),
          card_task: input.cardTask,
          decision_kind: input.decisionKind,
          recommendation_json:
            (input as { recommendationJson?: unknown }).recommendationJson ??
              null,
        } as AnalysisStreamRun;
        return Promise.resolve(run);
      },
      markDone: (args: { finalResult: unknown }) => {
        calls.push("markDone");
        markDone = args.finalResult;
        run = {
          ...run,
          status: "done",
          final_result_json: args.finalResult,
        } as AnalysisStreamRun;
        return Promise.resolve(run);
      },
      markFailedIfPending: (args: { code: string }) => {
        calls.push(`markFailedIfPending:${args.code}`);
        if (run.status !== "pending" || run.charged_at !== null) {
          return Promise.resolve(null);
        }
        run = { ...run, status: "failed", last_error_code: args.code };
        return Promise.resolve(run);
      },
    },
    userId: "matrix-user",
    analysisRunId: null,
    conversationHash: "matrix-hash",
    messages: options.messages ?? FLAG_MATRIX_MESSAGES,
    requestType: "analyze",
    effectiveTier: "essential",
    accountIsTest: false,
    quotaUsage: {
      shouldChargeQuota: true,
      quotaReason: "analyze_message_based",
      quotaUnit: "messages",
      chargedMessageCount: 5,
      estimatedMessageCount: 5,
    },
    monthlyLimit: 800,
    dailyLimit: 120,
    subMonthlyUsed: 0,
    subDailyUsed: 0,
    callRead: (req: { system: string; user: string; schema: unknown }) => {
      calls.push("read");
      requests.read = {
        system: req.system,
        user: req.user,
        schema: req.schema,
      };
      return Promise.resolve({
        text: options.readText ?? flagMatrixReadText(combo),
        model: "claude-sonnet-5-5",
      });
    },
    callWrite: (req: { system: string; user: string }) => {
      calls.push("write");
      requests.write = { system: req.system, user: req.user };
      return Promise.resolve({
        model: "claude-sonnet-5-5",
        textStream: stream((options.writeParts ?? flagMatrixCards)(req.user)),
      });
    },
    log: (
      event: string,
      metadata: Record<string, unknown>,
      level?: string,
    ) => logs.push({ event, metadata, level }),
    now: () => T0,
    heartbeatIntervalMs: 0,
    // 正式入口兩個開關都會給（沒開是 false）；說明呼叫只有兩段式開著才有。
    twoStage: combo.twoStage,
    relation: combo.relation,
    typingStyle: combo.typingStyle ?? false,
    shortPraise: combo.shortPraise ?? false,
    tensionStyle: combo.tensionStyle ?? false,
    phraseTidy: combo.phraseTidy ?? false,
    sweetShort: combo.sweetShort ?? false,
    ...(combo.twoStage
      ? {
        callExplain: (
          req: { system: string; user: string; schema: unknown },
        ) => {
          calls.push("explain");
          requests.explain = {
            system: req.system,
            user: req.user,
            schema: req.schema,
          };
          return Promise.resolve({
            text: (options.explainText ?? flagMatrixExplain)(req.user),
            model: "claude-sonnet-5-5",
          });
        },
      }
      : {}),
  } as unknown as GuideV3StreamDeps;
  const response = await handle(deps);
  const text = await response.text();
  return JSON.parse(JSON.stringify({
    status: response.status,
    events: text.split("\n").filter(Boolean).map((l) => JSON.parse(l)),
    calls,
    charges,
    markDone,
    requests,
    logs,
  }));
}

/// 拿掉每一層的這幾個 key（比兩段式 c8f64dfe 的行為時用：main 加的結案時間 completedAt、主審
/// 第 1 輪 P2 加的結果裡的 cardExplains）。
export function withoutKeys(value: unknown, keys: readonly string[]): unknown {
  if (Array.isArray(value)) return value.map((v) => withoutKeys(v, keys));
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .filter(([key]) => !keys.includes(key))
        .map(([key, v]) => [key, withoutKeys(v, keys)]),
    );
  }
  return value;
}

export function withoutCompletedAt(value: unknown): unknown {
  return withoutKeys(value, ["completedAt"]);
}

export async function outcomeDigest(outcome: unknown): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(JSON.stringify(outcome)),
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
