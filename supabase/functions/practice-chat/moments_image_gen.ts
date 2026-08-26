// 練習室動態貼文的生成配圖背景 job（PR-3）。
//
// 設計來源：docs/plans/2026-08-25-practice-moments-generated-images.md §1/§5/§9。
// 「文先圖後」：文字貼文照原路徑落地（imageId=null、image_status='pending'），
// 本模組在 EdgeRuntime.waitUntil 的背景裡把圖補上：
//
//   claim_practice_moment_image（token + 租約 + 同交易 per-user 限流）
//   → 場景句（一次便宜 DeepSeek 呼叫；失敗退題材模板句）
//   → fal.ai Seedream 4.5（同步端點；2026-08-26 從 FLUX schnell 換過來，
//     schnell 出的圖普遍是塑膠感／CG 感）
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
// fal 的 Seedream 4.5 API **沒有 negative_prompt 參數**；
// 素材規格書 NEGATIVE 清單的語義已折進 STYLE 前綴與每條場景句的措辭
// （no people／no readable text／室內光），黑圖保險與試打驗收再兜底一層。
import type { DeepSeekArgs } from "./deepseek.ts";
import { fnv1a } from "./moments_schedule.ts";
import { logInfo, logWarn } from "./logger.ts";
import { MODEL_RATE_LIMITS } from "../_shared/model_rate_limit.ts";
import {
  MAX_MOMENT_IMAGE_ATTEMPTS,
  MOMENT_IMAGE_CONTENT_TYPE,
  MOMENT_IMAGE_EXTENSION,
  MOMENT_IMAGE_SIZE_PRESET,
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
  /**
   * Storage 上傳（**不 upsert**——路徑以 token 隔離，永不覆寫）；
   * 失敗以 throw 表達。真實作在 handler.ts 用 supabase-js。
   */
  uploadImage: (
    path: string,
    bytes: Uint8Array,
    contentType: string,
  ) => Promise<void>;
  /**
   * Storage 刪單一物件（best effort）。輸家自刪用：上傳晚到（timeout 後
   * 才完成）或 commit 被打回時，把自己剛上傳的 token 路徑物件收掉。
   */
  removeImage: (path: string) => Promise<void>;
  /** 測試注入用；預設 globalThis.fetch。 */
  fetch?: typeof globalThis.fetch;
  /** 測試注入用；預設 crypto.randomUUID。 */
  randomToken?: () => string;
  /** 測試注入用的 timeout 覆寫；production 一律走常數。 */
  falTimeoutMs?: number;
  downloadTimeoutMs?: number;
  uploadTimeoutMs?: number;
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
  // 1. fal 自家 CDN：fal.media 與其子網域（實際回應見過 v3b.fal.media）。
  if (
    uri.hostname === FAL_CDN_HOST ||
    uri.hostname.endsWith(`.${FAL_CDN_HOST}`)
  ) {
    return true;
  }
  // 2. fal 的 GCS bucket：官方 output 範例是
  //    https://storage.googleapis.com/falserverless/...（第一輪複審 P1-2：
  //    只放行 fal.media 會把供應商成功生成的圖擋掉）。**精確 host ＋ 該
  //    bucket 的路徑前綴**兩個條件同時成立才放行——不是「放寬成任意
  //    GCS 物件」，更不是任意外部 URL。URL 解析會正規化路徑，所以
  //    /falserverless/../other 這種跳脫會落在別的前綴而被拒。
  return uri.hostname === FAL_GCS_HOST &&
    uri.pathname.startsWith(FAL_GCS_PATH_PREFIX);
}

/** fal 託管輸出的 GCS bucket（官方 output 範例的 host 與路徑前綴）。 */
const FAL_GCS_HOST = "storage.googleapis.com";
const FAL_GCS_PATH_PREFIX = "/falserverless/";

const FAL_IMAGE_ENDPOINT =
  "https://fal.run/fal-ai/bytedance/seedream/v4.5/text-to-image";

