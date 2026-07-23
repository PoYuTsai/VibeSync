// 單發生成引擎：Sonnet 5 一發 → 敗了立即補發 Haiku 4.5，不 repair 不重試同模型。
// 只負責 failover 與死線夾擠；產品守門全在呼叫端注入的 validate 裡。
import type { ChatMessage } from "./prompt.ts";
import type { ClaudeArgs } from "./claude.ts";

export type SingleShotClaudeCaller = (args: ClaudeArgs) => Promise<string>;

export interface SingleShotAttemptFailure {
  model: string;
  code: string; // "claude_timeout" | "claude_http_5xx" | "gate:<reason>" | "deadline_exhausted" | ...
  durationMs: number;
  /**
   * gate 打回的候選原文（截斷），供 ai_logs.response_body 診斷 TP/FP
   * （2026-07-23 真機 gh6 觀測缺口）。只有 gate 失敗帶；transport 失敗
   * 沒有候選。錯誤 message 仍只准機器碼，raw 絕不進 message/stack。
   */
  raw?: string;
}

const REJECTED_RAW_MAX_LENGTH = 4000;

export interface SingleShotArgs<T> {
  callClaude: SingleShotClaudeCaller;
  apiKey: string;
  messages: ChatMessage[];
  forcedTool: {
    name: string;
    description?: string;
    inputSchema: Record<string, unknown>;
  };
  maxTokens: number;
  /** 沿用各產品線既有溫度（hint 0.45／debrief 0.5）；Sonnet 5 路徑由 callClaude 自行忽略。 */
  temperature: number;
  perCallTimeoutMs: number;
  /** 請求絕對死線（epoch ms）。 */
  deadlineAtMs: number;
  /** 注入時鐘（測死線夾擠用）。 */
  now: () => number;
  /** [第一發, 第二發] = [Sonnet, Haiku]。 */
  models: [string, string];
  /** 丟 Error = gate 不過（含 parser／守門）。錯誤 message 只能是代碼，不得含候選原文。 */
  validate: (raw: string, model: string) => T;
}

export interface SingleShotOutcome<T> {
  result: T;
  model: string;
  /** 成功那一發的耗時（telemetry 用）。 */
  durationMs: number;
  attemptFailures: SingleShotAttemptFailure[];
}

export class SingleShotExhaustedError extends Error {
  attemptFailures: SingleShotAttemptFailure[];
  constructor(attemptFailures: SingleShotAttemptFailure[]) {
    super("single_shot_exhausted");
    this.name = "SingleShotExhaustedError";
    this.attemptFailures = attemptFailures;
  }
}

const DEADLINE_SAFETY_MARGIN_MS = 1_000;
const MIN_ATTEMPT_BUDGET_MS = 3_000;

export async function runSingleShot<T>(
  args: SingleShotArgs<T>,
): Promise<SingleShotOutcome<T>> {
  const attemptFailures: SingleShotAttemptFailure[] = [];

  for (const model of args.models) {
    const startedAt = args.now();
    const remainingMs = args.deadlineAtMs - startedAt;
    if (remainingMs < MIN_ATTEMPT_BUDGET_MS) {
      attemptFailures.push({ model, code: "deadline_exhausted", durationMs: 0 });
      continue;
    }
    const timeoutMs = Math.min(
      args.perCallTimeoutMs,
      remainingMs - DEADLINE_SAFETY_MARGIN_MS,
    );
    try {
      const raw = await args.callClaude({
        apiKey: args.apiKey,
        model,
        messages: args.messages,
        maxTokens: args.maxTokens,
        temperature: args.temperature,
        timeoutMs,
        forcedTool: args.forcedTool,
      });
      let result: T;
      try {
        result = args.validate(raw, model);
      } catch (gateError) {
        // gate 不過＝該發判敗。代碼照舊；候選原文截斷保留在 raw 欄
        // 供失敗觀測（不再一律丟棄——2026-07-23 拍板）。
        attemptFailures.push({
          model,
          code: gateError instanceof Error && gateError.message
            ? gateError.message
            : "gate:unknown",
          durationMs: args.now() - startedAt,
          raw: raw.slice(0, REJECTED_RAW_MAX_LENGTH),
        });
        continue;
      }
      return {
        result,
        model,
        durationMs: args.now() - startedAt,
        attemptFailures,
      };
    } catch (error) {
      attemptFailures.push({
        model,
        code: error instanceof Error && error.message
          ? error.message
          : "claude_unknown_error",
        durationMs: args.now() - startedAt,
      });
    }
  }

  throw new SingleShotExhaustedError(attemptFailures);
}
