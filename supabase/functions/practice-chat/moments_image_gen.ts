// 練習室動態貼文的生成配圖背景 job（PR-3）。
//
// 設計來源：docs/plans/2026-08-25-practice-moments-generated-images.md §1/§5/§9。
// 「文先圖後」：文字貼文照原路徑落地（imageId=null、image_status='pending'），
// 本模組在 EdgeRuntime.waitUntil 的背景裡把圖補上：
//
//   claim_practice_moment_image（token + 租約 + 同交易 per-user 限流）
//   → 場景句（一次便宜 DeepSeek 呼叫；失敗退題材模板句）
//   → fal.ai FLUX schnell（同步端點，1-4 步推理）
//   → 下載 → 大小檢查（黑圖保險）→ Storage upsert（決定論 key）
//   → commit_practice_moment_image（token fencing）
//   任一步失敗 → release_practice_moment_image（attempts 燒完轉 'failed' 終態）
//
// **隱私鐵則**：生圖輸入只有 committed body（本身由 server 事實生成）、
// theme_id 與本檔的常數模板，零使用者資料。moments_generated_only_source_test.ts
// 逐字串守門本檔不得 import 任何對話／記憶模組。
//
// **no-canned 的圖片版**：任何失敗都不落半成品——'failed' 是終態＝該則永久
// 純文字。場景句的「題材模板句」是**內部 prompt 的退路**，不是可見內容，
// 不違反 no-canned（該鐵則管可見文字）。
//
// fal 的 FLUX schnell API **沒有 negative_prompt 參數**（guidance-distilled 模型）；
// 素材規格書 NEGATIVE 清單的語義已折進 STYLE 前綴與每條場景句的措辭
// （no people／no readable text／室內光），黑圖保險與試打驗收再兜底一層。
import type { DeepSeekArgs } from "./deepseek.ts";
import { fnv1a } from "./moments_schedule.ts";
import { logInfo, logWarn } from "./logger.ts";
import { MODEL_RATE_LIMITS } from "../_shared/model_rate_limit.ts";
import {
  MAX_MOMENT_IMAGE_ATTEMPTS,
  MOMENT_IMAGE_DOWNLOAD_TIMEOUT_MS,
  MOMENT_IMAGE_MAX_BYTES,
  MOMENT_IMAGE_MIN_BYTES,
  MOMENT_IMAGE_MODEL_TIMEOUT_MS,
  MOMENT_IMAGE_RESERVE_LEASE_MS,
  MOMENT_IMAGE_SCENE_TIMEOUT_MS,
  MOMENT_IMAGE_UPLOAD_TIMEOUT_MS,
} from "./moments_constants.ts";

// ── 最小 RPC client 介面（與 moments_handler 的結構相容；獨立宣告避免循環）──
type Row = Record<string, unknown>;

export interface MomentsImageRpcClient {
  rpc(fn: string, params: Row): PromiseLike<{
    data: unknown;
    error: { message: string } | null;
  }>;
}

/** 生圖側的注入點；缺任一即等於 kill switch 關（呼叫端不組這個物件）。 */
export interface MomentImageGenDeps {
  falApiKey: string;
  deepSeekApiKey: string;
  callDeepSeek: (args: DeepSeekArgs) => Promise<string>;
  /** Storage upsert；失敗以 throw 表達。真實作在 handler.ts 用 supabase-js。 */
  uploadImage: (
    path: string,
    bytes: Uint8Array,
    contentType: string,
  ) => Promise<void>;
  /** 測試注入用；預設 globalThis.fetch。 */
  fetch?: typeof globalThis.fetch;
  /** 測試注入用；預設 crypto.randomUUID。 */
  randomToken?: () => string;
}

export interface MomentImageJob {
  profileId: string;
  isoDate: string;
  slot: number;
}

/** fal 生成結果 CDN 的 host allowlist：等於或屬於 fal.media 才准下載。 */
const FAL_CDN_HOST = "fal.media";

function isAllowedFalCdnUrl(raw: string): boolean {
  const uri = (() => {
    try {
      return new URL(raw);
    } catch {
      return null;
    }
  })();
  if (uri === null || uri.protocol !== "https:") return false;
  return uri.hostname === FAL_CDN_HOST ||
    uri.hostname.endsWith(`.${FAL_CDN_HOST}`);
}

const FAL_SCHNELL_ENDPOINT = "https://fal.run/fal-ai/flux/schnell";

