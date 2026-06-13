// supabase/functions/analyze-chat/ball_inventory.ts
//
// 球數案硬版：把模型最先 emit 的 `analysis.inventory` 事件解析成可比對的
// disposition map（sourceIndex → 接/併/略）。reframer 保留這份 map，等
// selected reply_option 到貨時用來驗「段只來自接/併球」＋「段數達下限」。
//
// 安全紅線（INV-H4 / INV-H6 / failure matrix）：
//   - 缺席 / 空 / 全略 / 無法解析 → 回傳 null（退回 soft，不驗證，絕不誤殺）。
//   - 寬鬆解析：個別壞掉的 ball 跳過，不讓一顆壞球拖垮整份盤點。

import type { StreamEvent } from "./stream_events.ts";

export type BallDisposition = "接" | "併" | "略";

const BALL_DISPOSITIONS = new Set<string>(["接", "併", "略"]);
const CATCHABLE_DISPOSITIONS = new Set<BallDisposition>(["接", "併"]);

export interface BallInventory {
  // sourceIndex（1-based）→ disposition。只收得到合法 disposition 的球。
  dispositions: Map<number, BallDisposition>;
  // 標 接 或 併 的球數，供下限 min(3, catchableCount) 計算。
  catchableCount: number;
}

export function parseBallInventory(
  event: StreamEvent | Record<string, unknown>,
): BallInventory | null {
  if (!event || event.type !== "analysis.inventory") return null;

  const balls = (event as Record<string, unknown>).balls;
  if (!Array.isArray(balls) || balls.length === 0) return null;

  const dispositions = new Map<number, BallDisposition>();
  let catchableCount = 0;

  for (const ball of balls) {
    if (!ball || typeof ball !== "object") continue;
    const record = ball as Record<string, unknown>;

    const sourceIndex = record.sourceIndex;
    if (typeof sourceIndex !== "number" || !Number.isFinite(sourceIndex)) {
      continue;
    }

    const disposition = record.disposition;
    if (typeof disposition !== "string" || !BALL_DISPOSITIONS.has(disposition)) {
      continue;
    }

    const value = disposition as BallDisposition;
    dispositions.set(sourceIndex, value);
    if (isCatchable(value)) catchableCount += 1;
  }

  // 缺席等義的軟退回：沒有任何可接球（全略或全壞）＝不驗證，絕不誤殺。
  if (catchableCount === 0) return null;

  return { dispositions, catchableCount };
}

export function isCatchable(disposition: BallDisposition): boolean {
  return CATCHABLE_DISPOSITIONS.has(disposition);
}

export type SegmentValidation =
  | { ok: true }
  | { ok: false; reason: string };

// 下限：連發多球時選中風格段數至少 min(3, 可接球數)。真球少於 3 時不可
// 要求超過真球數（failure matrix「2 接 → 2 段 PASS」例外）。
export function segmentFloor(inventory: BallInventory): number {
  return Math.min(3, inventory.catchableCount);
}

// 硬版唯一新增閘：選中風格的 segments 必須
//   (1) 不來自任何標「略」的球（INV-H6 segments ⊆ 接/併）；未在盤點出現的
//       sourceIndex 視為放行（絕不誤殺，盤點可能漏列）。
//   (2) 段數 ≥ segmentFloor（治 (b) inventory→reply 斷層）。
// 不改既有合法 segment 的處理（INV-H5）；只回 ok/理由，reframer 失敗時走
// 既有 STREAM_INCOMPLETE_REPLY_OPTIONS 路徑（INV-H2）。
export function validateSelectedSegments(
  inventory: BallInventory,
  segments: readonly Record<string, unknown>[],
): SegmentValidation {
  for (const segment of segments) {
    const sourceIndex = segment?.sourceIndex;
    if (typeof sourceIndex !== "number" || !Number.isFinite(sourceIndex)) {
      continue; // 段缺合法 sourceIndex：交既有 sanitize 處理，本閘不誤殺。
    }
    if (inventory.dispositions.get(sourceIndex) === "略") {
      return {
        ok: false,
        reason: `選中風格 segment 來自標「略」的球 (sourceIndex=${sourceIndex})`,
      };
    }
  }

  const floor = segmentFloor(inventory);
  if (segments.length < floor) {
    return {
      ok: false,
      reason: `選中風格段數 ${segments.length} 未達下限 ${floor}`,
    };
  }

  return { ok: true };
}

export { BALL_DISPOSITIONS };
