// opener_material.ts 話題優先（opener-two-stage-topic-first-v1）：照片／自介 Opener 是開場教練，這一則只開話題。
// 想約、幫我約、第一句就直接約、貼上寫給她的邀約原句，都是之後的目標，不產生採用要求；家人或朋友的事、
// 我＋過去經歷只當選題依據；真正想聊想問的 X 仍要被接住。採用證據只去掉用戶目標子句的目標字眼與「一起」；
// 目標子句裡其他的字（X 本身、週末、有空…）仍是字面證據，這是字面檢查，不是邀約偵測。
// 表格轉自最小改動提案的原型探針 probe_floor2.ts（115 條），預期取自擬議規則實測結果。
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildOpenerMaterials, cardAdoptsMaterial, checkMaterialAdoption } from "./opener_material.ts";
import { OPENER_FREE_V2_TYPES, OPENER_TYPES, type OpenerType } from "./opener_payload.ts";
import { buildOpenerAnalysisSnapshot } from "./opener_stage.ts";

/** 只有自介文字與線索的合成快照（同 naturalness.ts syntheticSnapshot），補充走正式原料整理。 */
function materialsFor(text: string, cues: string[]) {
  const bio = cues.join("、");
  const snapshot = buildOpenerAnalysisSnapshot({
    parsed: {
      profileDigest: bio,
      approach: { mode: "anchor_hooks", summary: "依可核對的資料與本次補充選題", avoid: [] },
      cues: cues.map((label, i) => ({ id: `cue_${i + 1}`, label, source: "profile_text", evidence: { field: "bio", quote: label } })),
      question: null,
    },
    rawProfileInfo: { bio },
    imageCount: 0,
    initialUserNote: null,
  });
  if (!snapshot || snapshot.cues.length !== cues.length) throw new Error(`invalid synthetic snapshot: ${text}`);
  return buildOpenerMaterials({ snapshot, contribution: { state: "answered", questionId: null, selectedOptionId: null, freeText: text }, option: null });
}

const RANK: OpenerType[] = ["extend", "humor", "tease", "resonate", "coldRead"];
function flagsUnused(openers: Record<string, string>, set: ReturnType<typeof materialsFor>, visibleTypes: readonly OpenerType[] = OPENER_FREE_V2_TYPES): boolean {
  return checkMaterialAdoption({ openers, materials: set, visibleTypes, rankedPicks: RANK }).some((f) => f.code === "material_unused");
}

// 離題卡逐題挑：與補充和線索不共用任何一個字、也沒有邀約字，才不會因「夜貓子／週末通常／做什麼」這類共用字誤判成接住。
const POOL = ["天氣變冷了", "颱風快來了耶", "週一症候群發作中", "今晚月亮好圓", "外面風好大", "鬧鐘響三次才起床", "夏天熱到融化", "冰淇淋季節", "晚安好夢", "星期五萬歲", "捷運好擠", "塞車塞到懷疑人生", "手搖飲甜度幾分", "午餐吃麵還是飯", "晴朗適合曬棉被", "雨傘又忘記帶", "早餐店奶茶最療癒", "颳風下雨別感冒", "咖哩飯派還是拉麵派", "牙膏擠中間還是尾巴", "睡飽沒", "今天星期幾", "周末補眠計畫", "加班到懷疑自我", "蚊子超多", "冷氣開幾度", "滷肉飯加蛋", "香菜派嗎", "薯條沾冰淇淋", "炸雞配啤酒", "耳機又打結", "手機快沒電", "電梯故障爬樓梯", "早晨跑步真累", "貓咪伸懶腰"];
const INVITE_WORDS = /(約|一起|要不要|有空|哪天|改天|找一天|下次)/u;
function offCards(text: string, cues: string[]): Record<string, string> {
  const used = new Set([...(text + cues.join(""))]);
  const picks = POOL.filter((p) => !INVITE_WORDS.test(p) && ![...p].some((ch) => used.has(ch))).slice(0, 5);
  if (picks.length < 5) throw new Error(`not enough off cards for ${text}`);
  return { extend: picks[0], humor: picks[1], tease: picks[2], resonate: picks[3], coldRead: picks[4] };
}
/** 聊到她線索的卡：推薦卡改成問她第一個線索。 */
function clueCards(text: string, cues: string[]): Record<string, string> {
  return { ...offCards(text, cues), extend: `妳${cues[0]}最喜歡哪個部分` };
}