// ── prompt 素材（字面沿用 docs/plans/2026-08-24-practice-moments-scene-image-prompts.md §4）──

/** 共用 STYLE 前綴：手機隨手拍、無人物、台北日常、深色 UI 友善。 */
export const MOMENT_IMAGE_STYLE_PREFIX =
  "Amateur smartphone photograph, taken casually with one hand. " +
  "No people in frame: no faces, no hands, no body parts, no silhouettes. " +
  "No readable text anywhere: no signage, no labels, no logos, no screens with UI. " +
  "Everyday life in Taipei, Taiwan, present day. Natural available light, soft and " +
  "slightly warm color, gentle contrast with lifted shadows, mild lens softness and " +
  "fine sensor grain. Slightly imperfect framing, lived-in and unstaged. Photorealistic. " +
  "Keep the main subject inside the central 4:3 area of the frame; leave the far left " +
  "and far right edges empty.";

/**
 * 題材級英文場景句：場景句 DeepSeek 呼叫失敗時的退路，也是給它靠攏的 hint。
 * 每一句都是「只有物件、沒有人、沒有可讀文字、看不出時間」的安全句。
 * 涵蓋 moments_schedule.ts 的全部題材 id（moments_image_gen_test.ts 逐日掃
 * 全名冊對帳，漏一個題材就紅）。
 */
const THEME_SCENE_LINES: Readonly<Record<string, string>> = {
  // ── 基本題材 ──────────────────────────────────────────────────────
  morning_commute:
    "An empty seat on a Taipei metro carriage, a handrail catching soft light, a bag resting beside the window.",
  coffee_start:
    "A cup of coffee on a small table next to a folded napkin, gentle steam rising, plain ceramic, indoor light.",
  work_grind:
    "A cluttered office desk with an open laptop showing a blurred unreadable screen, a mug and scattered sticky notes with no readable writing.",
  lunch_break:
    "A simple lunch box with rice and side dishes on a desk, chopsticks resting across the corner, indoor light.",
  afternoon_slump:
    "A half-eaten slice of cake on a plain plate beside a small cup of coffee, a fork resting on the rim.",
  off_work_walk:
    "A quiet Taipei arcade walkway in the evening with warm storefront glow, shutters half down, wet tiles reflecting light.",
  sunset_catch:
    "A wide sky over Taipei rooftops with soft orange and pink clouds, a rooftop water tower standing dark against the glow.",
  dinner_simple:
    "A small kitchen counter mid-cooking, a pan of vegetables on a gas stove, chopped scallions on a wooden board.",
  home_unwind:
    "A sofa corner with a crumpled blanket, a mug on a low table, a warm floor lamp glowing in a dim living room.",
  night_thoughts:
    "A dim bedside table with a warm lamp, a glass of water, and a phone lying screen-side down on the sheets.",
  late_snack:
    "A bowl of instant noodles with an egg on a small table at night, chopsticks resting on the rim, warm lamp light.",
  rainy_mood:
    "Raindrops running down a window pane with a blurred city behind, a mug silhouetted on the sill inside.",
  // ── 週末題材 ──────────────────────────────────────────────────────
  weekend_brunch:
    "A brunch plate with toast and eggs on a wooden table, a small glass of juice, relaxed cafe table setting.",
  weekend_outing:
    "A quiet lane in an old Taipei neighborhood with plants outside doorways and a parked bicycle, soft daylight.",
  weekend_slow:
    "A messy bed with rumpled sheets, a paperback lying open and overturned, soft light through a thin curtain.",
  // ── 興趣題材 ──────────────────────────────────────────────────────
  cafe_hunt:
    "A pour-over coffee setup on a wooden counter, a kettle and dripper, a filled cup beside them, cozy cafe corner.",
  home_kitchen:
    "A home kitchen counter with a mixing bowl, flour dusted on the surface, and a tray of something fresh out of the oven.",
  book_note:
    "An open paperback lying on a blanket with its pages softly out of focus, a warm reading lamp nearby.",
  screen_night:
    "A dim living room with a TV showing a blurred colorful frame, a remote and snacks on the sofa cushion.",
  live_music:
    "A small dark live-house stage lit in deep purple and blue, instruments standing ready, haze drifting through the light beams.",
  photo_walk:
    "A narrow Taipei street corner with layered signboards all blurred beyond reading, scooters parked along the curb.",
  travel_plan:
    "An open notebook with a pen on a desk beside a mug, a folded paper map tucked under the corner, no readable writing.",
  sea_day:
    "A northeast-coast rocky shoreline with clear blue-green water and white foam, wet stones in the foreground.",
  workout_done:
    "A rolled yoga mat and a water bottle on a gym floor beside dumbbells, soft neutral indoor light.",
  trail_day:
    "A subtropical mountain trail with stone steps rising through dense green ferns, mist between the trees.",
  pet_moment:
    "A cat curled asleep on a sofa cushion in warm afternoon shade, one paw over its nose.",
  food_find:
    "A steaming bowl of braised pork rice on a small metal table, chopsticks and a spoon resting beside it.",
  exhibition_visit:
    "A white gallery wall with one abstract original painting hung under a soft spotlight, wooden floor in front.",
  style_note:
    "A flat wooden tray with a watch, a ring, and a small bottle of lotion arranged loosely, soft window-less light.",
  night_walk:
    "A riverside path at night with evenly spaced lamps reflecting on the water, the far bank glowing softly.",
  // ── 職業題材 ──────────────────────────────────────────────────────
  shift_end:
    "A convenience-store bento and a warm drink on a small table under lamplight, chopsticks still in their wrapper.",
  clinic_day:
    "A tidy reception counter with a potted plant and a stack of plain folders, warm indoor light, no readable labels.",
  layover:
    "A carry-on suitcase by a hotel-room window at dusk, city lights blurred far below, curtain half drawn.",
  campus_grind:
    "A library desk with open books and a laptop showing a blurred document, a highlighter resting on a page of unreadable print.",
  lab_grind:
    "A lab bench with glassware, a notebook of unreadable scribbles, and a cold cup of coffee under white light.",
  shop_open:
    "An espresso machine mid-shot with a portafilter locked in, steam wand ready, cups stacked above, warm cafe light.",
  deadline_night:
    "A desk at night lit by a single lamp, a drawing tablet and pen, crumpled paper balls, a screen glowing with blurred artwork.",
  class_done:
    "An empty yoga studio with mats rolled against the wall, warm wooden floor, dim calm lighting.",
  coach_day:
    "A quiet gym corner with a barbell resting on the rack, weight plates stacked, a towel over the bench.",
  flower_shop:
    "A wrapped bouquet of seasonal flowers lying on a wooden work table among scissors, twine and loose stems.",
};

