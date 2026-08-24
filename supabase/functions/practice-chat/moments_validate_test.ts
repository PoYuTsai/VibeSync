// 動態貼文的驗證管線（設計報告 §5「驗證管線」，表驅動）。
//
// 三層長度的中間那層在這裡：prompt 指示 20-60、**驗證 18-66**、DB CHECK 1-220。
// 容差刻意留 ±10%——打回一則就吃掉一次 attempts，為了 61 字丟掉一則好貼文
// 不划算。若上線後打回率偏高，要調的是 prompt 的引導方式，不是放寬這裡。
//
// imageId 的處理刻意與其他項不同：**降級成純文字，不是整則打回**。
// 文字本身沒問題卻因為挑錯圖白燒一次 attempts 是不划算的。
import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { validateMomentDraft } from "./moments_validate.ts";
import {
  MOMENT_BODY_MAX_CHARS,
  MOMENT_BODY_MIN_CHARS,
} from "./moments_constants.ts";
import { SELF_PORTRAIT_IMAGE_ID } from "./moments_image_catalog.ts";
import { MOMENT_PROMPT_SENTINELS } from "./moments_prompt.ts";

const CANDIDATES = [SELF_PORTRAIT_IMAGE_ID];

function raw(text: string, imageId: string | null = null): string {
  return JSON.stringify({ text, imageId });
}

function repeat(count: number): string {
  return "咖".repeat(count);
}

function accept(text: string, imageCandidates: readonly string[] = []) {
  return validateMomentDraft({ raw: raw(text), imageCandidates });
}

// ── 長度：三層數字必須對得起來 ──────────────────────────────────────

Deno.test("長度邊界：17 拒、18 收、66 收、67 拒", () => {
  assertThrows(
    () => accept(repeat(MOMENT_BODY_MIN_CHARS - 1)),
    Error,
    "moment_length_out_of_range",
  );
  assertEquals(accept(repeat(MOMENT_BODY_MIN_CHARS)).body.length, 18);
  assertEquals(
    [...accept(repeat(MOMENT_BODY_MAX_CHARS)).body].length,
    MOMENT_BODY_MAX_CHARS,
  );
  assertThrows(
    () => accept(repeat(MOMENT_BODY_MAX_CHARS + 1)),
    Error,
    "moment_length_out_of_range",
  );
});

Deno.test("長度用字（code point）算，不是 UTF-16 code unit", () => {
  // 一個 emoji 是兩個 code unit、一個字。用 .length 會把 33 個 emoji
  // 誤判成 66 字而放行。
  const text = "今天心情還不錯".padEnd(7, "") + "🙂".repeat(11);
  assertEquals([...text].length, 18);
  assertEquals(text.length, 29);
  assertEquals([...accept(text).body].length, 18);
});

// ── 形狀 ──────────────────────────────────────────────────────────────

Deno.test("非 JSON、text 非字串、text 空白一律拒", () => {
  for (
    const [input, code] of [
      ["這不是 JSON", "moment_invalid_json"],
      ['{"text": 123}', "moment_missing_text"],
      ['{"text": "   "}', "moment_missing_text"],
      ["[]", "moment_invalid_json"],
      ['{"imageId": null}', "moment_missing_text"],
    ] as const
  ) {
    assertThrows(
      () => validateMomentDraft({ raw: input, imageCandidates: [] }),
      Error,
      code,
      input,
    );
  }
});

Deno.test("模型加了 markdown code fence 仍解析得出來", () => {
  const text = "今天的第一杯咖啡比鬧鐘有用多了，終於覺得自己醒著";
  const fenced = "```json\n" + raw(text) + "\n```";
  assertEquals(
    validateMomentDraft({ raw: fenced, imageCandidates: [] }).body,
    text,
  );
});

// ── 守門 ──────────────────────────────────────────────────────────────

Deno.test("命中內部標籤守門即拒", () => {
  assertThrows(
    () => accept("momentThemeBrief 今天想寫點什麼但腦袋一片空白喔喔喔"),
    Error,
    "moment_internal_label_leak",
  );
});

Deno.test("命中 L4 不安全可見文字即拒", () => {
  assertThrows(
    () => accept("今天晚上想找人來我家過夜，順便看個電影再說吧好嗎"),
    Error,
    "moment_unsafe_visible_text",
  );
});

