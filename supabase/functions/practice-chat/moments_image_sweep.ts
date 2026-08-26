// 練習室動態生成配圖的機會式清理（PR-4；第四輪複審後為三段）。
//
// 設計來源：docs/plans/2026-08-25-practice-moments-generated-images.md §8。
// 沒有 pg_net、沒有排程 workflow（決策 6），清掃跟著 feed 請求順路做
// （lazy purge，範式同 20260703120000 opener_charge_idempotency）。三段各自
// 負責一種「物件不該再存在」：
//
// 1. 主清掃 sweepExpiredMomentImages——**被引用但出窗**的圖：
//      list_expired_practice_moment_images(feed 窗起點, LIMIT 20)
//      → Storage 批次刪物件
//      → mark_practice_moment_images_expired（'ready' → 'expired'）
// 2. 帳本清算 sweepMomentImageOrphanLedger——**寫過但沒人引用**的圖：
//      list_practice_moment_image_orphans(LIMIT 20, 寬限 600s)
//      → Storage 批次刪物件
//      → clear_practice_moment_image_orphans（抹掉帳本紀錄）
// 3. prefix 對帳 sweepOrphanMomentImages——連帳本都沒有的殘留（舊部署、
//    人工上傳）：找出**最舊的出窗日期資料夾**，分頁把裡面的東西排掉。
//
// **順序鐵則（三段共用）：先刪物件、後改 DB。** 任何一步失敗就原地打住，
// 下一次 feed 請求重跑；Storage 刪除本身冪等，重試永遠安全。順序反過來會
// 製造「DB 已忘記、物件還在」的孤兒——那正是第 2、3 段要清的東西。
// 列本身永不 DELETE（D6：DB 永久保留）；'expired' 保留 image_path 作審計。
//
// 為什麼第 2 段是持久閉環而第 3 段只是兜底：物件路徑在 **claim 的同一筆
// 交易**就記進了 image_orphan_paths（見 20260826024500 migration），所以
// 「可能有物件」這件事不依賴任何 Edge 實例活著。第 3 段只是為了在帳本
// 出現之前寫下的物件、或人工放進 bucket 的東西留一條退路。
//
// 與生圖 kill switch 刻意無關：生成關掉之後，既有的圖出窗一樣要刪。
import { logInfo, logWarn } from "./logger.ts";
import {
  FEED_WINDOW_DAYS,
  MOMENT_IMAGE_LIST_PAGE_SIZE,
  MOMENT_IMAGE_ORPHAN_GRACE_SECONDS,
  MOMENT_IMAGE_ORPHAN_LEDGER_LIMIT,
  MOMENT_IMAGE_ORPHAN_MAX_PAGES,
  MOMENT_IMAGE_PREFIX_MAX_PAGES,
  MOMENT_IMAGE_SWEEP_LIMIT,
} from "./moments_constants.ts";
import type { MomentsImageRpcClient } from "./moments_image_gen.ts";
import { shiftIsoDate } from "./moments_date.ts";