/** 題材沒有對應句時的通用安全句（新題材上線而本表漏更新時的向前相容）。 */
const GENERIC_SCENE_LINE =
  "A small everyday scene from daily life in Taipei: ordinary objects on a table in soft indoor light.";

export function themeSceneLine(themeId: string): string {
  return THEME_SCENE_LINES[themeId] ?? GENERIC_SCENE_LINE;
}

/** 測試對帳用：本表涵蓋的題材 id。 */
export function coveredThemeIds(): readonly string[] {
  return Object.keys(THEME_SCENE_LINES);
}

// ── 場景句（以文生圖的「文」）─────────────────────────────────────────

/** ASCII 可見字元＋常見標點；場景句必須全英文，供生圖模型穩定理解。 */
const ASCII_PRINTABLE = /^[\x20-\x7E]+$/;

/**
 * 場景句禁詞：人與文字是兩條硬規則（素材規格書 §3-1/§3-2），驗證器擋，
 * 不信任模型自律。\b 邊界避免誤傷（handmade 不中 hand）。
 */
const SCENE_FORBIDDEN =
  /\b(person|people|woman|women|man|men|girl|boy|lady|guy|face|faces|hand|hands|finger|fingers|selfie|portrait|crowd|silhouette|silhouettes|text|sign|signs|signage|logo|logos|brand|brands|watermark|word|words|letter|letters)\b/i;

const SCENE_MIN_CHARS = 20;
const SCENE_MAX_CHARS = 300;

/** 場景句驗證；不合格丟錯（呼叫端捕捉後退題材模板句）。 */
export function validateSceneLine(raw: unknown): string {
  if (typeof raw !== "string") throw new Error("moment_scene_not_string");
  const scene = raw.trim();
  if (scene.length < SCENE_MIN_CHARS || scene.length > SCENE_MAX_CHARS) {
    throw new Error("moment_scene_length");
  }
  if (!ASCII_PRINTABLE.test(scene)) throw new Error("moment_scene_non_ascii");
  if (SCENE_FORBIDDEN.test(scene)) throw new Error("moment_scene_forbidden_word");
  return scene;
}

