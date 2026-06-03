// stream_run_store: data-access boundary for full streaming analyze runs.
//
// This intentionally uses a dedicated `analysis_stream_runs` table instead of
// the older two-stage `analysis_runs` table. The two lifecycles have different
// charge/resume semantics, and keeping them separate protects the live quota
// path while streaming is dogfooded.

import type { StreamRecommendationForCharge } from "./reframer.ts";
import type { StreamStyle } from "./stream_events.ts";

export type AnalysisStreamRunStatus = "pending" | "charged" | "done" | "failed";

export interface AnalysisStreamRun {
  id: string;
  user_id: string;
  conversation_hash: string;
  status: AnalysisStreamRunStatus;
  selected_style: StreamStyle | null;
  recommendation_json: Record<string, unknown> | null;
  final_result_json: Record<string, unknown> | null;
  charged_at: string | null;
  last_error_code: string | null;
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
  recommendation: StreamRecommendationForCharge;
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

export interface ChargeStreamRunDriverInput {
  runId: string;
  userId: string;
  conversationHash: string;
  recommendationJson: Record<string, unknown>;
  selectedStyle: StreamStyle;
  chargeQuota: boolean;
  messageCount: number;
}

export interface AnalysisStreamRunDriver {
  createPendingRun(
    input: CreatePendingStreamRunInput,
  ): Promise<AnalysisStreamRun>;
  getRun(input: GetStreamRunInput): Promise<AnalysisStreamRun>;
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
  return {
    selectedStyle: recommendation.selectedStyle,
    message: recommendation.message,
    reason: recommendation.reason,
    quotedContext: recommendation.quotedContext,
    warnings: recommendation.warnings,
    raw: recommendation.raw,
  };
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

    async chargeRun(
      input: ChargeStreamRunDriverInput,
    ): Promise<AnalysisStreamRun> {
      const { data, error } = await supabase.rpc(
        "charge_stream_analysis_run",
        {
          p_run_id: input.runId,
          p_user_id: input.userId,
          p_conversation_hash: input.conversationHash,
          p_recommendation_json: input.recommendationJson,
          p_selected_style: input.selectedStyle,
          p_message_count: input.messageCount,
          p_charge_quota: input.chargeQuota,
        },
      );
      if (error || !data) {
        throw new Error(
          `charge_stream_analysis_run failed: ${
            error ? JSON.stringify(error) : "no row returned"
          }`,
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
