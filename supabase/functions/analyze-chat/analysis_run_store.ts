// analysis_run_store: high-level helpers around the `analysis_runs` table.
// Invariants (must remain true; tested in analysis_run_store_test.ts):
//   I2 missing analysisRunId → MISSING_RUN_ID
//   I3 cross-user access    → RUN_FORBIDDEN (must fire BEFORE state-revealing
//      errors so attackers can't probe foreign run state)
//   I4 expired run          → RUN_EXPIRED
//   I5 hash mismatch        → RUN_CONVERSATION_MISMATCH
//   I6 retry bound          → RUN_RETRY_EXHAUSTED via reserveRetrySlot (atomic
//      UPDATE WHERE retry_count<3 RETURNING — see migration smoke note in the
//      plan; in-memory driver in tests proves the contract)
//   I8 quick aborted        → RUN_NOT_CHARGED (uncharged runs can't be used by
//      full path; otherwise client could grab free analysis by racing quick)

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

export interface NewRun {
  userId: string;
  conversationHash: string;
  quickResult: Record<string, unknown>;
  requestContext?: Record<string, unknown>;
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
  insert(row: NewRun): Promise<AnalysisRun>;
  selectById(id: string): Promise<AnalysisRun | null>;
  markCharged(id: string): Promise<void>;
  delete(id: string): Promise<void>;
  // Atomic reservation. Returns the updated row if a slot was claimed,
  // null otherwise (eligibility failed: not charged / expired / count exhausted).
  reserveRetrySlot(id: string, maxRetries: number): Promise<AnalysisRun | null>;
}

export const MAX_FULL_RETRIES = 3;

export class AnalysisRunStore {
  constructor(
    private readonly driver: AnalysisRunDriver,
    private readonly now: () => Date = () => new Date(),
  ) {}

  createRun(input: NewRun): Promise<AnalysisRun> {
    return this.driver.insert(input);
  }

  markCharged(id: string): Promise<void> {
    return this.driver.markCharged(id);
  }

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
      // Quick succeeded inserting the row but markCharged didn't land (quota
      // RPC crashed, edge function timed out). Client must restart from quick.
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

  async reserveRetrySlot(id: string): Promise<ReserveResult> {
    const updated = await this.driver.reserveRetrySlot(id, MAX_FULL_RETRIES);
    if (!updated) return { ok: false, error: "RUN_RETRY_EXHAUSTED" };
    return { ok: true, run: updated };
  }
}

// -----------------------------------------------------------------------------
// Supabase-backed driver. Kept thin: this file is unit-tested via the in-memory
// driver; the real DB roundtrip is covered by Phase 1 integration tests.
//
// The supabase-js client passed in MUST be created with the service_role key
// (the RLS policy on analysis_runs grants only service_role).
// -----------------------------------------------------------------------------

interface MinimalSupabaseClient {
  from(table: string): {
    insert(row: unknown): {
      select(): {
        single(): Promise<{ data: AnalysisRun | null; error: unknown }>;
      };
    };
    select(cols?: string): {
      eq(col: string, val: string): {
        maybeSingle(): Promise<{ data: AnalysisRun | null; error: unknown }>;
      };
    };
    update(patch: unknown): {
      eq(col: string, val: string): Promise<{ error: unknown }>;
    };
    delete(): {
      eq(col: string, val: string): Promise<{ error: unknown }>;
    };
  };
  rpc(fn: string, args: unknown): Promise<{ data: AnalysisRun | null; error: unknown }>;
}

export function createSupabaseAnalysisRunDriver(
  supabase: MinimalSupabaseClient,
): AnalysisRunDriver {
  return {
    async insert(row: NewRun): Promise<AnalysisRun> {
      const { data, error } = await supabase
        .from("analysis_runs")
        .insert({
          user_id: row.userId,
          conversation_hash: row.conversationHash,
          quick_result: row.quickResult,
          request_context: row.requestContext ?? null,
        })
        .select()
        .single();
      if (error || !data) {
        throw new Error(
          `analysis_runs insert failed: ${
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
        throw new Error(`analysis_runs select failed: ${JSON.stringify(error)}`);
      }
      return data ?? null;
    },

    async markCharged(id: string): Promise<void> {
      const { error } = await supabase
        .from("analysis_runs")
        .update({ charged: true })
        .eq("id", id);
      if (error) {
        throw new Error(`analysis_runs markCharged failed: ${JSON.stringify(error)}`);
      }
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
      id: string,
      maxRetries: number,
    ): Promise<AnalysisRun | null> {
      // Delegates the atomic UPDATE ... WHERE retry_count < $max RETURNING *
      // to a SQL function added by the Phase 1 migration. Using an RPC keeps
      // the row-level CAS in Postgres rather than racing here via supabase-js.
      const { data, error } = await supabase.rpc("reserve_analysis_run_retry", {
        p_run_id: id,
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
