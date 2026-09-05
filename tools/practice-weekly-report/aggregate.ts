// 練習室週報的純函式統計層（Phase 5 WP1）：吃 Management API 回來的查詢列，
// 吐一個統計物件。不打網路、不讀檔、不看時鐘。

import {
  DEEPSEEK_CHAT_USD_PER_CALL,
  estimateCostUsd,
  HAIKU_4_5_PRICING,
  SONNET_5_PRICING,
  type TokenPricing,
  type TokenUsage,
} from "../practice-agency-eval/pricing.ts";
import { type DateRange, MAX_TURNS } from "./sql.ts";

/** `buildSessionsSql` 的一列。 */
export interface SessionRow {
  practice_mode: string | null;
  ai_count: number | null;
  sessions: number;
  hints: number;
  debriefs: number;
  charged: number;
}

/** `buildAiLogsSql` 的一列。 */
export interface AiLogRow {
  mode: string | null;
  practice_mode: string | null;
  model: string;
  status: string;
  fallback_used: boolean;
  call_rows: number;
  retries: number;
}

export interface GenerationRow {
  mode: string;
  practiceMode: string;
  model: string;
  status: string;
  fallbackUsed: boolean;
  /** 列數 ＋ 同列重試數＝這批真的打了幾次模型。 */
  calls: number;
  /** 沒有單價（例如 DeepSeek 生成）時是 null，不是 0。 */
  costUsd: number | null;
}

export interface Economics {
  payers: { starter: number; essential: number };
  monthlyRevenueTwd: number;
  weeklyCostTwd: number;
  monthlyCostTwd: number;
  costShareOfRevenue: number | null;
}

export interface Stats {
  range: DateRange;
  sessions: {
    total: number;
    byMode: Record<string, number>;
    charged: number;
  };
  turnHistogram: { turns: number; sessions: number }[];
  /** `ai_count > MAX_TURNS` 的場次（現行上限下應為 0）。 */
  turnOverflowSessions: number;
  /** `ai_count = 0`：開了場但一則 AI 回覆都沒成功。 */
  zeroTurnSessions: number;
  hintTotal: number;
  debriefTotal: number;
  generation: GenerationRow[];
  generationTotalCalls: number;
  generationFallbackCalls: number;
  totalCostUsd: number;
  /** 有呼叫但沒單價可估的次數（估價的分母缺口，要跟 console 對帳時看這個）。 */
  unpricedCalls: number;
  costPerSessionUsd: number | null;
  economics: Economics | null;
  /** Edge Function logs 來源（沒查或查不到時是 null）。 */
  logs: LogStats | null;
}

/** D14：匯率 1 USD ≈ NT$32。 */
export const USD_TO_TWD = 32;

/** D14／D2：方案月費（NT$）。 */
export const PLAN_MONTHLY_TWD = { starter: 590, essential: 1290 } as const;

/**
 * 單次呼叫的 token 側寫，來自計畫 §2 D14 的「輸入 9k token，其中 8.1k 命中
 * cache」與提示 ~400／檢討 ~1,200 output tokens。
 *
 * 為什麼要用側寫而不是真 token 數：`ai_logs.input_tokens`／`output_tokens`
 * 在 practice-chat 的寫入端是**寫死的 0**（telemetry.ts `buildPracticeAiLogRow`
 * 的隱私邊界），`cost_usd` 也從來沒被填過。DB 裡拿不到 usage，只能用側寫 ×
 * 呼叫次數估。用這組側寫算出來的單次金額與 D14 表格逐格相同
 * （Sonnet 提示 $0.0074／檢討 $0.0154、Haiku 提示 $0.0037），對帳時可以直接
 * 對回計畫那張表。
 *
 * ponytail: 固定側寫，Anthropic console 對帳誤差 >10% 時就是該讓寫入端把
 * 真 usage 落進 ai_logs（改 telemetry.ts），而不是在這裡調係數。
 */
export const CALL_TOKEN_PROFILE: Record<string, TokenUsage> = {
  hint: {
    inputTokens: 900,
    cacheReadInputTokens: 8100,
    cacheCreationInputTokens: 0,
    outputTokens: 400,
  },
  debrief: {
    inputTokens: 900,
    cacheReadInputTokens: 8100,
    cacheCreationInputTokens: 0,
    outputTokens: 1200,
  },
};

