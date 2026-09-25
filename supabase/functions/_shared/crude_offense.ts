// 粗俗／性冒犯的確定性詞表（練習室與開場救星共用同一份，避免兩邊漂移）。
// 只收沒有無辜用法的詞；有自然語用法的字交給分類器或規劃模型判，寧漏不誤殺。
// 原本住在 practice-chat/game_fsm.ts 與 offense_ladder.ts，2026-09-25 原樣搬來。

/**
 * 詞表比對用的正規化：NFKC、小寫、去空白（「打 炮」與「打炮」同一個字串）。
 * 所有詞表判斷都必須走這一套，不然欲望詞例外在一邊抽得掉、另一邊抽不掉（Codex R1 P1-5）。
 */
export function normalizedOffenseText(text: string): string {
  return text
    .normalize("NFKC")
    .toLowerCase()
    .replace(/\s+/g, "");
}

/**
 * 粗俗性冒犯詞表（Eric 2026-08-08 拍板「扣到 0 為止」）：命中＝確定性嚴重
 * 越界，不看分類器、不看關係階段——這類句子沒有「高溫就可以」的豁免。
 * 詞表只收無曖昧空間的高精度詞（單字「屌」「幹」這類有自然語用法的不收，
 * 「高潮」有劇情高潮等 benign 用法也不收），寧漏給分類器判，不誤殺。
 * handler 的溫度判定與這裡的 NPC 行為（GREASY）共用同一份，避免兩面漂移。
 */
// Codex 首審修表（2026-08-08）：拔掉有自然語用法的低精度詞（露點=天氣、
// 胸部/精液/性交/自慰=健身醫療衛教、脫光=洗澡、舔你=寵物），補上同級粗俗
// 但漏收的高精度詞（幹死妳/插妳/內射/中出/含屌/強姦妳…）。
/** 導出供 debrief 點評欄的「玩家自己打過的字」代稱用（`debrief_card.ts`）。 */
export const CRUDE_SEXUAL_OFFENSE_TERMS = [
  "屁眼",
  "肛交",
  "口交",
  "口爆",
  "顏射",
  "颜射",
  "吞精",
  "做愛",
  "做爱",
  "打炮",
  "約炮",
  "约炮",
  // 台語諧音拼法（2026-08-19 真機實錄「咩修桿某」＝欲相幹無＝要不要打
  // 炮）：字面清單對音義分離輸入天生失明，分類器同樣被騙（該局還升溫
  // +2）。known 諧音拼法先硬堵；無法窮舉，新拼法照「實測會漏的抄進來」
  // 原則補。
  "咩修桿某",
  "咩修幹某",
  "修桿某",
  "修幹某",
  // 髒話的諧音拼法（2026-08-19 Eric 點名「乾林老師/糙機掰 應該要知道」）。
  // 只收完整詞組不收單字：裸「糙」「淦」會誤殺（糙米、淦 當自嘆詞）。
  // 「幹你娘/幹妳娘」已由上方「幹你/幹妳」子字串涵蓋。
  "乾林老師",
  "幹林老師",
  "幹恁老師",
  "乾恁老師",
  "幹恁娘",
  "乾恁娘",
  "乾你娘",
  "乾妳娘",
  "淦你娘",
  "淦妳娘",
  "糙機掰",
  "操機掰",
  "臭機掰",
  "糙你媽",
  "糙妳媽",
  // 英文粗俗（2026-08-19）：中英夾雜是本產品明寫的輸入常態，清單卻全中文
  // ＝「wanna fuck」直接繞過。normalized 已 lowercase＋去空白，詞條寫連寫形。
  // 只收指向對方的完整詞組：裸「fuck／dick」會誤殺（what the fuck 當感嘆、
  // moby dick）。
  "fuckyou",
  "fuckme",
  "wannafuck",
  "letsfuck",
  "fuckbuddy",
  "sendnude",
  "dickpic",
  "blowjob",
  "suckmydick",
  "showmeyourtits",
  "幹你",
  "幹妳",
  "幹死你",
  "幹死妳",
  "幹爆你",
  "幹爆妳",
  "干死你",
  "干死妳",
  "肏",
  "操你",
  "操妳",
  "草你",
  "草妳",
  "插妳",
  "內射",
  "内射",
  "中出",
  "強姦你",
  "強姦妳",
  "强奸你",
  "强奸妳",
  // Phase 5 WP6 性冒犯階梯（Eric 2026-09-06）：羞辱型詞表補上輪姦。
  "輪姦",
  "轮奸",
  "奶子",
  "摸奶",
  "摸胸",
  "揉胸",
  "雞雞",
  "鸡鸡",
  "雞巴",
  "鸡巴",
  "肉棒",
  "含屌",
  "吃屌",
  "騷貨",
  "骚货",
  "婊子",
  "賤貨",
  "贱货",
  "蕩婦",
  "荡妇",
  "破麻",
  "打手槍",
  "打手枪",
  "尻槍",
  "裸照",
  "淫蕩",
  "淫荡",
] as const;

export function containsCrudeSexualOffense(text: string): boolean {
  const compact = normalizedOffenseText(text);
  return CRUDE_SEXUAL_OFFENSE_TERMS.some((term) => compact.includes(term));
}

/**
 * 「打炮／打砲／約炮／約砲」同時躺在兩張既有詞表裡：`CRUDE_SEXUAL_OFFENSE_TERMS`
 * （Game FSM 的 GREASY／spicy 判定）與 `BOUNDARY_RE`。Eric 2026-09-06 對階梯的
 * 定義是「這幾個字是階段不對的**欲望**，不是羞辱」，所以判羞辱型之前先把它們
 * 從文字裡拿掉——**只影響本檔的階梯計分**，兩張原表一個字都沒動（Game FSM
 * 照舊把它們當粗俗冒犯）。拿掉之後它們在詞表層就是 0 分，跟其他性邀約一樣
 * 交給分類器判（2026-09-06 GLM 挑戰閘之後 +1 詞表整條移除）。
 */
export const DESIRE_NOT_INSULT_TERMS: readonly string[] = [
  "打炮",
  "打砲",
  "約炮",
  "约炮",
  "約砲",
  // 2026-09-06 GLM 挑戰閘：「做愛心便當」被 `CRUDE_SEXUAL_OFFENSE_TERMS` 的
  // 「做愛」命中判成羞辱型。它跟打炮同一類——是欲望不是羞辱，交給分類器判。
  "做愛",
  "做爱",
];

export function withoutDesireTerms(text: string): string {
  let stripped = text;
  for (const term of DESIRE_NOT_INSULT_TERMS) {
    stripped = stripped.split(term).join("");
  }
  return stripped;
}

/** 羞辱型粗俗詞（欲望詞先抽掉，交給分類器／規劃判）：練習室階梯 +2 與開場救星 P0 共用。 */
export function containsCrudeInsult(text: string): boolean {
  // 先正規化再抽欲望詞：舊版對原文 split，「打 炮」抽不掉卻被正規化後命中。
  return containsCrudeSexualOffense(withoutDesireTerms(normalizedOffenseText(text)));
}