// [補充, 她的線索, keep＝至少一張可見卡要接住／bg＝不要求, 說明]
const CASES: [string, string[], "keep" | "bg", string][] = [
  ["想約她一起去陶藝體驗課", ["陶藝教室", "拉坯"], "bg", "想約她去 X（之後的目標）"],
  ["想約她打羽球", ["羽球"], "bg", "想約她去 X（之後的目標）"],
  ["我想約她喝咖啡", ["一天三杯咖啡"], "bg", "想約她去 X（之後的目標）"],
  ["想約她去看展，看她哪天有空", ["當代藝術展"], "bg", "目標＋排時間"],
  ["想約她去看展，看她什麼時候方便", ["當代藝術展"], "bg", "目標＋排時間"],
  ["想約她打羽球，問她週末有沒有空", ["羽球"], "keep", "目標＋排時間"],
  ["直接約", ["當代藝術展"], "bg", "明確要求邀約（簡寫）"],
  ["直接約就好", ["當代藝術展"], "bg", "明確要求邀約（簡寫）"],
  ["想見面但她說不約", ["羽球"], "bg", "目標＋她的限制"],
  ["我哥是樂器行老闆，我自己沒玩過樂器", ["打鼓", "玩樂團"], "bg", "家人＋否定經歷"],
  ["我自己也烤過吐司", ["烤麵包", "養酵母"], "bg", "我＋過去經歷"],
  ["我妹也是美容師", ["美容師工作"], "bg", "家人"],
  ["我自己以前在寵物店打工過，現在沒有了", ["獸醫助理工作"], "bg", "我＋過去經歷"],
  ["我跟我妹一起去過陶藝課", ["陶藝教室"], "bg", "我＋過去經歷"],
  ["我朋友說她超愛爬山", ["爬山"], "keep", "轉述她"],
  ["我同事說她很會跳舞", ["跳舞"], "keep", "轉述她"],
  ["她提過想跟姊妹一起去沖繩，還沒訂", ["沖繩"], "keep", "她的計畫"],
  ["我看過她跳舞的影片", ["跳舞"], "keep", "關於她"],
  ["我哥是樂器行老闆 她好像也會打鼓", ["打鼓"], "keep", "空白分句，後半是她"],
  ["想約她去陶藝課 她IG常發拉坯", ["拉坯"], "bg", "目標補充裡的附帶資訊"],
  ["想約她去陶藝課順便聊她的拉坯", ["拉坯"], "keep", "目標＋想聊（無標點）"],
  ["想約她去陶藝課，想先聊她拉坯", ["拉坯"], "keep", "目標＋想聊"],
  ["我以前住台中，想問她台中哪裡好吃", ["台中美食"], "keep", "經歷＋想問"],
  ["我養了兩隻貓", ["貓"], "keep", "現在式自述"],
  ["我也養貓三年了", ["貓"], "keep", "現在式自述"],
  ["我住台中五年了", ["台中"], "keep", "現在式自述"],
  ["我也養貓", ["貓"], "keep", "現在式自述"],
  ["我住台中", ["台中"], "keep", "現在式自述"],
  ["我最近在找板橋晚餐店，不想聊工作", ["美容師工作"], "keep", "用戶現況當話題"],
  ["我猜她應該喜歡海邊，不確定", ["河堤練滑板"], "keep", "猜她"],
  ["其實我想問她都去哪些營地，不用聊狗", ["露營"], "keep", "想問"],
  ["我跟她上次一起去過音樂祭", ["音樂祭"], "keep", "先前互動"],
  ["我不想約她，先聊咖啡", ["咖啡"], "keep", "否定目標＋想聊"],
  ["我哥說她很會煮", ["料理"], "keep", "轉述她"],
  ["我妹跟她是同事", ["護理師"], "keep", "家人＋她"],
  ["想跟她去看電影", ["電影"], "keep", "非目標字眼的想約（邊界）"],
  ["想找她吃飯", ["美食"], "keep", "非目標字眼的想約（邊界）"],
  ["週末要不要一起去看展？", ["當代藝術展"], "bg", "貼上寫給她的邀約原句"],
  ["我姊也是美容師", ["美容師工作"], "bg", "家人（姊）"],
  ["我姊姊是美容師", ["美容師工作"], "bg", "家人（姊姊）"],
  ["我的妹妹是美容師", ["美容師工作"], "bg", "家人（我的）"],
  ["妹妹也是美容師", ["美容師工作"], "bg", "家人（省略我）"],
  ["我表妹是美容師", ["美容師工作"], "bg", "家人（表）"],
  ["我家開麵包店", ["烤麵包"], "bg", "我家"],
  ["家裡開樂器行", ["打鼓"], "bg", "家裡"],
  ["以前在寵物店打工過，現在沒有了", ["獸醫助理工作"], "bg", "省略主詞的過去經歷"],
  ["之前學過一年吉他", ["彈吉他"], "bg", "省略主詞的過去經歷"],
  ["大學玩過三年樂團", ["打鼓", "玩樂團"], "bg", "省略主詞的過去經歷"],
  ["自己也烤過吐司", ["烤麵包"], "bg", "省略主詞的過去經歷"],
  ["她妹妹是護理師", ["護理師"], "keep", "她的家人"],
  ["以前她在寵物店打工過", ["寵物店"], "keep", "她的過去"],
  ["幫我約她去看展", ["當代藝術展"], "bg", "想約的命令句"],
  ["我家的狗很黏人", ["狗"], "keep", "我家寵物（現在式，維持）"],
  ["想約她出來聊聊", ["當代藝術展"], "bg", "目標（出來聊聊）"],
  ["約她出來聊天", ["當代藝術展"], "bg", "目標（出來聊天）"],
  ["想約她見面聊聊", ["當代藝術展"], "bg", "目標（見面聊聊）"],
  ["想約她出來聊聊，看她哪天有空", ["當代藝術展"], "bg", "目標＋排時間"],
  ["想約她去看展，看她反應", ["當代藝術展"], "bg", "目標＋後設語"],
  ["想約她去看展，但我怕被拒絕", ["當代藝術展"], "bg", "目標＋心情"],
  ["想約她去看展，不過怕太快", ["當代藝術展"], "bg", "目標＋心情"],
  ["想約她去看展，先慢慢來", ["當代藝術展"], "bg", "目標＋後設語"],
  ["想約她去看展，可是我很緊張", ["當代藝術展"], "bg", "目標＋心情"],
  ["想約她打羽球，她說下次比賽在台中", ["羽球"], "bg", "目標補充裡的附帶資訊"],
  ["想約她去看展，她IG說有空都在逛美術館", ["當代藝術展"], "bg", "目標補充裡的附帶資訊"],
  ["想約她去看展，想問她下次想看什麼展", ["當代藝術展"], "keep", "目標＋想問"],
  ["想約她爬山，順便問她什麼時候最常去爬", ["爬山"], "keep", "目標＋順便問"],
  ["想約她去吃飯，想問她住哪附近比較方便", ["美食"], "keep", "目標＋想問"],
  ["她說想跟姊妹一起去沖繩", ["沖繩"], "keep", "她的計畫（她為主語）"],
  ["我朋友說她超想跟人一起去露營", ["露營"], "keep", "轉述她的計畫"],
  ["她最近想約朋友去爬山", ["爬山"], "keep", "她的計畫（她為主語）"],
  ["她常常被朋友約出去玩", ["出遊"], "keep", "她的事（她為主語）"],
  ["我同事邀她一起參加路跑", ["路跑"], "keep", "第三方邀她"],
  ["想邀她推薦幾本書", ["閱讀"], "bg", "邊界：想邀＝請她推薦"],
  ["我表妹也是護理師", ["護理師"], "bg", "家人（表妹）"],
  ["我阿姨開樂器行", ["打鼓"], "bg", "家人（阿姨）"],
  ["我之前在寵物店打工", ["獸醫助理工作"], "bg", "我＋之前"],
  ["之前也玩過樂團", ["打鼓"], "bg", "省略主詞的過去經歷"],
  ["我大學在寵物店打工", ["獸醫助理工作"], "keep", "邊界：沒有過去標記"],
  ["我以前在 Starbucks 打工過", ["咖啡"], "bg", "中英混寫的過去經歷"],
  ["我哥是 DJ", ["音樂"], "bg", "中英混寫的家人"],
  ["我朋友是攝影師", ["攝影"], "bg", "朋友"],
  ["我室友也在學日文", ["日文"], "bg", "室友"],
  ["幫我問她要不要一起去看展", ["當代藝術展"], "bg", "明確要求邀約（幫我問她要不要一起去）"],
  ["直接問她要不要一起去看展", ["當代藝術展"], "bg", "明確要求邀約（第一句／直接）"],
  ["第一句就直接問她要不要一起去看展", ["當代藝術展"], "bg", "明確要求邀約（第一句／直接）"],
  ["幫我直接約她去看展", ["當代藝術展"], "bg", "明確要求邀約（幫我直接約她去）"],
  ["最近有個當代藝術展，要不要一起去看？", ["當代藝術展"], "bg", "貼上寫給她的邀約原句"],
  ["我要不要約她？", ["當代藝術展"], "bg", "目標（自問）"],
  ["之前去過京都，超推", ["京都旅遊"], "keep", "ADV-1 經歷＋評語"],
  ["我以前也玩過樂團，很好玩", ["玩樂團"], "keep", "ADV-1 經歷＋評語"],
  ["我自己也烤過吐司，超療癒", ["烤麵包", "養酵母"], "keep", "ADV-1 經歷＋評語"],
  ["我妹也是美容師，她說這行很累", ["美容師工作"], "keep", "ADV-1 家人＋她說"],
  ["我表哥也在當工程師 所以大概懂", ["工程師"], "keep", "ADV-1 家人＋評語"],
  ["我曾經在日本住過兩年 想問她推薦哪裡", ["日本旅遊"], "keep", "ADV-1 經歷＋想問"],
  ["我以前也養過狗，現在很想再養", ["養狗"], "keep", "ADV-1 經歷＋現況"],
  ["不想約她 想聊她的貓", ["養貓"], "bg", "ADV-2 否定目標＋空白（舊規則也無底線）"],
  ["先不約 想問她平常都去哪爬山", ["爬山"], "bg", "ADV-2 否定目標＋空白（舊規則也無底線）"],
  ["我朋友說他超愛爬山", ["爬山"], "keep", "ADV-3 他＝她"],
  ["朋友建議我從咖啡聊起", ["手沖咖啡"], "keep", "ADV-3 朋友建議"],
  ["之前看過對方跑馬拉松的照片", ["馬拉松"], "keep", "ADV-3 對方"],
  ["邀她推薦一家咖啡廳", ["咖啡廳"], "keep", "ADV-3 邀她推薦"],
  ["我同事說他以前是國手", ["羽球"], "keep", "ADV-3 同事說他"],
  ["問她週末都跟誰一起去爬山", ["爬山"], "keep", "ADV-4 問她＋一起去"],
  ["想了解她平常都跟誰一起去看展", ["當代藝術展"], "keep", "ADV-4 想了解＋一起去"],
  ["感覺她很常跟朋友一起去夜市", ["逛夜市"], "keep", "ADV-4 她的事＋一起去"],
  ["上次聊天她說想跟我一起去看展", ["當代藝術展"], "keep", "ADV-4 先前互動"],
  ["之前一起去過音樂祭", ["音樂祭"], "keep", "ADV-4 共同經歷"],
  ["上次見個面後就沒聊了", ["咖啡"], "keep", "ADV-4 過去事件"],
  ["想跟她見面", ["爬山"], "bg", "ADV-5 見面目標"],
  ["想跟她約會", ["爬山"], "bg", "ADV-5 約會目標"],
  ["想找她出來", ["爬山"], "bg", "ADV-5 找她出來"],
  ["希望可以跟她碰個面", ["爬山"], "bg", "ADV-5 碰個面"],
  ["她問我要不要一起去看展", ["當代藝術展"], "keep", "她邀用戶（先前互動）"],
  ["好像很多人想約她", ["跳舞"], "keep", "第三方想約她"],
  ["我朋友想約她去看展", ["當代藝術展"], "keep", "第三方的目標"],
];

