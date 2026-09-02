// stream_run_store: data-access boundary for durable AnalyzeChat streams.
// The `analysis_stream_runs` ledger is the sole live AnalyzeChat charge/resume
// lifecycle and keeps persistence details out of the request handler.

import type {
  StreamChargePayload,
  StreamRecommendationForCharge,
} from "./reframer.ts";
import {
  isNoSendChargePayload,
  type NoSendDecisionKind,
  serializeNoSendRecommendation,
} from "./no_send_decision.ts";
import type { StreamStyle } from "./stream_events.ts";

export type AnalysisStreamRunStatus = "pending" | "charged" | "done" | "failed";

export interface AnalysisStreamRun {
  id: string;
  user_id: string;
  conversation_hash: string;
  status: AnalysisStreamRunStatus;
  selected_style: StreamStyle | null;
  // Phase 1a column; absent on rows returned by older driver mocks.
  decision_kind?: string | null;
  recommendation_json: Record<string, unknown> | null;
  final_result_json: Record<string, unknown> | null;
  charged_at: string | null;
  last_error_code: string | null;
  retry_count: number;
  request_context: Record<string, unknown> | null;
  created_at: string;
  expires_at: string;
}

export interface CreatePendingStreamRunInput {
  userId: string;
  conversationHash: string;
  requestContext?: Record<string, unknown>;
}

export interface ChargeStreamRunInput {
  runId: string;
  userId: string;
  conversationHash: string;
  recommendation: StreamChargePayload;
  chargeQuota: boolean;
  messageCount: number;
}

export interface MarkStreamRunDoneInput {
  runId: string;
  userId: string;
  conversationHash: string;
  finalResult: Record<string, unknown>;
}

export interface MarkStreamRunFailedInput {
  runId: string;
  userId: string;
  conversationHash: string;
  code: string;
}

export interface GetStreamRunInput {
  runId: string;
  userId: string;
  conversationHash: string;
}

export interface ReserveStreamRetryInput {
  runId: string;
  userId: string;
  conversationHash: string;
  maxRetries: number;
}

export interface ChargeStreamRunDriverInput {
  runId: string;
  userId: string;
  conversationHash: string;
  recommendationJson: Record<string, unknown>;
  selectedStyle: StreamStyle | null;
  decisionKind?: NoSendDecisionKind;
  chargeQuota: boolean;
  messageCount: number;
}

export interface AnalysisStreamRunDriver {
  createPendingRun(
    input: CreatePendingStreamRunInput,
  ): Promise<AnalysisStreamRun>;
  getRun(input: GetStreamRunInput): Promise<AnalysisStreamRun>;
  reserveRetry(input: ReserveStreamRetryInput): Promise<AnalysisStreamRun>;
  chargeRun(input: ChargeStreamRunDriverInput): Promise<AnalysisStreamRun>;
  markDone(input: MarkStreamRunDoneInput): Promise<AnalysisStreamRun>;
  markFailed(input: MarkStreamRunFailedInput): Promise<AnalysisStreamRun>;
}

export class AnalysisStreamRunStore {
  constructor(private readonly driver: AnalysisStreamRunDriver) {}

  createPendingRun(
    input: CreatePendingStreamRunInput,
  ): Promise<AnalysisStreamRun> {
    requireNonEmpty(input.userId, "userId");
    requireNonEmpty(input.conversationHash, "conversationHash");
    return this.driver.createPendingRun(input);
  }

  getRun(input: GetStreamRunInput): Promise<AnalysisStreamRun> {
    requireNonEmpty(input.runId, "runId");
    requireNonEmpty(input.userId, "userId");
    requireNonEmpty(input.conversationHash, "conversationHash");
    return this.driver.getRun(input);
  }

  reserveRetry(input: ReserveStreamRetryInput): Promise<AnalysisStreamRun> {
    requireNonEmpty(input.runId, "runId");
    requireNonEmpty(input.userId, "userId");
    requireNonEmpty(input.conversationHash, "conversationHash");
    if (!Number.isInteger(input.maxRetries) || input.maxRetries <= 0) {
      throw new Error("reserveRetry: maxRetries must be a positive integer");
    }
    return this.driver.reserveRetry(input);
  }

