// supabase/functions/analyze-chat/ball_inventory.ts
//
// 球數案硬版：把模型最先 emit 的 `analysis.inventory` 事件解析成可比對的
// disposition map（sourceIndex → 接/併/略）。reframer 保留這份 map，等
// selected reply_option 到貨時用來驗「段只以獨立接球為主來源」＋「段數達下限」。
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
  // 只有「接」是獨立真球；「併」只提供同一球的上下文，不增加段數下限。
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

  // sourceIndex 是盤點主鍵。模型偶爾可能重複列同一索引，段數下限只能以
  // 去重後的最終 disposition 計算，否則同一顆球會被灌成多顆。
  const dispositionValues = [...dispositions.values()];
  const catchableCount = dispositionValues.filter(isCatchable).length;
  const independentCount = dispositionValues.filter((value) => value === "接")
    .length;

  // 缺席等義的軟退回：沒有任何可接球（全略或全壞）＝不驗證，絕不誤殺。
  if (catchableCount === 0) return null;

  return { dispositions, catchableCount, independentCount };
}

/// 觀測用的盤點快照（Phase 0）：把模型實際列出的球連同原句與理由留在結果裡，
/// 讓「這一次為什麼這樣接」事後追得回來。目前只寫入 finalResult，不影響任何
/// 生成或守門行為。
///
/// 與 parseBallInventory 是刻意分開的兩件事，不可合併：
///   - parseBallInventory 產的是「驗證用」disposition map，全略／全壞時回 null
///     退回 soft、不驗證（INV-H4 絕不誤殺）。
///   - 這裡產的是「觀測用」原樣紀錄：全略正是最值得被看見的訊號（冷局），
///     不能跟著消失；個別欄位壞掉只略過該欄，不整份丟掉。
export const INVENTORY_BALL_LIMIT = 40;
const INVENTORY_TEXT_LIMIT = 120;

export interface InventoryBall {
  sourceIndex?: number;
  sourceMessage?: string;
  disposition?: BallDisposition;
  reason?: string;
}

export interface InventorySnapshot {
  balls: InventoryBall[];
  /// 只有真的因為上限而丟掉後續球時才標記——觀測資料被截斷卻不說，
  /// 事後分析會把它誤讀成「模型只列了這幾顆」。
  truncated?: boolean;
}

export function collectInventorySnapshot(
  event: StreamEvent | Record<string, unknown>,
): InventorySnapshot | null {
  if (!event || event.type !== "analysis.inventory") return null;

  const balls = (event as Record<string, unknown>).balls;
  if (!Array.isArray(balls) || balls.length === 0) return null;

  const collected: InventoryBall[] = [];
  let truncated = false;
  for (const ball of balls) {
    if (collected.length >= INVENTORY_BALL_LIMIT) {
      truncated = true;
      break;
    }
    if (!ball || typeof ball !== "object") continue;
    const record = ball as Record<string, unknown>;

    const snapshot: InventoryBall = {};
    const sourceIndex = record.sourceIndex;
    if (typeof sourceIndex === "number" && Number.isFinite(sourceIndex)) {
      snapshot.sourceIndex = sourceIndex;
    }
    const sourceMessage = inventoryText(record.sourceMessage);
    if (sourceMessage) snapshot.sourceMessage = sourceMessage;

    const disposition = record.disposition;
    if (
      typeof disposition === "string" && BALL_DISPOSITIONS.has(disposition)
    ) {
      snapshot.disposition = disposition as BallDisposition;
    }
    const reason = inventoryText(record.reason);
    if (reason) snapshot.reason = reason;

    // 四個欄位全壞的項目留著只是雜訊，沒有任何可追溯價值。
    if (Object.keys(snapshot).length === 0) continue;
    collected.push(snapshot);
  }

  if (collected.length === 0) return null;
  return truncated
    ? { balls: collected, truncated: true }
    : { balls: collected };
}

function inventoryText(value: unknown): string {
  if (typeof value !== "string") return "";
  const trimmed = value.trim();
  return trimmed.length > INVENTORY_TEXT_LIMIT
    ? trimmed.slice(0, INVENTORY_TEXT_LIMIT)
    : trimmed;
}

export function isCatchable(disposition: BallDisposition): boolean {
  return CATCHABLE_DISPOSITIONS.has(disposition);
}

export type SegmentValidation =
  | { ok: true }
  | { ok: false; reason: string };

// 下限：連發多球時選中風格段數至少 min(3, 獨立「接」球數)。「併」只補
// 同一球的背景，不得把段數膨脹。獨立真球少於 3 時不可
// 要求超過真球數（failure matrix「2 接 → 2 段 PASS」例外）。
export function segmentFloor(inventory: BallInventory): number {
  return Math.min(3, inventory.independentCount);
}

// 硬版唯一新增閘（2026-08-09 球數對齊批起，reframer 對每個風格都跑這個檢查，
// 不再只驗選中風格；fail-soft log-only 不變）：option 的 segments 必須
//   (1) 不來自標「併／略」的球（INV-H6 segments ⊆ 接）；未在盤點出現的
//       sourceIndex 視為放行（絕不誤殺，盤點可能漏列）。
//   (2) 段數 ≥ segmentFloor（治 (b) inventory→reply 斷層）。
// 不改既有合法 segment 的處理（INV-H5）；只回 ok/理由。2026-06-13 起 reframer
// 對失敗僅記 log（fail-soft），不再 reject／走 INCOMPLETE。函式名裡的
// Selected 是歷史沿革（原本只驗選中風格）；改名會牽動大量測試，刻意保留。
export function validateSelectedSegments(
  inventory: BallInventory,
  segments: readonly Record<string, unknown>[],
): SegmentValidation {
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
  }

  // 下限數「不同的獨立接球」而非段數（Codex adversarial P2）：重複 sourceIndex
  // 只算一次，盤點外（absent）的索引不算真接球。盤點外的段不會單獨致 REJECT
  // ——達標後多帶一段盤點外的句子仍放行（不誤殺 INV-H6'）。
  const covered = coveredIndependentBalls(inventory, segments);

  const floor = segmentFloor(inventory);
  if (covered.size < floor) {
    return {
      ok: false,
      reason:
        `風格實際接到 ${covered.size} 顆不同的獨立接球，未達下限 ${floor}`,
    };
  }

  return { ok: true };
}

// 一個 option 的 segments 實際覆蓋到哪些「接」球（去重、盤點外索引不算）。
// validateSelectedSegments 的下限計數與 reframer 的 [ball_coverage] telemetry
// 共用這一份，兩邊數字才對得起來。
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