// 既有行為（新舊規則相同，非本案改動）：補充的內容字與線索不共用（煮／料理、吃飯／美食、國手／羽球…），
// 只聊線索的卡本來就不算接住。
const CLUE_CARD_STILL_UNUSED = new Set([
  "我最近在找板橋晚餐店，不想聊工作",
  "我哥說她很會煮",
  "我妹跟她是同事",
  "想找她吃飯",
  "想約她去吃飯，想問她住哪附近比較方便",
  "我同事說他以前是國手",
  "上次見個面後就沒聊了",
  "她問我要不要一起去看展",
  "好像很多人想約她",
]);

Deno.test("話題優先 115 條：離題卡只在話題型補充被判 material_unused；聊到她線索的卡不新增錯誤", () => {
  const mismatches: string[] = [];
  for (const [text, cues, expected, note] of CASES) {
    const set = materialsFor(text, cues);
    const floor = flagsUnused(offCards(text, cues), set) ? "keep" : "bg";
    if (floor !== expected) mismatches.push(`離題卡 ${text}（${note}）：預期 ${expected}，實際 ${floor}`);
    const clueUnused = flagsUnused(clueCards(text, cues), set);
    if (clueUnused !== CLUE_CARD_STILL_UNUSED.has(text)) mismatches.push(`線索卡 ${text}（${note}）：material_unused=${clueUnused}`);
  }
  assertEquals(mismatches, []);
  assertEquals(CASES.length, 115);
  assertEquals(CASES.filter(([, , expected]) => expected === "bg").length, 59);
});