/**
 * 把貼文 body 轉成英文場景句。輸入只有 body 與題材模板句（server 事實）。
 * 任何失敗回 null——生圖照跑，用題材模板句；這條路不值得燒重試。
 */
async function describeScene(opts: {
  deps: MomentImageGenDeps;
  body: string;
  themeId: string;
}): Promise<string | null> {
  const { deps, body, themeId } = opts;
  const system =
    `You turn one Traditional Chinese social feed post into a scene description for a text-to-image model.
Rules:
1. Output JSON only: {"scene": "..."}.
2. One or two English sentences describing a physical scene with objects only.
3. Absolutely no people in the scene: no faces, hands, bodies, silhouettes or crowds.
4. Nothing readable in the scene: no signs, labels, logos, brands, or screens with UI.
5. Describe what a phone camera would see, not feelings. Everyday Taipei life, present day.
6. If the post mentions specific food, drink or objects, describe exactly those.`;
  const user = `post: ${body}\nsceneHint: ${themeSceneLine(themeId)}`;
  try {
    const raw = await deps.callDeepSeek({
      apiKey: deps.deepSeekApiKey,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
      maxTokens: 150,
      temperature: 0.4,
      jsonMode: true,
      timeoutMs: MOMENT_IMAGE_SCENE_TIMEOUT_MS,
    });
    const parsed = JSON.parse(raw) as { scene?: unknown };
    return validateSceneLine(parsed.scene);
  } catch (e) {
    logWarn("practice_moment_image_scene_degraded", {
      themeId,
      failureClass: e instanceof Error ? e.message : "unknown",
    });
    return null;
  }
}

/** 完整生圖 prompt：STYLE 前綴 + 場景句。 */
export function buildImagePrompt(sceneLine: string): string {
  return `${MOMENT_IMAGE_STYLE_PREFIX}\n\n${sceneLine}`;
}

// ── 決定論 ────────────────────────────────────────────────────────────

/** Storage 物件 key：日期前綴供過期清掃按 prefix 對帳孤兒；重試覆寫同 key。 */
export function momentImagePath(
  isoDate: string,
  profileId: string,
  slot: number,
): string {
  return `${isoDate}/${profileId}_${slot}.jpeg`;
}

/** fal 的 seed：沿用排程層的種子哲學，重試時輸出接近可重現。 */
export function momentImageSeed(
  profileId: string,
  isoDate: string,
  slot: number,
): number {
  return fnv1a(`${profileId}|${isoDate}|${slot}|image_seed`);
}

// ── fal.ai client（錯誤分類照 deepseek.ts 模板；provider body 不進錯誤訊息）──