/**
 * Seedream 4.5 的 custom image_size 合法性（官方 schema 原文）：
 * 「Width and height must be between 1920 and 4096, or total number of
 * pixels must be between 2560*1440 and 4096*4096.」
 *
 * production 送的是 enum preset，不會走到這裡；這支函式存在的目的是把
 * 規則寫成可執行的斷言，讓測試守住「日後有人改成自訂數字」的邊界
 * （第一輪複審 P1-1 就是自訂數字兩條都不滿足）。
 */
export function isLegalSeedreamImageSize(
  size: { width: number; height: number },
): boolean {
  const { width, height } = size;
  if (!Number.isInteger(width) || !Number.isInteger(height)) return false;
  const bothAxesInRange = width >= 1920 && width <= 4096 &&
    height >= 1920 && height <= 4096;
  const totalPixels = width * height;
  const totalInRange = totalPixels >= 2560 * 1440 &&
    totalPixels <= 4096 * 4096;
  return bothAxesInRange || totalInRange;
}

/** PNG 檔頭：89 50 4E 47 0D 0A 1A 0A。 */
const PNG_MAGIC = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] as const;

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
  // ── 社會觀察／感情／價值觀 ────────────────────────────────────────
  social_ai_everyday:
    "A closed silver laptop beside a plain notebook and a ceramic mug on a tidy desk, soft evening light.",
  social_after_hours:
    "A phone lying screen-side down beside a closed laptop on a dining table after dark, a small lamp glowing nearby.",
  social_online_comparison:
    "A phone resting screen-side down beside a small mirror and an unfinished cup of tea on a bedroom table.",
  social_public_courtesy:
    "A neat row of empty seats inside a quiet city train carriage, soft daylight through the windows.",
  relationship_pace:
    "Two ceramic cups cooling at different places on a small table, one chair slightly pulled back.",
  relationship_reciprocity:
    "Two matching mugs on opposite sides of a wooden table, both partly finished under warm light.",
  relationship_own_life:
    "A single reading chair by a window with a book, headphones, and a small plant nearby.",
  relationship_disagreement:
    "Two mugs set apart on a kitchen counter, a folded dish towel between them, quiet evening light.",
  value_time:
    "A simple analog clock beside keys and a half-finished cup of tea on a clear wooden shelf.",
  value_reliability:
    "A neatly folded umbrella drying beside a pair of shoes at an apartment doorway after rain.",
  value_spending:
    "A closed wallet beside a few coins and a plain paper receipt turned over on a table.",
  value_unfilled_time:
    "An empty balcony chair beside a small table with tea, late afternoon light and open sky beyond.",
  interest_current_fixation:
    "A small collection of hobby tools and everyday objects arranged loosely on a desk under warm light.",
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
  pet_house_rules:
    "A pet bed occupying the center of a sofa, a folded blanket pushed to one side in warm indoor light.",
  pet_care_detail:
    "A pet food bowl beside a grooming brush and a folded towel on a clean floor mat.",
  pet_owner_routine:
    "A small pet bowl beside a water dish and a folded cleaning cloth in a lived-in kitchen corner.",
  food_find:
    "A steaming bowl of braised pork rice on a small metal table, chopsticks and a spoon resting beside it.",
  exhibition_visit:
    "A white gallery wall with one abstract original painting hung under a soft spotlight, wooden floor in front.",
  style_note:
    "A flat wooden tray with a watch, a ring, and a small bottle of lotion arranged loosely, soft window-less light.",
  night_walk:
    "A riverside path at night with evenly spaced lamps reflecting on the water, the far bank glowing softly.",
  money_habit:
    "A closed wallet, a small coin tray, and a ceramic cup arranged on a plain wooden desk.",
  audio_note:
    "A pair of headphones beside a small audio recorder and a warm desk lamp in a quiet room.",
  making_things:
    "A work table with clay, pencils, scissors, and a small unfinished craft piece under soft window light.",
  tech_curiosity:
    "A laptop with a softly blurred display beside a compact keyboard, notebook, and mug on a clean desk.",
  city_detail:
    "A quiet old brick arcade with patterned floor tiles, potted plants, and soft daylight at the far end.",
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
  grooming_day:
    "A clean grooming table with a brush, comb, folded towel, and small spray bottle arranged nearby.",
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

