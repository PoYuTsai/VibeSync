// 可用素材閘門（DECISIONS.md D1 修正）：**替換**，不是過濾。
//
// 為什麼這件事值得一支獨立測試：20 張場景圖的素材檔案還不存在，v1 只有
// 自拍 sentinel 可用。若把候選「過濾」成只剩可用的，42 個題材裡只有 4 個
// 帶 "self" 標籤 → 38/42 得到空候選 → wantsImage 恆假 → v1 一則圖文貼文
// 都不會有，D3 的真機驗收目的直接落空。
//
// 正確語義：候選算完之後，若一個都不可用但候選本來非空（＝這個 slot 本來
// 就想配圖），就整批換成自拍 sentinel。素材到位那天把 20 個 id 加進可用
// 集合，替換分支自然停止觸發，生成端與 UI 一行都不用改（D5c 的機械保證）。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  AVAILABLE_MOMENT_IMAGE_IDS,
  MOMENT_IMAGES,
  momentImagesForTags,
  resolveAvailableMomentImages,
  SCENE_IMAGE_COUNT,
  SELF_PORTRAIT_IMAGE_ID,
} from "./moments_image_catalog.ts";

Deno.test("閘門全開：可用集合恰好是自拍＋20 張場景，無多無少", () => {
  // 2026-08-25 素材到位（PR #30）後翻面。用宣告表對帳而不是寫死 21：
  // 少一個＝有題材悄悄退回自拍牆；多一個＝開了不存在的素材。
  assertEquals(
    [...AVAILABLE_MOMENT_IMAGE_IDS].sort(),
    MOMENT_IMAGES.map((entry) => entry.id).sort(),
  );
});

Deno.test("每個開放的場景 id 都有對應素材檔案（防檔名打錯的安靜降級）", () => {
  // 檔名對不上不會報錯，只會讓那個題材的圖文貼文永遠降級成純文字。
  // CI 以 repo 根目錄執行且帶 --allow-read，直接逐檔 stat。
  for (const id of AVAILABLE_MOMENT_IMAGE_IDS) {
    if (id === SELF_PORTRAIT_IMAGE_ID) continue; // sentinel 用她本人的圖鑑照
    const path = `assets/images/practice_moments/${id}.webp`;
    const info = Deno.statSync(path);
    assert(info.isFile && info.size > 0, `素材缺檔或為空：${path}`);
  }
});

Deno.test("PR A 宣告的 20 張場景圖一張都沒被刪掉", () => {
  // D1 明訂不要刪那 20 筆：刪掉會動到 SCENE_IMAGE_COUNT === 20 的預算測試，
  // 而且之後補素材要改的東西更多。
  assertEquals(SCENE_IMAGE_COUNT, 20);
  assertEquals(MOMENT_IMAGES.length, 21);
});

Deno.test("候選全部可用 → 原樣照候選順序回傳，不塞自拍也不重排", () => {
  const resolved = resolveAvailableMomentImages([
    "moment_coffee_cup",
    SELF_PORTRAIT_IMAGE_ID,
    "moment_cafe_corner",
  ]);
  assertEquals([...resolved], [
    "moment_coffee_cup",
    SELF_PORTRAIT_IMAGE_ID,
    "moment_cafe_corner",
  ]);
});

Deno.test("替換分支仍然活著：可用集合縮回只剩自拍時，整批替換不變空集合", () => {
  // 閘門開了之後 runtime 走不到這個分支，但它是「日後撤下某張素材」的
  // 安全網，必須用 override 參數持續證明它沒被改壞（D1 修正的語義）。
  const candidates = momentImagesForTags(["coffee", "cafe"]);
  assert(candidates.length > 0, "前提：這組標籤本來就有候選");
  assertEquals(candidates.includes(SELF_PORTRAIT_IMAGE_ID), false);
  assertEquals(
    [...resolveAvailableMomentImages(candidates, [SELF_PORTRAIT_IMAGE_ID])],
    [SELF_PORTRAIT_IMAGE_ID],
  );
});

Deno.test("候選為空 → 回空集合，不無中生有配一張圖", () => {
  assertEquals([...resolveAvailableMomentImages([])], []);
});

Deno.test("整份圖庫的每一組題材標籤都不會因為閘門而失去配圖", () => {
  // 這是「做成過濾就會炸」的直接反證：逐一掃過所有場景標籤，
  // 只要 momentImagesForTags 給了候選，閘門就必須也給候選。
  const tags = [...new Set(MOMENT_IMAGES.flatMap((entry) => entry.tags))];
  let checked = 0;
  for (const tag of tags) {
    const candidates = momentImagesForTags([tag]);
    if (candidates.length === 0) continue;
    checked += 1;
    assert(
      resolveAvailableMomentImages(candidates).length > 0,
      `標籤 ${tag} 在閘門後失去所有候選——這就是「過濾」寫法的失敗模式`,
    );
  }
  assert(checked >= 20, `應該掃過至少 20 組標籤，實際 ${checked}`);
});

Deno.test("閘門永遠只回 allowlist 內的 id，且不重複", () => {
  const resolved = resolveAvailableMomentImages([
    SELF_PORTRAIT_IMAGE_ID,
    SELF_PORTRAIT_IMAGE_ID,
    "not_a_real_image",
  ]);
  assertEquals([...resolved], [SELF_PORTRAIT_IMAGE_ID]);
});

Deno.test("素材到位後（把場景 id 加進可用集合）替換分支就不再觸發", () => {
  // D5c 的機械保證：這條綠 = 補素材那天生成端零改動已被證明。
  // 用 override 參數重放「未來的可用集合」，不改動任何 runtime 常數。
  const futureAvailable = MOMENT_IMAGES.map((entry) => entry.id);
  const candidates = momentImagesForTags(["coffee", "cafe"]);
  assertEquals(
    [...resolveAvailableMomentImages(candidates, futureAvailable)],
    [...candidates],
    "可用集合補齊後應原樣回傳候選，不得再塞入自拍",
  );
  assertEquals(
    resolveAvailableMomentImages(candidates, futureAvailable).includes(
      SELF_PORTRAIT_IMAGE_ID,
    ),
    false,
  );
});
