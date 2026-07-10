// practice-chat draw_profile handler（自包含、可用 mock supabase client 測 RPC 行為）。
//
// 與 chat/debrief 完全隔離：不碰 practice_chat_sessions ledger、不需要 DEEPSEEK_API_KEY、
// 不呼叫 DeepSeek。流程：讀訂閱 → apply resets(UTC) + persist → 算 tier 額度/限額 →
// 查全歷史已抽 profile（永久去重；池抽滿降級回本窗排除）→ server 選候選 →
// 呼叫 claim_practice_profile_draw RPC（原子扣費 +
// idempotent）→ 映射 402/429/200。
//
// 回傳 { body, status }（不碰 HTTP/CORS）由 index.ts 包成 Response，藉此：
//   1. 避免與 index.ts 循環 import。
//   2. 整個 handler 可用 mock client 單元測試（無需起 HTTP / 真 Supabase）。
//
// 為何 self-contained 讀訂閱（而非沿用 index.ts 的 sub）：保持 chat/debrief 路徑 byte-
// for-byte 不動（純加法 dispatch），且讓 RPC 鎖內讀到的是 persist 後的 reset 計數。

import {
  applyResetsIfNeeded,
  buildQuotaExceededPayload,
  normalizeTier,
  resolveLimits,
  type SubscriptionRow,
  TEST_EMAILS,
} from "../_shared/quota.ts";
import {
  drawAllowanceForTier,
  paidExtraDrawAllowedForTier,
  PRACTICE_DRAW_EXTRA_COST,
  taipeiNoonResetWindow,
} from "./draw_decision.ts";
import {
  getPracticeGirlProfile,
  hasEligibleDrawCandidate,
  type PracticeGirlProfile,
  selectPracticeDrawProfile,
} from "./practice_persona.ts";
import type { PracticeDrawRequest } from "./validate.ts";
import { logError, logWarn, summarizeUser } from "./logger.ts";

// 撞號（同窗同 profile）時換一張重抽的上限。理論上不會用到（每窗抽數 << catalog 總數）。
const MAX_DRAW_SELECT_ATTEMPTS = 3;

// ── 最小 supabase client 介面（真 client 結構上即滿足；test 注入 mock）──────────
type Row = Record<string, unknown>;
export interface PostgrestResult<T> {
  data: T | null;
  error: { message: string } | null;
}
export interface DrawFilterBuilder extends PromiseLike<PostgrestResult<Row[]>> {
  eq(column: string, value: unknown): DrawFilterBuilder;
  maybeSingle(): PromiseLike<PostgrestResult<Row>>;
}
export interface DrawSupabaseClient {
  from(table: string): {
    select(columns: string): DrawFilterBuilder;
    update(values: Row): DrawFilterBuilder;
  };
  rpc(fn: string, params: Row): PromiseLike<PostgrestResult<unknown>>;
}

// claim_practice_profile_draw RPC 回傳（jsonb）形狀。
interface DrawReceipt {
  profile_id: string;
  cost_messages: number;
  free_allowance: number;
  free_used: number;
  free_remaining: number;
  daily_messages_used: number;
  monthly_messages_used: number;
  idempotent_replay?: boolean;
}

export interface DrawHandlerArgs {
  supabase: DrawSupabaseClient;
  userId: string;
  userEmail: string | null;
  request: PracticeDrawRequest;
  now: Date;
}

export interface DrawHandlerResult {
  body: unknown;
  status: number;
}

