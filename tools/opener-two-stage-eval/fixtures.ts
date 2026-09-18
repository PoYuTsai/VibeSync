// 兩段式真模型成對評估的固定資料（附件 §14.3）：12 組情境，每組 A／B／略過三種
// 回答。A 與 B 要有實質差異；expectations 只做可程式核對的部分（禁字、必接字眼、
// 否定），語意由盲審決定。全部是人工撰寫的規格示例，不是真模型輸出。

export interface EvalContribution {
  /** 選項語意（第一段有題目時，依 meaning 挑選項；沒有對應選項就只送 freeText）。 */
  preferOptionMeaning?: string;
  freeText?: string;
  /** 五句裡不得出現的字眼（捏造經歷、被排除的話題）。 */
  forbidden?: string[];
  /** 可見推薦或至少一張可見備選應包含的字眼之一（原料真的進了結果）。 */
  anchors?: string[];
}

export interface EvalScenario {
  id: string;
  shape: string;
  profileInfo: { name?: string; bio?: string; interests?: string; meetingContext?: string };
  /** 第一段附初稿的樣本（F02：初稿已說清楚想聊什麼＋為什麼時不應再問同一題）。 */
  initialUserNote?: string;
  /** 篩選型／她的抱怨字眼：任何臂都不得回應。 */
  profileForbidden?: string[];
  armA: EvalContribution;
  armB: EvalContribution;
}

