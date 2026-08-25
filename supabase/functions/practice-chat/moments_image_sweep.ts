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
  MOMENT_IMAGE_ORPHAN_SWEEP_DAYS,
  MOMENT_IMAGE_SWEEP_LIMIT,
} from "./moments_constants.ts";
import type { MomentsImageRpcClient } from "./moments_image_gen.ts";
import { shiftIsoDate } from "./moments_handler.ts";

/** Storage 操作的注入點；真實作在 handler.ts 用 supabase-js。 */
export interface MomentImageSweepDeps {
  removeImages: (paths: readonly string[]) => Promise<void>;
  /** 列出某個日期 prefix 下的物件 key（完整 path）。 */
  listImages: (prefix: string) => Promise<readonly string[]>;
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

/**
 * 孤兒對帳兜底（第三輪複審 P2；作者側終審再校準）：token 隔離路徑下，
 * 晚到上傳與失敗路徑的自刪都是 best effort（Edge 實例可能先回收）。
 * 這裡把兜底做成**可重複執行**的對帳：list 剛出窗 K 天內的一個日期
 * prefix，殘留的任何物件一律刪除——出窗日期的圖本來就不該露出；仍為
 * ready 的列（標記失敗的殘局）物件被刪後，下一輪主清掃會重列、冪等
 * 重刪並完成標記，最終一致。
 *
 * 每次請求只掃**一個** prefix（依 UTC 小時在 K 天帶內輪替）——~11 物件/天
 * 的量不值得每請求打 K 次 Storage list。誠實的邊界：這是「有流量就終會
 * 清掉」的最終一致兜底，**不是絕對保證**——feed 零流量超過 K 天的殘留
 * 孤兒會滑出掃描帶，由 orphans_swept／orphan_sweep_error 觀測記錄與
 * 手動 prefix 對帳接手（設計文件 §8）。
 */
export async function sweepOrphanMomentImages(opts: {
  deps: MomentImageSweepDeps;
  /** 台北今日（taipeiTimeContextFor(now).isoDate）。 */
  isoDate: string;
  /** 測試注入：固定輪替位移（1..K）。預設依 UTC 小時輪替。 */
  prefixOffset?: number;
}): Promise<number> {
  const { deps, isoDate } = opts;
  const before = shiftIsoDate(isoDate, -(FEED_WINDOW_DAYS - 1));
  const offset = opts.prefixOffset ??
    (1 + (new Date().getUTCHours() % MOMENT_IMAGE_ORPHAN_SWEEP_DAYS));
  const prefix = shiftIsoDate(before, -offset);
  try {
    const orphans = await deps.listImages(prefix);
    if (orphans.length === 0) return 0;
    await deps.removeImages(orphans);
    logInfo("practice_moment_image_orphans_swept", {
      prefix,
      deleted: orphans.length,
    });
    return orphans.length;
  } catch (e) {
    logWarn("practice_moment_image_orphan_sweep_error", {
      prefix,
      error: e instanceof Error ? e.message : "unknown",
    });
    return 0;
  }
}

type Row = Record<string, unknown>;
