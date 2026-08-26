// 生成配圖的 handler 接線測試（PR-3）：kill switch 開時的行為。
//
// 開關關（deps.imageGen undefined）的行為由既有 moments_handler_test.ts 的
// 28 條測試釘住——它們全部不注入 imageGen，等於在驗「導入後現行路徑
// bit-for-bit 不變」。本檔只驗開關開的新分支。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  handlePracticeMoments,
  type MomentsHandlerDeps,
  type MomentsSupabaseClient,
} from "./moments_handler.ts";
import { SELF_PORTRAIT_IMAGE_ID } from "./moments_image_catalog.ts";
import type { MomentImageGenDeps } from "./moments_image_gen.ts";
import { taipeiTimeContextFor } from "./time_context.ts";
import { MOMENT_IMAGE_FILL_MAX_PER_REQUEST } from "./moments_constants.ts";

type Row = Record<string, unknown>;

const USER_ID = "user-flow-test";
const PROFILE_ID = "practice_girl_001";
// 台北 23:00：morning slot 的 postedAt 必定已過。
const LATE_NIGHT = new Date("2026-08-25T15:00:00.000Z");
const ISO_DATE = taipeiTimeContextFor(LATE_NIGHT).isoDate;
const VALID_BODY = "下班路上的天色好到讓人想多走一站再慢慢回家";
const FAL_URL = "https://fal.run/fal-ai/flux/schnell";

interface FlowHarness {
  supabase: MomentsSupabaseClient;
  rpcCalls: { fn: string; params: Row }[];
  textModelPrompts: string[];
  sceneModelCalls: number;
  falCalls: number;
  uploads: string[];
  scheduled: Promise<void>[];
  deps: MomentsHandlerDeps;
}

