// moments_image_sweep.ts（PR-4）的單元與接線測試。
//
// 核心契約：**先刪物件、後標記列**；任何一步失敗都不得標記還沒刪掉的物件
// （順序反過來會製造掃不到的孤兒）。列永不 DELETE 由 migration source test
// 守（本模組根本沒有那種 RPC 可叫）。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type MomentImageSweepDeps,
  sweepExpiredMomentImages,
  sweepMomentImageOrphanLedger,
  sweepOrphanMomentImages,
} from "./moments_image_sweep.ts";
import type { MomentsImageRpcClient } from "./moments_image_gen.ts";
import {
  FEED_WINDOW_DAYS,
  MOMENT_IMAGE_LIST_PAGE_SIZE,
  MOMENT_IMAGE_ORPHAN_GRACE_SECONDS,
  MOMENT_IMAGE_ORPHAN_LEDGER_LIMIT,
  MOMENT_IMAGE_ORPHAN_MAX_PAGES,
  MOMENT_IMAGE_SWEEP_LIMIT,
} from "./moments_constants.ts";
import {
  handlePracticeMoments,
  type MomentsSupabaseClient,
} from "./moments_handler.ts";

const ISO_DATE = "2026-08-25";
const PATHS = [
  "2026-08-01/practice_girl_001_0.jpeg",
  "2026-08-02/practice_girl_002_1.jpeg",
];

interface SweepHarness {
  supabase: MomentsImageRpcClient;
  rpcCalls: { fn: string; params: Record<string, unknown> }[];
  removed: string[][];
  events: string[];
}

/**
 * Storage 假替身用「真的會被刪掉」的記憶體 bucket，分頁測試才有意義：
 * listImages 回前 limit 筆、removeImages 真的把它們拿掉，所以呼叫端
 * 「列一頁刪一頁、永遠從頭列」的收斂性是被實際驗到的，不是被 mock 出來的。
 */
