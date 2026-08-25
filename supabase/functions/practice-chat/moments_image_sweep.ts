// 練習室動態生成配圖的機會式過期清理（PR-4）。
//
// 設計來源：docs/plans/2026-08-25-practice-moments-generated-images.md §8。
// 沒有 pg_net、沒有排程 workflow（決策 6），清掃跟著 feed 請求順路做
// （lazy purge，範式同 20260703120000 opener_charge_idempotency）：
//
//   list_expired_practice_moment_images(feed 窗起點, LIMIT 20)
//   → Storage 批次刪物件
//   → mark_practice_moment_images_expired（image_status='ready' → 'expired'）
//
// **順序鐵則：先刪物件、後標記列。** 標記失敗下輪重掃重刪（Storage 刪除
// 冪等）；順序反過來會製造「已標記、掃不到、物件還在」的孤兒。
// 列本身永不 DELETE（D6：DB 永久保留）；'expired' 保留 image_path 作審計。
//
// 與生圖 kill switch 刻意無關：生成關掉之後，既有的圖出窗一樣要刪。
import { logInfo, logWarn } from "./logger.ts";
import {
  FEED_WINDOW_DAYS,
  MOMENT_IMAGE_SWEEP_LIMIT,
} from "./moments_constants.ts";
import type { MomentsImageRpcClient } from "./moments_image_gen.ts";

/** Storage 批次刪除的注入點；真實作在 handler.ts 用 supabase-js。 */
export interface MomentImageSweepDeps {
  removeImages: (paths: readonly string[]) => Promise<void>;
}

/** shiftIsoDate 的極簡版（moments_handler 內的同名 helper 未 export）。 */
function shiftIsoDate(isoDate: string, deltaDays: number): string {
  const base = new Date(`${isoDate}T00:00:00.000Z`);
  base.setUTCDate(base.getUTCDate() + deltaDays);
  return base.toISOString().slice(0, 10);
}

/**
 * 清掃一批出窗的生成圖。永不 throw（跑在 waitUntil 背景）；任何失敗只
 * 記錄，下一輪請求自然重試。回傳實際標記數（測試與觀測用）。
 */
export async function sweepExpiredMomentImages(opts: {
  supabase: MomentsImageRpcClient;
  deps: MomentImageSweepDeps;
  /** 台北今日（taipeiTimeContextFor(now).isoDate）。 */
  isoDate: string;
}): Promise<number> {
  const { supabase, deps, isoDate } = opts;
  // feed 顯示的是 [today-13, today]；嚴格小於 today-13 即出窗。
  const before = shiftIsoDate(isoDate, -(FEED_WINDOW_DAYS - 1));

  let paths: string[];
  try {
    const { data, error } = await supabase.rpc(
      "list_expired_practice_moment_images",
      { p_before: before, p_limit: MOMENT_IMAGE_SWEEP_LIMIT },
    );
    if (error) {
      logWarn("practice_moment_image_sweep_list_error", {
        error: error.message,
      });
      return 0;
    }
    paths = (Array.isArray(data) ? data : [])
      .map((row) =>
        typeof (row as { image_path?: unknown }).image_path === "string"
          ? (row as { image_path: string }).image_path
          : null
      )
      .filter((path): path is string => path !== null);
  } catch (e) {
    logWarn("practice_moment_image_sweep_list_error", {
      error: e instanceof Error ? e.message : "unknown",
    });
    return 0;
  }
  if (paths.length === 0) return 0;

  // 先刪物件。失敗就此打住——絕不標記還沒刪掉的物件。
  try {
    await deps.removeImages(paths);
  } catch (e) {
    logWarn("practice_moment_image_sweep_remove_error", {
      count: paths.length,
      error: e instanceof Error ? e.message : "unknown",
    });
    return 0;
  }

  try {
    const { data, error } = await supabase.rpc(
      "mark_practice_moment_images_expired",
      { p_before: before, p_paths: paths },
    );
    if (error) {
      // 物件已刪、標記失敗：下輪 list 會再列出同一批，重刪冪等後重標。
      logWarn("practice_moment_image_sweep_mark_error", {
        count: paths.length,
        error: error.message,
      });
      return 0;
    }
    const row = Array.isArray(data) ? (data[0] as Row | undefined) : null;
    const marked = typeof row?.marked_count === "number" ? row.marked_count : 0;
    logInfo("practice_moment_image_expired_swept", {
      deleted: paths.length,
      marked,
    });
    return marked;
  } catch (e) {
    logWarn("practice_moment_image_sweep_mark_error", {
      count: paths.length,
      error: e instanceof Error ? e.message : "unknown",
    });
    return 0;
  }
}

type Row = Record<string, unknown>;
