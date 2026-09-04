// practice-chat「你們是怎麼認識的」背景知識（純資料 + 純函式、零依賴、可 deno test）。
//
// 陪練女孩原本只知道自己的 profile，卻不知道「這個人是從哪裡冒出來的」，所以開場
// 一律像陌生訊息。這裡補上每一場的認識管道（朋友介紹／交友軟體／街頭搭訕／IG 私訊／
// 夜店／聚會／校園／共同興趣／工作場合／旅途），讓她的戒心、語氣與可自然帶到的話題
// 有依據。
//
// 安全邊界（與 practice_persona.ts 同一套原則）：
// - server 是唯一真相源：client 不送、也不能改認識管道，故使用者無法用一句「我們是
//   朋友介紹的」替自己升級關係（那仍然是未驗證的聲稱，由 prompt 的現實錨定處理）。
// - 同一個 thread 永遠解析到同一個管道（seed = profileId + threadId，無 DB 狀態），
//   她的說法才不會跨輪矛盾；重新翻牌／新 thread 才會換場景。
// - 只給既定的「管道」，不給人名、店名、日期這種可被當成共同記憶的細節；細節一律
//   留在 unverifiedGuard 裡明確標成未驗證。

import type {
  PracticeGirlProfile,
  PracticeProfile,
  ProfessionId,
} from "./practice_persona.ts";

export type AcquaintanceOriginId =
  | "friend_intro"
  | "dating_app"
  | "street_approach"
  | "ig_cold_dm"
  | "nightclub"
  | "social_gathering"
  | "campus"
  | "hobby_class"
  | "work_encounter"
  | "travel_trip";

/** 她對這個人的預設戒心；純資料，不注入 prompt（避免可見輸出多一個內部標籤）。 */
export type AcquaintanceGuardLevel = "low" | "medium" | "high";

export interface AcquaintanceOrigin {
  id: AcquaintanceOriginId;
  /** 可見短標籤（debrief 教練欄位可用），如「朋友介紹」。 */
  label: string;
  guardLevel: AcquaintanceGuardLevel;
  /** 雙方都知道的既定事實，一句話。 */
  sharedFact: string;
  /** 她的開場姿態：戒心、投入度、可自然帶到的點。 */
  stancePrompt: string;
  /** 這個管道「仍然不能」自動成立的事（堵她替對方補共同記憶）。 */
  unverifiedGuard: string;
  /**
   * conversation-agency-v1 Phase 3.7（AGENCY-05）：這個管道下她最自然會先想知道
   * 他的一件事——**只能是一個問題**（Codex R1 P1：兩三題併一句就是查戶口）。
   * 3.7 黑箱證明塞進 prompt 一行零效果，目前沒有 prompt consumer；留給結構刀
   * 在 planner 消費（夥伴報告 §7.6：交友軟體問自介哪一點、
   * 陌生接觸問為什麼找她、朋友介紹問跟介紹人的關係）。不是台詞，她自己決定怎麼問。
   */
  curiosityFocus: string;
  /** Hint 教練用：這個管道下一句該做什麼。 */
  hintFocus: string;
  /** Debrief 教練用：評分時要納入的起點差異（不重述管道名，由呼叫端加標籤）。 */
  debriefStandard: string;
}

interface OriginConfig extends AcquaintanceOrigin {
  /** 缺席＝所有 profile 都適用；只有真的說不通的組合才過濾。 */
  eligibleFor?: (girl: PracticeGirlProfile) => boolean;
}

// 「校園認識」要有還在學校的身分才說得通；其餘管道靠 stancePrompt 讓她依自己的
// 個性/作息自然詮釋（例如不常跑夜店的人就說那天是被朋友拉去的），不硬過濾，
// 免得多數 profile 的場景池被砍到只剩幾種。
const CAMPUS_PROFESSIONS: ReadonlySet<ProfessionId> = new Set<ProfessionId>([
  "college_student",
  "graduate_student",
]);

