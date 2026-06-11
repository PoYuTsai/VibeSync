// overcharge_claims: ADR #19 定案 #5 — confirmed >2000 扣費的 idempotency。
//
// 設計（Codex r3-P1-3 + 終審「hash 優先」建議）：
//   - client 確認時生成 confirmationId（UUID），連同 payloadHash +
//     billableChars 一起送（confirmedOvercharge）。
//   - server 在通過確認驗證後、實際扣費前，先 claim：
//       "claimed"  → 第一次見到此確認 → 照常扣 20。
//       "replay"   → 同 (user, confirmationId) 且同 payload 已 claim 過
//                    （TTL 內）→ 本次扣 0（上次已扣），分析照常執行。
//                    重送/雙送絕不重扣 20。
//       "mismatch" → 同 confirmationId 但 payload hash 不同（確認後內容
//                    又改過）→ caller 回新的 confirmation_required。
//       "expired"  → 同 payload 但超出 TTL（防 modded client 用舊確認
//                    永久免費重分析）→ caller 回新的 confirmation_required。
//   - 原子性由 Postgres RPC `claim_overcharge_confirmation` 的
//     INSERT ... ON CONFLICT 保證（partial-failure 方向：claim 成功但後續
//     扣費失敗 → 重送走 replay 扣 0 → 用戶往便宜方向錯，與 r2 user-safe
//     哲學一致；絕無「先扣再退」髒狀態）。
//   - RPC 不可用（migration 未套用 / DB 故障）→ caller 必須 fail closed
//     （回 503 不分析不扣費），絕不退化成無 idempotency 的扣費。

export type OverchargeClaimVerdict =
  | "claimed"
  | "replay"
  | "mismatch"
  | "expired";

const CLAIM_VERDICTS: ReadonlySet<string> = new Set([
  "claimed",
  "replay",
  "mismatch",
  "expired",
]);

export interface OverchargeClaimInput {
  userId: string;
  confirmationId: string;
  payloadHash: string;
  billableChars: number;
  chargedUnits: number;
}

export interface OverchargeClaimDriver {
  claim(input: OverchargeClaimInput): Promise<OverchargeClaimVerdict>;
}

const PAYLOAD_HASH_PATTERN = /^[0-9a-f]{64}$/;

export class OverchargeClaimStore {
  constructor(private readonly driver: OverchargeClaimDriver) {}

  claim(input: OverchargeClaimInput): Promise<OverchargeClaimVerdict> {
    // index.ts 已驗證過 request 欄位；這裡是 defense-in-depth（與
    // analysis_run_store.createChargedRun 的 messageCount 防護同模式），
    // 防未來新 caller 繞過驗證打進 DB。
    if (!input.userId || !input.confirmationId) {
      return Promise.reject(
        new Error("overcharge claim: userId and confirmationId are required"),
      );
    }
    if (!PAYLOAD_HASH_PATTERN.test(input.payloadHash)) {
      return Promise.reject(
        new Error("overcharge claim: payloadHash must be 64-char hex"),
      );
    }
    if (!Number.isInteger(input.billableChars) || input.billableChars <= 0) {
      return Promise.reject(
        new Error("overcharge claim: billableChars must be a positive integer"),
      );
    }
    if (!Number.isInteger(input.chargedUnits) || input.chargedUnits <= 0) {
      return Promise.reject(
        new Error("overcharge claim: chargedUnits must be a positive integer"),
      );
    }
    return this.driver.claim(input);
  }
}

// -----------------------------------------------------------------------------
// Supabase-backed driver（service_role only，同 analysis_run_store 模式）。
// -----------------------------------------------------------------------------

interface MinimalSupabaseRpcClient {
  rpc(
    fn: string,
    args: unknown,
  ): Promise<{ data: unknown; error: unknown }>;
}

export function createSupabaseOverchargeClaimDriver(
  supabase: MinimalSupabaseRpcClient,
): OverchargeClaimDriver {
  return {
    async claim(
      input: OverchargeClaimInput,
    ): Promise<OverchargeClaimVerdict> {
      const { data, error } = await supabase.rpc(
        "claim_overcharge_confirmation",
        {
          p_user_id: input.userId,
          p_confirmation_id: input.confirmationId,
          p_payload_hash: input.payloadHash,
          p_billable_chars: input.billableChars,
          p_charged_units: input.chargedUnits,
        },
      );
      if (error) {
        throw new Error(
          `claim_overcharge_confirmation failed: ${JSON.stringify(error)}`,
        );
      }
      if (typeof data !== "string" || !CLAIM_VERDICTS.has(data)) {
        throw new Error(
          `claim_overcharge_confirmation returned unexpected verdict: ${
            JSON.stringify(data)
          }`,
        );
      }
      return data as OverchargeClaimVerdict;
    },
  };
}
