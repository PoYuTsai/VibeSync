import { calculateCost, logInfo } from "./logger.ts";

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