/**
 * Storage 物件 key：**以 image_token 隔離**（2026-08-25 第二輪複審 P1-1）。
 * 每次認領寫自己的路徑，晚到的舊上傳在物理上碰不到 winner 的物件；
 * 輸家（timeout 晚到、commit 被打回）自刪自己的物件。日期前綴供過期
 * 清掃按 prefix 對帳孤兒。
 */
export function momentImagePath(
  isoDate: string,
  profileId: string,
  slot: number,
  imageToken: string,
): string {
  return `${isoDate}/${profileId}_${slot}_${imageToken}.${MOMENT_IMAGE_EXTENSION}`;
}

/**
 * fal 的 seed：沿用排程層的種子哲學（同輸入可重現），但混入 attempt——
 * 內容相依的失敗（NSFW 命中、黑圖）若用同 seed 重試，會生出同一張圖、
 * 以同一種方式再失敗，第二次 attempt 等於白燒（作者側終審發現）。
 */
export function momentImageSeed(
  profileId: string,
  isoDate: string,
  slot: number,
  attempt: number,
): number {
  return fnv1a(`${profileId}|${isoDate}|${slot}|image_seed|${attempt}`);
}

// ── fal.ai client（錯誤分類照 deepseek.ts 模板；provider body 不進錯誤訊息）──

