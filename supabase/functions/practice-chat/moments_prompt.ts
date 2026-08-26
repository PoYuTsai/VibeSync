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
import { fnv1a, type MomentContentKind } from "./moments_schedule.ts";
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

const CONTENT_KIND_LABEL: Readonly<Record<MomentContentKind, string>> = {
  daily_life: "生活片段",
  social_observation: "社會觀察",
  relationship_thought: "感情想法",
  personal_value: "個人價值觀",
  interest: "個人興趣",
  pet_life: "寵物生活",
};

/**
 * 題材類型的寫法守門。這一層決定內容，不覆蓋 persona 的聲音。
 * 特別是社會觀察：模型沒有新聞檢索，只准談一般現象與自己的選擇，避免
 * 「很像時事」卻帶著假人物、假數字或假政策的貼文。
 */
export const MOMENT_CONTENT_GUIDANCE: Readonly<
  Record<MomentContentKind, string>
> = {
  daily_life: "抓一個真的看得到或感覺得到的小細節，不替平凡的一天硬找意義。",
  social_observation:
    "對最近常被討論的生活或社會現象，給一個溫和但清楚的立場。只談一般現象與自己的選擇；不得捏造新聞、人物、數字、政策、災害或未提供的事實，也不做政黨站隊。",
  relationship_thought:
    "分享自己的感情步調或相處偏好。只說自己在意什麼，不教別人談戀愛、不影射前任、不苦情，也不把所有人一概而論。",
  personal_value:
    "說一個自己真的會做的取捨，最好帶一個很短的理由或矛盾。不要寫成金句、雞湯或對別人的道德評分。",
  interest:
    "從自己的興趣講一個具體偏好、門道或最近在意的細節；不要只剩『喜歡、療癒、充電』這類空泛感受。",
  pet_life:
    "寫照顧、相處或遇到動物的具體細節。只有題材明確說家裡有養，才能自稱飼主；可愛可以，但不要把寵物寫成萬用療癒文。",
};

/**
 * 100 位女孩其實有 93 組不同的 personalityTags；舊 prompt 沒使用，最後只剩
 * 五種 persona 聲線。這裡把既有資料轉成「她怎麼看事情」的濾鏡，而不是要
 * 模型把標籤逐字寫進貼文，避免人設用力過頭。
 */
export function momentCharacterLensFor(girl: PracticeGirlProfile): string {
  return `個人底色是${
    girl.personalityTags.join("、")
  }，感情步調是「${girl.relationshipGoal}」。` +
    `這些只決定會注意什麼、偏好什麼、怎麼下判斷；不要把標籤寫出來，` +
    `不要自我介紹，也不要為了顯得有個性而變得刻薄、極端或討好。`;
}

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

/**
 * 觀點類內容（社會觀察／感情想法／個人價值觀）：講的是立場，不是眼前的畫面。
 * 切入形狀與配圖指示都要跟生活紀錄分流，所以判斷收在這一支——兩邊各寫一份
 * 條件，日後新增內容類型時只會改到一半。
 */
export function isMomentOpinionKind(contentKind: MomentContentKind): boolean {
  return contentKind === "social_observation" ||
    contentKind === "relationship_thought" ||
    contentKind === "personal_value";
}

/**
 * 觀點類不能沿用「今天的糗、懶或慘」這種生活形狀，否則新增感情／價值題材
 * 最後仍會被 prompt 拉回日記。這組只談立場的呈現方式，仍不提供可抄的例句。
 */
export const MOMENT_OPINION_POST_SHAPES: readonly string[] = [
  "先把自己的偏好講出來，再補一個很短的理由，不交代完整背景",
  "承認自己也有點矛盾，停在矛盾那裡，不急著得出答案",
  "從一個很小的取捨帶出看法，講到剛好就停，不上升成大道理",
  "說一個不一定討喜但不傷人的偏好，乾脆收尾，不替自己辯護",
  "先像是同意常見說法，後半句補上自己的保留",
  "只講自己會怎麼做，不替別人下結論，也不要求認同",
];

/** 種子選形狀：同一 slot 重生成拿到同一形狀（重試語義不變），跨 slot 散開。 */
export function momentShapeFor(
  profileId: string,
  isoDate: string,
  slot: number,
  contentKind: MomentContentKind = "daily_life",
): string {
  const shapes = isMomentOpinionKind(contentKind)
    ? MOMENT_OPINION_POST_SHAPES
    : MOMENT_POST_SHAPES;
  const seed = `${profileId}|${isoDate}|moment|${slot}|shape|${contentKind}`;
  return shapes[fnv1a(seed) % shapes.length];
}