async function callFalSchnell(opts: {
  deps: MomentImageGenDeps;
  prompt: string;
  seed: number;
}): Promise<string> {
  const { deps, prompt, seed } = opts;
  const doFetch = deps.fetch ?? globalThis.fetch;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), MOMENT_IMAGE_MODEL_TIMEOUT_MS);
  let response: Response;
  try {
    response = await doFetch(FAL_SCHNELL_ENDPOINT, {
      method: "POST",
      headers: {
        "Authorization": `Key ${deps.falApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        prompt,
        image_size: "landscape_4_3",
        num_images: 1,
        output_format: "jpeg",
        enable_safety_checker: true,
        seed,
      }),
      signal: controller.signal,
    });
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") {
      throw new Error("fal_image_timeout");
    }
    throw new Error("fal_image_network");
  } finally {
    clearTimeout(timer);
  }
  if (!response.ok) {
    // 讀掉 body 避免連線懸置；內容絕不進錯誤訊息（可能含 provider 細節）。
    await response.text().catch(() => {});
    throw new Error(`fal_image_http_${response.status}`);
  }
  let payload: {
    images?: { url?: unknown }[];
    has_nsfw_concepts?: unknown;
  };
  try {
    payload = await response.json();
  } catch {
    throw new Error("fal_image_bad_json");
  }
  // safety checker 結果 fail-closed（複審 blocking item 1）：只有明確回報
  // 「第一張不是 NSFW」才放行；命中、欄位缺席或形狀不對，一律不下載、
  // 不上傳、不 commit。形狀錯用獨立錯誤碼，供應商改 schema 時觀測得出來。
  const nsfw = payload.has_nsfw_concepts;
  if (!Array.isArray(nsfw) || typeof nsfw[0] !== "boolean") {
    throw new Error("fal_image_safety_unverified");
  }
  if (nsfw[0] !== false) {
    throw new Error("fal_image_nsfw");
  }
  const url = payload.images?.[0]?.url;
  if (typeof url !== "string" || url.length === 0) {
    throw new Error("fal_image_empty");
  }
  // 只信任 fal 自家 CDN 的 https URL（複審 blocking item 2：來源驗證）。
  if (!isAllowedFalCdnUrl(url)) {
    throw new Error("fal_image_untrusted_url");
  }
  return url;
}

async function downloadImage(
  deps: MomentImageGenDeps,
  url: string,
): Promise<Uint8Array> {
  const doFetch = deps.fetch ?? globalThis.fetch;
  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort(),
    MOMENT_IMAGE_DOWNLOAD_TIMEOUT_MS,
  );
  let response: Response;
  try {
    response = await doFetch(url, { signal: controller.signal });
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") {
      throw new Error("fal_image_download_timeout");
    }
    throw new Error("fal_image_download_failed");
  } finally {
    clearTimeout(timer);
  }
  if (!response.ok) {
    await response.text().catch(() => {});
    throw new Error("fal_image_download_failed");
  }
  // MIME 驗證：只收 jpeg/png（我們指定 output_format=jpeg；png 留容錯）。
  const contentType = (response.headers.get("content-type") ?? "")
    .split(";")[0].trim().toLowerCase();
  if (contentType !== "image/jpeg" && contentType !== "image/png") {
    await response.body?.cancel().catch(() => {});
    throw new Error("fal_image_bad_content_type");
  }
  // 大小硬上限做兩層：Content-Length 預檢（省流量），再流式累計硬擋
  // （header 可缺可謊，不能只信 header）。異常大回應不落入記憶體。
  const declaredLength = Number(response.headers.get("content-length") ?? "");
  if (Number.isFinite(declaredLength) && declaredLength > MOMENT_IMAGE_MAX_BYTES) {
    await response.body?.cancel().catch(() => {});
    throw new Error("fal_image_too_large");
  }
  const reader = response.body?.getReader();
  if (!reader) throw new Error("fal_image_download_failed");
  const chunks: Uint8Array[] = [];
  let received = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      received += value.byteLength;
      if (received > MOMENT_IMAGE_MAX_BYTES) {
        await reader.cancel().catch(() => {});
        throw new Error("fal_image_too_large");
      }
      chunks.push(value);
    }
  } catch (e) {
    if (e instanceof Error && e.message === "fal_image_too_large") throw e;
    if (e instanceof DOMException && e.name === "AbortError") {
      throw new Error("fal_image_download_timeout");
    }
    throw new Error("fal_image_download_failed");
  }
  const bytes = new Uint8Array(received);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  // 黑圖保險：safety checker 之外的第二層——全黑 jpeg 遠小於正常場景圖。
  if (bytes.byteLength < MOMENT_IMAGE_MIN_BYTES) {
    throw new Error("fal_image_too_small");
  }
  return bytes;
}

/** 上傳 timeout：注入的 uploadImage 沒有自帶死線，這裡統一包。 */
async function uploadWithTimeout(
  deps: MomentImageGenDeps,
  path: string,
  bytes: Uint8Array,
  contentType: string,
): Promise<void> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    await Promise.race([
      deps.uploadImage(path, bytes, contentType),
      new Promise<never>((_, reject) => {
        timer = setTimeout(
          () => reject(new Error("fal_image_upload_timeout")),
          MOMENT_IMAGE_UPLOAD_TIMEOUT_MS,
        );
      }),
    ]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

// ── 主 job ────────────────────────────────────────────────────────────

/**
 * 背景生圖一則。永不 throw（waitUntil 的 promise 不得 unhandled rejection）；
 * 任何失敗走 release（attempts 燒完由 RPC 轉 'failed' 終態）。
 *
 * claim 未成功（別人在跑、已 ready、已 failed、限流）一律靜默結束——
 * 這是機會式接手的正常路徑，不是錯誤。
 */
export async function generateMomentImage(opts: {
  supabase: MomentsImageRpcClient;
  deps: MomentImageGenDeps;
  job: MomentImageJob;
  userId: string;
  isTestAccount: boolean;
  /** 台北今日的 feed 窗起點（YYYY-MM-DD）；claim 的出窗守衛（清理競態圍籬）。 */
  expiryBefore: string;
}): Promise<void> {
  const { supabase, deps, job, userId, isTestAccount, expiryBefore } = opts;
  const token = (deps.randomToken ?? (() => crypto.randomUUID()))();
  const limits = MODEL_RATE_LIMITS.practice_moment_image;
  const jobParams = {
    p_profile_id: job.profileId,
    p_post_date: job.isoDate,
    p_slot: job.slot,
  };

  let claimedBody: string;
  let claimedThemeId: string;
  try {
    const { data, error } = await supabase.rpc("claim_practice_moment_image", {
      ...jobParams,
      p_image_token: token,
      p_user_id: userId,
      p_minute_limit: limits.perMinute,
      p_daily_limit: limits.perDay,
      p_count_user_usage: !isTestAccount,
      p_expiry_before: expiryBefore,
      p_max_attempts: MAX_MOMENT_IMAGE_ATTEMPTS,
      p_lease_seconds: MOMENT_IMAGE_RESERVE_LEASE_MS / 1000,
    });
    if (error) {
      // 限流或 DB 錯誤：背景 job 只記錄，絕不影響 feed 回應。
      logWarn("practice_moment_image_claim_error", {
        profileId: job.profileId,
        slot: job.slot,
        error: error.message,
      });
      return;
    }
    const row = Array.isArray(data) ? (data[0] as Row | undefined) : null;
    if (!row || row.claimed !== true) return;
    claimedBody = typeof row.body === "string" ? row.body : "";
    claimedThemeId = typeof row.theme_id === "string" ? row.theme_id : "";
    if (claimedBody.length === 0) {
      // 理論上不可達（claim 只放行 status='ready'，ready 必有 body）。
      await releaseImage(supabase, jobParams, token, job);
      return;
    }
  } catch (e) {
    logWarn("practice_moment_image_claim_error", {
      profileId: job.profileId,
      slot: job.slot,
      error: e instanceof Error ? e.message : "unknown",
    });
    return;
  }

  try {
    const scene = (await describeScene({
      deps,
      body: claimedBody,
      themeId: claimedThemeId,
    })) ?? themeSceneLine(claimedThemeId);
    const imageUrl = await callFalSchnell({
      deps,
      prompt: buildImagePrompt(scene),
      seed: momentImageSeed(job.profileId, job.isoDate, job.slot),
    });
    const bytes = await downloadImage(deps, imageUrl);
    const path = momentImagePath(job.isoDate, job.profileId, job.slot);
    try {
      await uploadWithTimeout(deps, path, bytes, "image/jpeg");
    } catch (e) {
      if (e instanceof Error && e.message === "fal_image_upload_timeout") throw e;
      throw new Error("fal_image_upload_failed");
    }

    const { data, error } = await supabase.rpc(
      "commit_practice_moment_image",
      { ...jobParams, p_image_token: token, p_image_path: path },
    );
    const row = Array.isArray(data) ? (data[0] as Row | undefined) : null;
    if (error || row?.committed !== true) {
      // token fencing 打回（被接手）：物件已 upsert 到決定論 key，
      // 成功者會覆寫同一 key，無孤兒；不 release（token 已不是我的）。
      logWarn("practice_moment_image_commit_rejected", {
        profileId: job.profileId,
        slot: job.slot,
        error: error?.message ?? "not_committed",
      });
      return;
    }
    logInfo("practice_moment_image_committed", {
      profileId: job.profileId,
      slot: job.slot,
      bytes: bytes.byteLength,
    });
  } catch (e) {
    await releaseImage(supabase, jobParams, token, job);
    logWarn("practice_moment_image_failed", {
      profileId: job.profileId,
      slot: job.slot,
      failureClass: e instanceof Error ? e.message : "unknown",
    });
  }
}

async function releaseImage(
  supabase: MomentsImageRpcClient,
  jobParams: Row,
  token: string,
  job: MomentImageJob,
): Promise<void> {
  try {
    const { error } = await supabase.rpc("release_practice_moment_image", {
      ...jobParams,
      p_image_token: token,
      p_max_attempts: MAX_MOMENT_IMAGE_ATTEMPTS,
    });
    if (error) {
      logWarn("practice_moment_image_release_error", {
        profileId: job.profileId,
        slot: job.slot,
        error: error.message,
      });
    }
  } catch (e) {
    logWarn("practice_moment_image_release_error", {
      profileId: job.profileId,
      slot: job.slot,
      error: e instanceof Error ? e.message : "unknown",
    });
  }
}
