// 練習室動態貼文的配圖 allowlist（純資料 + 純函式、零依賴、可 deno test）。
//
// 為什麼是 allowlist 而不是讓模型自由描述圖片：
// - 我們沒有生圖能力，圖片一定是 app 內既有的 bundled 素材；模型只能「挑一張」，
//   挑不到 allowlist 內的 id 就降級成純文字貼文。
// - 這與現行 photoId 是同一套安全模型（server 是唯一真相源、client 只認 id）。
//   模型永遠不會產生檔名或路徑，故也不會有 raw filename 洩漏進可見文字的問題。
//
// SELF_PORTRAIT_IMAGE_ID 是唯一的例外：它不對應新素材，而是指「用她自己在
// 角色圖鑑裡的那張照片」，讓自拍類貼文不必額外進素材。client 端負責把這個 id
// 解析成該角色的 photoAssetPath。
//
// 素材數量刻意控制在 20 張場景圖：現況 100 張角色照已佔 13 MB，動態配圖再無
// 節制擴張會直接反映在 App 體積上（設計報告決定 D）。

/** 場景圖標籤；主題池用 imageTags 與這裡取交集決定候選。 */
export type MomentImageTag =
  | "cafe"
  | "coffee"
  | "dessert"
  | "food"
  | "cooking"
  | "night"
  | "city"
  | "walk"
  | "sky"
  | "calm"
  | "sea"
  | "travel"
  | "outdoor"
  | "nature"
  | "fitness"
  | "pet"
  | "book"
  | "desk"
  | "work"
  | "art"
  | "music"
  | "rain"
  | "commute"
  | "self";

export interface MomentImageEntry {
  id: string;
  tags: readonly MomentImageTag[];
}

/** 用她本人的圖鑑照片，不佔新素材預算。 */
export const SELF_PORTRAIT_IMAGE_ID = "moment_self_portrait";

export const MOMENT_IMAGES: readonly MomentImageEntry[] = [
  { id: "moment_coffee_cup", tags: ["coffee", "cafe", "calm"] },
  { id: "moment_cafe_corner", tags: ["cafe", "work", "desk"] },
  { id: "moment_dessert_plate", tags: ["dessert", "cafe", "food"] },
  { id: "moment_home_cooking", tags: ["cooking", "food"] },
  { id: "moment_late_night_snack", tags: ["food", "night"] },
  { id: "moment_street_night", tags: ["night", "city", "walk"] },
  { id: "moment_sunset_sky", tags: ["sky", "calm", "outdoor"] },
  { id: "moment_sea_view", tags: ["sea", "travel", "outdoor"] },
  { id: "moment_mountain_trail", tags: ["outdoor", "nature", "fitness"] },
  { id: "moment_gym_corner", tags: ["fitness"] },
  { id: "moment_yoga_mat", tags: ["fitness", "calm"] },
  { id: "moment_cat_nap", tags: ["pet", "calm"] },
  { id: "moment_dog_walk", tags: ["pet", "outdoor", "walk"] },
  { id: "moment_bookshelf", tags: ["book", "calm"] },
  { id: "moment_desk_work", tags: ["desk", "work"] },
  { id: "moment_exhibition_wall", tags: ["art", "city"] },
  { id: "moment_live_stage", tags: ["music", "night"] },
  { id: "moment_flower_bunch", tags: ["calm", "nature"] },
  { id: "moment_rainy_window", tags: ["rain", "calm"] },
  { id: "moment_train_window", tags: ["commute", "travel"] },
  { id: SELF_PORTRAIT_IMAGE_ID, tags: ["self"] },
];

const IMAGE_IDS: ReadonlySet<string> = new Set(
  MOMENT_IMAGES.map((entry) => entry.id),
);

/** 需要新素材的場景圖張數（不含用她本人照片的自拍 id）。 */
export const SCENE_IMAGE_COUNT = MOMENT_IMAGES.length - 1;