export const SCENARIOS: EvalScenario[] = [
  {
    id: "multi-hook",
    shape: "多個正向線索",
    profileInfo: { name: "測試丁", bio: "白天在會計事務所對數字\n晚上在 livehouse 打鼓\n最近在學調酒 家裡貓比我早睡", interests: "鼓、調酒、貓", meetingContext: "交友軟體" },
    armA: { preferOptionMeaning: "pick_cue", freeText: "我對打鼓有興趣，我玩過三年樂團", anchors: ["鼓", "樂團"] },
    armB: { freeText: "我對她的貓比較有興趣，我沒養過貓", forbidden: ["我也養", "我家的貓", "我的貓"], anchors: ["貓"] },
  },
  {
    id: "single-hook-dog",
    shape: "單一興趣線索",
    profileInfo: { name: "測試乙", bio: "養了一隻不給摸的柴犬", meetingContext: "交友軟體" },
    armA: { preferOptionMeaning: "assert_sender_fact", freeText: "我家狗散步都自己選路", anchors: ["散步", "選路", "帶路"] },
    armB: { preferOptionMeaning: "curious_without_experience", freeText: "我沒養狗，只好奇牠散步會不會自己選路", forbidden: ["我家那隻", "我也養", "養狗人都懂", "我的狗"], anchors: ["散步", "選路"] },
  },
  {
    id: "rules-plus-hobby",
    shape: "規則與嗜好混合",
    profileInfo: { name: "測試甲", bio: "喜歡把休假拿來學新東西\n\n在醫院輪大夜，作息跟大家相反\n不要問我薪水 也不要問科別\n不喝酒 不要約唱歌\n不聊色 不快速見面\n打字沒誠意的不會回", meetingContext: "交友軟體" },
    profileForbidden: ["薪水", "科別", "喝酒", "唱歌", "誠意"],
    armA: { freeText: "我對「休假學新東西」有興趣，我自己最近在學木工", anchors: ["學", "木工"] },
    armB: { freeText: "想聊大夜作息，我以前也輪過班，現在沒有了", forbidden: ["我現在也輪", "我也在輪"], anchors: ["大夜", "作息", "輪"] },
  },
  {
    id: "filter-heavy",
    shape: "抱怨與篩選條件為主",
    profileInfo: { name: "小可愛", bio: "本人是肉肉的～不能接受請不要滑右邊～\n滑了聊天又叫我改變…我就是長這樣…\n騙色騙財 真的先不要～\n麻煩可以多一點正常人嗎？\n真的不要玩玩～想約的麻煩左滑謝謝～有女朋友的也不要滑右邊～\n想找情緒穩定～有耐心的男生～可以長長久久", interests: "職業：美容師；地區：新北", meetingContext: "交友軟體" },
    profileForbidden: ["正常人", "肉", "騙", "玩玩", "改變", "耐心", "穩定", "自介"],
    armA: { freeText: "我妹也是美容師", forbidden: ["我也是美容師", "我們做美容的"], anchors: ["美容", "妹"] },
    armB: { freeText: "我最近在找板橋晚餐店，不想聊工作", forbidden: ["美容", "工作"], anchors: ["板橋", "晚餐", "吃"] },
  },
  {
    id: "basic-fields-only",
    shape: "只有基本欄位",
    profileInfo: { name: "測試丙", interests: "看電影", meetingContext: "交友軟體" },
    armA: { freeText: "我想問她最近有沒有看到值得進戲院的片", anchors: ["戲院", "片", "電影"] },
    armB: { freeText: "隨口的新話題就好，不用聊電影", forbidden: ["電影"] },
  },
  {
    id: "photo-scene",
    shape: "照片或限動（純文字替身：用戶描述照片）",
    profileInfo: { name: "測試戊", bio: "自介只有一句：週末不在家", interests: "照片：河堤旁的咖啡店、一杯拿鐵", meetingContext: "IG" },
    armA: { freeText: "我認得照片那家店，在河堤旁邊，我去過一次", anchors: ["店", "河堤"] },
    armB: { freeText: "我沒去過那家店，只想問在哪", forbidden: ["我去過", "我也去過", "常去"], anchors: ["店", "哪"] },
  },
  {
    id: "real-life-scene",
    shape: "現實認識的共同場景",
    profileInfo: { name: "測試己", bio: "朋友生日聚餐認識，她負責訂餐廳", meetingContext: "現實認識" },
    armA: { freeText: "上次聚會她帶了一隻很乖的狗來，想接這個", forbidden: ["一起遛", "我們遛"], anchors: ["狗", "聚會", "上次"] },
    armB: { freeText: "上次她訂的那家餐廳我很喜歡，想問還有沒有推薦", anchors: ["餐廳", "推薦"] },
  },
  {
    id: "family-fact",
    shape: "家人的事 vs 自己的事",
    profileInfo: { name: "測試庚", bio: "在動物醫院當獸醫助理，下班只想睡", meetingContext: "交友軟體" },
    armA: { freeText: "我妹下班完全不想聊工作，我猜她也是", forbidden: ["我下班也", "我也是助理"], anchors: ["妹", "下班"] },
    armB: { freeText: "我自己以前在寵物店打工過，現在沒有了", forbidden: ["我現在在寵物店", "我也在寵物店"], anchors: ["寵物店", "以前"] },
  },
  {
    id: "she-said-vs-guess",
    shape: "她曾說過的事 vs 用戶猜的",
    profileInfo: { name: "測試辛", bio: "假日固定去河堤練滑板", meetingContext: "交友軟體" },
    armA: { freeText: "她上次聊天提過想去沖繩，還沒訂", forbidden: ["妳下個月去沖繩", "已經訂好"], anchors: ["沖繩"] },
    armB: { freeText: "我猜她應該喜歡海邊，不確定", forbidden: ["妳上次說", "妳說過"], anchors: ["海", "滑板"] },
  },
  {
    id: "raw-sentence",
    shape: "已經有原始句子（第一段附初稿）",
    profileInfo: { name: "測試壬", bio: "照片：登山路線，霧很大", interests: "爬山", meetingContext: "交友軟體" },
    initialUserNote: "我想問她照片那條路線新手走不走得完，我沒爬過山",
    armA: { freeText: "我想問她照片那條路線新手走不走得完，我沒爬過山", forbidden: ["我上次也爬", "我也爬過"], anchors: ["路線", "新手"] },
    armB: { freeText: "我想問她那條路線值不值得去，看起來很漂亮", anchors: ["路線", "漂亮", "值"] },
  },
  {
    id: "explicit-exclusion",
    shape: "明確排除某個話題（第一段附初稿）",
    profileInfo: { name: "測試癸", bio: "工程師，週末在家烤司康，養一隻很吵的玄鳳", meetingContext: "交友軟體" },
    initialUserNote: "不要聊她的工作，想聊玄鳳",
    armA: { freeText: "不要聊她的工作，想聊玄鳳", forbidden: ["工程師", "工作"], anchors: ["玄鳳", "鳥"] },
    armB: { freeText: "不要聊玄鳳，司康我有興趣但沒烤過", forbidden: ["玄鳳", "我也烤", "我烤過"], anchors: ["司康", "烤"] },
  },
  {
    id: "goal-not-consent",
    shape: "用戶的目標不等於對方意願",
    profileInfo: { name: "測試子", bio: "咖啡成癮，一天三杯", interests: "咖啡", meetingContext: "交友軟體" },
    armA: { freeText: "我想約她喝咖啡", forbidden: ["妳想見面", "妳答應", "妳說要約"], anchors: ["咖啡"] },
    armB: { freeText: "我對咖啡沒研究，只想知道她三杯是怎麼分配的", forbidden: ["我也一天三杯", "我也成癮"], anchors: ["三杯", "咖啡"] },
  },
];

/**
 * 附加實驗「舊單段＋A 補充」用的補充字串（鏡像 tools/opener-blackbox 的 supplement 臂）。
 * 規格要求的控制組是「原樣舊單段、同樣對方資料、不注入補充」；這個只在
 * --legacy-plus-a 時另列，不混成基準。
 */
export function legacySupplementFor(arm: EvalContribution): string | null {
  return arm.freeText ?? null;
}

/** 圖片／限動情境本工具不涵蓋（純文字 API 路徑）；列出來讓報告明說未涵蓋。 */
export const NOT_COVERED = ["照片／限動的實際讀圖（photo-scene 只是文字替身）", "第一段 wrongSurface 錯圖判定", "Free／paid 在 App 端的鎖卡渲染"];
