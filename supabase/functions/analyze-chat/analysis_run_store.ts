// analysis_run_store: high-level helpers around the `analysis_runs` table.
//
// Invariants (must remain true; tested in analysis_run_store_test.ts):
//   I1 single charge       → createChargedRun calls create_charged_analysis_run
//      RPC which charges + inserts in one Postgres TX; no client-side rollback
//      window (Codex Phase 0 P1 fix).
//   I2 missing analysisRunId → MISSING_RUN_ID
//   I3 cross-user access    → RUN_FORBIDDEN; reserveRetrySlot also re-checks
//      user_id in SQL WHERE as defense-in-depth (Codex Phase 0 P2 fix).
//   I4 expired run          → RUN_EXPIRED
//   I5 hash mismatch        → RUN_CONVERSATION_MISMATCH; reserveRetrySlot also
//      re-checks conversation_hash in SQL WHERE (Codex Phase 0 P2 fix).
//   I6 retry bound          → RUN_RETRY_EXHAUSTED via reserve_analysis_run_retry
//      v2 RPC (atomic UPDATE WHERE retry_count<3 RETURNING).
//   I8 quick aborted        → RUN_NOT_CHARGED (defensive — atomic RPC makes
//      this state unreachable in production, but the check still pins the
//      invariant in case future code paths regress).

export interface AnalysisRun {
  id: string;
  user_id: string;
  conversation_hash: string;
  charged: boolean;
  quick_result: Record<string, unknown>;
  request_context: Record<string, unknown> | null;
  retry_count: number;
  created_at: string;
  expires_at: string;
  consumed_at: string | null;
}

export interface NewChargedRun {
  userId: string;
  conversationHash: string;
  quickResult: Record<string, unknown>;
  requestContext?: Record<string, unknown>;
  // Test/free-quota accounts pass false to skip increment_usage. The explicit
  // boolean is required (not derived) so the Edge handler's decision logic
  // stays auditable and Codex can grep for callers.
  chargeQuota: boolean;
  // Ignored when chargeQuota=false. Required positive integer otherwise.
  messageCount: number;
}

export interface ReserveInput {
  runId: string;
  userId: string;
  conversationHash: string;
}

export type ValidateError =
  | "MISSING_RUN_ID"
  | "RUN_NOT_FOUND"
  | "RUN_FORBIDDEN"
  | "RUN_NOT_CHARGED"
  | "RUN_EXPIRED"
  | "RUN_CONVERSATION_MISMATCH";

export interface ValidateInput {
  runId: string | null | undefined;
  userId: string;
  conversationHash: string;
}

export type ValidateResult =
  | { ok: true; run: AnalysisRun }
  | { ok: false; error: ValidateError };

export type ReserveResult =
  | { ok: true; run: AnalysisRun }
  | { ok: false; error: "RUN_RETRY_EXHAUSTED" };

// Driver interface — abstract the DB so tests can substitute an in-memory
// implementation. The Supabase-backed driver is created via
// `createSupabaseAnalysisRunDriver(client)` below.
export interface AnalysisRunDriver {
  createChargedRun(input: NewChargedRun): Promise<AnalysisRun>;
  selectById(id: string): Promise<AnalysisRun | null>;
  delete(id: string): Promise<void>;
  // Atomic reservation. Returns the updated row if a slot was claimed,
  // null otherwise (eligibility failed: not charged / expired / count exhausted
  // / user_id mismatch / conversation_hash mismatch).
  reserveRetrySlot(
    input: ReserveInput,
    maxRetries: number,
  ): Promise<AnalysisRun | null>;
}

export const MAX_FULL_RETRIES = 3;

export class AnalysisRunStore {
  constructor(
    private readonly driver: AnalysisRunDriver,
    private readonly now: () => Date = () => new Date(),
  ) {}

  createChargedRun(input: NewChargedRun): Promise<AnalysisRun> {
    if (input.chargeQuota && (!Number.isInteger(input.messageCount) || input.messageCount <= 0)) {
      // Mirror the DB-side guard so test/store callers fail fast without a
      // network roundtrip. The DB also RAISE EXCEPTIONs in this case.
      throw new Error(
        "createChargedRun: messageCount must be a positive integer when chargeQuota=true",
      );
    }
    return this.driver.createChargedRun(input);
  }