/** Storage 操作的注入點；真實作在 handler.ts 用 supabase-js。 */
export interface MomentImageSweepDeps {
  removeImages: (paths: readonly string[]) => Promise<void>;
  /**
   * 列出某個日期 prefix 下的物件 key（完整 path），單頁最多 limit 筆。
   * 呼叫端每翻一頁就把該頁刪掉，所以永遠從頭列——offset 反而會跳過東西。
   */
  listImages: (
    prefix: string,
    opts: { limit: number },
  ) => Promise<readonly string[]>;
  /** 列出 bucket 根目錄的日期資料夾名稱（可分頁）。 */
  listPrefixes: (
    opts: { limit: number; offset: number },
  ) => Promise<readonly string[]>;
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
 * 帳本清算：把「claim 記過、但沒人引用」的物件刪掉，再抹掉帳本紀錄。
 *
 * 這是晚到上傳與不確定態 commit 的**持久重試閉環**（第四輪複審 P2-2）。
 * 路徑在 claim 的同一筆交易就寫進 image_orphan_paths，因此不管 Edge 實例
 * 何時被回收、物件何時落地，這一筆都還在；每個 feed 請求順手清一批，
 * 直到清乾淨為止。DB 端兩道守門讓這件事永遠安全：寬限期之內的紀錄不列
 * （在跑的 job 動不到），列自己 image_path 指著的物件不列（已被引用的
 * 圖絕不刪）。
 *
 * 永不 throw（跑在 waitUntil 背景）。回傳實際刪除的物件數。
 */
export async function sweepMomentImageOrphanLedger(opts: {
  supabase: MomentsImageRpcClient;
  deps: MomentImageSweepDeps;
}): Promise<number> {
  const { supabase, deps } = opts;

  let paths: string[];
  try {
    const { data, error } = await supabase.rpc(
      "list_practice_moment_image_orphans",
      {
        p_limit: MOMENT_IMAGE_ORPHAN_LEDGER_LIMIT,
        p_grace_seconds: MOMENT_IMAGE_ORPHAN_GRACE_SECONDS,
      },
    );
    if (error) {
      logWarn("practice_moment_image_orphan_list_error", {
        error: error.message,
      });
      return 0;
    }
    paths = (Array.isArray(data) ? data : [])
      .map((row) =>
        typeof (row as { orphan_path?: unknown }).orphan_path === "string"
          ? (row as { orphan_path: string }).orphan_path
          : null
      )
      .filter((path): path is string => path !== null);
  } catch (e) {
    logWarn("practice_moment_image_orphan_list_error", {
      error: e instanceof Error ? e.message : "unknown",
    });
    return 0;
  }
  if (paths.length === 0) return 0;

  // 先刪物件。失敗就此打住——帳本原封不動，下輪重試（刪除冪等）。
  try {
    await deps.removeImages(paths);
  } catch (e) {
    logWarn("practice_moment_image_orphan_remove_error", {
      count: paths.length,
      error: e instanceof Error ? e.message : "unknown",
    });
    return 0;
  }

  try {
    const { error } = await supabase.rpc(
      "clear_practice_moment_image_orphans",
      { p_paths: paths },
    );
    if (error) {
      // 物件已刪、帳本沒清：下輪重列同一批，重刪冪等後重清。
      logWarn("practice_moment_image_orphan_clear_error", {
        count: paths.length,
        error: error.message,
      });
      return paths.length;
    }
  } catch (e) {
    logWarn("practice_moment_image_orphan_clear_error", {
      count: paths.length,
      error: e instanceof Error ? e.message : "unknown",
    });
    return paths.length;
  }

  logInfo("practice_moment_image_orphan_ledger_swept", {
    deleted: paths.length,
  });
  return paths.length;
}

/** Storage 根目錄裡「日期資料夾」的樣子。 */
const ISO_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

/**
 * prefix 對帳兜底：清掉**最舊的出窗日期資料夾**裡的所有殘留物件。
 *
 * 第四輪複審 P2-2 前的版本依 UTC 小時在固定 K 天帶內輪替一個 prefix，
 * 有兩個漏法：feed 零流量超過 K 天，殘留就永遠滑出掃描帶；單一 prefix
 * 超過 100 筆（Storage list 上限）也永遠掃不完。現在改成：
 *
 * 1. **掃描目標由 bucket 自己說了算**——list 根目錄拿到還存在的日期資料夾，
 *    取其中最舊的出窗日期。資料夾清空就會從列表消失，因此沒有「滑出時間
 *    帶」這回事：停機一個月，回來時那些資料夾仍在，仍會被挑中。
 * 2. **分頁排空**——一頁 100 筆刪一頁，單次請求最多 MAX_PAGES 頁；沒清完
 *    的下一次請求接著清（已刪的不會再出現在列表裡，所以永遠從頭列即可）。
 *
 * 窗內日期絕不觸碰（name < before 才是候選），這是刪錯圖的最後一道守門。
 * 出窗日期的物件本來就不該再露出，全刪安全：仍是 ready 的列（標記失敗的
 * 殘局）物件被刪後，主清掃下一輪會重列、冪等重刪並完成標記。
 *
 * 永不 throw。回傳實際刪除的物件數。
 */
export async function sweepOrphanMomentImages(opts: {
  deps: MomentImageSweepDeps;
  /** 台北今日（taipeiTimeContextFor(now).isoDate）。 */
  isoDate: string;
}): Promise<number> {
  const { deps, isoDate } = opts;
  const before = shiftIsoDate(isoDate, -(FEED_WINDOW_DAYS - 1));

  let prefix: string | null;
  try {
    prefix = await findOldestExpiredPrefix(deps, before);
  } catch (e) {
    logWarn("practice_moment_image_orphan_sweep_error", {
      error: e instanceof Error ? e.message : "unknown",
    });
    return 0;
  }
  if (prefix === null) return 0;

  let deleted = 0;
  try {
    for (let page = 0; page < MOMENT_IMAGE_ORPHAN_MAX_PAGES; page++) {
      const objects = await deps.listImages(prefix, {
        limit: MOMENT_IMAGE_LIST_PAGE_SIZE,
      });
      if (objects.length === 0) break;
      await deps.removeImages(objects);
      deleted += objects.length;
      // 不滿一頁代表這個 prefix 已經排空。
      if (objects.length < MOMENT_IMAGE_LIST_PAGE_SIZE) break;
    }
  } catch (e) {
    logWarn("practice_moment_image_orphan_sweep_error", {
      prefix,
      deleted,
      error: e instanceof Error ? e.message : "unknown",
    });
    return deleted;
  }

  if (deleted > 0) {
    logInfo("practice_moment_image_orphans_swept", { prefix, deleted });
  }
  return deleted;
}

/**
 * 翻 bucket 根目錄，找出還存在的日期資料夾裡**最舊的出窗日**。
 * 沒有出窗資料夾就回 null（正常穩態）。
 */
async function findOldestExpiredPrefix(
  deps: MomentImageSweepDeps,
  before: string,
): Promise<string | null> {
  let oldest: string | null = null;
  for (let page = 0; page < MOMENT_IMAGE_PREFIX_MAX_PAGES; page++) {
    const names = await deps.listPrefixes({
      limit: MOMENT_IMAGE_LIST_PAGE_SIZE,
      offset: page * MOMENT_IMAGE_LIST_PAGE_SIZE,
    });
    for (const name of names) {
      if (!ISO_DATE_PATTERN.test(name)) continue;
      // 窗內的日期一律不碰——這是刪錯圖的最後一道守門。
      if (name >= before) continue;
      if (oldest === null || name < oldest) oldest = name;
    }
    if (names.length < MOMENT_IMAGE_LIST_PAGE_SIZE) break;
  }
  return oldest;
}

type Row = Record<string, unknown>;
