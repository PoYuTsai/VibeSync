// moments_image_gen.ts（PR-3）的單元測試：純函式契約 + 生圖 job 全流程
// （mock RPC / fetch / upload，零網路、零真金）。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildImagePrompt,
  coveredThemeIds,
  generateMomentImage,
  MOMENT_IMAGE_STYLE_PREFIX,
  momentImagePath,
  momentImageSeed,
  type MomentsImageRpcClient,
  themeSceneLine,
  validateSceneLine,
} from "./moments_image_gen.ts";
import { momentPlanFor } from "./moments_schedule.ts";
import { GIRL_PROFILES } from "./practice_persona.ts";
import { taipeiTimeContextFor } from "./time_context.ts";
import {
  MAX_MOMENT_IMAGE_ATTEMPTS,
  MOMENT_IMAGE_MIN_BYTES,
} from "./moments_constants.ts";

const JOB = { profileId: "practice_girl_007", isoDate: "2026-08-25", slot: 0 };
const USER_ID = "11111111-2222-3333-4444-555555555555";
const FAL_URL = "https://fal.run/fal-ai/flux/schnell";
const CDN_URL = "https://fal.media/files/abc/result.jpeg";
const BODY = "下班隨便弄了碗麵 吃完才發現醬料包過期一個月";

// ---------------------------------------------------------------------------
// 題材模板句：覆蓋所有排程會產出的 themeId
// ---------------------------------------------------------------------------

Deno.test("題材模板句涵蓋排程 30 天內出現的每一個 themeId", () => {
  const covered = new Set(coveredThemeIds());
  const seen = new Set<string>();
  for (let day = 0; day < 30; day++) {
    const time = taipeiTimeContextFor(
      new Date(Date.UTC(2026, 7, 1 + day, 4)),
    );
    for (const girl of GIRL_PROFILES) {
      for (const slot of momentPlanFor({ girl, time }).slots) {
        seen.add(slot.themeId);
      }
    }
  }
  assert(seen.size >= 30, `掃出的題材太少（${seen.size}），掃法可能壞了`);
  const missing = [...seen].filter((id) => !covered.has(id));
  assertEquals(
    missing,
    [],
    "以下題材缺英文模板句，場景句降級時會退到 generic 句",
  );
});

Deno.test("每一條模板句本身通過場景句驗證", () => {
  for (const id of coveredThemeIds()) {
    validateSceneLine(themeSceneLine(id)); // 不合格會 throw
  }
  // 未知題材退 generic 句，一樣要合格。
  validateSceneLine(themeSceneLine("theme_not_yet_invented"));
});

// ---------------------------------------------------------------------------
// 場景句驗證器
// ---------------------------------------------------------------------------

Deno.test("validateSceneLine 擋人、擋字、擋非 ASCII，不誤傷複合字", () => {
  const ok = validateSceneLine(
    "A handmade ceramic cup on a wooden table in soft light.",
  );
  assert(ok.includes("handmade"), "handmade 不得被 \\bhand\\b 誤傷");

  for (
    const [bad, reason] of [
      ["A person sitting by the window with a coffee.", "person"],
      ["A neon sign above the shop door.", "sign"],
      ["桌上有一杯咖啡與甜點。", "non-ascii"],
      ["too short", "length"],
    ] as const
  ) {
    let threw = false;
    try {
      validateSceneLine(bad);
    } catch {
      threw = true;
    }
    assert(threw, `應擋下（${reason}）：${bad}`);
  }
});

Deno.test("完整 prompt = STYLE 前綴 + 場景句，且 STYLE 自帶兩條硬規則", () => {
  const prompt = buildImagePrompt("A cup of tea on a desk in soft light.");
  assert(prompt.startsWith(MOMENT_IMAGE_STYLE_PREFIX));
  assert(prompt.endsWith("A cup of tea on a desk in soft light."));
  assert(MOMENT_IMAGE_STYLE_PREFIX.includes("No people in frame"));
  assert(MOMENT_IMAGE_STYLE_PREFIX.includes("No readable text anywhere"));
});

Deno.test("物件 key 與 seed 是決定論", () => {
  assertEquals(
    momentImagePath("2026-08-25", "practice_girl_007", 1),
    "2026-08-25/practice_girl_007_1.jpeg",
  );
  assertEquals(
    momentImageSeed("practice_girl_007", "2026-08-25", 0),
    momentImageSeed("practice_girl_007", "2026-08-25", 0),
  );
  assert(
    momentImageSeed("practice_girl_007", "2026-08-25", 0) !==
      momentImageSeed("practice_girl_007", "2026-08-25", 1),
    "不同 slot 的 seed 必須不同",
  );
});

// ---------------------------------------------------------------------------
// 生圖 job 全流程（mock）
// ---------------------------------------------------------------------------

