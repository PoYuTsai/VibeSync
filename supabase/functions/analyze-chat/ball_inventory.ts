// supabase/functions/analyze-chat/ball_inventory.ts
//
// 球數案硬版：把模型最先 emit 的 `analysis.inventory` 事件解析成可比對的
// disposition map（sourceIndex → 接/併/略）。reframer 保留這份 map，等
// 每個 reply_option 到貨時觀測獨立接球的 exact source coverage。
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
  // 標 接 或 併 的可用內容數；用來判斷是否存在可驗證盤點。
  catchableCount: number;
  // 只有「接」是獨立 conversational move；「併」只提供同一球的上下文。
  independentCount: number;
}

export function parseBallInventory(
  event: StreamEvent | Record<string, unknown>,
): BallInventory | null {
  if (!event || event.type !== "analysis.inventory") return null;

  const balls = (event as Record<string, unknown>).balls;
  if (!Array.isArray(balls) || balls.length === 0) return null;

  const dispositions = new Map<number, BallDisposition>();
  for (const ball of balls) {
    if (!ball || typeof ball !== "object") continue;
    const record = ball as Record<string, unknown>;

    const sourceIndex = record.sourceIndex;
    if (typeof sourceIndex !== "number" || !Number.isFinite(sourceIndex)) {
      continue;
    }

    const disposition = record.disposition;
    if (
      typeof disposition !== "string" || !BALL_DISPOSITIONS.has(disposition)
    ) {
      continue;
    }

    const value = disposition as BallDisposition;
    dispositions.set(sourceIndex, value);
  }

  // sourceIndex 是盤點主鍵。模型偶爾可能重複列同一索引，inventory count 以
  // 去重後的最終 disposition 計算，避免同一顆球被灌成多顆。
  const dispositionValues = [...dispositions.values()];
  const catchableCount = dispositionValues.filter(isCatchable).length;
  const independentCount = dispositionValues.filter((value) => value === "接")
    .length;

  // 缺席等義的軟退回：沒有任何可接球（全略或全壞）＝不驗證，絕不誤殺。
  if (catchableCount === 0) return null;

  return { dispositions, catchableCount, independentCount };
}

export function isCatchable(disposition: BallDisposition): boolean {
  return CATCHABLE_DISPOSITIONS.has(disposition);
}

export type SegmentValidation =
  | { ok: true }
  | { ok: false; reason: string };

// Validate only source semantics. Coverage count is determined by the
// inventory's independent moves and compared across options by the reframer;
// there is deliberately no minimum-three floor here. The caller keeps this
// validation fail-soft and log-only so malformed model output never blocks a
// usable option or triggers a retry.
export function validateReplySegments(
  inventory: BallInventory,
  segments: readonly Record<string, unknown>[],
): SegmentValidation {
  const seenIndependentSources = new Set<number>();
  for (const segment of segments) {
    const sourceIndex = segment?.sourceIndex;
    if (typeof sourceIndex !== "number" || !Number.isFinite(sourceIndex)) {
      continue; // 段缺合法 sourceIndex：交既有 sanitize 處理，本閘不誤殺。
    }
    const disposition = inventory.dispositions.get(sourceIndex);
    if (disposition === "略") {
      return {
        ok: false,
        reason: `segment 來自標「略」的球 (sourceIndex=${sourceIndex})`,
      };
    }
    if (disposition === "併") {
      return {
        ok: false,
        reason: `segment 把標「併」的背景獨立成段 (sourceIndex=${sourceIndex})`,
      };
    }
    if (disposition === "接") {
      if (seenIndependentSources.has(sourceIndex)) {
        return {
          ok: false,
          reason: `segment 重複獨立 conversational move (sourceIndex=${sourceIndex})`,
        };
      }
      seenIndependentSources.add(sourceIndex);
    }
  }
  return { ok: true };
}

// Return independent source indices in the option's authored order. Duplicates
// remain visible so exact coverage telemetry can flag count/order drift rather
// than silently treating repeated segments as a valid set.
export function independentMoveSourceIndices(
  inventory: BallInventory,
  segments: readonly Record<string, unknown>[],
): number[] {
  return segments.flatMap((segment) => {
    const sourceIndex = segment?.sourceIndex;
    if (typeof sourceIndex !== "number" || !Number.isFinite(sourceIndex)) {
      return [];
    }
    return inventory.dispositions.get(sourceIndex) === "接" ? [sourceIndex] : [];
  });
}

// 一個 option 的 segments 實際覆蓋到哪些「接」球（去重、盤點外索引不算）。
// 與 exact coverage telemetry 共用同一份 independent source 定義。
export function coveredIndependentBalls(
  inventory: BallInventory,
  segments: readonly Record<string, unknown>[],
): Set<number> {
  const covered = new Set<number>();
  for (const segment of segments) {
    const sourceIndex = segment?.sourceIndex;
    if (typeof sourceIndex !== "number" || !Number.isFinite(sourceIndex)) {
      continue;
    }
    if (inventory.dispositions.get(sourceIndex) === "接") {
      covered.add(sourceIndex);
    }
  }
  return covered;
}

export { BALL_DISPOSITIONS };