  // Test/cleanup helper. Not part of the normal quick/full flow — atomic RPC
  // means we no longer roll back via delete on quota RPC failure.
  deleteRun(id: string): Promise<void> {
    return this.driver.delete(id);
  }

  async validateRunForFull(input: ValidateInput): Promise<ValidateResult> {
    const runId = (input.runId ?? "").trim();
    if (!runId) return { ok: false, error: "MISSING_RUN_ID" };

    const run = await this.driver.selectById(runId);
    if (!run) return { ok: false, error: "RUN_NOT_FOUND" };

    // Security check FIRST so cross-user requests never see state.
    if (run.user_id !== input.userId) {
      return { ok: false, error: "RUN_FORBIDDEN" };
    }

    if (!run.charged) {
      // Defensive: with the atomic RPC, the row can't exist without charged=true.
      // Kept as a backstop in case future code paths regress.
      return { ok: false, error: "RUN_NOT_CHARGED" };
    }

    if (new Date(run.expires_at).getTime() <= this.now().getTime()) {
      return { ok: false, error: "RUN_EXPIRED" };
    }

    if (run.conversation_hash !== input.conversationHash) {
      return { ok: false, error: "RUN_CONVERSATION_MISMATCH" };
    }

    return { ok: true, run };
  }

  async reserveRetrySlot(input: ReserveInput): Promise<ReserveResult> {
    const updated = await this.driver.reserveRetrySlot(input, MAX_FULL_RETRIES);
    if (!updated) return { ok: false, error: "RUN_RETRY_EXHAUSTED" };
    return { ok: true, run: updated };
  }
}

// -----------------------------------------------------------------------------
// Supabase-backed driver. Kept thin: this file is unit-tested via the
// in-memory driver; the real DB roundtrip is covered by Phase 1 integration
// tests.
//
// The supabase-js client passed in MUST be created with the service_role key
// (the RLS policy on analysis_runs grants only service_role; the two RPCs
// REVOKE PUBLIC + GRANT service_role only).
// -----------------------------------------------------------------------------

interface MinimalSupabaseClient {
  from(table: string): {
    select(cols?: string): {
      eq(col: string, val: string): {
        maybeSingle(): Promise<{ data: AnalysisRun | null; error: unknown }>;
      };
    };
    delete(): {
      eq(col: string, val: string): Promise<{ error: unknown }>;
    };
  };
  rpc(
    fn: string,
    args: unknown,
  ): Promise<{ data: AnalysisRun | null; error: unknown }>;
}

export function createSupabaseAnalysisRunDriver(
  supabase: MinimalSupabaseClient,
): AnalysisRunDriver {
  return {
    async createChargedRun(input: NewChargedRun): Promise<AnalysisRun> {
      const { data, error } = await supabase.rpc(
        "create_charged_analysis_run",
        {
          p_user_id: input.userId,
          p_conversation_hash: input.conversationHash,
          p_quick_result: input.quickResult,
          p_request_context: input.requestContext ?? null,
          p_charge_quota: input.chargeQuota,
          p_message_count: input.messageCount,
        },
      );
      if (error || !data) {
        throw new Error(
          `create_charged_analysis_run failed: ${
            error ? JSON.stringify(error) : "no row returned"
          }`,
        );
      }
      return data;
    },

    async selectById(id: string): Promise<AnalysisRun | null> {
      const { data, error } = await supabase
        .from("analysis_runs")
        .select("*")
        .eq("id", id)
        .maybeSingle();
      if (error) {
        throw new Error(
          `analysis_runs select failed: ${JSON.stringify(error)}`,
        );
      }
      return data ?? null;
    },

    async delete(id: string): Promise<void> {
      const { error } = await supabase
        .from("analysis_runs")
        .delete()
        .eq("id", id);
      if (error) {
        throw new Error(`analysis_runs delete failed: ${JSON.stringify(error)}`);
      }
    },

    async reserveRetrySlot(
      input: ReserveInput,
      maxRetries: number,
    ): Promise<AnalysisRun | null> {
      const { data, error } = await supabase.rpc("reserve_analysis_run_retry", {
        p_run_id: input.runId,
        p_user_id: input.userId,
        p_conversation_hash: input.conversationHash,
        p_max_retries: maxRetries,
      });
      if (error) {
        throw new Error(
          `reserve_analysis_run_retry failed: ${JSON.stringify(error)}`,
        );
      }
      return data ?? null;
    },
  };
}