Deno.test("命中 raw 檔名即拒", () => {
  assertThrows(
    () => accept("今天拍的 IMG_2841.jpg 這張我自己還蠻喜歡的，光線剛剛好"),
    Error,
    "moment_raw_filename",
  );
});

Deno.test("命中 prompt 外洩 sentinel 即拒", () => {
  assertThrows(
    () => accept(MOMENT_PROMPT_SENTINELS[0] + "，好的我知道了沒問題"),
    Error,
    "moment_prompt_leak",
  );
});

Deno.test("貼文正文裡出現任何圖庫 id 即拒", () => {
  assertThrows(
    () => accept("今天想配一張 moment_self_portrait 的照片來當紀念好了"),
    Error,
    "moment_internal_label_leak",
  );
});

// ── 全域內容不得對某個使用者說話（決策 A 的延伸限制）──────────────

Deno.test("出現第二人稱「你」或「妳」即拒", () => {
  for (
    const text of [
      "今天的咖啡好喝到我想推薦給你，下次一起去那間店坐坐吧",
      "剛剛看到路邊那隻貓，忽然覺得妳應該也會喜歡牠那個表情",
    ]
  ) {
    assertThrows(() => accept(text), Error, "moment_second_person");
  }
});

Deno.test("問句結尾即拒（不管全形半形）", () => {
  for (
    const text of [
      "今天下午的天氣好到有點過分，是不是應該翹班去走走呢？",
      "今天下午的天氣好到有點過分，是不是應該翹班去走走呢?",
    ]
  ) {
    assertThrows(() => accept(text), Error, "moment_question_form");
  }
});

Deno.test("正常的第一人稱敘述照過", () => {
  const text = "今天的第一杯咖啡比鬧鐘有用多了，終於覺得自己醒著";
  const result = accept(text);
  assertEquals(result.body, text);
  assertEquals(result.imageId, null);
});

// ── 繁體化 ────────────────────────────────────────────────────────────

Deno.test("簡體輸入轉繁體後通過", () => {
  const result = accept("今天的第一杯咖啡比闹钟有用多了，终于觉得自己醒着了呢");
  assert(result.body.includes("鬧鐘"));
  assert(result.body.includes("終於"));
  assertEquals(result.body.includes("闹"), false);
});

// ── imageId：降級而不是打回 ─────────────────────────────────────────

Deno.test("imageId 在 allowlist 且在本 slot 候選內 → 保留", () => {
  const result = validateMomentDraft({
    raw: raw(
      "今天的第一杯咖啡比鬧鐘有用多了，終於覺得自己醒著",
      SELF_PORTRAIT_IMAGE_ID,
    ),
    imageCandidates: CANDIDATES,
  });
  assertEquals(result.imageId, SELF_PORTRAIT_IMAGE_ID);
});

Deno.test("imageId 不在 allowlist → 降級成純文字，不是整則拒", () => {
  const result = validateMomentDraft({
    raw: raw(
      "今天的第一杯咖啡比鬧鐘有用多了，終於覺得自己醒著",
      "moment_not_real",
    ),
    imageCandidates: CANDIDATES,
  });
  assertEquals(result.imageId, null);
  assert(result.body.length > 0);
});

Deno.test("imageId 在 allowlist 但不在本 slot 候選 → 同樣降級", () => {
  const result = validateMomentDraft({
    raw: raw(
      "今天的第一杯咖啡比鬧鐘有用多了，終於覺得自己醒著",
      "moment_coffee_cup",
    ),
    imageCandidates: CANDIDATES,
  });
  assertEquals(result.imageId, null);
});

Deno.test("本 slot 沒有候選圖時，模型硬塞 imageId 一律降級", () => {
  const result = validateMomentDraft({
    raw: raw(
      "今天的第一杯咖啡比鬧鐘有用多了，終於覺得自己醒著",
      SELF_PORTRAIT_IMAGE_ID,
    ),
    imageCandidates: [],
  });
  assertEquals(result.imageId, null);
});

Deno.test("通過驗證的 body 一定在 DB CHECK 的 1-220 內", () => {
  const result = accept(repeat(MOMENT_BODY_MAX_CHARS));
  assert(result.body.length >= 1 && result.body.length <= 220);
});
