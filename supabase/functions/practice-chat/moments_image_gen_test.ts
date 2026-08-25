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
const TOKEN = "img-token-1";
const TOKEN_PATH = `${JOB.isoDate}/${JOB.profileId}_${JOB.slot}_${TOKEN}.jpeg`;

/** 產生開頭是合法 JPEG magic（FF D8 FF）的假圖 bytes。 */
function fakeJpeg(size: number): Uint8Array<ArrayBuffer> {
  const bytes = new Uint8Array(size);
  if (size >= 3) {
    bytes[0] = 0xFF;
    bytes[1] = 0xD8;
    bytes[2] = 0xFF;
  }
  return bytes;
}

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

Deno.test("物件 key 以 token 隔離且 seed 是決定論", () => {
  assertEquals(
    momentImagePath("2026-08-25", "practice_girl_007", 1, "tok-a"),
    "2026-08-25/practice_girl_007_1_tok-a.jpeg",
  );
  assert(
    momentImagePath("2026-08-25", "practice_girl_007", 1, "tok-a") !==
      momentImagePath("2026-08-25", "practice_girl_007", 1, "tok-b"),
    "不同 token 必須寫不同物件（晚到上傳碰不到 winner）",
  );
  assertEquals(
    momentImageSeed("practice_girl_007", "2026-08-25", 0, 1),
    momentImageSeed("practice_girl_007", "2026-08-25", 0, 1),
  );
  assert(
    momentImageSeed("practice_girl_007", "2026-08-25", 0, 1) !==
      momentImageSeed("practice_girl_007", "2026-08-25", 1, 1),
    "不同 slot 的 seed 必須不同",
  );
  assert(
    momentImageSeed("practice_girl_007", "2026-08-25", 0, 1) !==
      momentImageSeed("practice_girl_007", "2026-08-25", 0, 2),
    "不同 attempt 的 seed 必須不同——內容相依的失敗重試才有意義",
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
  removals: string[];
  sceneCalls: string[];
}

function makeJobHarness(options: {
  claim?: Record<string, unknown> | null;
  claimError?: string;
  commitImage?: Record<string, unknown>;
  /** commit RPC 直接拋錯（DB 連線炸掉之類）。 */
  commitThrows?: boolean;
  falStatus?: number;
  falPayload?: unknown;
  imageBytes?: number;
  scene?: () => Promise<string>;
  uploadFails?: boolean;
  /** 上傳懸掛；harness.releaseUpload() 使晚到的上傳完成。 */
  uploadHangs?: boolean;
  downloadContentType?: string;
  downloadDeclaredLength?: number;
  /** fal JSON body 永不完結（測 hanging body timeout）。 */
  falBodyHangs?: boolean;
  /** 圖片串流永不完結（測 hanging stream timeout）。 */
  imageStreamHangs?: boolean;
  /** 圖片 URL 觸發轉址（redirect:"error" 下 reject）。 */
  imageRedirects?: boolean;
  /** 圖不帶 JPEG magic（測 magic bytes 驗證）。 */
  badMagic?: boolean;
} = {}): JobHarness & {
  deps: {
    falApiKey: string;
    deepSeekApiKey: string;
    callDeepSeek: (args: { messages: { content: string }[] }) => Promise<string>;
    uploadImage: (p: string, b: Uint8Array, c: string) => Promise<void>;
    fetch: typeof globalThis.fetch;
    randomToken: () => string;
    removeImage: (p: string) => Promise<void>;
    falTimeoutMs: number;
    downloadTimeoutMs: number;
    uploadTimeoutMs: number;
  };
  releaseUpload: () => void;
} {
  const rpcCalls: JobHarness["rpcCalls"] = [];
  const fetchCalls: JobHarness["fetchCalls"] = [];
  const uploads: JobHarness["uploads"] = [];
  const removals: string[] = [];
  const sceneCalls: string[] = [];
  let releaseUpload: () => void = () => {};

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
        if (options.commitThrows) {
          return Promise.reject(new Error("db connection lost"));
        }
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
  /** signal abort 時 error 掉、否則永不完結的 body（模擬懸掛連線）。 */
  const hangingBody = (signal: AbortSignal | null | undefined) =>
    new ReadableStream<Uint8Array>({
      start(ctrl) {
        signal?.addEventListener("abort", () => {
          ctrl.error(new DOMException("aborted", "AbortError"));
        });
      },
    });
  const fetchMock = ((input: Request | URL | string, init?: RequestInit) => {
    const url = String(input);
    const requestBody = init?.body ? JSON.parse(String(init.body)) : null;
    fetchCalls.push({ url, body: requestBody });
    if (url === FAL_URL) {
      if (options.falBodyHangs) {
        return Promise.resolve(
          new Response(hangingBody(init?.signal), { status: 200 }),
        );
      }
      if (options.falStatus && options.falStatus !== 200) {
        return Promise.resolve(
          new Response("provider detail", { status: options.falStatus }),
        );
      }
      const payload = options.falPayload ?? {
        images: [{ url: CDN_URL }],
        has_nsfw_concepts: [false],
      };
      return Promise.resolve(
        new Response(JSON.stringify(payload), { status: 200 }),
      );
    }
    // 圖片下載
    if (options.imageRedirects) {
      // redirect:"error" 下，真 fetch 遇到轉址會 reject。
      return Promise.reject(new TypeError("redirect not allowed"));
    }
    const headers: Record<string, string> = {
      "content-type": options.downloadContentType ?? "image/jpeg",
    };
    if (options.downloadDeclaredLength !== undefined) {
      headers["content-length"] = String(options.downloadDeclaredLength);
    }
    if (options.imageStreamHangs) {
      return Promise.resolve(
        new Response(hangingBody(init?.signal), { status: 200, headers }),
      );
    }
    const bytes = options.badMagic
      ? new Uint8Array(imageBytes)
      : fakeJpeg(imageBytes);
    return Promise.resolve(new Response(bytes, { status: 200, headers }));
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
      if (options.uploadHangs) {
        // 懸掛直到測試呼叫 releaseUpload()——模擬「timeout 後晚到完成」。
        return new Promise<void>((resolve) => {
          releaseUpload = () => {
            uploads.push({ path, bytes: bytes.byteLength, contentType });
            resolve();
          };
        });
      }
      if (options.uploadFails) return Promise.reject(new Error("boom"));
      uploads.push({ path, bytes: bytes.byteLength, contentType });
      return Promise.resolve();
    },
    removeImage: (path: string) => {
      removals.push(path);
      return Promise.resolve();
    },
    fetch: fetchMock,
    randomToken: () => TOKEN,
    // 測試不等真時鐘：懸掛類測試用短 timeout。
    falTimeoutMs: 150,
    downloadTimeoutMs: 150,
    uploadTimeoutMs: 150,
  };

  return {
    supabase,
    rpcCalls,
    fetchCalls,
    uploads,
    removals,
    sceneCalls,
    deps,
    releaseUpload: () => releaseUpload(),
  };
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
  assert(
    !("p_expiry_before" in claim),
    "cutoff 由 DB 端以當下 now() 計算，呼叫端不得傳 snapshot",
  );
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
    momentImageSeed(JOB.profileId, JOB.isoDate, JOB.slot, 1),
    "seed 必須混入 claim 回傳的 attempt（重試才不會生出同一張再失敗一次）",
  );
  const prompt = String(falCall.body.prompt);
  assert(prompt.startsWith(MOMENT_IMAGE_STYLE_PREFIX));
  assert(prompt.includes("instant noodles"));
  // 上傳到 token 隔離的 key，commit 帶同一個 path、token 與出窗守衛。
  assertEquals(harness.uploads, [{
    path: TOKEN_PATH,
    bytes: 20_000,
    contentType: "image/jpeg",
  }]);
  const commit = harness.rpcCalls[1].params;
  assertEquals(commit.p_image_path, TOKEN_PATH);
  assertEquals(commit.p_image_token, TOKEN);
  assert(!("p_expiry_before" in commit));
  assertEquals(harness.removals, [], "winner 不刪自己的物件");
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

Deno.test("commit 被 fencing 或出窗守衛打回：自刪物件、不 release", async () => {
  const harness = makeJobHarness({ commitImage: { committed: false } });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "commit_practice_moment_image",
  ]);
  assertEquals(
    harness.removals,
    [TOKEN_PATH],
    "被打回的 worker 必須收掉自己剛上傳的物件",
  );
});