/**
 * 題材守門的收尾句。「不要硬補照片場景」是為純文字貼文寫的：這一則真的會配圖
 * 時留著它，等於同時要求「不要寫場景」與規則 10 的配圖寫法，兩套指令並存。
 * 有配圖時只保留咖啡／天氣／下班這幾個被寫爛的生活場景禁令，照片怎麼寫一律
 * 交還規則 10（已依 contentKind 分流）。
 *
 * 判準是「這一則到底有沒有圖」，不是「圖是不是生成的」（2026-08-26 Eric 複審
 * P2-1）：生圖旗標關閉時走的是 catalog 圖，同樣會配圖，同樣不能再禁場景。
 */
function themeScopeLine(hasImage: boolean): string {
  const head = "題材決定這則要講生活、觀點、感情、興趣或寵物；" +
    "不是生活片段時，不要硬補咖啡、天氣、下班";
  return hasImage
    ? `${head}場景。配圖怎麼寫只看規則 10，這裡不另外要求場景。`
    : `${head}或照片場景。`;
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

/**
 * 配圖指示。**每一條有圖的路徑都要依 contentKind 分流**，不只生成配圖那條
 * （2026-08-26 Eric 複審 P2-1）：生圖旗標關閉或缺 FAL_API_KEY 時走的是 catalog
 * 圖，觀點題材照樣拿得到，舊版在那條路上仍會同時收到「把文字寫成配得上那張圖」
 * 與「不是生活片段時不要硬補照片場景」兩套指令。
 *
 * 觀點類三條路徑講的是同一件事：**圖是搭配，不是題材**，文字照樣寫想法或取捨。
 */
function imageDirective(
  imageCandidates: readonly string[],
  generatedImage: boolean,
  contentKind: MomentContentKind,
): string {
  const opinion = isMomentOpinionKind(contentKind);
  if (generatedImage) {
    // 生成配圖模式（PR-3）：圖會在文字落地後由生圖模型「以文生圖」。
    // 兩種題材要的「文」不一樣，所以這裡依 contentKind 分流
    // （2026-08-26 Eric 複審 P2）：觀點題材同樣有 imageTags，會真的走到
    // generatedImage=true，若沿用生活片段那句「寫得像拍下眼前的東西」，
    // 模型會為了配圖把社會觀察／感情／價值觀又寫回咖啡與桌面，且與下面
    // 「不是生活片段時不要硬補場景」互相打架——同一個情境兩套指令，
    // 模型只會挑一套照做。觀點類的圖不靠文字描述場景也生得出來：
    // moments_image_gen.ts 的題材場景句本來就替每個觀點題材備好了靜物。
    // 兩條路都維持 imageId = null：生成圖走獨立的 image 欄位組，
    // 不走 catalog allowlist。
    if (opinion) {
      return `10. 這一則會配上一張你隨手拍的照片（拍眼前的東西或場景，不是自拍）。` +
        `照片只是此刻手邊剛好的畫面，不是這則要講的事——文字照樣寫你的想法或取捨，` +
        `不要為了配圖改寫成場景描述，也不要描述照片本身。imageId 必須是 null。`;
    }
    return `10. 這一則會配上一張你隨手拍的照片（拍眼前的東西或場景，不是自拍）。` +
      `把文字寫成你真的拍下了那個畫面的樣子——講具體看得到的東西，` +
      `不要描述照片本身。imageId 必須是 null。`;
  }
  if (imageCandidates.length === 0) {
    return `10. 這一則沒有配圖，imageId 必須是 null。不要在文字裡描述照片。`;
  }
  const onlySelfPortrait = imageCandidates.length === 1 &&
    imageCandidates[0] === SELF_PORTRAIT_IMAGE_ID;
  if (onlySelfPortrait) {
    // resolveAvailableMomentImages 的保底：候選全部不可用時整批換成自拍
    // sentinel，所以任何題材都可能落到這裡，觀點題材也不例外。目前閘門全開
    // 時實測 0 則，但這是資料狀態不是保證，兩種寫法都先定義好。
    if (opinion) {
      return `10. 這一則會配上你自己的照片（一張自拍）。照片只是此刻的你，` +
        `不是這則要講的事——文字照樣寫你的想法或取捨，不要改成描述自己的樣子或所在的場景。` +
        `imageId 必須填 "${SELF_PORTRAIT_IMAGE_ID}"。`;
    }
    // 圖決定文，不是文決定圖：先讓模型知道會配自拍，文案才不會出現
    // 「宵夜」配大頭照那種違和。
    return `10. 這一則會配上你自己的照片（一張自拍）。把文字寫成配得上一張自拍的樣子——` +
      `講你此刻的狀態、心情或樣子，不要描述一個你人不在畫面裡的場景。` +
      `imageId 必須填 "${SELF_PORTRAIT_IMAGE_ID}"。`;
  }
  if (opinion) {
    return `10. 這一則會配一張圖。從 momentImageOptions 裡挑一個最貼題材的 id 填進 imageId；` +
      `那張圖只是搭配，不是這則要講的事——文字照樣寫你的想法或取捨，` +
      `不要為了配圖改寫成場景描述，也不要描述照片本身。不要自己發明 id。`;
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
  contentKind: MomentContentKind;
  brief: string;
  dayPart: TaipeiDayPart;
  isoDate: string;
  isWeekend: boolean;
  slot: number;
  imageCandidates: readonly string[];
  /** 生成配圖模式：候選必為空、imageId 恆 null，圖由背景 job 以文生圖。 */
  generatedImage?: boolean;
}): ChatMessage[] {
  const {
    girl,
    themeId,
    contentKind,
    brief,
    dayPart,
    isoDate,
    isWeekend,
    slot,
    imageCandidates,
  } = opts;
  const generatedImage = opts.generatedImage ?? false;
  const voice = PERSONA_VOICE[girl.personaId];
  const characterLens = momentCharacterLensFor(girl);
  const contentGuidance = MOMENT_CONTENT_GUIDANCE[contentKind];
  const shape = momentShapeFor(girl.profileId, isoDate, slot, contentKind);

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
6. ${characterLens}你平常在意的是${girl.interestTags.join("、")}，生活習慣是${
      girl.lifestyleTags.join("、")
    }。這些是素材庫，不是每一則都要塞進去。
7. 不要用開頭問候語、不要加 hashtag、不要寫成廣告或文案。
8. 結尾不准總結、不准昇華、不准硬轉正能量。真人發廢文不會幫自己的一天下註解。
9. 不用把事情講完整，破碎一點反而真。標點自由：可以整句沒有句號，可以用空格斷句。
${imageDirective(imageCandidates, generatedImage, contentKind)}
11. 這則是「${CONTENT_KIND_LABEL[contentKind]}」：${contentGuidance}
12. 用自然的台灣繁中口語，刪掉可以省略的鋪墊，直接進那個細節或念頭。不要寫成小作文、論說文或完整起承轉合；少用萬用感悟詞（突然覺得／原來／生活就是／儀式感／小確幸／被治癒／好好生活）。語氣詞與 emoji 只有真的符合這個人時才用，不要每則硬塞。

這一則的切入形狀：${shape}。形狀是方向不是模板，貼著你的語感寫。
${themeScopeLine(generatedImage || imageCandidates.length > 0)}
規則 1-4、7、10，以及規則 11 裡的事實與安全限制是硬邊界，違反就作廢重寫；其餘一律以「像這個真人隨手打的」優先——可以隨口、可以不完整、可以有自己的立場，規則沒寫到的寫法都放行。

輸出格式：只輸出一個 JSON 物件，不要有其他文字。
{"text": "貼文內容", "imageId": null}${PROMPT_LEAK_DEFENSE_DIRECTIVE}`;

  const optionsLine = !generatedImage && imageCandidates.length > 0
    ? imageCandidates.join(", ")
    : "（無，imageId 必須是 null）";

  const user = `momentPostSpec
momentDayPart: ${DAY_PART_LABEL[dayPart]}（${isoDate}，${
    isWeekend ? "週末" : "平日"
  }）
momentThemeBrief: ${themeId}（${CONTENT_KIND_LABEL[contentKind]}）— ${brief}
momentImageOptions: ${optionsLine}

照上面的規則寫這一則貼文。`;

  return [
    { role: "system", content: system },
    { role: "user", content: user },
  ];
}
