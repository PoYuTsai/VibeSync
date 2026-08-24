// 動態貼文的 prompt 組裝。
//
// **隱私鐵則**：貼文是全域的——同一位角色同一天的貼文，所有看得到她的
// 使用者讀到的是同一則。所以這支檔案的輸入永遠只有 server profile、日期、
// 題材與候選 imageId，沒有任何欄位塞得下使用者的對話、暱稱或關係狀態。
// 這件事由 moments_generated_only_source_test.ts 逐字串守門。
//
// **注入標籤必登記**：下面 MOMENT_INTERNAL_LABELS 的每一個標籤都同步登記
// 進 visible_text_guard.ts 的 INTERNAL_VISIBLE_LABELS，模型若把標籤原樣抄
// 進貼文，驗證管線會直接打回。
//
// 標籤刻意全用英文複合詞：visible_text_guard 的 normalizeVisibleText 會把
// 中文整個剝掉，中文標籤那張表（INTERNAL_CHINESE_LABELS）攔的是另一組詞，
// 這裡不新增中文標籤就不必動那份清單。

import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "../_shared/prompt_leak_guard.ts";
import type { ChatMessage } from "./prompt.ts";
import type { PracticeGirlProfile } from "./practice_persona.ts";
import type { TaipeiDayPart } from "./time_context.ts";
import { SELF_PORTRAIT_IMAGE_ID } from "./moments_image_catalog.ts";
import {
  MOMENT_PROMPT_MAX_CHARS,
  MOMENT_PROMPT_MIN_CHARS,
} from "./moments_constants.ts";

/** 注入 prompt 的內部標籤；每一個都必須登記進 visible_text_guard。 */
export const MOMENT_INTERNAL_LABELS: readonly string[] = [
  "momentPostSpec",
  "momentDayPart",
  "momentThemeBrief",
  "momentImageOptions",
];

/**
 * 本 prompt 獨有的指示片段，給 containsPromptLeak 當 sentinel。
 * 取「正常貼文絕不會自然出現」的長句，短於 8 字的會被忽略。
 */
export const MOMENT_PROMPT_SENTINELS: readonly string[] = [
  "這是你發在社群上給不特定多數人看的動態",
  "只輸出一個 JSON 物件，不要有其他文字",
];

const DAY_PART_LABEL: Readonly<Record<TaipeiDayPart, string>> = {
  dawn: "清晨",
  morning: "早上",
  noon: "中午",
  afternoon: "下午",
  early_evening: "傍晚",
  evening: "晚上",
  late_night: "深夜",
};

function imageDirective(imageCandidates: readonly string[]): string {
  if (imageCandidates.length === 0) {
    return `7. 這一則沒有配圖，imageId 必須是 null。不要在文字裡描述照片。`;
  }
  const onlySelfPortrait = imageCandidates.length === 1 &&
    imageCandidates[0] === SELF_PORTRAIT_IMAGE_ID;
  if (onlySelfPortrait) {
    // 圖決定文，不是文決定圖：先讓模型知道會配自拍，文案才不會出現
    // 「宵夜」配大頭照那種違和。
    return `7. 這一則會配上你自己的照片（一張自拍）。把文字寫成配得上一張自拍的樣子——` +
      `講你此刻的狀態、心情或樣子，不要描述一個你人不在畫面裡的場景。` +
      `imageId 必須填 "${SELF_PORTRAIT_IMAGE_ID}"。`;
  }
  return `7. 這一則會配一張圖。從 momentImageOptions 裡挑一個最貼題材的 id 填進 imageId，` +
    `並把文字寫成配得上那張圖的樣子。不要自己發明 id。`;
}

/**
 * 組出貼文生成的訊息。輸入全是 server 事實，沒有任何使用者資料。
 */
export function buildMomentMessages(opts: {
  girl: PracticeGirlProfile;
  themeId: string;
  brief: string;
  dayPart: TaipeiDayPart;
  isoDate: string;
  isWeekend: boolean;
  imageCandidates: readonly string[];
}): ChatMessage[] {
  const { girl, themeId, brief, dayPart, isoDate, isWeekend, imageCandidates } =
    opts;

  const system = `你是${girl.displayName}，${girl.age} 歲，在${girl.city}的${girl.professionLabel}。
${girl.professionPrompt}

現在你要寫一則自己的社群動態貼文。這是你發在社群上給不特定多數人看的動態，不是傳訊息給某一個人。

寫作規則（每一條都是硬約束，違反就作廢重寫）：
1. 用繁體中文，${MOMENT_PROMPT_MIN_CHARS} 到 ${MOMENT_PROMPT_MAX_CHARS} 個字，第一人稱，像真人隨手打的一兩句話。
2. 絕對不可以出現「你」或「妳」。不可以寫成問句，不可以要求別人回覆、按讚或私訊。
3. 不可以提到任何特定的人、任何對話內容、任何跟誰約好的事。這則貼文只講你自己。
4. 不可以出現真實品牌、真實店名、真實地址、真實帳號或真實網址。
5. 語氣要像你的個性：${girl.personalityTags.join("、")}。你平常在意的是${
    girl.interestTags.join("、")
  }，生活習慣是${girl.lifestyleTags.join("、")}。
6. 不要用開頭問候語、不要加 hashtag、不要寫成廣告或文案。
${imageDirective(imageCandidates)}

輸出格式：只輸出一個 JSON 物件，不要有其他文字。
{"text": "貼文內容", "imageId": null}${PROMPT_LEAK_DEFENSE_DIRECTIVE}`;

  const optionsLine = imageCandidates.length > 0
    ? imageCandidates.join(", ")
    : "（無，imageId 必須是 null）";

  const user = `momentPostSpec
momentDayPart: ${DAY_PART_LABEL[dayPart]}（${isoDate}，${
    isWeekend ? "週末" : "平日"
  }）
momentThemeBrief: ${themeId} — ${brief}
momentImageOptions: ${optionsLine}

照上面的規則寫這一則貼文。`;

  return [
    { role: "system", content: system },
    { role: "user", content: user },
  ];
}