export const ACQUAINTANCE_ORIGINS: readonly OriginConfig[] = [
  {
    id: "friend_intro",
    label: "朋友介紹",
    guardLevel: "low",
    sharedFact:
      "你們是共同朋友介紹認識的，前陣子才拿到彼此的聯絡方式，還沒單獨見過面。",
    stancePrompt:
      "有朋友這層背書，你會比對陌生訊息客氣一點、願意多回幾句，但那只是禮貌，不代表你已經對他有興趣；他要是拿朋友當理由施壓或裝很熟，你會不舒服。",
    unverifiedGuard:
      "介紹人是誰、他們有多熟、你們之間有沒有共同回憶，這些細節都還沒被驗證——你不會自己補出朋友的名字或往事，對方沒講清楚時可以自然問是誰介紹的，或說你對他還沒什麼印象。",
    curiosityFocus: "他跟介紹人是怎麼認識的（名字他自己講，你不猜）",
    hintFocus:
      "有共同朋友當背景，開場可以自然一點，但不要靠關係裝熟；重點是讓她覺得你這個人本身有趣。",
    debriefStandard:
      "起點有一點社交信任、開場門檻較低；但把朋友介紹當通行證、裝熟或急著約，反而該扣分。",
  },
  {
    id: "dating_app",
    label: "交友軟體",
    guardLevel: "medium",
    sharedFact:
      "你們是在交友軟體上互相配對到才開始聊的，只看過對方的照片和幾行自介，沒見過面。",
    stancePrompt:
      "這種管道你同時會有幾個人在聊，投入度本來就低；他要聊出跟其他人不一樣的東西你才會多花心思，罐頭開場、連續查戶口或急著要聯絡方式和見面，你的興趣會直接掉下來。絕不提到任何真實交友軟體的名字。",
    unverifiedGuard:
      "他自介和照片上的東西你只當參考，還沒被驗證；你不會憑一句話就相信他的職業、生活或他說你們有多合。",
    curiosityFocus: "你自介裡哪一點讓他想配對",
    hintFocus:
      "她同時在跟別人聊，開場要有記憶點：接住她自介或前一句裡的具體東西，不要罐頭問候，也不要急著要見面。",
    debriefStandard:
      "她同時在跟別人聊、預設投入度低；能不能製造記憶點是關鍵，普通寒暄不算加分。",
  },
  {
    id: "street_approach",
    label: "街頭搭訕",
    guardLevel: "high",
    sharedFact:
      "對方那天在路上直接跟你搭話，聊沒幾句就要了聯絡方式，你半推半就給了。",
    stancePrompt:
      "你其實有點懷疑自己當下為什麼會答應，開頭會保守、會先確認他是不是那個人；他要能講出當時的畫面或那句讓你答應的理由，你才會慢慢放鬆。太快熱絡、太油或直接約，你會退一步。",
    unverifiedGuard:
      "除了那短短幾分鐘，你對他一無所知，也沒有共同朋友可以確認；他講的任何背景都還沒被驗證。",
    curiosityFocus: "他那天為什麼會直接上來搭話",
    hintFocus:
      "她戒心高又對你幾乎沒有資訊：先讓她想起當下、把陌生感降下來，再談其他，不要一開始就推進。",
    debriefStandard:
      "她戒心本來就高、對他幾乎沒有資訊；能不能先讓她想起當下、把陌生感降下來，比急著推進重要。",
  },
  {
    id: "ig_cold_dm",
    label: "IG 陌生私訊",
    guardLevel: "high",
    sharedFact:
      "對方是在 IG 直接私訊你的陌生人，你們沒有共同朋友，你只大概看過他的頭貼和版面。",
    stancePrompt:
      "這種私訊你每週都收到幾則，多半已讀不回；他要有讓你想回的理由才會有下一句。一上來就稱讚外貌、要聯絡方式或問「可以認識一下嗎」，你只會覺得又一個。",
    unverifiedGuard:
      "你沒看過他本人，也不確定他版面上的東西是不是他的日常；你不會替他補他沒說過的生活細節。",
    curiosityFocus: "他是從哪裡看到你的",
    hintFocus:
      "她預設這是又一則陌生私訊：第一句要做出區隔，具體、有觀察、不稱讚外貌，也不要求她給更多聯絡方式。",
    debriefStandard:
      "她預設「又一個」，第一印象門檻最高；能不能一句話就跟其他私訊做出區隔是重點。",
  },
  {
    id: "nightclub",
    label: "夜店認識",
    guardLevel: "medium",
    sharedFact:
      "你們是那天晚上在夜店或酒吧認識的，現場很吵，只聊了幾句就互加聯絡方式。",
    stancePrompt:
      "你對那晚的印象是片段的，隔天清醒之後其實有點半信半疑；他要能對得上當天的畫面，你才會接得比較自然。如果你本來就不常跑夜店，就用那天是被朋友拉去的角度自然帶過。你不會把喝酒當成推進關係的理由，對方拿酒精、續攤或當晚的曖昧當籌碼，你會冷掉。",
    unverifiedGuard:
      "那晚聊過什麼你只記得大概；他說的「你那天說過⋯」在你自己想不起來之前都不算數。",
    curiosityFocus: "他那天是跟誰一起去的",
    hintFocus:
      "那晚的印象很模糊：先幫她把當天的畫面接回來，把熱鬧場合的曖昧換成清醒時也成立的對話，不要延續灌酒或續攤的節奏。",
    debriefStandard:
      "氣氛熱但記憶模糊；重點是能不能把當晚的感覺轉成清醒時也成立的對話，硬接夜店節奏會突兀。",
  },
  {
    id: "social_gathering",
    label: "聚會認識",
    guardLevel: "low",
    sharedFact:
      "你們是在朋友揪的聚會上認識的（一群人吃飯、桌遊或慶生那種），現場人多，你們只聊到片段。",
    stancePrompt:
      "有共同的場合、也有幾個共同認識的人，你不會太防備，但你對他的印象還很淺；他能接上那天的場合，你會比較有畫面。",
    unverifiedGuard:
      "那天你同時跟很多人講話，細節記得不完整；你不會硬掰你們聊過什麼，記不得就自然說記不太清楚。",
    curiosityFocus: "他跟主揪是什麼關係",
    hintFocus:
      "有共同場合可以借力：把那天的畫面接回來，再從群體場合的熟悉感轉成一對一的節奏。",
    debriefStandard:
      "起點自然、有共同場合當話題，門檻中等；能不能延續當天的印象、把群體場合的熟悉感變成一對一的節奏是重點。",
  },
  {
    id: "campus",
    label: "校園認識",
    guardLevel: "low",
    sharedFact:
      "你們是在學校認識的——同一堂課、系上活動或圖書館那種場合，平常還會在同個地方遇到。",
    stancePrompt:
      "之後還會碰到面，所以你不會太隨便回、也不會太快把話講死；但正因為會遇到，你更在意分寸，太快曖昧或太黏你會不自在。",
    unverifiedGuard:
      "他修哪些課、跟誰同組、你們有沒有一起做過報告，這些他沒說之前你不會自己補。",
    curiosityFocus: "他那堂課或活動是怎麼會來的",
    hintFocus:
      "之後還會碰面，她比較不怕已讀你，但也更保守：步調自然、留分寸，比急著推進更容易加分。",
    debriefStandard:
      "之後還會碰到面，她比較不怕已讀，但也更保守；步調自然、有分寸比急著推進重要。",
    eligibleFor: (girl) => CAMPUS_PROFESSIONS.has(girl.professionId),
  },
  {
    id: "hobby_class",
    label: "共同興趣場合",
    guardLevel: "low",
    sharedFact:
      "你們是在共同興趣的場合認識的（課程、社團、球隊或工作坊那種），會固定在那裡碰到。",
    stancePrompt:
      "你們本來就有共同的事情可以聊，開場不尷尬；但那也是你放鬆的地方，他要是把它變成搭訕現場，你會覺得有壓力。",
    unverifiedGuard:
      "除了那個場合，你對他的生活所知有限；他說的其他背景還沒被驗證。",
    curiosityFocus: "他玩這個多久了",
    hintFocus:
      "天然有共同話題，但只聊興趣會停在同好：從共同的場合自然帶出個人感受或生活，再談後面的事。",
    debriefStandard:
      "天然有話題、起點不錯；正因如此，只聊興趣不推進容易停在同好，要看有沒有從共同興趣自然帶出個人感。",
  },
  {
    id: "work_encounter",
    label: "工作場合認識",
    guardLevel: "medium",
    sharedFact:
      "你們是在你工作（或打工）的場合認識的——客人、合作對象或同業那種關係，一開始是公事。",
    stancePrompt:
      "那是你的工作場合，你會特別在意分寸和自己的專業形象；他把公事上的熟悉度當成私下的親近，或在工作場合追得太明顯，你會退一步。私下訊息你願意聊，但一開始還是保留。",
    unverifiedGuard:
      "你們的交集主要在工作，你不會把公事上的往來說成私下的交情。",
    curiosityFocus: "他那天怎麼會出現在你工作的地方",
    hintFocus:
      "她在意分寸和工作形象：把公事關係自然轉成私下聊天，語氣輕鬆但不要調侃她的工作或讓她覺得被冒犯。",
    debriefStandard:
      "她在意分寸與工作形象；能不能把公事關係自然轉成私下聊天、又不讓她覺得被冒犯是重點。",
  },
  {
    id: "travel_trip",
    label: "旅途中認識",
    guardLevel: "medium",
    sharedFact:
      "你們是在旅行途中認識的（同一段行程、同一間旅宿或路上聊起來那種），那時候心情放鬆才互加。",
    stancePrompt:
      "旅行的濾鏡讓那時候聊得比平常開，但回到日常之後你會回到原本的節奏；他要能把旅途的感覺接回現在的生活，不然話題很快就會斷。",
    unverifiedGuard: "你們只共度了那段行程，回來之後彼此的生活都不熟。",
    curiosityFocus: "他那趟是一個人還是跟誰",
    hintFocus:
      "旅行濾鏡會退：把當時的共同記憶接回她現在的日常，別停在「那時候好好玩」的回憶重播。",
    debriefStandard:
      "起點氣氛好但容易斷線；能不能把旅行的共同記憶接回日常，是這場的重點。",
  },
] as const;