/** 只有 Anthropic 兩支有 token 牌價；DeepSeek 生成沒有可信單價常數。 */
const PRICING_BY_MODEL: Record<string, TokenPricing> = {
  "claude-sonnet-5": SONNET_5_PRICING,
  "claude-haiku-4-5-20251001": HAIKU_4_5_PRICING,
};

/** 計畫 WP1 點名、但 production 沒有寫進任何資料表的欄位。 */
export const MISSING_FIELDS: readonly { field: string; reason: string }[] = [
  {
    field: "agency 介入率",
    reason:
      "只在 `practice_chat_succeeded` console 事件的 `agency` 區塊（handler.ts 5200 一帶），不寫 DB。",
  },
  {
    field: "chatModel 分佈",
    reason:
      "`chatModel`／`chatModelCalls` 只在 `practice_chat_succeeded` console 事件（handler.ts:5152），不寫 DB。",
  },
  {
    field: "chatModelFallback 比率",
    reason: "同上（handler.ts:5153）。本報告的 fallback 只涵蓋提示／檢討列。",
  },
  {
    field: "每場聊天成本（chatModelUsage）",
    reason:
      "`chatModelUsage` 四格 token 只在 console 事件（handler.ts:5154）；`ai_logs` 沒有聊天回合的列，成本欄只含提示與檢討。",
  },
  {
    field: "checkOutStructuralFail 比率",
    reason:
      "只在 console 事件的 `agency.checkOutStructuralFail`（handler.ts:5309）。",
  },
  {
    field: "checkOutRewriteInjected × checkOutStructuralFail 交叉比率",
    reason: "兩個 key 都只在 console 事件（handler.ts:5307-5310）。",
  },
  {
    field: "readOnlyReply 比率",
    reason: "只在 console 事件的 `agency.readOnlyReply`（handler.ts:5298）。",
  },
];

function costOf(mode: string, model: string, calls: number): number | null {
  // DeepSeek 沒有 token 牌價，只有餘額差反推的每次觀測單價（pricing.ts）。
  if (model.startsWith("deepseek")) {
    return calls * DEEPSEEK_CHAT_USD_PER_CALL;
  }
  const pricing = PRICING_BY_MODEL[model];
  const profile = CALL_TOKEN_PROFILE[mode];
  if (!pricing || !profile) return null;
  return estimateCostUsd(profile, pricing) * calls;
}

export function aggregate(input: {
  range: DateRange;
  sessions: readonly SessionRow[];
  aiLogs: readonly AiLogRow[];
  payers?: { starter: number; essential: number };
  logs?: LogStats | null;
}): Stats {
  const byMode: Record<string, number> = {};
  const histogram = new Map<number, number>();
  let total = 0;
  let charged = 0;
  let hintTotal = 0;
  let debriefTotal = 0;
  let turnOverflowSessions = 0;
  let zeroTurnSessions = 0;

  for (const row of input.sessions) {
    const count = Number(row.sessions) || 0;
    const mode = row.practice_mode ?? "unknown";
    byMode[mode] = (byMode[mode] ?? 0) + count;
    total += count;
    charged += Number(row.charged) || 0;
    hintTotal += Number(row.hints) || 0;
    debriefTotal += Number(row.debriefs) || 0;
    const turns = Number(row.ai_count) || 0;
    if (turns <= 0) zeroTurnSessions += count;
    else if (turns > MAX_TURNS) turnOverflowSessions += count;
    else histogram.set(turns, (histogram.get(turns) ?? 0) + count);
  }

  const generation: GenerationRow[] = input.aiLogs.map((row) => {
    const calls = (Number(row.call_rows) || 0) + (Number(row.retries) || 0);
    const mode = row.mode ?? "unknown";
    return {
      mode,
      practiceMode: row.practice_mode ?? "unknown",
      model: row.model,
      status: row.status,
      fallbackUsed: row.fallback_used === true,
      calls,
      costUsd: costOf(mode, row.model, calls),
    };
  });

  let generationTotalCalls = 0;
  let generationFallbackCalls = 0;
  let totalCostUsd = 0;
  let unpricedCalls = 0;
  for (const row of generation) {
    generationTotalCalls += row.calls;
    if (row.fallbackUsed) generationFallbackCalls += row.calls;
    if (row.costUsd === null) unpricedCalls += row.calls;
    else totalCostUsd += row.costUsd;
  }

  const turnHistogram = Array.from({ length: MAX_TURNS }, (_, index) => ({
    turns: index + 1,
    sessions: histogram.get(index + 1) ?? 0,
  }));

  return {
    range: input.range,
    sessions: { total, byMode, charged },
    turnHistogram,
    turnOverflowSessions,
    zeroTurnSessions,
    hintTotal,
    debriefTotal,
    generation,
    generationTotalCalls,
    generationFallbackCalls,
    totalCostUsd,
    unpricedCalls,
    costPerSessionUsd: total > 0 ? totalCostUsd / total : null,
    economics: input.payers ? buildEconomics(input.payers, totalCostUsd) : null,
    logs: input.logs ?? null,
  };
}