interface JobHarness {
  supabase: MomentsImageRpcClient;
  rpcCalls: { fn: string; params: Record<string, unknown> }[];
  fetchCalls: { url: string; body: Record<string, unknown> | null }[];
  uploads: { path: string; bytes: number; contentType: string }[];
  sceneCalls: string[];
}

function makeJobHarness(options: {
  claim?: Record<string, unknown> | null;
  claimError?: string;
  commitImage?: Record<string, unknown>;
  falStatus?: number;
  falPayload?: unknown;
  imageBytes?: number;
  scene?: () => Promise<string>;
  uploadFails?: boolean;
} = {}): JobHarness & {
  deps: {
    falApiKey: string;
    deepSeekApiKey: string;
    callDeepSeek: (args: { messages: { content: string }[] }) => Promise<string>;
    uploadImage: (p: string, b: Uint8Array, c: string) => Promise<void>;
    fetch: typeof globalThis.fetch;
    randomToken: () => string;
  };
} {
  const rpcCalls: JobHarness["rpcCalls"] = [];
  const fetchCalls: JobHarness["fetchCalls"] = [];
  const uploads: JobHarness["uploads"] = [];
  const sceneCalls: string[] = [];

  const supabase: MomentsImageRpcClient = {
    rpc(fn, params) {
      rpcCalls.push({ fn, params });
      if (fn === "claim_practice_moment_image") {
        if (options.claimError) {
          return Promise.resolve({
            data: null,
            error: { message: options.claimError },
          });
        }
        const row = options.claim === null ? { claimed: false } : options.claim ?? {
          claimed: true,
          token: params.p_image_token,
          attempt_count: 1,
          body: BODY,
          theme_id: "dinner_simple",
        };
        return Promise.resolve({ data: [row], error: null });
      }
      if (fn === "commit_practice_moment_image") {
        return Promise.resolve({
          data: [options.commitImage ?? { committed: true }],
          error: null,
        });
      }
      if (fn === "release_practice_moment_image") {
        return Promise.resolve({ data: [{ released: true }], error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };

  const imageBytes = options.imageBytes ?? 20_000;
  const fetchMock = ((input: Request | URL | string, init?: RequestInit) => {
    const url = String(input);
    const requestBody = init?.body ? JSON.parse(String(init.body)) : null;
    fetchCalls.push({ url, body: requestBody });
    if (url === FAL_URL) {
      if (options.falStatus && options.falStatus !== 200) {
        return Promise.resolve(
          new Response("provider detail", { status: options.falStatus }),
        );
      }
      const payload = options.falPayload ?? { images: [{ url: CDN_URL }] };
      return Promise.resolve(
        new Response(JSON.stringify(payload), { status: 200 }),
      );
    }
    // 圖片下載
    return Promise.resolve(
      new Response(new Uint8Array(imageBytes), { status: 200 }),
    );
  }) as typeof globalThis.fetch;

  const deps = {
    falApiKey: "fal-test-key",
    deepSeekApiKey: "ds-test-key",
    callDeepSeek: async (args: { messages: { content: string }[] }) => {
      sceneCalls.push(args.messages[1]?.content ?? "");
      if (options.scene) return await options.scene();
      return JSON.stringify({
        scene: "A bowl of instant noodles on a small table at night.",
      });
    },
    uploadImage: (path: string, bytes: Uint8Array, contentType: string) => {
      if (options.uploadFails) return Promise.reject(new Error("boom"));
      uploads.push({ path, bytes: bytes.byteLength, contentType });
      return Promise.resolve();
    },
    fetch: fetchMock,
    randomToken: () => "img-token-1",
  };

  return { supabase, rpcCalls, fetchCalls, uploads, sceneCalls, deps };
}

function runJob(
  harness: ReturnType<typeof makeJobHarness>,
): Promise<void> {
  return generateMomentImage({
    supabase: harness.supabase,
    deps: harness.deps,
    job: JOB,
    userId: USER_ID,
    isTestAccount: false,
  });
}

function rpcNames(harness: { rpcCalls: { fn: string }[] }): string[] {
  return harness.rpcCalls.map((c) => c.fn);
}

Deno.test("成功路徑：claim → 場景句 → fal → 下載 → 上傳 → commit", async () => {
  const harness = makeJobHarness();
  await runJob(harness);

  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "commit_practice_moment_image",
  ]);
  // claim 帶齊限流與租約參數。
  const claim = harness.rpcCalls[0].params;
  assertEquals(claim.p_user_id, USER_ID);
  assertEquals(claim.p_count_user_usage, true);
  assertEquals(claim.p_max_attempts, MAX_MOMENT_IMAGE_ATTEMPTS);
  // 場景句呼叫的輸入只有 body 與題材 hint（隱私鐵則的行為面）。
  assertEquals(harness.sceneCalls.length, 1);
  assert(harness.sceneCalls[0].includes(BODY));
  assert(harness.sceneCalls[0].includes("sceneHint:"));
  // fal 請求：4:3、單張、jpeg、決定論 seed、prompt 含 STYLE 與場景句。
  const falCall = harness.fetchCalls.find((c) => c.url === FAL_URL);
  assert(falCall && falCall.body);
  assertEquals(falCall.body.image_size, "landscape_4_3");
  assertEquals(falCall.body.num_images, 1);
  assertEquals(falCall.body.output_format, "jpeg");
  assertEquals(falCall.body.enable_safety_checker, true);
  assertEquals(
    falCall.body.seed,
    momentImageSeed(JOB.profileId, JOB.isoDate, JOB.slot),
  );
  const prompt = String(falCall.body.prompt);
  assert(prompt.startsWith(MOMENT_IMAGE_STYLE_PREFIX));
  assert(prompt.includes("instant noodles"));
  // 上傳到決定論 key，commit 帶同一個 path 與 token。
  assertEquals(harness.uploads, [{
    path: "2026-08-25/practice_girl_007_0.jpeg",
    bytes: 20_000,
    contentType: "image/jpeg",
  }]);
  const commit = harness.rpcCalls[1].params;
  assertEquals(commit.p_image_path, "2026-08-25/practice_girl_007_0.jpeg");
  assertEquals(commit.p_image_token, "img-token-1");
});

Deno.test("claim 未成功：靜默結束，零 fal 呼叫、零上傳", async () => {
  const harness = makeJobHarness({ claim: null });
  await runJob(harness);
  assertEquals(rpcNames(harness), ["claim_practice_moment_image"]);
  assertEquals(harness.fetchCalls.length, 0);
  assertEquals(harness.uploads.length, 0);
});

Deno.test("claim 撞限流（RPC error）：靜默結束，不打 fal、不 release", async () => {
  const harness = makeJobHarness({
    claimError: 'unhandled exception: "MODEL_RATE_LIMITED_MINUTE"',
  });
  await runJob(harness);
  assertEquals(rpcNames(harness), ["claim_practice_moment_image"]);
  assertEquals(harness.fetchCalls.length, 0);
});

Deno.test("場景句失敗：退題材模板句，生圖照走且成功 commit", async () => {
  const harness = makeJobHarness({
    scene: () => Promise.reject(new Error("deepseek_timeout")),
  });
  await runJob(harness);
  const falCall = harness.fetchCalls.find((c) => c.url === FAL_URL);
  assert(falCall && falCall.body);
  assert(
    String(falCall.body.prompt).includes(themeSceneLine("dinner_simple")),
    "場景句失敗必須退回題材模板句",
  );
  assert(rpcNames(harness).includes("commit_practice_moment_image"));
});

Deno.test("場景句含禁詞：驗證器擋下後退模板句", async () => {
  const harness = makeJobHarness({
    scene: () =>
      Promise.resolve(JSON.stringify({
        scene: "A woman eating noodles at a table near a sign.",
      })),
  });
  await runJob(harness);
  const falCall = harness.fetchCalls.find((c) => c.url === FAL_URL);
  assert(falCall && falCall.body);
  assert(!String(falCall.body.prompt).includes("woman"));
  assert(String(falCall.body.prompt).includes(themeSceneLine("dinner_simple")));
});

Deno.test("fal 回 5xx：release、零上傳", async () => {
  const harness = makeJobHarness({ falStatus: 503 });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "release_practice_moment_image",
  ]);
  assertEquals(harness.uploads.length, 0);
});

Deno.test("黑圖保險：小於下限的回應視為失敗並 release", async () => {
  const harness = makeJobHarness({ imageBytes: MOMENT_IMAGE_MIN_BYTES - 1 });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "release_practice_moment_image",
  ]);
  assertEquals(harness.uploads.length, 0);
});

Deno.test("上傳失敗：release，絕不 commit", async () => {
  const harness = makeJobHarness({ uploadFails: true });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "release_practice_moment_image",
  ]);
});

Deno.test("commit 被 token fencing 打回：不 release（token 已非本 worker 所有）", async () => {
  const harness = makeJobHarness({ commitImage: { committed: false } });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "commit_practice_moment_image",
  ]);
});

Deno.test("測試帳號：p_count_user_usage 為 false", async () => {
  const harness = makeJobHarness();
  await generateMomentImage({
    supabase: harness.supabase,
    deps: harness.deps,
    job: JOB,
    userId: USER_ID,
    isTestAccount: true,
  });
  assertEquals(harness.rpcCalls[0].params.p_count_user_usage, false);
});