  chargeRun(input: ChargeStreamRunInput): Promise<AnalysisStreamRun> {
    requireNonEmpty(input.runId, "runId");
    requireNonEmpty(input.userId, "userId");
    requireNonEmpty(input.conversationHash, "conversationHash");

    if (
      input.chargeQuota &&
      (!Number.isInteger(input.messageCount) || input.messageCount <= 0)
    ) {
      throw new Error(
        "chargeRun: messageCount must be a positive integer when chargeQuota=true",
      );
    }

    if (isNoSendChargePayload(input.recommendation)) {
      return this.driver.chargeRun({
        runId: input.runId,
        userId: input.userId,
        conversationHash: input.conversationHash,
        recommendationJson: serializeNoSendRecommendation(input.recommendation),
        selectedStyle: null,
        decisionKind: input.recommendation.decisionKind,
        chargeQuota: input.chargeQuota,
        messageCount: input.messageCount,
      });
    }

    return this.driver.chargeRun({
      runId: input.runId,
      userId: input.userId,
      conversationHash: input.conversationHash,
      recommendationJson: serializeRecommendation(input.recommendation),
      selectedStyle: input.recommendation.selectedStyle,
      chargeQuota: input.chargeQuota,
      messageCount: input.messageCount,
    });
  }

  markDone(input: MarkStreamRunDoneInput): Promise<AnalysisStreamRun> {
    requireNonEmpty(input.runId, "runId");
    requireNonEmpty(input.userId, "userId");
    requireNonEmpty(input.conversationHash, "conversationHash");
    return this.driver.markDone(input);
  }

  markFailed(input: MarkStreamRunFailedInput): Promise<AnalysisStreamRun> {
    requireNonEmpty(input.runId, "runId");
    requireNonEmpty(input.userId, "userId");
    requireNonEmpty(input.conversationHash, "conversationHash");
    requireNonEmpty(input.code, "code");
    return this.driver.markFailed(input);
  }
}

function requireNonEmpty(value: string, name: string): string {
  if (!value.trim()) {
    throw new Error(`${name} must be non-empty`);
  }
  return value;
}

function serializeRecommendation(
  recommendation: StreamRecommendationForCharge,
): Record<string, unknown> {
  const analysisDecisionV2 = asRecord(recommendation.analysisDecisionV2);
  const analysisInventory = asRecord(recommendation.analysisInventory);
  const analysisEvidenceLinkage = asRecord(
    recommendation.analysisEvidenceLinkage,
  );
  const analysisDivergencePlan = asRecord(
    recommendation.analysisDivergencePlan,
  );
  return {
    selectedStyle: recommendation.selectedStyle,
    message: recommendation.message,
    reason: recommendation.reason,
    quotedContext: recommendation.quotedContext,
    warnings: recommendation.warnings,
    raw: recommendation.raw,
    ...(analysisDecisionV2 ? { analysisDecisionV2 } : {}),
    ...(analysisInventory ? { analysisInventory } : {}),
    ...(analysisEvidenceLinkage ? { analysisEvidenceLinkage } : {}),
    ...(analysisDivergencePlan ? { analysisDivergencePlan } : {}),
  };
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

interface DbResult<T> {
  data: T | null;
  error: unknown;
}

interface SupabaseSingleBuilder<T> {
  single(): Promise<DbResult<T>>;
  maybeSingle(): Promise<DbResult<T>>;
}

interface SupabaseSelectBuilder<T> {
  select(cols?: string): SupabaseSingleBuilder<T>;
}

interface SupabaseFilterBuilder<T> {
  eq(col: string, val: string): SupabaseFilterBuilder<T>;
  single(): Promise<DbResult<T>>;
  maybeSingle(): Promise<DbResult<T>>;
  select(cols?: string): SupabaseSingleBuilder<T>;
}

interface MinimalSupabaseClient {
  from(table: string): {
    select(cols?: string): SupabaseFilterBuilder<AnalysisStreamRun>;
    insert(
      values: Record<string, unknown>,
    ): SupabaseSelectBuilder<AnalysisStreamRun>;
    update(
      values: Record<string, unknown>,
    ): SupabaseFilterBuilder<AnalysisStreamRun>;
  };
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): Promise<DbResult<AnalysisStreamRun>>;
}