function buildEconomics(
  payers: { starter: number; essential: number },
  totalCostUsd: number,
): Economics {
  const monthlyRevenueTwd = payers.starter * PLAN_MONTHLY_TWD.starter +
    payers.essential * PLAN_MONTHLY_TWD.essential;
  const weeklyCostTwd = totalCostUsd * USD_TO_TWD;
  // 一週外推成一個月：52 週／12 個月。營收是月費，成本是週觀測，兩邊要同口徑。
  const monthlyCostTwd = weeklyCostTwd * 52 / 12;
  return {
    payers,
    monthlyRevenueTwd,
    weeklyCostTwd,
    monthlyCostTwd,
    costShareOfRevenue: monthlyRevenueTwd > 0
      ? monthlyCostTwd / monthlyRevenueTwd
      : null,
  };
}

/** Logs Explorer 回來的一列。 */
export interface LogRow {
  timestamp: string | number | null;
  event_message: string | null;
}

export interface LogStats {
  /** 端點實際回了幾列（撞到 limit 就代表被截斷）。 */
  rowsReturned: number;
  /** 重試後仍拿不到的日子（限流），涵蓋範圍段會逐日列出。 */
  missingDays: string[];
  /** 涵蓋範圍：保留期把時間窗吃掉時，這兩個值會比 --from／--to 窄。 */
  earliest: string | null;
  latest: string | null;
  /** 解析成功的 `practice_chat_succeeded` 輪數。 */
  turns: number;
  skippedOtherEvent: number;
  skippedUnparsable: number;

  agencyTurns: number;
  agencyApplied: number;
  agencyAppliedRate: number | null;

  chatModelTurns: number;
  chatModelDistribution: Record<string, number>;
  chatModelCalls: { haiku: number; deepseek: number };
  chatModelFallbackTurns: number;
  chatModelFallbackRate: number | null;
  chatModelUsage: TokenUsage;
  chatCostUsd: number;

  checkOutStructuralFail: number;
  checkOutStructuralFailRate: number | null;
  checkOutRewriteInjected: number;
  checkOutRewriteAndFail: number;
  checkOutRewriteFailRate: number | null;
  readOnlyReply: number;
  readOnlyReplyRate: number | null;
}

const EVENT = "practice_chat_succeeded";

/**
 * Logs Explorer 的 `timestamp` 是**微秒整數**（例 1788558109700000），
 * 不是 ISO 字串。換算成 ISO 才能印涵蓋範圍、才能字典序比大小。
 * 已經是字串的（其他來源／未來改版）原樣留著。
 */
export function logTimestampToIso(value: unknown): string | null {
  if (typeof value === "string" && value.length > 0) return value;
  const micros = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(micros) || micros <= 0) return null;
  return new Date(Math.floor(micros / 1000)).toISOString();
}