// ---------------------------------------------------------------------------
// 複審 blocking items 1-2：NSFW fail-closed 與下載邊界
// ---------------------------------------------------------------------------

Deno.test("NSFW 命中：不下載、不上傳、不 commit，直接 release", async () => {
  const harness = makeJobHarness({
    falPayload: { images: [{ url: CDN_URL }], has_nsfw_concepts: [true] },
  });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "release_practice_moment_image",
  ]);
  assertEquals(
    harness.fetchCalls.filter((c) => c.url === CDN_URL).length,
    0,
    "NSFW 命中絕不下載",
  );
  assertEquals(harness.uploads.length, 0);
});

Deno.test("safety 欄位缺席或形狀錯：fail-closed，一樣 release", async () => {
  for (
    const payload of [
      { images: [{ url: CDN_URL }] },
      { images: [{ url: CDN_URL }], has_nsfw_concepts: "no" },
      { images: [{ url: CDN_URL }], has_nsfw_concepts: [] },
    ]
  ) {
    const harness = makeJobHarness({ falPayload: payload });
    await runJob(harness);
    assertEquals(
      rpcNames(harness),
      ["claim_practice_moment_image", "release_practice_moment_image"],
      `payload ${JSON.stringify(payload)} 應 fail-closed`,
    );
    assertEquals(harness.uploads.length, 0);
  }
});