export function createSupabaseAnalysisStreamRunDriver(
  supabase: MinimalSupabaseClient,
): AnalysisStreamRunDriver {
  return {
    async createPendingRun(
      input: CreatePendingStreamRunInput,
    ): Promise<AnalysisStreamRun> {
      const { data, error } = await supabase
        .from("analysis_stream_runs")
        .insert({
          user_id: input.userId,
          conversation_hash: input.conversationHash,
          status: "pending",
          retry_count: 0,
          request_context: input.requestContext ?? null,
        })
        .select("*")
        .single();
      if (error || !data) {
        throw new Error(
          `analysis_stream_runs insert failed: ${
            error ? JSON.stringify(error) : "no row returned"
          }`,
        );
      }
      return data;
    },

    async getRun(input: GetStreamRunInput): Promise<AnalysisStreamRun> {
      const { data, error } = await supabase
        .from("analysis_stream_runs")
        .select("*")
        .eq("id", input.runId)
        .eq("user_id", input.userId)
        .eq("conversation_hash", input.conversationHash)
        .maybeSingle();
      if (error || !data) {
        throw new Error(
          `analysis_stream_runs get failed: ${
            error ? JSON.stringify(error) : "no row returned"
          }`,
        );
      }
      return data;
    },

    async reserveRetry(
      input: ReserveStreamRetryInput,
    ): Promise<AnalysisStreamRun> {
      const { data, error } = await supabase.rpc(
        "reserve_stream_analysis_retry",
        {
          p_run_id: input.runId,
          p_user_id: input.userId,
          p_conversation_hash: input.conversationHash,
          p_max_retries: input.maxRetries,
        },
      );
      if (error || !data) {
        throw new Error(
          `reserve_stream_analysis_retry failed: ${
            error ? JSON.stringify(error) : "no row returned"
          }`,
        );
      }
      return data;
    },

    async chargeRun(
      input: ChargeStreamRunDriverInput,
    ): Promise<AnalysisStreamRun> {
      // v1 send runs keep calling the untouched v1 RPC; only a no-send
      // decision uses charge_stream_analysis_run_v2 (migration 20260902120000).
      const { data, error } = input.decisionKind
        ? await supabase.rpc("charge_stream_analysis_run_v2", {
          p_run_id: input.runId,
          p_user_id: input.userId,
          p_conversation_hash: input.conversationHash,
          p_recommendation_json: input.recommendationJson,
          p_decision_kind: input.decisionKind,
          p_selected_style: null,
          p_message_count: input.messageCount,
          p_charge_quota: input.chargeQuota,
        })
        : await supabase.rpc("charge_stream_analysis_run", {
          p_run_id: input.runId,
          p_user_id: input.userId,
          p_conversation_hash: input.conversationHash,
          p_recommendation_json: input.recommendationJson,
          p_selected_style: input.selectedStyle,
          p_message_count: input.messageCount,
          p_charge_quota: input.chargeQuota,
        });
      if (error || !data) {
        throw new Error(
          `${
            input.decisionKind
              ? "charge_stream_analysis_run_v2"
              : "charge_stream_analysis_run"
          } failed: ${error ? JSON.stringify(error) : "no row returned"}`,
        );
      }
      return data;
    },

    async markDone(
      input: MarkStreamRunDoneInput,
    ): Promise<AnalysisStreamRun> {
      const { data, error } = await supabase
        .from("analysis_stream_runs")
        .update({
          status: "done",
          final_result_json: input.finalResult,
          last_error_code: null,
        })
        .eq("id", input.runId)
        .eq("user_id", input.userId)
        .eq("conversation_hash", input.conversationHash)
        .select("*")
        .maybeSingle();
      if (error || !data) {
        throw new Error(
          `analysis_stream_runs mark done failed: ${
            error ? JSON.stringify(error) : "no row returned"
          }`,
        );
      }
      return data;
    },

    async markFailed(
      input: MarkStreamRunFailedInput,
    ): Promise<AnalysisStreamRun> {
      const { data, error } = await supabase
        .from("analysis_stream_runs")
        .update({
          status: "failed",
          last_error_code: input.code,
        })
        .eq("id", input.runId)
        .eq("user_id", input.userId)
        .eq("conversation_hash", input.conversationHash)
        .select("*")
        .maybeSingle();
      if (error || !data) {
        throw new Error(
          `analysis_stream_runs mark failed failed: ${
            error ? JSON.stringify(error) : "no row returned"
          }`,
        );
      }
      return data;
    },
  };
}