function rate(part: number, whole: number): number | null {
  return whole > 0 ? part / whole : null;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function addUsage(total: TokenUsage, value: unknown): TokenUsage {
  const usage = asRecord(value);
  if (!usage) return total;
  const num = (key: string) => {
    const raw = usage[key];
    return typeof raw === "number" && Number.isFinite(raw) ? raw : 0;
  };
  return {
    inputTokens: total.inputTokens + num("inputTokens"),
    cacheReadInputTokens: total.cacheReadInputTokens +
      num("cacheReadInputTokens"),
    cacheCreationInputTokens: total.cacheCreationInputTokens +
      num("cacheCreationInputTokens"),
    outputTokens: total.outputTokens + num("outputTokens"),
  };
}

/**
 * 把 function logs 的原始列折成統計。一行 log ＝ `logger.ts` 的
 * `JSON.stringify({ level, event, ...data })`，沒有前綴、沒有多行。
 *
 * 容錯：不是 JSON、不是物件、不是 `practice_chat_succeeded` 的列一律跳過並
 * 分別計數（壞行不能讓整份報告掛掉，但也不能無聲吃掉）。
 *
 * 分母刻意分開：`conversationAgency`／`chatModel` 這兩個 key 在旗標關著時
 * **整組不存在**（handler.ts 的等價保證），所以比率的分母是「帶那個 key 的
 * 輪數」，不是全部輪數。
 */
export function aggregateLogs(
  rows: readonly LogRow[],
  missingDays: readonly string[] = [],
): LogStats {
  let turns = 0;
  let skippedOtherEvent = 0;
  let skippedUnparsable = 0;
  let earliest: string | null = null;
  let latest: string | null = null;

  let agencyTurns = 0;
  let agencyApplied = 0;
  let chatModelTurns = 0;
  const chatModelDistribution: Record<string, number> = {};
  const chatModelCalls = { haiku: 0, deepseek: 0 };
  let chatModelFallbackTurns = 0;
  let chatModelUsage: TokenUsage = {
    inputTokens: 0,
    cacheReadInputTokens: 0,
    cacheCreationInputTokens: 0,
    outputTokens: 0,
  };
  let checkOutStructuralFail = 0;
  let checkOutRewriteInjected = 0;
  let checkOutRewriteAndFail = 0;
  let readOnlyReply = 0;

  for (const row of rows) {
    const stamp = logTimestampToIso(row.timestamp);
    if (stamp !== null) {
      if (earliest === null || stamp < earliest) earliest = stamp;
      if (latest === null || stamp > latest) latest = stamp;
    }

    let payload: Record<string, unknown> | null = null;
    try {
      payload = asRecord(JSON.parse(row.event_message ?? ""));
    } catch {
      payload = null;
    }
    if (!payload) {
      skippedUnparsable += 1;
      continue;
    }
    if (payload.event !== EVENT) {
      skippedOtherEvent += 1;
      continue;
    }
    turns += 1;

    const agency = asRecord(payload.conversationAgency);
    if (agency) {
      agencyTurns += 1;
      if (agency.applied === true) agencyApplied += 1;
      if (agency.readOnlyReply === true) readOnlyReply += 1;
      const failed = agency.checkOutStructuralFail === true;
      const rewritten = agency.checkOutRewriteInjected === true;
      if (failed) checkOutStructuralFail += 1;
      if (rewritten) checkOutRewriteInjected += 1;
      if (rewritten && failed) checkOutRewriteAndFail += 1;
    }

    if (typeof payload.chatModel === "string") {
      chatModelTurns += 1;
      chatModelDistribution[payload.chatModel] =
        (chatModelDistribution[payload.chatModel] ?? 0) + 1;
      if (payload.chatModelFallback === true) chatModelFallbackTurns += 1;
      const calls = asRecord(payload.chatModelCalls);
      if (calls) {
        for (const key of ["haiku", "deepseek"] as const) {
          const value = calls[key];
          if (typeof value === "number" && Number.isFinite(value)) {
            chatModelCalls[key] += value;
          }
        }
      }
      chatModelUsage = addUsage(chatModelUsage, payload.chatModelUsage);
    }
  }

  return {
    rowsReturned: rows.length,
    missingDays: [...missingDays],
    earliest,
    latest,
    turns,
    skippedOtherEvent,
    skippedUnparsable,
    agencyTurns,
    agencyApplied,
    agencyAppliedRate: rate(agencyApplied, agencyTurns),
    chatModelTurns,
    chatModelDistribution,
    chatModelCalls,
    chatModelFallbackTurns,
    chatModelFallbackRate: rate(chatModelFallbackTurns, chatModelTurns),
    chatModelUsage,
    // Haiku 走 token 牌價（usage 只累加成功的 Claude 呼叫），DeepSeek 沒有
    // token 牌價、只有餘額差反推的每次觀測單價。
    chatCostUsd: estimateCostUsd(chatModelUsage, HAIKU_4_5_PRICING) +
      chatModelCalls.deepseek * DEEPSEEK_CHAT_USD_PER_CALL,
    checkOutStructuralFail,
    checkOutStructuralFailRate: rate(checkOutStructuralFail, agencyTurns),
    checkOutRewriteInjected,
    checkOutRewriteAndFail,
    checkOutRewriteFailRate: rate(
      checkOutRewriteAndFail,
      checkOutRewriteInjected,
    ),
    readOnlyReply,
    readOnlyReplyRate: rate(readOnlyReply, agencyTurns),
  };
}