export async function handleDrawProfile(
  args: DrawHandlerArgs,
): Promise<DrawHandlerResult> {
  const { supabase, userId, userEmail, request, now } = args;

  // ── 1. 讀訂閱 ──────────────────────────────────────────────────────────
  const { data: subRow, error: subError } = await supabase
    .from("subscriptions")
    .select(
      "tier, monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at",
    )
    .eq("user_id", userId)
    .maybeSingle();
  if (subError) {
    logWarn("practice_draw_sub_fetch_error", {
      user: summarizeUser(userId),
      error: subError.message,
    });
    return { body: { error: "subscription_fetch_failed" }, status: 500 };
  }
  if (!subRow) {
    return { body: { error: "No subscription found" }, status: 403 };
  }

  // ── 2. apply resets(UTC) + persist（RPC 鎖內讀的是 persist 後計數）─────────
  let sub = subRow as unknown as SubscriptionRow;
  const reset = applyResetsIfNeeded(sub, now);
  sub = reset.sub;
  if (reset.dailyReset || reset.monthlyReset) {
    const { error: persistError } = await supabase
      .from("subscriptions")
      .update({
        daily_messages_used: sub.daily_messages_used,
        monthly_messages_used: sub.monthly_messages_used,
        daily_reset_at: sub.daily_reset_at,
        monthly_reset_at: sub.monthly_reset_at,
      })
      .eq("user_id", userId);
    if (persistError) {
      logWarn("practice_draw_reset_persist_error", {
        user: summarizeUser(userId),
        error: persistError.message,
      });
      return { body: { error: "subscription_fetch_failed" }, status: 500 };
    }
  }

  // ── 3. tier → 免費額度 / 是否可付費額外 / 限額 / 測試帳號 / reset window ─────
  const tier = normalizeTier(sub.tier);
  const accountIsTest = TEST_EMAILS.includes(userEmail ?? "");
  const limits = resolveLimits(tier);
  const freeAllowance = drawAllowanceForTier(tier);
  const allowPaidExtra = paidExtraDrawAllowedForTier(tier);
  const window = taipeiNoonResetWindow(now);

  // ── 4. 查已抽 profiles：全歷史（永久去重）＋本窗（池抽滿降級用）──────────
  // 表是 per-user 抽卡事件（每窗抽數個位數），全撈無效能疑慮。reset_window_start_at
  // 以 Date 解析比對，不做字串比對（PostgREST timestamptz 格式與 toISOString 不同）。
  const { data: drawnRows, error: drawnError } = await supabase
    .from("practice_profile_draw_events")
    .select("profile_id, reset_window_start_at")
    .eq("user_id", userId);
  if (drawnError) {
    logWarn("practice_draw_events_fetch_error", {
      user: summarizeUser(userId),
      error: drawnError.message,
    });
    return { body: { error: "draw_failed" }, status: 500 };
  }
  const windowStartMs = new Date(window.resetWindowStartAt).getTime();
  const permanentExcluded = new Set<string>();
  const windowExcluded = new Set<string>();
  for (const r of drawnRows ?? []) {
    const id = String(r.profile_id);
    permanentExcluded.add(id);
    if (new Date(String(r.reset_window_start_at)).getTime() === windowStartMs) {
      windowExcluded.add(id);
    }
  }

  // 永久去重把切池抽滿 → 降級回現行「當日視窗排除」（允許跨窗重複收藏過的角色），
  // 絕不讓抽卡因無候選而失敗。降級與否都用同一個 excluded 集合走選牌＋撞號重抽。
  let excluded = permanentExcluded;
  if (
    !hasEligibleDrawCandidate({
      currentProfileId: request.currentProfileId,
      excludedProfileIds: permanentExcluded,
      catalogSize: request.catalogSize,
    })
  ) {
    logWarn("practice_draw_dedup_fallback", {
      user: summarizeUser(userId),
      drawnCount: permanentExcluded.size,
    });
    excluded = windowExcluded;
  }

  // ── 5. 選候選 + 呼叫 RPC（撞號重抽，最多 3 次）─────────────────────────
  // catalogSize（client 宣告的 catalog 人數）只影響「新抽」的候選切池，刻意不進
  // 冪等識別：RPC 以 (user, requestId) 去重，replay 一律回 ledger 上原本抽到的
  // profile_id（下方 getPracticeGirlProfile 反查全 catalog），與本地候選無關。
  // 因此部署邊界上舊 client 的 in-flight retry（同 requestId、無 catalogSize）
  // 仍命中原 receipt，不會因新欄位缺席而失效或換人。
  for (let attempt = 0; attempt < MAX_DRAW_SELECT_ATTEMPTS; attempt++) {
    const candidate = selectPracticeDrawProfile({
      currentProfileId: request.currentProfileId,
      excludedProfileIds: excluded,
      seed: `${userId}:${request.requestId}:${window.resetWindowStartAt}:${attempt}`,
      catalogSize: request.catalogSize,
    });

    const { data: rpcData, error: rpcError } = await supabase.rpc(
      "claim_practice_profile_draw",
      {
        p_user_id: userId,
        p_request_id: request.requestId,
        p_profile_id: candidate.profileId,
        p_reset_window_start_at: window.resetWindowStartAt,
        p_tier: tier,
        p_free_allowance: freeAllowance,
        p_extra_cost: PRACTICE_DRAW_EXTRA_COST,
        p_allow_paid_extra: allowPaidExtra,
        p_daily_limit: limits.daily,
        p_monthly_limit: limits.monthly,
        p_charge_quota: !accountIsTest,
      },
    );

    if (rpcError) {
      const msg = rpcError.message ?? "";
      if (msg.includes("PRACTICE_DRAW_PROFILE_CONFLICT")) {
        excluded.add(candidate.profileId); // 換一張重抽
        continue;
      }
      return mapDrawRpcError(msg, {
        freeAllowance,
        allowPaidExtra,
        sub,
        limits,
        nextResetAt: window.nextResetAt,
        userId,
      });
    }

    const receipt =
      (Array.isArray(rpcData) ? rpcData[0] : rpcData) as DrawReceipt | null;
    if (!receipt || typeof receipt.profile_id !== "string") {
      logError("practice_draw_empty_receipt", { user: summarizeUser(userId) });
      return { body: { error: "draw_failed" }, status: 500 };
    }

    // idempotent replay 時 RPC 回的是「原本抽到的」profile_id；一律以它反查同一位，
    // 不可用本地重選的 candidate（否則 replay 會回到別人）。
    const girl = getPracticeGirlProfile(receipt.profile_id) ?? candidate;
    return {
      body: buildDrawResponseBody(
        girl,
        receipt,
        window.nextResetAt,
        limits,
        allowPaidExtra,
      ),
      status: 200,
    };
  }

  // 連續撞號耗盡（理論上不可達）。
  logError("practice_draw_profile_conflict_exhausted", {
    user: summarizeUser(userId),
  });
  return { body: { error: "draw_failed" }, status: 500 };
}