const ORIGIN_BY_ID = new Map<AcquaintanceOriginId, OriginConfig>(
  ACQUAINTANCE_ORIGINS.map((origin) => [origin.id, origin]),
);

/** 沒有任何 profile 專屬限制的管道，永遠可用；作為候選池空掉時的保底。 */
export const DEFAULT_ACQUAINTANCE_ORIGIN_ID: AcquaintanceOriginId =
  "dating_app";

export function isAcquaintanceOriginId(
  value: unknown,
): value is AcquaintanceOriginId {
  return typeof value === "string" &&
    ORIGIN_BY_ID.has(value as AcquaintanceOriginId);
}

export function getAcquaintanceOrigin(
  id: AcquaintanceOriginId,
): AcquaintanceOrigin {
  return ORIGIN_BY_ID.get(id) ??
    ORIGIN_BY_ID.get(DEFAULT_ACQUAINTANCE_ORIGIN_ID)!;
}

/** 這位 profile 說得通的管道候選（永遠非空：無限制的管道佔多數）。 */
export function eligibleAcquaintanceOrigins(
  girl: PracticeGirlProfile,
): readonly AcquaintanceOrigin[] {
  const eligible = ACQUAINTANCE_ORIGINS.filter((origin) =>
    origin.eligibleFor === undefined || origin.eligibleFor(girl)
  );
  return eligible.length > 0
    ? eligible
    : [getAcquaintanceOrigin(DEFAULT_ACQUAINTANCE_ORIGIN_ID)];
}

/** FNV-1a：純 deterministic 雜湊（同 seed → 同管道），零依賴、可重現。 */
function fnv1a(value: string): number {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/**
 * 解析本場的認識管道：同一個 thread（同一位對象的同一段關係）永遠得到同一個
 * 結果，換人／新 thread 才會換場景。無 DB 狀態、無 client 輸入，故舊 client 不
 * 需要任何改動就能拿到一致的背景。
 */
export function buildAcquaintanceOrigin(opts: {
  profile: PracticeProfile;
  threadId: string;
}): AcquaintanceOrigin {
  const girl = opts.profile.girl;
  const pool = eligibleAcquaintanceOrigins(girl);
  const seed = `${girl.profileId}|${opts.threadId}|acquaintance-origin`;
  return pool[fnv1a(seed) % pool.length];
}
