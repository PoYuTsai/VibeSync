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
  sweepExpiredMomentImages,
  sweepOrphanMomentImages,
} from "./moments_image_sweep.ts";
import type { MomentsImageRpcClient } from "./moments_image_gen.ts";
import {
  FEED_WINDOW_DAYS,
  MOMENT_IMAGE_ORPHAN_SWEEP_DAYS,
  MOMENT_IMAGE_SWEEP_LIMIT,
} from "./moments_constants.ts";
import {
  handlePracticeMoments,
  type MomentsSupabaseClient,
} from "./moments_handler.ts";

const ISO_DATE = "2026-08-25";
const PATHS = ["2026-08-01/practice_girl_001_0.jpeg", "2026-08-02/practice_girl_002_1.jpeg"];

interface SweepHarness {
  supabase: MomentsImageRpcClient;
  rpcCalls: { fn: string; params: Record<string, unknown> }[];
  removed: string[][];
  events: string[];
}

function makeSweepHarness(options: {
  expired?: string[];
  listError?: string;
  removeFails?: boolean;
  markError?: string;
  orphans?: Record<string, string[]>;
  listFails?: boolean;
} = {}): SweepHarness & {
  deps: {
    removeImages: (p: readonly string[]) => Promise<void>;
    listImages: (prefix: string) => Promise<readonly string[]>;
  };
  listedPrefixes: string[];
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
          return Promise.resolve({ data: null, error: { message: options.listError } });
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
          return Promise.resolve({ data: null, error: { message: options.markError } });
        }
        const count = (params.p_paths as string[]).length;
        return Promise.resolve({ data: [{ marked_count: count }], error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };
  const listedPrefixes: string[] = [];
  const deps = {
    removeImages: (paths: readonly string[]) => {
      events.push("remove");
      if (options.removeFails) return Promise.reject(new Error("boom"));
      removed.push([...paths]);
      return Promise.resolve();
    },
    listImages: (prefix: string) => {
      listedPrefixes.push(prefix);
      if (options.listFails) return Promise.reject(new Error("list boom"));
      return Promise.resolve(options.orphans?.[prefix] ?? []);
    },
  };
  return { supabase, rpcCalls, removed, events, deps, listedPrefixes };
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
// Durable 孤兒對帳（第三輪複審 P2）：出窗 prefix 的殘留物件一律刪除
// ---------------------------------------------------------------------------

Deno.test("orphan 對帳：掃剛出窗 K 天的 prefix，殘留物件全刪", async () => {
  const windowStart = "2026-08-12"; // isoDate 2026-08-25、FEED_WINDOW_DAYS=14
  const orphanPath = "2026-08-11/practice_girl_009_1_dead-token.jpeg";
  const harness = makeSweepHarness({
    orphans: { "2026-08-11": [orphanPath] },
  });
  const deleted = await sweepOrphanMomentImages({
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(deleted, 1);
  // 掃描範圍：窗起點往前 K 天，每一天一個 prefix。
  assertEquals(
    harness.listedPrefixes.length,
    MOMENT_IMAGE_ORPHAN_SWEEP_DAYS,
  );
  for (const prefix of harness.listedPrefixes) {
    assert(prefix < windowStart, `只掃出窗日期，實際掃到 ${prefix}`);
  }
  assertEquals(harness.removed, [[orphanPath]]);
});

Deno.test("orphan 對帳：list 失敗只記錄，不影響其他 prefix 也不拋錯", async () => {
  const harness = makeSweepHarness({ listFails: true });
  const deleted = await sweepOrphanMomentImages({
    deps: harness.deps,
    isoDate: ISO_DATE,
  });
  assertEquals(deleted, 0);
  assertEquals(harness.removed.length, 0);
});

Deno.test("orphan 對帳：零殘留時零刪除呼叫", async () => {
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