Deno.test("教練定位：明確要求邀約或貼邀約原句都只開場，本身不產生採用要求；Free 與付費一致", () => {
  const cues = ["陶藝教室", "拉坯"];
  for (const text of [
    "週末要不要一起去陶藝教室？",
    "第一句就直接約她去陶藝教室",
    "第一句就直接約她",
    "幫我約她去陶藝教室",
    "幫我問她要不要一起去陶藝教室",
    "想約她一起去陶藝體驗課",
  ]) {
    const set = materialsFor(text, cues);
    for (const visibleTypes of [OPENER_FREE_V2_TYPES, OPENER_TYPES]) {
      assertEquals(flagsUnused(offCards(text, cues), set, visibleTypes), false, `${text}：離題卡不因目標被擋（${visibleTypes.length} 卡）`);
      assertEquals(flagsUnused(clueCards(text, cues), set, visibleTypes), false, `${text}：聊到她線索的卡直接交付（${visibleTypes.length} 卡）`);
    }
  }
  // 沒碰到 X 的邀約卡不算接住；聊到 X 本身才算（目標子句的其他字仍是字面證據，見檔尾一則）。
  const invite = materialsFor("幫我約她去陶藝教室", cues);
  assertEquals(cardAdoptsMaterial("改天有空嗎", invite), false, "沒碰到 X 的邀約卡不算接住");
  assertEquals(cardAdoptsMaterial("陶藝教室上課都在做杯子還是碗", invite), true);
});

