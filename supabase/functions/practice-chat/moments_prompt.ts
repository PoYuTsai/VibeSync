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
import type { PersonaId, PracticeGirlProfile } from "./practice_persona.ts";
import { fnv1a } from "./moments_schedule.ts";
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

/**
 * 每種 persona 的「聲音」——不是她是什麼人，是她打字的樣子。
 *
 * **只描述語感，絕不給例句。** 這個 repo 的 opener prompt 用六輪 A/B 證明過：
 * 寫在 prompt 裡的示範句會被模型逐字照抄進輸出，等於發罐頭（no-canned 的
 * prompt 層變體）。語氣詞白名單（「笑死」這種單詞）不算例句——它是功能詞，
 * 抄了也不構成一則貼文。
 *
 * 型別刻意用 Record<PersonaId, string>：新增第六種 persona 而忘了配聲音，
 * 編譯器直接紅，不會安靜地退回無聲音。
 */
const PERSONA_VOICE: Readonly<Record<PersonaId, string>> = {
  slow_worker: "能量很低。短句，常省略主詞，句號直接收掉或乾脆整句不加標點。" +
    "不用驚嘆號、不用可愛語氣詞。像下班後只剩一格電時打的字。" +
    "抱怨的方式是平鋪直敘地陳述事實，不喊累。",
  playful_extrovert: "節奏快，會誇飾——形容詞放很大，但自己知道在鬧。" +
    "可以用「笑死」「超」「欸」這類口語，驚嘆號可以用但別每句都用。" +
    "習慣把一件小事講成一個事件。",
  cool_rational: "觀察者視角。冷冷的陳述句，用字精準，帶一點不動聲色的毒舌。" +
    "幾乎不用語氣詞和驚嘆號。對小事下判斷時非常篤定，篤定得有點好笑。",
  teasing_humor:
    "自嘲是預設模式。把自己的慘講成好笑的，或前半句正經、後半句誠實地歪掉。" +
    "可以講反話。損自己可以，賣慘不行。",
  clear_boundaries:
    "直球。有立場，敢對雞毛蒜皮的事下非常篤定的結論，不繞彎、不鋪墊。" +
    "句子乾脆，說完就完，不解釋。",
};

/**
 * 貼文的切入形狀。每個 slot 用種子輪替一種，跨貼文的節奏才會散開——
 * 這是 opener「切入角度輪替」的同一招（該輪實測跨輪重複 65%→33%）。
 * 形狀是方向不是模板；同樣**只描述形狀，不給例句**。
 */
export const MOMENT_POST_SHAPES: readonly string[] = [
  "把一個小到不行的細節講得很認真，具體到只有真的經歷過的人寫得出來",
  "前半句往一個方向走，後半句誠實地垮掉或歪掉",
  "講一件大家都經歷過、但很少有人講出口的小事",
  "對一件無關緊要的事，下一個過度篤定的結論",
  "把自己今天的糗、懶或慘直接攤開，講成好笑的，不是可憐的",
  "沒頭沒尾地講到一半，不交代前因後果，像自言自語被聽到",
];

/** 種子選形狀：同一 slot 重生成拿到同一形狀（重試語義不變），跨 slot 散開。 */
export function momentShapeFor(
  profileId: string,
  isoDate: string,
  slot: number,
): string {
  const seed = `${profileId}|${isoDate}|moment|${slot}|shape`;
  return MOMENT_POST_SHAPES[fnv1a(seed) % MOMENT_POST_SHAPES.length];
}

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
    return `10. 這一則沒有配圖，imageId 必須是 null。不要在文字裡描述照片。`;
  }
  const onlySelfPortrait = imageCandidates.length === 1 &&
    imageCandidates[0] === SELF_PORTRAIT_IMAGE_ID;
  if (onlySelfPortrait) {
    // 圖決定文，不是文決定圖：先讓模型知道會配自拍，文案才不會出現
    // 「宵夜」配大頭照那種違和。
    return `10. 這一則會配上你自己的照片（一張自拍）。把文字寫成配得上一張自拍的樣子——` +
      `講你此刻的狀態、心情或樣子，不要描述一個你人不在畫面裡的場景。` +
      `imageId 必須填 "${SELF_PORTRAIT_IMAGE_ID}"。`;
  }
  return `10. 這一則會配一張圖。從 momentImageOptions 裡挑一個最貼題材的 id 填進 imageId，` +
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
  slot: number;
  imageCandidates: readonly string[];
}): ChatMessage[] {
  const {
    girl,
    themeId,
    brief,
    dayPart,
    isoDate,
    isWeekend,
    slot,
    imageCandidates,
  } = opts;
  const voice = PERSONA_VOICE[girl.personaId];
  const shape = momentShapeFor(girl.profileId, isoDate, slot);

  const system =
    `你是${girl.displayName}，${girl.age} 歲，在${girl.city}的${girl.professionLabel}。
${girl.professionPrompt}

現在你要寫一則自己的社群動態貼文。這是你發在社群上給不特定多數人看的動態，不是傳訊息給某一個人。

寫作規則：
1. 用繁體中文，${MOMENT_PROMPT_MIN_CHARS} 到 ${MOMENT_PROMPT_MAX_CHARS} 個字，第一人稱，像真人隨手打的一兩句話。
2. 絕對不可以出現「你」或「妳」。不可以寫成問句，不可以要求別人回覆、按讚或私訊。
3. 不可以提到任何特定的人、任何對話內容、任何跟誰約好的事。這則貼文只講你自己。
4. 不可以出現真實品牌、真實店名、真實地址、真實帳號或真實網址。
5. 你打字的樣子（語感，比內容更重要）：${voice}
6. 你平常在意的是${girl.interestTags.join("、")}，生活習慣是${
      girl.lifestyleTags.join("、")
    }——內容從這裡長出來，但不要像在自我介紹。
7. 不要用開頭問候語、不要加 hashtag、不要寫成廣告或文案。
8. 結尾不准總結、不准昇華、不准硬轉正能量。真人發廢文不會幫自己的一天下註解。
9. 不用把事情講完整，破碎一點反而真。標點自由：可以整句沒有句號，可以用空格斷句。
${imageDirective(imageCandidates)}

這一則的切入形狀：${shape}。形狀是方向不是模板，貼著你的語感寫。
規則 1-4、7 與 10 是硬邊界，違反就作廢重寫；其餘一律以「像真人隨手打的」優先——可以隨口、可以不完整、可以無厘頭，規則沒寫到的寫法都放行。

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
