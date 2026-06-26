// practice-chat 每日翻牌決策（純函式、零副作用、可 deno test）。
//
// 安全模型：tier→免費額度/是否可付費額外/限額 全部算在 Edge（_shared/quota.ts 為
// tier 正規化單一真實來源），再把結果傳給 claim_practice_profile_draw RPC。RPC 不重
// 算 tier 邏輯，避免 DB 與 Edge 兩處數字漂移（RPC 僅做原子扣費/idempotent）。
//
// 規則（見 docs/superpowers/specs/2026-06-26-practice-card-draw-design.md）：
//   每日免費翻牌：Free 1 / Starter 3 / Essential 5。
//   免費用完：Free 不開放額外（導升級）；Starter/Essential 每次額外扣 5 則一般 quota。
//   重置點：Asia/Taipei 中午 12:00（UTC+8 無 DST → 對應 04:00 UTC）。

import { normalizeTier } from "../_shared/quota.ts";

/** 額外翻牌固定成本（鎖死 5，與 ledger CHECK cost_messages IN (0,5) 一致）。 */
export const PRACTICE_DRAW_EXTRA_COST = 5;

/** 每日免費翻牌額度（依 tier）。 */
export const PRACTICE_DRAW_FREE_ALLOWANCE = {
  free: 1,
  starter: 3,
  essential: 5,
} as const;

/** 該 tier 每日免費翻牌次數。未知/缺 tier 一律 normalizeTier→free（fail-closed 到 1）。 */
export function drawAllowanceForTier(tier: string | null | undefined): number {
  return PRACTICE_DRAW_FREE_ALLOWANCE[normalizeTier(tier)];
}

/** 免費用完後是否可付費額外翻牌。Free 不可（導升級）；starter/essential 可。 */
export function paidExtraDrawAllowedForTier(
  tier: string | null | undefined,
): boolean {
  return normalizeTier(tier) !== "free";
}

const DAY_MS = 24 * 60 * 60 * 1000;
const TAIPEI_OFFSET_MS = 8 * 60 * 60 * 1000; // UTC+8，台灣無 DST。

/**
 * 以 Asia/Taipei 中午 12:00 為每日重置點，回傳本視窗起點與下一次重置點（皆 ISO UTC）。
 *
 *   現在 Taipei 時間 >= 今日 12:00 → windowStart = 今日 12:00（Taipei）
 *   現在 Taipei 時間 <  今日 12:00 → windowStart = 昨日 12:00（Taipei）
 *   nextResetAt = windowStart + 24h
 *
 * 中午 12:00 Taipei = 04:00 UTC，故回傳的 ISO 會是 ...T04:00:00.000Z。
 */
export function taipeiNoonResetWindow(
  now: Date,
): { resetWindowStartAt: string; nextResetAt: string } {
  // 位移成 Taipei 牆鐘，再以 UTC 欄位讀出 Taipei 的 年/月/日/時。
  const taipei = new Date(now.getTime() + TAIPEI_OFFSET_MS);
  const y = taipei.getUTCFullYear();
  const m = taipei.getUTCMonth();
  const d = taipei.getUTCDate();
  const hour = taipei.getUTCHours();

  // 今日 12:00 Taipei 對應的 UTC 瞬間 = Date.UTC(y,m,d,12) - 8h。
  let windowStartMs = Date.UTC(y, m, d, 12, 0, 0, 0) - TAIPEI_OFFSET_MS;
  if (hour < 12) {
    windowStartMs -= DAY_MS; // 未過中午 → 視窗從昨日中午起。
  }
  const nextResetMs = windowStartMs + DAY_MS;

  return {
    resetWindowStartAt: new Date(windowStartMs).toISOString(),
    nextResetAt: new Date(nextResetMs).toISOString(),
  };
}