Deno.test("教練定位：想約之外還有明確想聊想問的子句，仍要被接住", () => {
  const cues = ["陶藝教室", "拉坯"];
  for (const text of ["想約她去陶藝課，想先聊她拉坯", "幫我約她去陶藝課，想先問她拉坯多久了", "想約她去陶藝課順便聊她的拉坯"]) {
    const set = materialsFor(text, cues);
    for (const visibleTypes of [OPENER_FREE_V2_TYPES, OPENER_TYPES]) {
      assertEquals(flagsUnused(offCards(text, cues), set, visibleTypes), true, `${text}：離題卡仍擋（${visibleTypes.length} 卡）`);
      assertEquals(flagsUnused(clueCards(text, cues), set, visibleTypes), false, `${text}：聊到她線索的卡算接住（${visibleTypes.length} 卡）`);
    }
  }
});

Deno.test("採用證據：用戶目標子句的想約／約她／一起不算接住，想問的話題仍要被接住；她的事裡的同樣字眼照舊算", () => {
  const cues = ["一天三杯咖啡"];
  const mix = materialsFor("想約她喝咖啡，想問她三杯怎麼分配", cues);
  const inviteOnly = { extend: "有空想約妳出來走走", humor: "猜妳是貓派", tease: "最近在追什麼劇" };
  assertEquals(flagsUnused(inviteOnly, mix), true, "邀約卡冒充不了想問的話題：仍要一次修正");
  assertEquals(cardAdoptsMaterial("有空想約妳出來走走", mix), false);
  assertEquals(cardAdoptsMaterial("三杯是早中晚各一杯嗎", mix), true, "接住想問的三杯才算");
  for (const [text, card] of [
    ["我想約她喝咖啡", "找一天想約妳喝一杯"],
    ["我想約她一起喝咖啡", "找一天一起喝一杯吧"],
    ["想約她一起去陶藝課，想問她都做什麼作品", "週末一起去吧"],
    ["想約她一起去陶藝體驗課", "改天一起去吧"],
  ]) assertEquals(cardAdoptsMaterial(card, materialsFor(text, ["陶藝教室", "拉坯", ...cues])), false, `${text}／${card}`);
  assertEquals(cardAdoptsMaterial("一天三杯咖啡 是靠什麼撐的", materialsFor("我想約她一起喝咖啡", cues)), true, "X 本身仍是接住");
  // 「約出去」是她的事，不是用戶的目標：聊她出遊的卡照舊算接住。
  assertEquals(cardAdoptsMaterial("妳出遊最喜歡哪個部分", materialsFor("她常常被朋友約出去玩", ["出遊"])), true);
});