async function callFalImageModel(opts: {
  deps: MomentImageGenDeps;
  prompt: string;
  seed: number;
}): Promise<string> {
  const { deps, prompt, seed } = opts;
  const doFetch = deps.fetch ?? globalThis.fetch;
  const controller = new AbortController();
  // timer 的生命週期必須涵蓋**完整 response body**（第二輪複審 P1-2）：
  // headers 到了之後 json() 仍可能無限掛，太早 clear 等於沒有 timeout。
  const timer = setTimeout(
    () => controller.abort(),
    deps.falTimeoutMs ?? MOMENT_IMAGE_MODEL_TIMEOUT_MS,
  );
  let payload: {
    images?: { url?: unknown }[];
  };
  try {
    let response: Response;
    try {
      response = await doFetch(FAL_IMAGE_ENDPOINT, {
        method: "POST",
        headers: {
          "Authorization": `Key ${deps.falApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          prompt,
          // **用官方 enum，不要自己算數字**（第一輪複審 P1-1）：Seedream 4.5
          // 的 custom size 規則是「兩軸皆在 1920-4096」**或**「總像素落在
          // 2560×1440 到 4096×4096」，先前自訂的 1920×1440 兩條都不滿足
          // （高度 1440 低於 1920、總像素 2.76MP 低於 3.69MP 下限），
          // production 會被供應商打回。enum 由 fal 自己映射到該模型的合法
          // 尺寸，構造上不可能違規；代價只是實際像素數未公開。
          // isLegalSeedreamImageSize 把上面那條規則寫成程式，測試用它守住
          // 「日後有人改回自訂數字」的邊界。
          image_size: MOMENT_IMAGE_SIZE_PRESET,
          num_images: 1,
          // 一次生成最多回幾張。固定 1，避免付了多張的錢又只用一張。
          max_images: 1,
          // **安全鐵則：這個旗標永遠是 true。**（見下方 safety 註解；
          // moments_image_gen_test.ts 有測試釘住它。）
          enable_safety_checker: true,
          seed,
        }),
        signal: controller.signal,
        // API 端點不該轉址；有轉址一律當異常拒絕。
        redirect: "error",
      });
    } catch (e) {
      if (e instanceof DOMException && e.name === "AbortError") {
        throw new Error("fal_image_timeout");
      }
      throw new Error("fal_image_network");
    }
    if (!response.ok) {
      // 讀掉 body 避免連線懸置；內容絕不進錯誤訊息（可能含 provider 細節）。
      await response.text().catch(() => {});
      throw new Error(`fal_image_http_${response.status}`);
    }
    try {
      payload = await response.json();
    } catch (e) {
      if (e instanceof DOMException && e.name === "AbortError") {
        throw new Error("fal_image_timeout");
      }
      throw new Error("fal_image_bad_json");
    }
  } finally {
    clearTimeout(timer);
  }
  // ## Safety 契約（2026-08-26 換 Seedream 4.5 時的**明確降級**，請複審注意）
  //
  // 換模型前的 FLUX schnell 回應帶 `has_nsfw_concepts` 逐張布林，舊版能做到
  // 「只有明確回報 false 才放行」的 fail-closed 判定。**Seedream 4.5 的
  // output schema 只有 `images` 與 `seed`，沒有任何 NSFW 欄位**（fal 官方
  // OpenAPI 查證），因此那道逐張判定在這個模型上不存在，硬留著只會 100%
  // 擋掉所有圖。
  //
  // 取代它的是三層：
  // 1. **平台端 safety checker**：請求固定帶 `enable_safety_checker: true`
  //    （schema 預設即為 true，關掉還需要帳號授權）。**但要說清楚它保證
  //    到哪裡**：官方 schema 只保證這個檢查可以被啟用，**沒有**規定命中時
  //    的回應形狀（HTTP error？空 images？黑圖？）。所以我們不依賴任何
  //    特定的失敗形狀——不論回來的是錯誤碼、沒有 images、還是一張擋不住
  //    的圖，都由既有路徑各自收斂（HTTP 錯誤 → fal_image_http_*；沒有
  //    images → fal_image_empty；不是 PNG／太小 → 對應的 failureClass）。
  //    我們**不能**宣稱「不合格的圖絕不會到我們手上」。
  // 2. **輸入端硬約束**：prompt 前綴明文禁人物、禁可讀文字、禁品牌，且
  //    場景句本身經 validateSceneLine 過濾（禁詞、ASCII、長度）。
  // 3. **黑圖保險**：min-bytes 仍在（見 downloadImage）。
  //
  // 代價要說清楚：我們少了一個「供應商自己說這張有問題」的訊號，也少了
  // fal_image_nsfw / fal_image_safety_unverified 這兩個觀測點，而剩下的
  // 三層都不是逐張的內容判定。若日後換回有逐張判定的模型，把 fail-closed
  // 那段加回來即是。
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
  // timer 涵蓋 headers ＋ 完整串流（第二輪複審 P1-2）：reader.read() 可能
  // 無限掛，clear 必須等 body 讀完才做。
  const timer = setTimeout(
    () => controller.abort(),
    deps.downloadTimeoutMs ?? MOMENT_IMAGE_DOWNLOAD_TIMEOUT_MS,
  );
  try {
    let response: Response;
    try {
      // 轉址直接拒絕：allowlist 驗的是原始 URL，跟隨轉址等於讓 CDN 帶我們
      // 離開 fal.media。fal 正常回應不轉址。
      response = await doFetch(url, {
        signal: controller.signal,
        redirect: "error",
      });
    } catch (e) {
      if (e instanceof DOMException && e.name === "AbortError") {
        throw new Error("fal_image_download_timeout");
      }
      throw new Error("fal_image_download_failed");
    }
    // 縱深：runtime 若仍回報了最終 URL，驗它沒有離開 allowlist
    // （redirect:"error" 是主防線；手造 Response 的 url 為空字串則略過）。
    if (response.url && !isAllowedFalCdnUrl(response.url)) {
      await response.body?.cancel().catch(() => {});
      throw new Error("fal_image_untrusted_url");
    }
    if (!response.ok) {
      await response.text().catch(() => {});
      throw new Error("fal_image_download_failed");
    }
    // MIME 驗證：**只收 image/png**（第二輪複審 P2-3 的同一道守門；
    // Seedream 4.5 沒有 output_format 參數、固定出 PNG，寫入的副檔名與
    // contentType 也一起是 png，不收異類）。
    const contentType = (response.headers.get("content-type") ?? "")
      .split(";")[0].trim().toLowerCase();
    if (contentType !== MOMENT_IMAGE_CONTENT_TYPE) {
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
    // magic bytes：PNG 必以 89 50 4E 47 0D 0A 1A 0A 開頭——contentType
    // header 可謊，位元組不會。
    if (
      bytes.byteLength < PNG_MAGIC.length ||
      PNG_MAGIC.some((byte, index) => bytes[index] !== byte)
    ) {
      throw new Error("fal_image_bad_magic");
    }
    // 黑圖保險：平台端 safety checker 之外的第二層——近乎單色的圖無損
    // 壓縮後遠小於正常場景圖。
    if (bytes.byteLength < MOMENT_IMAGE_MIN_BYTES) {
      throw new Error("fal_image_too_small");
    }
    return bytes;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * 上傳 timeout。底層 supabase-js 上傳收不到取消訊號，所以 timeout 是
 * 「本 job 放棄等待」而不是「上傳被中止」——安全性由兩件事保證
 * （第二輪複審 P1-1）：
 * 1. 物件路徑以 token 隔離：晚到的上傳只會寫到**自己的**路徑，物理上
 *    碰不到 winner 的物件，也不可能在清理後重建 committed 物件。
 * 2. 晚到的上傳完成後**自刪**（best effort）：race 輸掉時在原 promise 上
 *    掛 removeImage，孤兒不落地；失敗再由日期 prefix 對帳兜底。
 */
async function uploadWithTimeout(
  deps: MomentImageGenDeps,
  path: string,
  bytes: Uint8Array,
  contentType: string,
): Promise<void> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const upload = deps.uploadImage(path, bytes, contentType);
  try {
    await Promise.race([
      upload,
      new Promise<never>((_, reject) => {
        timer = setTimeout(
          () => reject(new Error("fal_image_upload_timeout")),
          deps.uploadTimeoutMs ?? MOMENT_IMAGE_UPLOAD_TIMEOUT_MS,
        );
      }),
    ]);
  } catch (e) {
    if (e instanceof Error && e.message === "fal_image_upload_timeout") {
      // 晚到的上傳完成後自刪。這是**快路徑**，不是保證：實例被回收時這個
      // detached promise 就沒了。持久保證在孤兒帳本——路徑已在 claim 的同
      // 一筆交易記下，物件不管幾點落地，清算都找得到它（第四輪複審 P2-2）。
      upload
        .then(() => deps.removeImage(path))
        .catch(() => {});
    } else {
      // 上傳自身失敗：確保 race 的 rejection 不外洩成 unhandled。
      upload.catch(() => {});
    }
    throw e;
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
}): Promise<void> {
  const { supabase, deps, job, userId, isTestAccount } = opts;
  const token = (deps.randomToken ?? (() => crypto.randomUUID()))();
  // 物件路徑在 claim 之前就算得出來（token 由這裡產生），所以它可以跟著
  // claim 進同一筆交易記進孤兒帳本——「我可能會寫這個物件」這件事在物件
  // 存在之前就已經持久化了（第四輪複審 P2-2）。
  const path = momentImagePath(job.isoDate, job.profileId, job.slot, token);
  const limits = MODEL_RATE_LIMITS.practice_moment_image;
  const jobParams = {
    p_profile_id: job.profileId,
    p_post_date: job.isoDate,
    p_slot: job.slot,
  };

  let claimedBody: string;
  let claimedThemeId: string;
  let claimedAttempt: number;
  try {
    const { data, error } = await supabase.rpc("claim_practice_moment_image", {
      ...jobParams,
      p_image_token: token,
      p_image_path: path,
      p_user_id: userId,
      p_minute_limit: limits.perMinute,
      p_daily_limit: limits.perDay,
      p_count_user_usage: !isTestAccount,
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
    claimedAttempt = typeof row.attempt_count === "number" ? row.attempt_count : 1;
    if (claimedBody.length === 0) {
      // 理論上不可達（claim 只放行 status='ready'，ready 必有 body）。
      // 連上傳都沒開始，帳本那一筆確定沒有物件，一併抹掉。
      await clearOrphanLedger(supabase, path);
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

  let uploadedPath: string | null = null;
  // 「上傳這件事有沒有發生過」與「上傳有沒有成功」是兩回事：上傳一旦發出，
  // 就算最後回錯或 timeout，物件都可能已經在 Storage 上（回應在路上丟了也
  // 算）。只有**完全沒發出**的失敗才能安全地抹掉帳本紀錄。
  let uploadAttempted = false;
  try {
    const scene = (await describeScene({
      deps,
      body: claimedBody,
      themeId: claimedThemeId,
    })) ?? themeSceneLine(claimedThemeId);
    const imageUrl = await callFalImageModel({
      deps,
      prompt: buildImagePrompt(scene),
      seed: momentImageSeed(job.profileId, job.isoDate, job.slot, claimedAttempt),
    });
    const bytes = await downloadImage(deps, imageUrl);
    try {
      uploadAttempted = true;
      await uploadWithTimeout(deps, path, bytes, MOMENT_IMAGE_CONTENT_TYPE);
      uploadedPath = path;
    } catch (e) {
      if (e instanceof Error && e.message === "fal_image_upload_timeout") throw e;
      throw new Error("fal_image_upload_failed");
    }

    // commit 的結果分三態（第四輪複審 P2-1 收嚴）：
    //   明確 true  → 成功。
    //   明確 false → **確定**被 fencing／出窗守衛打回：物件在自己的 token
    //                路徑，自刪收掉；不 release（token 已不是我的）。
    //   其餘一律不確定 → **絕不刪物件**：DB 可能其實已 commit（回應在路上
    //                丟了），刪掉會讓 ready 列指向 404 一整個窗期。
    //
    // 「其餘」包含 RPC error／throw，也包含**回應形狀不完整**：data 為 null、
    // 空陣列、缺 committed 欄位、欄位不是 boolean。這些都只證明「我不知道
    // DB 做了什麼」，不證明沒 commit——壓成 false 會刪掉 DB 已引用的圖，
    // 正是三態要避免的事。不確定態走 release（fence 保護：已 commit 的列
    // token 已清空，release 自然無效），物件則交給 orphan 帳本清算。
    let committed: boolean | null = null;
    try {
      const { data, error } = await supabase.rpc(
        "commit_practice_moment_image",
        { ...jobParams, p_image_token: token, p_image_path: path },
      );
      if (!error) {
        const row = Array.isArray(data) ? (data[0] as Row | undefined) : null;
        const flag = row?.committed;
        if (typeof flag === "boolean") committed = flag;
      }
    } catch {
      committed = null;
    }
    if (committed === true) {
      logInfo("practice_moment_image_committed", {
        profileId: job.profileId,
        slot: job.slot,
        bytes: bytes.byteLength,
      });
      return;
    }
    if (committed === false) {
      await deps.removeImage(path).catch(() => {});
      logWarn("practice_moment_image_commit_rejected", {
        profileId: job.profileId,
        slot: job.slot,
        error: "not_committed",
      });
      return;
    }
    await releaseImage(supabase, jobParams, token, job);
    logWarn("practice_moment_image_commit_indeterminate", {
      profileId: job.profileId,
      slot: job.slot,
    });
  } catch (e) {
    // 上傳前或上傳本身失敗（commit 的三態已在上面自行收斂，不會 throw 到
    // 這裡）；uploadedPath 非 null 只剩理論路徑，保守自刪。
    if (uploadedPath !== null) {
      await deps.removeImage(uploadedPath).catch(() => {});
    } else if (!uploadAttempted) {
      // 連上傳都沒發出（場景／fal／下載失敗）→ 這個路徑確定沒有物件，
      // 順手把帳本那一筆抹掉，清算不必再為它打一次 Storage remove。
      // 上傳發出過就一律留著（timeout 還在飛、或回錯但其實已落地），
      // 帳本是那個物件唯一的持久紀錄。
      // 抹不掉也無妨——清算對不存在的物件本來就是 no-op（冪等）。
      await clearOrphanLedger(supabase, path);
    }
    await releaseImage(supabase, jobParams, token, job);
    logWarn("practice_moment_image_failed", {
      profileId: job.profileId,
      slot: job.slot,
      failureClass: e instanceof Error ? e.message : "unknown",
    });
  }
}

/**
 * 抹掉孤兒帳本裡確定不會有物件的那一筆（best effort）。
 *
 * 只在「確定沒上傳」時呼叫。失敗完全無害：帳本留著只是讓清算多打一次
 * 冪等的 Storage remove。
 */
async function clearOrphanLedger(
  supabase: MomentsImageRpcClient,
  path: string,
): Promise<void> {
  try {
    await supabase.rpc("clear_practice_moment_image_orphans", {
      p_paths: [path],
    });
  } catch {
    // 清算會接手。
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
