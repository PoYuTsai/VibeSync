// 動態貼文的驗證管線。**失敗一律丟錯，由呼叫端 release，永不落盤。**
//
// 三層長度（設計報告 §5，複審 2026-08-21 P2）：
//   prompt 指示 20-60 字 → 這裡守 18-66 字 → DB CHECK 1-220（縱深防禦）。
// 中間那層才是產品守門；±10% 容差是因為打回一則就吃掉一次 attempts，
// 為了 61 字丟掉一則好貼文不划算。打回率偏高時要調 prompt，不是放寬這裡。
//
// imageId 的處理刻意與其他項不同：**降級成純文字，不是整則打回**。
// 文字本身沒問題卻因為挑錯圖白燒一次 attempts 是不划算的；純文字貼文
// 本來就是八成的常態（IMAGE_PROBABILITY = 0.2，D5a/D5b）。

import { toTraditionalChinese } from "../_shared/traditional_chinese.ts";
import { containsPromptLeak } from "../_shared/prompt_leak_guard.ts";
import { containsRawImageFilename } from "./prompt_sanitizer.ts";
import {
  rejectL4UnsafeVisibleText,
  rejectVisibleInternalLabelLeak,
} from "./visible_text_guard.ts";
import {
  MOMENT_BODY_MAX_CHARS,
  MOMENT_BODY_MIN_CHARS,
} from "./moments_constants.ts";
import { isMomentImageId, MOMENT_IMAGES } from "./moments_image_catalog.ts";
import { MOMENT_PROMPT_SENTINELS } from "./moments_prompt.ts";

export interface MomentDraft {
  body: string;
  imageId: string | null;
}

/** 第二人稱：全域貼文不能對某一個使用者說話（設計報告決策 A 的延伸限制）。 */
const SECOND_PERSON_PATTERN = /[你妳]/u;

/** 問句：貼文不該拉人回覆（D4 這一版沒有留言功能，問了也沒人答得了）。 */
const QUESTION_TAIL_PATTERN = /[?？]\s*$/u;

const MOMENT_IMAGE_IDS = MOMENT_IMAGES.map((entry) => entry.id);

/** 模型偶爾會把 JSON 包在 markdown code fence 裡；剝掉再解析。 */
function stripCodeFence(value: string): string {
  const trimmed = value.trim();
  if (!trimmed.startsWith("```")) return trimmed;
  const withoutOpen = trimmed.replace(/^```[a-zA-Z]*\s*/u, "");
  const closeAt = withoutOpen.lastIndexOf("```");
  return (closeAt >= 0 ? withoutOpen.slice(0, closeAt) : withoutOpen).trim();
}

/**
 * 驗證模型回傳的貼文草稿。通過回 { body, imageId }；任何一條硬約束不過
 * 就丟 Error(錯誤碼)，呼叫端據此 release 並回 retryable，**絕不寫進 DB**。
 */
export function validateMomentDraft(opts: {
  raw: string;
  imageCandidates: readonly string[];
}): MomentDraft {
  const { raw, imageCandidates } = opts;

  let parsed: unknown;
  try {
    parsed = JSON.parse(stripCodeFence(raw));
  } catch {
    throw new Error("moment_invalid_json");
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("moment_invalid_json");
  }

  const draft = parsed as Record<string, unknown>;
  const rawText = draft.text;
  if (typeof rawText !== "string" || rawText.trim().length === 0) {
    throw new Error("moment_missing_text");
  }

  // 繁體化在長度判定之前：cn2t 是 1:1 字元對映，不會改變字數，但先轉才能
  // 讓後面的中文守門看到最終要送出去的那一份文字。
  const body = toTraditionalChinese(rawText.trim());

  const charCount = [...body].length;
  if (
    charCount < MOMENT_BODY_MIN_CHARS || charCount > MOMENT_BODY_MAX_CHARS
  ) {
    throw new Error("moment_length_out_of_range");
  }

  if (containsRawImageFilename(body)) {
    throw new Error("moment_raw_filename");
  }
  // 圖庫 id 是內部識別碼，出現在可見文字裡就是內部詞外洩。
  if (MOMENT_IMAGE_IDS.some((id) => body.includes(id))) {
    throw new Error("moment_internal_label_leak");
  }
  rejectVisibleInternalLabelLeak(body, "moment_internal_label_leak");
  rejectL4UnsafeVisibleText(body, "moment_unsafe_visible_text");
  if (containsPromptLeak(body, MOMENT_PROMPT_SENTINELS)) {
    throw new Error("moment_prompt_leak");
  }
  if (SECOND_PERSON_PATTERN.test(body)) {
    throw new Error("moment_second_person");
  }
  if (QUESTION_TAIL_PATTERN.test(body)) {
    throw new Error("moment_question_form");
  }

  // imageId：不在 allowlist、或不在本 slot 的候選內，一律降級成純文字。
  const rawImageId = draft.imageId;
  const allowed = new Set(imageCandidates);
  const imageId = typeof rawImageId === "string" &&
      isMomentImageId(rawImageId) && allowed.has(rawImageId)
    ? rawImageId
    : null;

  return { body, imageId };
}