Deno.test("非 fal.media 的結果 URL：拒絕下載並 release", async () => {
  for (
    const url of [
      "https://evil.example.com/x.jpeg",
      "http://fal.media/x.jpeg",
      "https://notfal.media/x.jpeg",
      "https://fal.media.evil.com/x.jpeg",
    ]
  ) {
    const harness = makeJobHarness({
      falPayload: { images: [{ url }], has_nsfw_concepts: [false] },
    });
    await runJob(harness);
    assertEquals(
      rpcNames(harness),
      ["claim_practice_moment_image", "release_practice_moment_image"],
      `URL ${url} 應被來源驗證擋下`,
    );
    assertEquals(harness.uploads.length, 0);
  }
});

Deno.test("下載回應的 Content-Type 不是圖片：release", async () => {
  const harness = makeJobHarness({ downloadContentType: "text/html" });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "release_practice_moment_image",
  ]);
  assertEquals(harness.uploads.length, 0);
});

Deno.test("Content-Length 宣告超限：不讀 body 直接 release", async () => {
  const harness = makeJobHarness({ downloadDeclaredLength: 999_000_000 });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "release_practice_moment_image",
  ]);
});

Deno.test("實際位元組超限（header 說謊）：流式硬擋並 release", async () => {
  const harness = makeJobHarness({
    imageBytes: 4_000_001,
    downloadDeclaredLength: 20_000,
  });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "release_practice_moment_image",
  ]);
  assertEquals(harness.uploads.length, 0);
});

// ---------------------------------------------------------------------------
// 第二輪複審 P1-1／P1-2／P2-3：晚到上傳、懸掛 body、轉址、magic bytes
// ---------------------------------------------------------------------------

Deno.test("上傳 timeout 後晚到完成：自刪自己的物件，winner 不受影響", async () => {
  const harness = makeJobHarness({ uploadHangs: true });
  await runJob(harness);
  // timeout → release（job 已放棄）。
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "release_practice_moment_image",
  ]);
  assertEquals(harness.removals, [], "上傳還沒完成，無物件可刪");
  // 晚到的上傳此刻才完成 → 自刪必須跟上。
  harness.releaseUpload();
  await new Promise((resolve) => setTimeout(resolve, 10));
  assertEquals(harness.uploads.length, 1, "晚到的上傳確實落地過");
  assertEquals(
    harness.removals,
    [TOKEN_PATH],
    "晚到的上傳完成後必須自刪，不留 public 孤兒",
  );
});

Deno.test("fal JSON body 懸掛：timeout 涵蓋完整 body，release 收場", async () => {
  const harness = makeJobHarness({ falBodyHangs: true });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "release_practice_moment_image",
  ]);
  assertEquals(harness.uploads.length, 0);
});

Deno.test("圖片串流懸掛：timeout 涵蓋整段下載，release 收場", async () => {
  const harness = makeJobHarness({ imageStreamHangs: true });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "release_practice_moment_image",
  ]);
  assertEquals(harness.uploads.length, 0);
});

Deno.test("圖片下載遇到轉址：redirect error 直接拒絕並 release", async () => {
  const harness = makeJobHarness({ imageRedirects: true });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "release_practice_moment_image",
  ]);
  assertEquals(harness.uploads.length, 0);
});

Deno.test("兩個 fetch 都以 redirect:error 發出", async () => {
  const harness = makeJobHarness({});
  const seenRedirects: (string | undefined)[] = [];
  const inner = harness.deps.fetch;
  harness.deps.fetch = ((input: Request | URL | string, init?: RequestInit) => {
    seenRedirects.push(init?.redirect);
    return inner(input, init);
  }) as typeof globalThis.fetch;
  await runJob(harness);
  assertEquals(seenRedirects, ["error", "error"]);
});

Deno.test("Content-Type 是 png：僅收 jpeg，拒絕並 release", async () => {
  const harness = makeJobHarness({ downloadContentType: "image/png" });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "release_practice_moment_image",
  ]);
});

Deno.test("magic bytes 不是 JPEG：header 說謊也擋，release 收場", async () => {
  const harness = makeJobHarness({ badMagic: true });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "release_practice_moment_image",
  ]);
  assertEquals(harness.uploads.length, 0);
});

Deno.test("commit RPC 拋錯（結果不確定）：保留物件、release 收場", async () => {
  // DB 可能其實已 commit（回應在路上丟了）；刪物件會讓 ready 列指向 404
  // 一整個窗期（作者側終審修正）。孤兒情況由出窗 prefix 對帳兜底。
  const harness = makeJobHarness({ commitThrows: true });
  await runJob(harness);
  assertEquals(rpcNames(harness), [
    "claim_practice_moment_image",
    "commit_practice_moment_image",
    "release_practice_moment_image",
  ]);
  assertEquals(
    harness.removals,
    [],
    "結果不確定時絕不刪物件——它可能已被 DB 引用",
  );
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