function mapDrawRpcError(
  message: string,
  ctx: {
    freeAllowance: number;
    allowPaidExtra: boolean;
    sub: SubscriptionRow;
    limits: { monthly: number; daily: number };
    nextResetAt: string;
    userId: string;
  },
): DrawHandlerResult {
  // Free 免費用完 → 402 導付費牆（draw payload 連動文案）。
  if (message.includes("PRACTICE_DRAW_UPGRADE_REQUIRED")) {
    return {
      status: 402,
      body: {
        error: "practice_draw_upgrade_required",
        message: "升級後每天可以翻更多陪練女孩。",
        draw: {
          freeAllowance: ctx.freeAllowance,
          freeUsed: ctx.freeAllowance,
          freeRemaining: 0,
          extraCostMessages: extraCostForPayload(ctx.allowPaidExtra),
          nextResetAt: ctx.nextResetAt,
        },
      },
    };
  }
  // 付費額外抽但 quota 不足 → 沿用既有 429 quota payload（不回 profile、不扣費）。
  if (message.includes("PRACTICE_DRAW_QUOTA_EXCEEDED_MONTHLY")) {
    return {
      status: 429,
      body: buildQuotaExceededPayload({
        sub: ctx.sub,
        cost: PRACTICE_DRAW_EXTRA_COST,
        reason: "monthly_limit_exceeded",
        monthlyLimit: ctx.limits.monthly,
        dailyLimit: ctx.limits.daily,
      }),
    };
  }
  if (message.includes("PRACTICE_DRAW_QUOTA_EXCEEDED_DAILY")) {
    return {
      status: 429,
      body: buildQuotaExceededPayload({
        sub: ctx.sub,
        cost: PRACTICE_DRAW_EXTRA_COST,
        reason: "daily_limit_exceeded",
        monthlyLimit: ctx.limits.monthly,
        dailyLimit: ctx.limits.daily,
      }),
    };
  }
  // PRACTICE_DRAW_NO_SUBSCRIPTION / 其他未預期 → 500 fail-closed。
  logWarn("practice_draw_rpc_error", {
    user: summarizeUser(ctx.userId),
    message,
  });
  return { body: { error: "draw_failed" }, status: 500 };
}

/** draw payload 的加抽宣傳成本：不可付費額外抽的 tier（Free）一律 0，絕不出價。 */
function extraCostForPayload(allowPaidExtra: boolean): number {
  return allowPaidExtra ? PRACTICE_DRAW_EXTRA_COST : 0;
}

function buildDrawResponseBody(
  girl: PracticeGirlProfile,
  receipt: DrawReceipt,
  nextResetAt: string,
  limits: { monthly: number; daily: number },
  allowPaidExtra: boolean,
) {
  return {
    profile: {
      profileId: girl.profileId,
      nameId: girl.nameId,
      professionId: girl.professionId,
      photoId: girl.photoId,
      personaId: girl.personaId,
    },
    draw: {
      costMessages: receipt.cost_messages,
      freeAllowance: receipt.free_allowance,
      freeUsed: receipt.free_used,
      freeRemaining: receipt.free_remaining,
      extraCostMessages: extraCostForPayload(allowPaidExtra),
      nextResetAt,
    },
    usage: {
      monthlyUsed: receipt.monthly_messages_used,
      monthlyLimit: limits.monthly,
      dailyUsed: receipt.daily_messages_used,
      dailyLimit: limits.daily,
    },
  };
}