function makeFlowHarness(options: {
  imageGenOn?: boolean;
  slots?: Row[];
  existing?: Row[];
  imageCandidates?: string[];
  storageBase?: string;
} = {}): FlowHarness {
  const rpcCalls: { fn: string; params: Row }[] = [];
  const textModelPrompts: string[] = [];
  const uploads: string[] = [];
  const scheduled: Promise<void>[] = [];
  const counters = { scene: 0, fal: 0 };

  const supabase: MomentsSupabaseClient = {
    from() {
      const builder = {
        eq() {
          return builder;
        },
        then(resolve: (value: unknown) => unknown) {
          return Promise.resolve(resolve({
            data: [{
              profile_id: PROFILE_ID,
              created_at: "2026-08-01T00:00:00.000Z",
            }],
            error: null,
          }));
        },
      };
      return { select: () => builder as never };
    },
    rpc(fn: string, params: Row) {
      rpcCalls.push({ fn, params });
      if (fn === "list_practice_moment_posts") {
        return Promise.resolve({ data: options.existing ?? [], error: null });
      }
      if (fn === "reserve_practice_moment_slot") {
        return Promise.resolve({
          data: [{ claimed: true, token: "t-text", attempt_count: 1 }],
          error: null,
        });
      }
      if (fn === "commit_practice_moment_post") {
        return Promise.resolve({ data: [{ committed: true }], error: null });
      }
      if (fn === "claim_practice_moment_image") {
        return Promise.resolve({
          data: [{
            claimed: true,
            token: params.p_image_token,
            attempt_count: 1,
            body: VALID_BODY,
            theme_id: "off_work_walk",
          }],
          error: null,
        });
      }
      if (fn === "commit_practice_moment_image") {
        return Promise.resolve({ data: [{ committed: true }], error: null });
      }
      if (fn === "release_practice_moment_image") {
        return Promise.resolve({ data: [{ released: true }], error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };

  const fetchMock = ((input: Request | URL | string) => {
    const url = String(input);
    if (url === FAL_URL) {
      counters.fal++;
      return Promise.resolve(
        new Response(
          JSON.stringify({
            images: [{ url: "https://fal.media/x.jpeg" }],
            has_nsfw_concepts: [false],
          }),
          { status: 200 },
        ),
      );
    }
    const jpeg = new Uint8Array(20_000);
    jpeg[0] = 0xFF;
    jpeg[1] = 0xD8;
    jpeg[2] = 0xFF;
    return Promise.resolve(
      new Response(jpeg, {
        status: 200,
        headers: { "content-type": "image/jpeg" },
      }),
    );
  }) as typeof globalThis.fetch;

  const imageGen: MomentImageGenDeps = {
    falApiKey: "fal-test",
    deepSeekApiKey: "ds-test",
    callDeepSeek: () => {
      counters.scene++;
      return Promise.resolve(JSON.stringify({
        scene: "A quiet Taipei arcade walkway in the evening with warm glow.",
      }));
    },
    uploadImage: (path: string) => {
      uploads.push(path);
      return Promise.resolve();
    },
    removeImage: () => Promise.resolve(),
    fetch: fetchMock,
    randomToken: () => "img-token",
  };

  const deps: MomentsHandlerDeps = {
    apiKey: "test-key",
    fillDeadlineMs: 800,
    randomToken: () => "text-token",
    callDeepSeek: (args) => {
      textModelPrompts.push(
        args.messages.map((m) => m.content).join("\n---\n"),
      );
      return Promise.resolve(JSON.stringify({ text: VALID_BODY, imageId: null }));
    },
    planFor: () => ({
      profileId: PROFILE_ID,
      isoDate: ISO_DATE,
      slots: (options.slots ?? [{
        slot: 0,
        dayPart: "morning",
        themeId: "off_work_walk",
        brief: "下班路上的空檔",
        wantsImage: true,
        imageCandidates: options.imageCandidates ??
          ["moment_street_night", "moment_sunset_sky"],
      }]) as never,
    }),
    waitUntil: (task) => {
      scheduled.push(task);
    },
    storagePublicUrlBase: options.storageBase ??
      "https://x.supabase.co/storage/v1/object/public/practice-moment-images",
    imageGen: (options.imageGenOn ?? true) ? imageGen : undefined,
  };

  return {
    supabase,
    rpcCalls,
    textModelPrompts,
    get sceneModelCalls() {
      return counters.scene;
    },
    get falCalls() {
      return counters.fal;
    },
    uploads,
    scheduled,
    deps,
  };
}

async function runFlow(harness: FlowHarness) {
  const result = await handlePracticeMoments({
    supabase: harness.supabase,
    userId: USER_ID,
    now: LATE_NIGHT,
    isTestAccount: false,
    deps: harness.deps,
  });
  // 背景 job 全部收乾，斷言才不是競態。
  await Promise.all(harness.scheduled);
  return result;
}

function rpcNames(harness: FlowHarness): string[] {
  return harness.rpcCalls.map((c) => c.fn);
}

Deno.test("開關開：候選清空、commit 標 pending、背景 job 生圖到 commit", async () => {
  const harness = makeFlowHarness({});
  const result = await runFlow(harness);
  assertEquals(result.status, 200);

  // 文字 prompt 不得再出現 catalog 候選 id（生成模式的圖不從 allowlist 挑）。
  assertEquals(harness.textModelPrompts.length, 1);
  assert(!harness.textModelPrompts[0].includes("moment_street_night"));
  assert(
    harness.textModelPrompts[0].includes("你隨手拍的照片"),
    "生成模式要用「圖決定文」的措辭",
  );

  const commit = harness.rpcCalls.find((c) =>
    c.fn === "commit_practice_moment_post"
  );
  assert(commit);
  assertEquals(commit.params.p_wants_image, true);
  assertEquals(commit.params.p_image_id, null);

  // 背景 job 完整跑完：claim → fal → 上傳 → commit image。
  assertEquals(harness.scheduled.length, 1);
  assert(rpcNames(harness).includes("claim_practice_moment_image"));
  assert(rpcNames(harness).includes("commit_practice_moment_image"));
  assertEquals(harness.falCalls, 1);
  assertEquals(harness.uploads, [`${ISO_DATE}/${PROFILE_ID}_0_img-token.jpeg`]);

  // 本回應的貼文 imageUrl 為 null（圖在背景生成中）。
  const posts = (result.body as { posts: { imageUrl: string | null }[] }).posts;
  assertEquals(posts[0].imageUrl, null);
});

Deno.test("開關開但候選只剩自拍：照舊走 sentinel 路徑，不生成", async () => {
  const harness = makeFlowHarness({
    imageCandidates: [SELF_PORTRAIT_IMAGE_ID],
  });
  await runFlow(harness);

  const commit = harness.rpcCalls.find((c) =>
    c.fn === "commit_practice_moment_post"
  );
  assert(commit);
  assert(
    !("p_wants_image" in commit.params),
    "非生成 slot 必須省略 p_wants_image 鍵（部署窗內舊 DB 只有 7-arg commit）",
  );
  assert(
    harness.textModelPrompts[0].includes(SELF_PORTRAIT_IMAGE_ID),
    "自拍 slot 的 prompt 仍走現行 sentinel 指示",
  );
  assertEquals(harness.scheduled.length, 0);
  assertEquals(harness.falCalls, 0);
});

Deno.test("開關關：wantsImage slot 走現行 bundled 候選路徑，零生圖", async () => {
  const harness = makeFlowHarness({ imageGenOn: false });
  await runFlow(harness);

  assert(
    harness.textModelPrompts[0].includes("moment_street_night"),
    "開關關必須維持候選清單進 prompt 的現行行為",
  );
  const commit = harness.rpcCalls.find((c) =>
    c.fn === "commit_practice_moment_post"
  );
  assert(commit);
  assert(
    !("p_wants_image" in commit.params),
    "開關關必須省略 p_wants_image 鍵，部署窗內舊 DB 才不會 PGRST202",
  );
  assertEquals(harness.scheduled.length, 0);
  assertEquals(harness.falCalls, 0);
});

Deno.test("list 的 pending 列在零缺口請求上被接手", async () => {
  const harness = makeFlowHarness({
    slots: [],
    existing: [{
      profile_id: PROFILE_ID,
      post_date: ISO_DATE,
      slot: 0,
      day_part: "morning",
      body: VALID_BODY,
      image_id: null,
      image_status: "pending",
      image_path: null,
    }],
  });
  const result = await runFlow(harness);
  assertEquals(result.status, 200);
  assertEquals(harness.scheduled.length, 1, "pending 列必須被接手");
  assert(rpcNames(harness).includes("claim_practice_moment_image"));
  assertEquals(harness.falCalls, 1);
});

Deno.test("ready 列組出 public imageUrl；其他狀態一律 null", async () => {
  const path = `${ISO_DATE}/${PROFILE_ID}_0.jpeg`;
  const harness = makeFlowHarness({
    slots: [],
    existing: [
      {
        profile_id: PROFILE_ID,
        post_date: ISO_DATE,
        slot: 0,
        day_part: "morning",
        body: VALID_BODY,
        image_id: null,
        image_status: "ready",
        image_path: path,
      },
      {
        profile_id: PROFILE_ID,
        post_date: ISO_DATE,
        slot: 1,
        day_part: "morning",
        body: VALID_BODY,
        image_id: null,
        image_status: "failed",
        image_path: null,
      },
    ],
  });
  const result = await runFlow(harness);
  const posts =
    (result.body as { posts: { slot: number; imageUrl: string | null }[] })
      .posts;
  const bySlot = new Map(posts.map((p) => [p.slot, p.imageUrl]));
  assertEquals(
    bySlot.get(0),
    `https://x.supabase.co/storage/v1/object/public/practice-moment-images/${path}`,
  );
  assertEquals(bySlot.get(1), null);
});

Deno.test("單一請求最多排 MOMENT_IMAGE_FILL_MAX_PER_REQUEST 個生圖 job", async () => {
  const harness = makeFlowHarness({
    slots: [],
    existing: [0, 1].map((slot) => ({
      profile_id: PROFILE_ID,
      post_date: ISO_DATE,
      slot,
      day_part: "morning",
      body: VALID_BODY,
      image_id: null,
      image_status: "pending",
      image_path: null,
    })).concat([{
      profile_id: PROFILE_ID,
      post_date: "2026-08-24",
      slot: 0,
      day_part: "morning",
      body: VALID_BODY,
      image_id: null,
      image_status: "pending",
      image_path: null,
    }]),
  });
  await runFlow(harness);
  assertEquals(harness.scheduled.length, MOMENT_IMAGE_FILL_MAX_PER_REQUEST);
});
