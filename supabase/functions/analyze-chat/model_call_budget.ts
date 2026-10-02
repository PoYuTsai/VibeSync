import { calculateCost, type LogEntry, logInfo } from "./logger.ts";

export type ProviderUsage = Partial<Record<
  "inputTokens" | "cacheCreationTokens" | "cacheReadTokens" | "outputTokens",
  number
>>;

export function readProviderUsage(data: unknown): ProviderUsage {
  const raw = (data as { usage?: Record<string, unknown> } | null)?.usage;
  const usage: ProviderUsage = {};
  for (const [key, source] of Object.entries({
    inputTokens: "input_tokens",
    cacheCreationTokens: "cache_creation_input_tokens",
    cacheReadTokens: "cache_read_input_tokens",
    outputTokens: "output_tokens",
  })) {
    const value = raw?.[source];
    if (typeof value === "number" && Number.isFinite(value) && value >= 0) {
      usage[key as keyof ProviderUsage] = value;
    }
  }
  return usage;
}

export class ModelCallBudgetError extends Error {
  constructor(public readonly code: "PROVIDER_CALL_LIMIT" | "DEADLINE_EXCEEDED") {
    super(code);
  }
}

/** One invocation only. Cross-lease logical-operation budgets require Q2 storage. */
export class ModelCallBudget {
  private calls = 0;
  constructor(
    readonly deadlineAtMs: number,
    private readonly context: Record<string, unknown>,
    private readonly report: (record: Record<string, unknown>) => void =
      (record) => logInfo("opener_provider_attempt", record),
  ) {}

  begin(model: string, purpose: string, route: string) {
    if (Date.now() >= this.deadlineAtMs) {
      throw new ModelCallBudgetError("DEADLINE_EXCEEDED");
    }
    if (this.calls >= 3) throw new ModelCallBudgetError("PROVIDER_CALL_LIMIT");
    const attempt = ++this.calls;
    const started = Date.now();
    const usage: ProviderUsage = {};
    let finished = false;
    return {
      observe: (observed: ProviderUsage) => Object.assign(usage, observed),
      finish: (status: "success" | "failed") => {
        if (finished) return;
        finished = true;
        const complete = [usage.inputTokens, usage.cacheCreationTokens,
          usage.cacheReadTokens, usage.outputTokens].every((v) => v !== undefined);
        this.report({
          ...this.context, model, attempt, purpose, route, status,
          elapsedMs: Date.now() - started,
          inputTokens: usage.inputTokens ?? null,
          cacheCreationTokens: usage.cacheCreationTokens ?? null,
          cacheReadTokens: usage.cacheReadTokens ?? null,
          outputTokens: usage.outputTokens ?? null,
          usageComplete: complete, usage_unknown: !complete,
          estimatedCostUsd: complete
            ? calculateCost(model, usage.inputTokens!, usage.outputTokens!,
              usage.cacheCreationTokens!, usage.cacheReadTokens!)
            : null,
          pricingSource: "analyze-chat/logger.ts:TOKEN_COSTS",
        });
      },
    };
  }
}

export type ProviderAttemptLogEntry = Omit<LogEntry, "userId">;

// ai_logs 一列＝一次供應商呼叫（含 fallback 跳轉與修復）。request_body 只收
// 白名單：用途、路由、識別與版本；絕不放 profile、圖片、素材原文或模型輸出，
// user 摘要也不放（user_id 有自己的欄位）。快取 token 沒有欄位，只進 cost_usd。
const ATTEMPT_LOG_BODY_KEYS = [
  "purpose", "route", "attempt", "stage", "operation", "flowVersion", "tier",
  "usageComplete", "responseMode",
];

export function providerAttemptLogEntry(
  requestType: string,
  record: Record<string, unknown>,
  extra: Record<string, unknown> = {},
): ProviderAttemptLogEntry {
  const count = (key: string) => typeof record[key] === "number" ? record[key] as number : 0;
  const failed = record.status === "failed";
  return {
    model: String(record.model),
    requestType,
    inputTokens: count("inputTokens"),
    outputTokens: count("outputTokens"),
    cacheCreationTokens: count("cacheCreationTokens"),
    cacheReadTokens: count("cacheReadTokens"),
    latencyMs: count("elapsedMs"),
    status: failed ? "failed" : "success",
    errorCode: failed ? "PROVIDER_ATTEMPT_FAILED" : undefined,
    fallbackUsed: record.route === "fallback",
    retryCount: record.route === "retry" ? 1 : 0,
    requestBody: {
      ...Object.fromEntries(ATTEMPT_LOG_BODY_KEYS.filter((key) => key in record).map((key) => [key, record[key]])),
      ...extra,
    },
  };
}

/** 保留原本的 console 事件，另交一列給 recordAiCall（沒注入就不寫，測試不會打 DB）。 */
export function attemptReporter(
  event: string,
  requestType: string,
  recordAiCall?: (entry: ProviderAttemptLogEntry) => void,
  extra?: Record<string, unknown>,
) {
  return (record: Record<string, unknown>) => {
    logInfo(event, record);
    recordAiCall?.(providerAttemptLogEntry(requestType, record, extra));
  };
}