function makeSweepHarness(options: {
  expired?: string[];
  listError?: string;
  removeFails?: boolean;
  markError?: string;
  /** 記憶體 bucket：prefix → 物件 key。 */
  objects?: Record<string, string[]>;
  /** 根目錄的日期資料夾；預設由 objects 的 key 推得。 */
  prefixes?: string[];
  listFails?: boolean;
  listPrefixesFails?: boolean;
  /** 孤兒帳本 RPC 回傳的路徑。 */
  ledger?: string[];
  ledgerListError?: string;
  ledgerClearError?: string;
} = {}): SweepHarness & {
  deps: MomentImageSweepDeps;
  listedPrefixes: string[];
  prefixPages: { limit: number; offset: number }[];
  objects: Record<string, string[]>;
} {
  const rpcCalls: SweepHarness["rpcCalls"] = [];
  const removed: string[][] = [];
  const events: string[] = [];
  const supabase: MomentsImageRpcClient = {
    rpc(fn, params) {
      rpcCalls.push({ fn, params });
      events.push(`rpc:${fn}`);
      if (fn === "list_expired_practice_moment_images") {
        if (options.listError) {
          return Promise.resolve({
            data: null,
            error: { message: options.listError },
          });
        }
        return Promise.resolve({
          data: (options.expired ?? PATHS).map((path) => ({
            profile_id: "x",
            post_date: "2026-08-01",
            slot: 0,
            image_path: path,
          })),
          error: null,
        });
      }
      if (fn === "mark_practice_moment_images_expired") {
        if (options.markError) {
          return Promise.resolve({
            data: null,
            error: { message: options.markError },
          });
        }
        const count = (params.p_paths as string[]).length;
        return Promise.resolve({
          data: [{ marked_count: count }],
          error: null,
        });
      }
      if (fn === "list_practice_moment_image_orphans") {
        if (options.ledgerListError) {
          return Promise.resolve({
            data: null,
            error: { message: options.ledgerListError },
          });
        }
        return Promise.resolve({
          data: (options.ledger ?? []).map((path) => ({ orphan_path: path })),
          error: null,
        });
      }
      if (fn === "clear_practice_moment_image_orphans") {
        if (options.ledgerClearError) {
          return Promise.resolve({
            data: null,
            error: { message: options.ledgerClearError },
          });
        }
        return Promise.resolve({ data: [{ cleared_count: 1 }], error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };
  const objects: Record<string, string[]> = {};
  for (const [prefix, keys] of Object.entries(options.objects ?? {})) {
    objects[prefix] = [...keys];
  }
  const listedPrefixes: string[] = [];
  const prefixPages: { limit: number; offset: number }[] = [];
  const deps: MomentImageSweepDeps = {
    removeImages: (paths: readonly string[]) => {
      events.push("remove");
      if (options.removeFails) return Promise.reject(new Error("boom"));
      removed.push([...paths]);
      for (const prefix of Object.keys(objects)) {
        objects[prefix] = objects[prefix].filter((key) => !paths.includes(key));
      }
      return Promise.resolve();
    },
    listImages: (prefix: string, opts: { limit: number }) => {
      listedPrefixes.push(prefix);
      if (options.listFails) return Promise.reject(new Error("list boom"));
      return Promise.resolve((objects[prefix] ?? []).slice(0, opts.limit));
    },
    listPrefixes: (opts: { limit: number; offset: number }) => {
      prefixPages.push({ ...opts });
      if (options.listPrefixesFails) {
        return Promise.reject(new Error("prefix list boom"));
      }
      // 明確給 prefixes 時保留呼叫端順序：production 的 Storage list 雖然
      // 要求升冪，但對帳邏輯不該依賴那個保證。
      const all = options.prefixes ??
        [...Object.keys(objects)].filter((prefix) => objects[prefix].length > 0)
          .sort();
      return Promise.resolve(all.slice(opts.offset, opts.offset + opts.limit));
    },
  };
  return {
    supabase,
    rpcCalls,
    removed,
    events,
    deps,
    listedPrefixes,
    prefixPages,
    objects,
  };
}

Deno.test("成功路徑：list → 刪物件 → 標記，窗起點與上限正確", async () => {
  const harness = makeSweepHarness({});
  const marked = await sweepExpiredMomentImages({
    supabase: harness.supabase,
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(marked, 2);
  assertEquals(harness.events, [
    "rpc:list_expired_practice_moment_images",
    "remove",
    "rpc:mark_practice_moment_images_expired",
  ], "順序鐵則：先刪物件、後標記");

  const list = harness.rpcCalls[0].params;
  // feed 顯示 [today-13, today]；出窗＝嚴格小於 today-13。
  assertEquals(list.p_before, "2026-08-12");
  assertEquals(FEED_WINDOW_DAYS, 14);
  assertEquals(list.p_limit, MOMENT_IMAGE_SWEEP_LIMIT);
  assertEquals(harness.removed, [PATHS]);
  const mark = harness.rpcCalls[1].params;
  assertEquals(mark.p_paths, PATHS);
  assertEquals(mark.p_before, "2026-08-12");
});

Deno.test("零過期：只打 list，零刪除零標記", async () => {
  const harness = makeSweepHarness({ expired: [] });
  const marked = await sweepExpiredMomentImages({
    supabase: harness.supabase,
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(marked, 0);
  assertEquals(harness.events, ["rpc:list_expired_practice_moment_images"]);
});

Deno.test("刪物件失敗：絕不標記（下輪重掃重刪）", async () => {
  const harness = makeSweepHarness({ removeFails: true });
  const marked = await sweepExpiredMomentImages({
    supabase: harness.supabase,
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(marked, 0);
  assert(
    !harness.events.includes("rpc:mark_practice_moment_images_expired"),
    "物件還在就標記＝製造掃不到的孤兒",
  );
});

Deno.test("list 失敗：靜默結束、零副作用", async () => {
  const harness = makeSweepHarness({ listError: "db down" });
  const marked = await sweepExpiredMomentImages({
    supabase: harness.supabase,
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(marked, 0);
  assertEquals(harness.removed.length, 0);
});

Deno.test("標記失敗：回 0（物件已刪，冪等重刪後下輪重標）", async () => {
  const harness = makeSweepHarness({ markError: "db down" });
  const marked = await sweepExpiredMomentImages({
    supabase: harness.supabase,
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(marked, 0);
  assertEquals(harness.removed, [PATHS]);
});

// ---------------------------------------------------------------------------
// 帳本清算（第四輪複審 P2-2）：list → 刪物件 → clear，永遠可重試
// ---------------------------------------------------------------------------

Deno.test("帳本清算：list → 刪物件 → clear，參數與順序正確", async () => {
  const orphan = "2026-08-24/practice_girl_009_1_dead-token.jpeg";
  const harness = makeSweepHarness({ ledger: [orphan] });
  const deleted = await sweepMomentImageOrphanLedger({
    supabase: harness.supabase,
    deps: harness.deps,
  });
  assertEquals(deleted, 1);
  assertEquals(harness.events, [
    "rpc:list_practice_moment_image_orphans",
    "remove",
    "rpc:clear_practice_moment_image_orphans",
  ], "順序鐵則：先刪物件、後清帳本");
  assertEquals(
    harness.rpcCalls[0].params.p_limit,
    MOMENT_IMAGE_ORPHAN_LEDGER_LIMIT,
  );
  assertEquals(
    harness.rpcCalls[0].params.p_grace_seconds,
    MOMENT_IMAGE_ORPHAN_GRACE_SECONDS,
  );
  assertEquals(harness.removed, [[orphan]]);
  assertEquals(harness.rpcCalls[1].params.p_paths, [orphan]);
});

Deno.test("帳本清算：帳本空時零刪除零 clear", async () => {
  const harness = makeSweepHarness({ ledger: [] });
  const deleted = await sweepMomentImageOrphanLedger({
    supabase: harness.supabase,
    deps: harness.deps,
  });
  assertEquals(deleted, 0);
  assertEquals(harness.events, ["rpc:list_practice_moment_image_orphans"]);
});

Deno.test("帳本清算：刪物件失敗絕不清帳本（下輪原樣重試）", async () => {
  const harness = makeSweepHarness({ ledger: ["a.jpeg"], removeFails: true });
  const deleted = await sweepMomentImageOrphanLedger({
    supabase: harness.supabase,
    deps: harness.deps,
  });
  assertEquals(deleted, 0);
  assert(
    !harness.events.includes("rpc:clear_practice_moment_image_orphans"),
    "物件還在就清帳本＝把唯一的持久紀錄丟掉",
  );
});

Deno.test("帳本清算：clear 失敗仍回報已刪（下輪重列重刪冪等）", async () => {
  const harness = makeSweepHarness({
    ledger: ["a.jpeg"],
    ledgerClearError: "db down",
  });
  const deleted = await sweepMomentImageOrphanLedger({
    supabase: harness.supabase,
    deps: harness.deps,
  });
  assertEquals(deleted, 1);
  assertEquals(harness.removed, [["a.jpeg"]]);
});

Deno.test("帳本清算：list 失敗靜默結束、零副作用", async () => {
  const harness = makeSweepHarness({ ledgerListError: "db down" });
  const deleted = await sweepMomentImageOrphanLedger({
    supabase: harness.supabase,
    deps: harness.deps,
  });
  assertEquals(deleted, 0);
  assertEquals(harness.removed.length, 0);
});

Deno.test("帳本清算：回應形狀壞掉（null／缺欄位）一律當空", async () => {
  for (const data of [null, [{}], [{ orphan_path: 42 }]]) {
    const events: string[] = [];
    const supabase: MomentsImageRpcClient = {
      rpc(fn) {
        events.push(fn);
        if (fn === "list_practice_moment_image_orphans") {
          return Promise.resolve({ data, error: null });
        }
        return Promise.resolve({ data: null, error: null });
      },
    };
    const removed: string[][] = [];
    const deleted = await sweepMomentImageOrphanLedger({
      supabase,
      deps: {
        removeImages: (paths) => {
          removed.push([...paths]);
          return Promise.resolve();
        },
        listImages: () => Promise.resolve([]),
        listPrefixes: () => Promise.resolve([]),
      },
    });
    assertEquals(deleted, 0);
    assertEquals(removed.length, 0, "壞掉的回應不得觸發任何刪除");
    assertEquals(events, ["list_practice_moment_image_orphans"]);
  }
});

// ---------------------------------------------------------------------------
// prefix 對帳兜底（第四輪複審 P2-2）：最舊出窗資料夾、可分頁、不遺漏
// ---------------------------------------------------------------------------

Deno.test("prefix 對帳：挑最舊的出窗資料夾，殘留物件全刪", async () => {
  const oldest = "2026-07-30/practice_girl_009_1_dead-token.jpeg";
  const newer = "2026-08-11/practice_girl_008_0_dead-token.jpeg";
  const harness = makeSweepHarness({
    objects: { "2026-07-30": [oldest], "2026-08-11": [newer] },
  });
  const deleted = await sweepOrphanMomentImages({
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(deleted, 1);
  assertEquals(harness.listedPrefixes[0], "2026-07-30", "先清最舊的");
  assertEquals(harness.removed, [[oldest]]);
});

Deno.test("prefix 對帳：窗內資料夾永遠不碰", async () => {
  // 窗起點 2026-08-12；窗內（含當天）一律不得被列為候選。
  const harness = makeSweepHarness({
    objects: {
      "2026-08-12": ["2026-08-12/in_window_0_tok.jpeg"],
      "2026-08-25": ["2026-08-25/today_0_tok.jpeg"],
    },
  });
  const deleted = await sweepOrphanMomentImages({
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(deleted, 0);
  assertEquals(harness.listedPrefixes.length, 0, "連 list 都不該打");
  assertEquals(harness.removed.length, 0);
});

Deno.test("prefix 對帳：單一 prefix 超過一頁時分頁排空", async () => {
  const many = Array.from(
    { length: MOMENT_IMAGE_LIST_PAGE_SIZE + 30 },
    (_, i) => `2026-07-30/obj_${i}.jpeg`,
  );
  const harness = makeSweepHarness({ objects: { "2026-07-30": many } });
  const deleted = await sweepOrphanMomentImages({
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(deleted, many.length, "100 筆上限不得讓殘留永久漏掃");
  assertEquals(harness.objects["2026-07-30"], []);
  assertEquals(harness.removed.length, 2, "一頁刪一頁");
  assertEquals(harness.removed[0].length, MOMENT_IMAGE_LIST_PAGE_SIZE);
});

Deno.test("prefix 對帳：超過單次頁數上限就留給下一次請求（不遺漏）", async () => {
  const total = MOMENT_IMAGE_LIST_PAGE_SIZE *
    (MOMENT_IMAGE_ORPHAN_MAX_PAGES + 1);
  const many = Array.from(
    { length: total },
    (_, i) => `2026-07-30/obj_${i}.jpeg`,
  );
  const harness = makeSweepHarness({ objects: { "2026-07-30": many } });
  const first = await sweepOrphanMomentImages({
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(
    first,
    MOMENT_IMAGE_LIST_PAGE_SIZE * MOMENT_IMAGE_ORPHAN_MAX_PAGES,
    "單次請求有上界",
  );
  // 剩下的在下一次請求被同一支函式接著清乾淨——沒有「永久漏掃」。
  const second = await sweepOrphanMomentImages({
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(first + second, total);
  assertEquals(harness.objects["2026-07-30"], []);
});

Deno.test("prefix 對帳：零流量很久之後，舊資料夾仍掃得到（不隨時間滑走）", async () => {
  // 出窗超過任何固定掃描帶的日期：舊版依 UTC 小時輪替 3 天帶會永久漏掉它。
  const ancient = "2026-01-05/practice_girl_003_0_dead-token.jpeg";
  const harness = makeSweepHarness({ objects: { "2026-01-05": [ancient] } });
  const deleted = await sweepOrphanMomentImages({
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(deleted, 1);
  assertEquals(harness.removed, [[ancient]]);
});

Deno.test("prefix 對帳：根目錄超過一頁時翻頁找候選（不靠排序保證）", async () => {
  // isoDate 2026-09-30 → 窗起點 2026-09-17；第一頁塞滿窗內日期，唯一的
  // 出窗資料夾排在第二頁。Storage 的排序不該是正確性的前提。
  const inWindow = Array.from(
    { length: MOMENT_IMAGE_LIST_PAGE_SIZE + 5 },
    (_, i) => `2026-09-${String(17 + (i % 14)).padStart(2, "0")}`,
  );
  const stale = "2026-09-01";
  const harness = makeSweepHarness({
    objects: { [stale]: [`${stale}/obj.jpeg`] },
    prefixes: [...inWindow, stale],
  });
  const deleted = await sweepOrphanMomentImages({
    deps: harness.deps,
    isoDate: "2026-09-30",
  });
  assertEquals(deleted, 1);
  assert(harness.prefixPages.length >= 2, "第一頁沒找到就要翻下一頁");
  assertEquals(harness.prefixPages[1].offset, MOMENT_IMAGE_LIST_PAGE_SIZE);
  assertEquals(harness.listedPrefixes[0], stale);
});

Deno.test("prefix 對帳：非日期資料夾一律忽略", async () => {
  const harness = makeSweepHarness({
    objects: { "not-a-date": ["not-a-date/whatever.jpeg"] },
    prefixes: ["not-a-date", ".emptyFolderPlaceholder"],
  });
  const deleted = await sweepOrphanMomentImages({
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(deleted, 0);
  assertEquals(harness.removed.length, 0);
});

Deno.test("prefix 對帳：list 失敗只記錄、不拋錯", async () => {
  const harness = makeSweepHarness({
    objects: { "2026-07-30": ["2026-07-30/a.jpeg"] },
    listFails: true,
  });
  const deleted = await sweepOrphanMomentImages({
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(deleted, 0);
  assertEquals(harness.removed.length, 0);
});

Deno.test("prefix 對帳：根目錄 list 失敗只記錄、不拋錯", async () => {
  const harness = makeSweepHarness({ listPrefixesFails: true });
  const deleted = await sweepOrphanMomentImages({
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(deleted, 0);
  assertEquals(harness.listedPrefixes.length, 0);
});

Deno.test("prefix 對帳：零殘留時零刪除呼叫", async () => {
  const harness = makeSweepHarness({});
  const deleted = await sweepOrphanMomentImages({
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(deleted, 0);
  assertEquals(harness.removed.length, 0);
});

// ---------------------------------------------------------------------------
// handler 接線：每個 feed 請求排一次背景清掃；deps 缺席不排
// ---------------------------------------------------------------------------

function makeFeedSupabase(rpcCalls: { fn: string }[]): MomentsSupabaseClient {
  return {
    from() {
      const b = {
        eq: () => b,
        then: (r: (v: unknown) => unknown) =>
          Promise.resolve(r({ data: [], error: null })),
      };
      return { select: () => b as never };
    },
    rpc(fn: string) {
      rpcCalls.push({ fn });
      return Promise.resolve({ data: [], error: null });
    },
  };
}

Deno.test("feed 請求（零解鎖之外的早退路）也會排背景清掃", async () => {
  const rpcCalls: { fn: string }[] = [];
  const scheduled: Promise<void>[] = [];
  // 有解鎖角色但 planFor 回空 → 走「零缺口」早退路。
  const supabase: MomentsSupabaseClient = {
    from() {
      const b = {
        eq: () => b,
        then: (r: (v: unknown) => unknown) =>
          Promise.resolve(r({
            data: [{
              profile_id: "practice_girl_001",
              created_at: "2026-08-01T00:00:00.000Z",
            }],
            error: null,
          })),
      };
      return { select: () => b as never };
    },
    rpc(fn: string) {
      rpcCalls.push({ fn });
      if (fn === "list_expired_practice_moment_images") {
        return Promise.resolve({ data: [], error: null });
      }
      return Promise.resolve({ data: [], error: null });
    },
  };
  const result = await handlePracticeMoments({
    supabase,
    userId: "u",
    now: new Date("2026-08-25T15:00:00.000Z"),
    isTestAccount: false,
    deps: {
      apiKey: "k",
      callDeepSeek: () => Promise.resolve("{}"),
      planFor: () => ({
        profileId: "practice_girl_001",
        isoDate: "2026-08-25",
        slots: [],
      }),
      waitUntil: (task) => {
        scheduled.push(task);
      },
      imageSweep: {
        removeImages: () => Promise.resolve(),
        listImages: () => Promise.resolve([]),
        listPrefixes: () => Promise.resolve([]),
      },
    },
  });
  await Promise.all(scheduled);
  assertEquals(result.status, 200);
  assertEquals(scheduled.length, 1, "早退路也要排清掃");
  assert(
    rpcCalls.some((c) => c.fn === "list_expired_practice_moment_images"),
  );
});

Deno.test("deps.imageSweep 缺席：不排清掃（既有測試環境零行為變化）", async () => {
  const rpcCalls: { fn: string }[] = [];
  const scheduled: Promise<void>[] = [];
  const result = await handlePracticeMoments({
    supabase: makeFeedSupabase(rpcCalls),
    userId: "u",
    now: new Date("2026-08-25T15:00:00.000Z"),
    isTestAccount: false,
    deps: {
      apiKey: "k",
      callDeepSeek: () => Promise.resolve("{}"),
      waitUntil: (task) => {
        scheduled.push(task);
      },
    },
  });
  assertEquals(result.status, 200);
  assertEquals(scheduled.length, 0);
  assert(
    !rpcCalls.some((c) => c.fn === "list_expired_practice_moment_images"),
  );
});