export function isMomentImageId(value: unknown): value is string {
  return typeof value === "string" && IMAGE_IDS.has(value);
}

/**
 * 依標籤取候選圖。回傳順序固定（依 MOMENT_IMAGES 宣告序），呼叫端再用種子挑，
 * 才能保證「同一天同一角色永遠得到同一張圖」。
 */
export function momentImagesForTags(
  tags: readonly MomentImageTag[],
): readonly string[] {
  if (tags.length === 0) return [];
  const wanted = new Set<string>(tags);
  return MOMENT_IMAGES
    .filter((entry) => entry.tags.some((tag) => wanted.has(tag)))
    .map((entry) => entry.id);
}

// ── 可用素材閘門（DECISIONS.md D1 修正）──────────────────────────────
//
// 上面那 20 個場景 id 是**宣告**，素材檔案還不存在；v1 只有自拍 sentinel
// 是真的可用的（client 把它解析成該角色的 photoAssetPath，零新素材）。
//
// 語義刻意是「替換」不是「過濾」。過濾寫法會失敗，理由是硬的：42 個題材裡
// 只有 4 個帶 "self" 標籤，把候選過濾成只剩自拍的話 38/42 得到空候選 →
// wantsImage 恆假 → v1 一則圖文貼文都不會有，真機驗收的兩種貼文型態就少一種。
//
// 2026-08-25 素材到位（PR #30）後閘門已開，替換分支
// 自然停止觸發，生成端與 UI 一行都不用改（D5c）。

/**
 * 目前真的有素材、可以送進 prompt 給模型挑的 id。
 *
 * **刻意逐字列舉，不從 MOMENT_IMAGES 推導**：這個常數是閘門，不是宣告的鏡像。
 * 若改成推導，未來宣告第 21 張場景時，素材檔案還不存在閘門就先開了——
 * 正是這個閘門要防的事。每個場景 id 都必須有
 * `assets/images/practice_moments/<id>.webp`，由 moments_image_gate_test.ts
 * 逐檔 stat 機械保證。
 */
export const AVAILABLE_MOMENT_IMAGE_IDS: readonly string[] = [
  SELF_PORTRAIT_IMAGE_ID,
  "moment_coffee_cup",
  "moment_cafe_corner",
  "moment_dessert_plate",
  "moment_home_cooking",
  "moment_late_night_snack",
  "moment_street_night",
  "moment_sunset_sky",
  "moment_sea_view",
  "moment_mountain_trail",
  "moment_gym_corner",
  "moment_yoga_mat",
  "moment_cat_nap",
  "moment_dog_walk",
  "moment_bookshelf",
  "moment_desk_work",
  "moment_exhibition_wall",
  "moment_live_stage",
  "moment_flower_bunch",
  "moment_rainy_window",
  "moment_train_window",
];

/**
 * 把排程算出的候選收斂成「現在真的配得出來的圖」。
 *
 * - 候選內有可用 id → 只回那些（保持宣告順序、去重）。
 * - 候選非空但全部不可用 → 整批替換成自拍 sentinel。
 * - 候選為空（這個 slot 本來就是純文字貼文）→ 回空陣列，不無中生有。
 *
 * `available` 只給測試重放「未來素材到位」的情境用；runtime 一律用預設值。
 */
export function resolveAvailableMomentImages(
  candidates: readonly string[],
  available: readonly string[] = AVAILABLE_MOMENT_IMAGE_IDS,
): readonly string[] {
  if (candidates.length === 0) return [];
  const usable = new Set(available);
  const seen = new Set<string>();
  const resolved: string[] = [];
  for (const id of candidates) {
    if (!usable.has(id) || seen.has(id)) continue;
    seen.add(id);
    resolved.push(id);
  }
  if (resolved.length > 0) return resolved;
  return usable.has(SELF_PORTRAIT_IMAGE_ID) ? [SELF_PORTRAIT_IMAGE_ID] : [];
}
