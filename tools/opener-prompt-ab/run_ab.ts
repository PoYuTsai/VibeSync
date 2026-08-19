// Prompt A/B：比較兩個版本的 system prompt 在同一份輸入下的輸出。
//
// 用途：prompt 瘦身／改寫時，證明「輸出有沒有變鬆」不是靠感覺。變因只有
// system prompt，user message 兩邊逐字相同、模型與參數相同。
//
// 跑法（repo 根目錄，需要 Eric 當次授權——會產生 Anthropic 費用）：
//   export ANTHROPIC_API_KEY="$(cat ~/.config/anthropic/key)"
//   deno run --allow-read --allow-env --allow-net --allow-run \
//     tools/opener-prompt-ab/run_ab.ts <baseline-git-ref> [runs] [--mode=opener|newtopic]
//       [--judge] [--fixture=short]   # --fixture=short 換第二份自介（只有 opener 有）
//
// baseline-git-ref 取該 commit 版本的原始檔當對照組，HEAD 工作區當實驗組。
// 想只量現況基準線（還沒有對照組）時用 --mode=xxx 搭 baseline ref = HEAD。
//
// 指標正則自檢（不打 API、不用金鑰）：
//   deno run --allow-read --allow-env --allow-run tools/opener-prompt-ab/run_ab.ts --self-check

// echo 從「回一個數字」改成「回證據配對」（2026-08-20）：複述是這批優化的
// 主要靶，但一個沒有出處的整數沒辦法驗評測員自己有沒有亂判——13/20 跟 8/20
// 差在哪，看不到配對就只能猜。數字直接由配對數推出來，說不出出處就不算。
import { parseFullPayload } from "../../supabase/functions/analyze-chat/full_response.ts";

const JUDGE_SYSTEM =
  `你是文本評測員。給你五則要傳給同一個女生的第一句訊息，以及她的公開資料。只輸出 JSON，不要任何說明。
判斷三件事：
1. skeleton（0-5 整數）：有幾則落在「先講一個通則或前提，再轉折到她身上」的骨架。**不管有沒有用「但／不過／其實」這類連接詞**——用逗號接、換行接、或連接詞整個省略但結構還在的，一樣算。
2. echoPairs（陣列）：哪幾則**沒有給出自介以外的任何新資訊**。唯一判準是：把這則拿給一個只讀過她自介的人看，他有沒有因此多知道一件事？
   - 沒有＝列進來：把自介的字換句話說、換個角度講同一件事、把兩項資料拼在一起、稱讚自介裡的某一句。
   - 有＝不要列進來：給了自介沒寫的推測、畫面、後果、對方可以反駁的判斷，或講了說話者自己的事。**句子裡提到自介的內容不算複述**——開場本來就該貼著她的資料，重點是有沒有多長出東西。
   每一則填 bio（它重複的自介原文）與 how（10 字內說它為什麼沒有多給東西）。指不出 bio 原文就不要列。格式 [{"line":2,"bio":"自介原文片段","how":"換句話說同一件事"}]。
3. casual（0-5 整數）：有幾則讀起來像真人順手丟的（可以不工整、可以不完整、可以只有幾個字），而不是寫過的句子。
輸出格式：{"skeleton":0,"echoPairs":[],"casual":0,"note":"20字內講最明顯的問題"}`;

type EchoPair = { line: number; bio: string; how?: string };
type Verdict = { skeleton: number; echoPairs: EchoPair[]; casual: number; note: string };

// 壞掉一律 throw，不回 null——安靜降級會讓整批評測看起來只是少幾筆。
async function judge(lines: string[], profile: string): Promise<Verdict> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
      // 600：echoPairs 要附原文出處，300 會在配對列到一半被截斷。
      max_tokens: 600,
      // sonnet-5 已棄用 temperature（API 直接 400）；thinking 關掉就夠穩定。
      thinking: { type: "disabled" },
      system: JUDGE_SYSTEM,
      messages: [{
        role: "user",
        content: `她的資料：\n${profile}\n\n五則訊息：\n` +
          lines.map((l, i) => `${i + 1}. ${l.replace(/\n/g, " ⏎ ")}`).join("\n"),
      }],
    }),
  });
  const json = await res.json();
  // 評測員自己壞掉時必須吵——安靜降級成「無法解析」會讓整批評測看起來
  // 只是少了幾筆，實際上是一筆都沒跑（2026-08-19 踩過）。
  if (json?.error) throw new Error(`judge API 失敗：${JSON.stringify(json.error)}`);
  const text = (json?.content as Array<{ type: string; text?: string }> ?? [])
    .find((b) => b?.type === "text")?.text ?? "";
  const m = text.match(/\{[\s\S]*\}/);
  if (!m) throw new Error(`judge 沒回 JSON：${text.slice(0, 200)}`);
  const v = JSON.parse(m[0]) as Verdict;
  // 沒回陣列＝評測員自己壞了，跟 API 錯誤同級要吵，不要靜靜當成 0 則複述。
  if (!Array.isArray(v.echoPairs)) {
    throw new Error(`judge 沒回 echoPairs 陣列：${m[0].slice(0, 200)}`);
  }
  return v;
}

// ── 客觀指標 ────────────────────────────────────────────────
/**
 * 前提＋轉折骨架（「A 但 B」「A，其實 B」「妳感覺是那種…的人」…）。
 * 2026-08-19 補：禁掉連接詞之後模型改用「通常X，妳Y」「以為X，結果Y」——
 * 連接詞消失但骨架原封不動，只抓連接詞會把規避誤讀成改善（實測 20/40 → 真實 24/40）。
 */
const PIVOT =
  /[但不過其實可是然而]|感覺(?:妳|你)是那種|通常.{0,8}兩(?:種|個)|(?:通常|都|大多|一般)[^，,\n]{0,14}[，,\n].{0,6}(?:妳|你)|(?:以為|還以為)[^，,\n]{0,16}[，,\n]/u;
/** 問號收尾。 */
const ASKS = /[?？]\s*$/u;
/**
 * 實質疑問句——不打問號照樣在問（2026-08-19 新話題基準線：句末問號 0/20，
 * 但 12/20 是問句）。只數問號等於被規避，要數句式。
 */
const QUESTION_FORM =
  /[?？]|[嗎嘛呢齁吧]\s*$|還是|有沒有|會不會|要不要|是不是|[怎哪什幾誰多][麼裡樣時個久]|幹嘛/u;
/** 「妳是那種…的人」——最容易變成每題都套的單一骨架，單獨追蹤。 */
const THAT_TYPE = /(?:妳|你)(?:是|感覺是|應該是)那種/u;
/** 句末句號＝聊天情境的冷淡感，複製貼上後直接傷質感。 */
const TRAILING_PERIOD = /[。.]\s*$/u;
/** 不可直接送出的包裝：引號整句包、編號、教學括號。 */
const WRAPPED = /^[「『"']|^[0-9]+[.、)]|（.*?(?:技巧|鉤子|冷讀|微拉).*?）/u;
/**
 * 只有我們懂的詞漏進使用者看得到的欄位（2026-08-19 Eric 真機抓到「內梗」）。
 * 機制跟示範句一樣：寫在 prompt 裡的東西會出現在輸出裡，不管它是例句還是術語。
 * 「作戰板」不列入——那是 client 真的在用的 UI 名稱。
 */
const JARGON =
  /內梗|位階|資格審查|共同身分|換皮|情勒|破冰腦力|深度階梯|兩段式|冷讀|鉤子|微拉|唸稿|骨架/gu;
/** 同一句裡你／妳混用——複製貼上寄出去就露餡（2026-08-19 新話題實測 3/20）。 */
const MIXED_YOU = /(?=.*你)(?=.*妳)/su;
/** 用戶自己的目標／備註被寫成「她的事」——grounding 破口，任何欄位都不准出現。 */
const LEAK = /(?:你|妳)(?:之前|上次)(?:說|提到)|(?:你|妳)想約|(?:聽起來|看來|感覺)(?:你|妳)是/u;

/**
 * 這句有沒有從 prompt 裡抄。2026-08-19 最重要的發現（示範句被逐字照抄＝發罐頭）
 * 一直靠人眼比對，換個 prompt 就得重新盯一次；改成跟 prompt 本文對，
 * 不維護黑名單也就不會過期。
 * ponytail: 逐長度掃 substring，句子 ≤40 字所以 O(n²) 無所謂；要量長文再換 suffix automaton。
 */
/**
 * 唸稿開頭：句子開頭原樣複述她資料裡的字。原本是手維護的關鍵詞名單，
 * 2026-08-19 實測只抓到 3/25、實際 9/25——名單不維護就過期，跟黑名單式
 * 照抄偵測同一個毛病。改成跟輸入本文對，換案例也不用改程式。
 *
 * k=3 是離線校準值（同一份 25 句：k=3 抓 9 且零誤判、k=4 掉到 3、k=5 掛零）。
 * ponytail: 只掃句子前 10 字——唸稿感來自「開頭就複述」，句中提到她的詞是正常的。
 */
const ECHO_MIN_RUN = 3;
const ECHO_HEAD = 10;
function echoesInput(line: string, source: string): boolean {
  const src = source.replace(/\s/g, "");
  const head = Array.from(line.replace(/\s/g, "")).slice(0, ECHO_HEAD);
  for (let i = 0; i + ECHO_MIN_RUN <= head.length; i++) {
    if (src.includes(head.slice(i, i + ECHO_MIN_RUN).join(""))) return true;
  }
  return false;
}

const COPY_MIN_RUN = 6;
function copiesFromPrompt(line: string, prompt: string): boolean {
  const chars = Array.from(line.replace(/\s/g, ""));
  for (let i = 0; i + COPY_MIN_RUN <= chars.length; i++) {
    if (prompt.includes(chars.slice(i, i + COPY_MIN_RUN).join(""))) return true;
  }
  return false;
}

// 指標本身會決定 prompt 怎麼改，量錯比不量更糟——樣本取自 2026-08-19 的
// 真實基準線輸出，正則改壞就會炸。
if (Deno.args.includes("--self-check")) {
  const cases: Array<[RegExp, string, boolean]> = [
    [QUESTION_FORM, "突然多一天假，妳第一件事幹嘛", true],
    [QUESTION_FORM, "妳是那種會把冰箱塞滿的人嗎", true],
    [QUESTION_FORM, "突然多一天假妳會拿來睡還是亂跑", true],
    [QUESTION_FORM, "鄰居最近有沒有偷用我家網路", true],
    [QUESTION_FORM, "看不懂的展妳都怎麼裝懂", true],
    [QUESTION_FORM, "鄰居我跟你說，樓下開始練鼓了", false],
    [QUESTION_FORM, "我們一起看展大概會在同一幅畫前面吵起來", false],
    [THAT_TYPE, "妳是那種會為了一杯咖啡多繞路的人齁", true],
    [THAT_TYPE, "感覺妳是那種閒不下來的人吧", true],
    [THAT_TYPE, "我覺得妳沖咖啡一定很龜毛", false],
    [ASKS, "妳是那種鬧鐘響一次就起來的人嗎", false],
    [PIVOT, "感覺妳篩人條件是狠，但心裡其實蠻好聊的那種", true],
    [LEAK, "妳上次說想找人一起去", true],
    [LEAK, "我們一起旅行大概第三天就會迷路", false],
  ];
  const bad = cases.filter(([re, text, want]) => re.test(text) !== want);
  for (const [re, text, want] of bad) {
    console.error(`✗ ${re.source} 對「${text}」應為 ${want}`);
  }
  // 抄自 prompt：樣本是 40afdb72^ 真的被照抄出來的句子 vs 同批乾淨句。
  // k=6 是實測校準值：40afdb72^（有示範句）8/15 命中、40afdb72（刪掉後）0/15；
  // k=5 連乾淨的那組都誤判 3/15，k=7 以上漏掉半數真照抄。
  const promptSample = "例如「我先把查戶口題庫刪掉」這種先給再問的寫法，或「休假不是補眠就是開新副本」。";
  const copyCases: Array<[string, boolean]> = [
    ["我先把查戶口題庫刪一刪 剩下能問的其實不多", true],
    // 已知天花板：改寫過的照抄（共同片段只剩「查戶口題庫」5 字）抓不到，
    // 所以這個指標會低估。低估可接受，誤報不行——k=6 是往「寧可漏」那邊站。
    ["查戶口題庫先刪一半 剩下的問題比較像人話", false],
    ["大夜班還有力氣學新東西，妳是那種閒不下來的人吧", false],
  ];
  const copyBad = copyCases.filter(([t, want]) => copiesFromPrompt(t, promptSample) !== want);
  for (const [t, want] of copyBad) console.error(`✗ copiesFromPrompt 對「${t}」應為 ${want}`);
  const youCases: Array<[string, boolean]> = [
    ["鄰居，我覺得你其實會偷用我家wifi", false],
    ["如果拉你去爬山，妳大概走十分鐘就想放棄", true],
    ["妳是那種行程排到分鐘的人嗎", false],
  ];
  const youBad = youCases.filter(([t, want]) => MIXED_YOU.test(t) !== want);
  // 唸稿：開頭複述 vs 消化成自己的話。前者是她的原字，後者是模型的詞。
  const echoCases: Array<[string, boolean]> = [
    ["大夜班下班還有力氣學新東西 這體力也太狠", true],
    ["講話直接的人聊起來最省力，喜歡", true],
    // 「日夜顛倒」不在她自介裡（她寫的是「大夜班」）＝模型自己的話，不算唸稿。
    ["日夜顛倒的人才懂，別人的晚安是我的早安", false],
    ["所以妳的假日其實是別人的星期二對吧", false],
  ];
  const echoSample = "喜歡認識新朋友，熱愛學習嘗試新事物 從事酒店外場，大夜班工作者 " +
    "微胖女生 講話直接，不喜歡沒誠意的人";
  const echoBad = echoCases.filter(([t, want]) => echoesInput(t, echoSample) !== want);
  for (const [t, want] of echoBad) console.error(`✗ echoesInput 對「${t}」應為 ${want}`);
  for (const [t, want] of youBad) console.error(`✗ MIXED_YOU 對「${t}」應為 ${want}`);
  const total = bad.length + copyBad.length + youBad.length + echoBad.length;
  console.log(total === 0
    ? `✓ 指標自檢 ${cases.length + copyCases.length + youCases.length + echoCases.length} 項全過`
    : `✗ ${total} 項失敗`);
  Deno.exit(total === 0 ? 0 : 1);
}

const apiKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
if (!apiKey) {
  console.error("缺 ANTHROPIC_API_KEY");
  Deno.exit(2);
}

const positional = Deno.args.filter((a) => !a.startsWith("--"));
const modeArg = Deno.args.find((a) => a.startsWith("--mode="))?.slice(7) ?? "opener";
// 實驗組預設是工作區；給 ref 就變成任兩個 commit 對比（回頭驗舊批次的因果結論用）。
const currentRef = Deno.args.find((a) => a.startsWith("--current="))?.slice(10);
// client 顯示四欄＋推薦理由；只印 openingLine 會漏掉一半的品質問題。
const dump = Deno.args.includes("--dump");
// 原型：把 prompt 裡「先發散再個人化」的第一段拆成獨立呼叫。
// 同一次呼叫裡作戰板就攤在模型眼前，「暫時放下她的興趣清單」做不到——
// 第一段必須在看不到作戰板的情況下跑，才可能真的發散（2026-08-19）。
const twoPass = Deno.args.includes("--twopass");
// 方法 A：每次生成換一個切入角度。根因是「同樣輸入永遠同樣輸出」，
// 種子輪替直接打在那上面，零額外呼叫、零延遲，而且清單是我們定的。
const seeded = Deno.args.includes("--seeded");
// LLM judge（照 tools/practice-behavior-smoke 的形狀：確定性 pattern 先跑，
// 再交給 temperature 0 的 judge）。加進來的原因是正則有結構性盲點——
// 2026-08-19 禁掉轉折連接詞後模型改用「通常X，妳Y」，正則把規避讀成改善。
// 每輪多一次呼叫，所以是 opt-in。
const useJudge = Deno.args.includes("--judge");
// 同一批句子連判 N 次。判 judge 自己穩不穩用的——跨輪的擺盪分不出是生成
// 變了還是評測員在跳（2026-08-20：同條件兩批 n=40，複述 29 vs 39）。
const judgeRepeat = Number(
  Deno.args.find((a) => a.startsWith("--judge-repeat="))?.slice(15) ?? "1",
);
const baselineRef = positional[0];
const runs = Number(positional[1] ?? "3");
if (!baselineRef) {
  console.error("用法：run_ab.ts <baseline-git-ref> [runs] [--mode=opener|newtopic]");
  Deno.exit(2);
}

// 生產端兩個功能都跑 claude-sonnet-5（index.ts openerModel / newTopicModel）。
const MODEL = "claude-sonnet-5";

/**
 * 切入角度輪替清單：彼此語意距離要遠，才不會輪了跟沒輪一樣。
 * production 用 requestId 取模選一個（同一次生成 replay 會拿到同一個角度）。
 */
// 新話題：她已經是熟人，可以用生活面向。
const NEW_TOPIC_ANGLES = [
  "作息與睡眠",
  "食物與口味的固執",
  "花錢的習慣",
  "小時候與長大的地方",
  "住的環境與鄰居",
  "工作以外的身分",
  "收集癖或怪習慣",
  "對某件小事的偏激意見",
  "無厘頭的假設情境",
  "最近一件蠢事",
];

// 開場白：只有一份自介、對方是陌生人，角度必須是「讀她資料的鏡頭」，
// 不能是需要熟悉度的生活面向（那會變成憑空假設）。
const OPENER_ANGLES = [
  "她自介裡最沒人問過的那一句",
  "她刻意沒寫的東西",
  "她的作息或職業造成的生活時差",
  "她寫自介的語氣本身，不是內容",
  "她設下的那些規則在防什麼",
  "一個她大概每天被問、你偏不問的話題",
  "把她放進一個具體的日常情境",
  "她大概會有意見的一件小事",
  "一個輕微、可否認的誤判",
  "她自介裡最像人、最不像條件的那一點",
];

function angleBlock(i: number): string {
  const a = mode.angles[i % mode.angles.length];
  return `\n\n## 這次的切入角度：${a}\n` +
    "五個裡至少兩個要從這個角度長出來，其餘自由；風格分工不變。" +
    "這是為了讓同一份資料每次生成不會撞題，不是題目本身——不要把角度的名字寫進訊息裡。";
}

interface Mode {
  path: string;
  constName: string;
  userContent: string;
  /** 從模型 JSON 取出「可直接傳出去的那一句」清單。 */
  lines: (parsed: Record<string, unknown>) => string[];
  /** 全欄位掃描用（grounding 洩漏檢查看得到 nextMove/reason）。 */
  allText: (parsed: Record<string, unknown>) => string;
  /**
   * 唸稿判定的比對來源＝她的資料原文（只放對方欄位，不放指令與段落標題，
   * 否則會拿「請依系統規則」之類的句子誤判）。
   */
  echoSource: string;
  /** 判斷五題是不是換皮不換題用的已知興趣詞。 */
  knownInterests: string[];
  /** --twopass 第一段的輸入：只有關係階段與狀況，**不含作戰板**。 */
  divergeUserContent?: string;
  /** --seeded 的切入角度輪替清單（每個功能的可用角度不同）。 */
  angles: string[];
}

// grace（2026-08-19 真機案例）：長自介、規則牆、唯一正向線索是「熱愛學習
// 嘗試新事物」。刻意用純文字路徑——變因要只有 system prompt。
const OPENER_USER_CONTENT = `對方資料：
名字：grace
年齡：36
所在地：高雄市
身高：166 cm
語言：中文、閩南語
產業：Communications & Media／服務業
自介：
喜歡認識新朋友，熱愛學習嘗試新事物

從事酒店外場，大夜班工作者
請不要一直問我在哪間上班
上班不需要喝酒 不要一直問
本人也沒有那麼喜歡喝酒
微胖女生
喜歡骨感 輕盈的請跳過我
不要浪費彼此時間
講話直接，不喜歡沒誠意的人
不聊色也不約
請看完個人自介在聊天
無法接受請往左滑，謝謝

認識管道：交友軟體
請依系統規則產出 JSON。`;

// 第二份開場白自介（--fixture=short）：三行、零規則、兩個具體線索。
// grace 是「規則牆」極端值，只有她一份的話所有結論都綁死在那一種輸入上
// （2026-08-20：整晚的複述／骨架結論全部建立在單一樣本）。
const OPENER_SHORT_USER_CONTENT = `對方資料：
名字：Ally
年齡：28
所在地：台北市
身高：160 cm
語言：中文、英文
產業：設計／文創
自介：
養了一隻很兇的貓

假日大多在中和的舊書店

認識管道：交友軟體
請依系統規則產出 JSON。`;

// 新話題基準線案例：刻意踩三個已知病灶——(1) 興趣清單集中在旅行／咖啡，
// 看五題會不會全繞同一塊；(2) 備註含主詞不明的用戶目標「想約出來見面」，
// 看會不會被寫成她的事；(3) 狀態是「聊得來但還沒約」，看會不會催邀約。
// 作戰板逐字照 NewTopicPartnerContextBuilder 的實際輸出格式（欄位標籤、
// 「、」分隔、結尾那行禁令都一樣），差一個字都會讓量到的不是生產行為。
const NEW_TOPIC_USER_CONTENT = `## 對方作戰板（唯一可當對方事實的來源）
[對象作戰板：小雅]
- 累計對話：3 段，最後互動 2026-08-14
- 最近熱度：68
- 興趣：旅行、手沖、看展
- 性格：慢熱、幽默愛鬧
- 你的備註：慢熱、聊得來還沒約、愛喝咖啡、上次互相叫對方房東、想約出來見面
- 只可使用以上明確紀錄，不得猜補對方興趣

## 關於我（用戶本人的風格與興趣，只能做自我揭露）
我做後端工程師，假日大多在爬山或窩在家看電影，講話偏冷幽默。

## 目前狀況（只影響節奏與語氣）
聊天卡住了（不知道接什麼新話題）

請依系統規則產出恰好五個新話題的 JSON。`;

const MODES: Record<string, Mode> = {
  opener: {
    path: "supabase/functions/analyze-chat/index.ts",
    constName: "OPENER_PROMPT",
    userContent: OPENER_USER_CONTENT,
    lines: (parsed) => {
      const openers = (parsed.openers ?? {}) as Record<string, unknown>;
      return ["extend", "resonate", "tease", "humor", "coldRead"]
        .map((k) => String(openers[k] ?? ""))
        .filter((v) => v.length > 0);
    },
    allText: (parsed) => JSON.stringify(parsed),
    echoSource: OPENER_USER_CONTENT,
    knownInterests: [],
    angles: OPENER_ANGLES,
  },
  newtopic: {
    path: "supabase/functions/analyze-chat/new_topic_prompt.ts",
    constName: "NEW_TOPIC_PROMPT",
    userContent: NEW_TOPIC_USER_CONTENT,
    lines: (parsed) =>
      ((parsed.topics ?? []) as Array<Record<string, unknown>>)
        .map((t) => String(t?.openingLine ?? ""))
        .filter((v) => v.length > 0),
    allText: (parsed) => JSON.stringify(parsed),
    angles: NEW_TOPIC_ANGLES,
    echoSource: NEW_TOPIC_USER_CONTENT.split("## 關於我")[0],
    knownInterests: ["旅行", "旅遊", "咖啡", "手沖", "看展", "展覽"],
    divergeUserContent:
      "關係階段：聊得來但還沒約。\n目前狀況：聊天卡住了（不知道接什麼新話題）。\n請產出 8 個方向的 JSON。",
  },
};

const DIVERGE_PROMPT =
  `你在幫一個聊天教練做「話題發散」。你**拿不到對方的任何資料**，這是刻意的設計——看得到她喜歡什麼，就一定會繞著那幾樣打轉。
只根據關係階段與目前狀況，想 8 個彼此語意距離很遠的聊天方向。
- 每個方向一句話（≤20 字），只描述方向本身，不要寫成可以傳出去的訊息。
- 八個必須落在八個不同的生活面向，不可以是同一件事的八種切法。
只輸出 JSON，不要 code fence：{"directions":["...","...","...","...","...","...","...","..."]}`;

/** 第二段：把發散結果注進 user message，核心話題只能從這 8 個裡挑。 */
function buildDirectionsBlock(directions: string[]): string {
  return "\n\n## 已經先發散好的 8 個方向\n" +
    directions.map((d, i) => `${i + 1}. ${d}`).join("\n") +
    "\n從這 8 個裡挑 5 個最合當下階段的，再用作戰板的線索把它們寫成她的語言。" +
    "核心話題必須來自這 8 個方向，作戰板只提供語言、稱呼和梗，不提供話題本身。";
}

const mode = MODES[modeArg];
if (!mode) {
  console.error(`未知 --mode=${modeArg}（可用：${Object.keys(MODES).join("／")}）`);
  Deno.exit(2);
}
// --fixture=short：換掉開場白的輸入自介，其餘變因不動。
if (Deno.args.includes("--fixture=short")) {
  if (modeArg !== "opener") {
    console.error("--fixture=short 只支援 --mode=opener");
    Deno.exit(2);
  }
  mode.userContent = OPENER_SHORT_USER_CONTENT;
  mode.echoSource = OPENER_SHORT_USER_CONTENT;
}

/** 從原始碼抽出指定 prompt 樣板字串的內容。 */
function extractPrompt(source: string, constName: string): string {
  const start = source.indexOf(`const ${constName} =`);
  if (start < 0) throw new Error(`找不到 ${constName}`);
  const tick = source.indexOf("`", start);
  // 樣板字串以未跳脫的反引號收尾。
  let i = tick + 1;
  while (i < source.length) {
    if (source[i] === "\\") { i += 2; continue; }
    if (source[i] === "`") break;
    i++;
  }
  return source.slice(tick + 1, i)
    // prompt 內嵌的 ${...} 對本比較無意義，換成佔位符讓兩邊一致。
    .replace(/\$\{[^}]*\}/g, "");
}

async function gitShow(ref: string, path: string): Promise<string> {
  const cmd = new Deno.Command("git", { args: ["show", `${ref}:${path}`] });
  const { code, stdout, stderr } = await cmd.output();
  if (code !== 0) throw new Error(new TextDecoder().decode(stderr));
  return new TextDecoder().decode(stdout);
}

async function generate(systemPrompt: string, extraUser = ""): Promise<{ lines: string[]; all: string; parsed: Record<string, unknown> }> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 3000,
      // 生產端 fallback.ts resolveThinkingContract：sonnet-5 若 caller 沒指定
      // 就送 disabled。不跟著關，thinking 會吃光 3000 token 產出零可見輸出。
      thinking: { type: "disabled" },
      system: systemPrompt,
      messages: [{ role: "user", content: mode.userContent + extraUser }],
    }),
  });
  const json = await res.json();
  // content[0] 不保證是 text（同 fallback.ts extractClaudeText 的理由）。
  const text = (json?.content as Array<{ type: string; text?: string }> ?? [])
    .find((b) => b?.type === "text")?.text;
  if (typeof text !== "string") {
    throw new Error(`API 回覆異常：${JSON.stringify(json).slice(0, 300)}`);
  }
  // 用生產端同一支解析器，不要自己 JSON.parse：模型偶爾回帶尾逗號的 JSON，
  // 整批 A/B 會死在中間（2026-08-20 實驗臂 run 5）。順帶讓 harness 的容錯
  // 跟線上一致——線上吞得下的輸出，harness 不該量成失敗。
  const res2 = parseFullPayload(text);
  if (!res2.ok) throw new Error(`JSON 解析失敗（${res2.error}）：${text.slice(-400)}`);
  const parsed = res2.result.payload;
  const lines = mode.lines(parsed);
  // 修過的 JSON 可能少掉被截斷的那幾則，指標分母會悄悄從 5 變小。
  if (res2.result.source === "repaired" || lines.length !== 5) {
    console.log(`    [解析 ${res2.result.source}，取到 ${lines.length} 則]`);
  }
  return { lines, all: mode.allText(parsed), parsed };
}

function metrics(lines: string[], all: string, prompt: string) {
  const lens = lines.map((l) => Array.from(l.replace(/\n/g, "")).length);
  return {
    n: lines.length,
    lenMin: Math.min(...lens),
    lenMax: Math.max(...lens),
    lenAvg: Math.round(lens.reduce((a, b) => a + b, 0) / lens.length),
    over30: lens.filter((l) => l > 30).length,
    pivot: lines.filter((l) => PIVOT.test(l)).length,
    asks: lines.filter((l) => ASKS.test(l)).length,
    questionForm: lines.filter((l) => QUESTION_FORM.test(l)).length,
    thatType: lines.filter((l) => THAT_TYPE.test(l)).length,
    periods: lines.filter((l) => TRAILING_PERIOD.test(l)).length,
    wrapped: lines.filter((l) => WRAPPED.test(l)).length,
    quotesBio: lines.filter((l) => echoesInput(l, mode.echoSource)).length,
    multiline: lines.filter((l) => l.includes("\n")).length,
    // 換皮不換題：五題各自有沒有踩在同一組已知興趣詞上。
    sameInterest: mode.knownInterests.length === 0 ? 0 : lines.filter((l) =>
      mode.knownInterests.some((k) => l.includes(k))
    ).length,
    // grounding 洩漏掃全欄位（含 nextMove / reason），不只可見訊息。
    leak: (all.match(new RegExp(LEAK, "gu")) ?? []).length,
    copied: lines.filter((l) => copiesFromPrompt(l, prompt)).length,
    mixedYou: lines.filter((l) => MIXED_YOU.test(l)).length,
    jargon: (all.match(JARGON) ?? []).length,
  };
}

const baselineSource = await gitShow(baselineRef, mode.path);
const currentSource = currentRef
  ? await gitShow(currentRef, mode.path)
  : await Deno.readTextFile(mode.path);
const currentLabel = currentRef ? `current(${currentRef})` : "current(worktree)";
const baselinePrompt = extractPrompt(baselineSource, mode.constName);
const currentPrompt = extractPrompt(currentSource, mode.constName);
// 兩邊一字不差時（例如量基準線用 baseline=HEAD）只跑一組，不白花一半的錢。
// --twopass 時兩臂用同一份 prompt，變因只有「發散段有沒有獨立呼叫」。
// --seeded 第二臂＝工作區 prompt＋種子；第一臂＝baseline ref 的 prompt、無種子。
// 兩者 prompt 相同時就退化成純種子測試。
const arms: Array<[string, string, boolean]> = seeded
  ? [
    ["對照（baseline prompt，無種子）", baselinePrompt, false],
    ["實驗（worktree prompt＋種子輪替）", currentPrompt, false],
  ]
  : twoPass
  ? [
    ["單段（現況）", currentPrompt, false],
    ["兩段式原型", currentPrompt, true],
  ]
  : baselinePrompt === currentPrompt
  ? [[`${currentLabel}＝baseline，只跑一組`, currentPrompt, false]]
  : [
    [`baseline(${baselineRef})`, baselinePrompt, false],
    [currentLabel, currentPrompt, false],
  ];

for (const [label, prompt, armTwoPass] of arms) {
  console.log(`\n═══ ${modeArg} ${label} — prompt ${prompt.length} 字元 ═══`);
  const runLines: string[][] = [];
  const jAgg = { skeleton: 0, echo: 0, casual: 0, n: 0, spread: 0 };
  const agg = { pivot: 0, thatType: 0, asks: 0, questionForm: 0, over30: 0, quotesBio: 0, multiline: 0, periods: 0, wrapped: 0, sameInterest: 0, leak: 0, copied: 0, mixedYou: 0, jargon: 0, lens: [] as number[] };
  for (let r = 1; r <= runs; r++) {
    let extraUser = seeded && label.startsWith("實驗") ? angleBlock(r - 1) : "";
    if (armTwoPass) {
      if (!mode.divergeUserContent) throw new Error(`--twopass 不支援 ${modeArg}`);
      const res = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: MODEL,
          max_tokens: 1000,
          thinking: { type: "disabled" },
          system: DIVERGE_PROMPT,
          messages: [{ role: "user", content: mode.divergeUserContent }],
        }),
      });
      const dj = await res.json();
      const dtext = (dj?.content as Array<{ type: string; text?: string }> ?? [])
        .find((b) => b?.type === "text")?.text ?? "";
      const dm = dtext.match(/\{[\s\S]*\}/);
      if (!dm) throw new Error(`發散段沒有 JSON：${dtext.slice(0, 200)}`);
      const dirs = (JSON.parse(dm[0]).directions ?? []) as string[];
      extraUser = buildDirectionsBlock(dirs);
      if (dump) dirs.forEach((d, i) => console.log(`    [發散 ${i + 1}] ${d}`));
    }
    const { lines, all, parsed } = await generate(prompt, extraUser);
    const m = metrics(lines, all, prompt);
    agg.pivot += m.pivot; agg.thatType += m.thatType;
    agg.asks += m.asks; agg.questionForm += m.questionForm; agg.over30 += m.over30;
    agg.quotesBio += m.quotesBio; agg.multiline += m.multiline;
    agg.periods += m.periods; agg.wrapped += m.wrapped;
    agg.sameInterest += m.sameInterest; agg.leak += m.leak; agg.copied += m.copied; agg.mixedYou += m.mixedYou; agg.jargon += m.jargon;
    agg.lens.push(m.lenMin, m.lenMax);
    runLines.push(lines);
    if (useJudge) {
      // 同一批句子連判 judgeRepeat 次＝量評測員自己的重複性。跨輪的差異混著
      // 「生成不一樣」與「評測員不穩」兩個來源，只有同一份輸入重判才分得開。
      const vs: Verdict[] = [];
      for (let j = 0; j < judgeRepeat; j++) vs.push(await judge(lines, mode.echoSource));
      // 數「有幾則」不是「有幾對」——一則同時複述兩段自介時 judge 會列兩筆，
      // 用 length 會讓分數超過 5（2026-08-20 舊定義實測跑出 9/5、8/5，
      // 當時被誤讀成評測員的雜訊）。
      const echoes = vs.map((v) => new Set(v.echoPairs.map((p) => p.line)).size);
      const v = vs[0];
      jAgg.skeleton += v.skeleton;
      jAgg.echo += echoes[0];
      jAgg.casual += v.casual;
      jAgg.n += 1;
      if (judgeRepeat > 1) {
        jAgg.spread += Math.max(...echoes) - Math.min(...echoes);
        console.log(
          `    [judge ×${judgeRepeat}] 複述 ${echoes.join("/")}／5｜同骨架 ${vs.map((x) => x.skeleton).join("/")}｜隨口 ${vs.map((x) => x.casual).join("/")}`,
        );
      } else {
        console.log(`    [judge] 同骨架 ${v.skeleton}/5｜複述 ${echoes[0]}/5｜隨口 ${v.casual}/5｜${v.note}`);
      }
      for (const p of v.echoPairs) {
        console.log(`      複述 #${p.line} ← 自介「${p.bio}」${p.how ? `（${p.how}）` : ""}`);
      }
    }
    console.log(`\n[run ${r}] 長度 ${m.lenMin}-${m.lenMax}（均 ${m.lenAvg}）｜轉折骨架 ${m.pivot}/5（那種句型 ${m.thatType}）｜實質問句 ${m.questionForm}/5（句末問號 ${m.asks}）｜>30字 ${m.over30}/5｜唸稿開頭 ${m.quotesBio}/5｜分則 ${m.multiline}/5｜句末句號 ${m.periods}/5｜包裝 ${m.wrapped}/5｜撞已知興趣 ${m.sameInterest}/5｜grounding 洩漏 ${m.leak}｜抄自 prompt ${m.copied}/5｜你妳混用 ${m.mixedYou}/5｜術語外洩 ${m.jargon}`);
    if (dump) {
      // client 顯示四欄＋推薦理由，只看 openingLine 會漏掉一半的品質問題
      // （2026-08-19 Eric 在手機上抓到「內梗」漏進畫面，harness 當時看不到）。
      for (const t of (parsed.topics ?? []) as Array<Record<string, unknown>>) {
        console.log(`    ▸ ${String(t.openingLine ?? "").replace(/\n/g, " ⏎ ")}`);
        console.log(`      direction : ${t.direction}`);
        console.log(`      whyItWorks: ${t.whyItWorks}`);
        console.log(`      nextMove  : ${t.nextMove}`);
      }
      const rec = parsed.recommendation as Record<string, unknown> | undefined;
      console.log(`    推薦理由：${rec?.reason ?? "(無)"}`);
    } else {
      lines.forEach((l) => console.log("   ", l.replace(/\n/g, " ⏎ ")));
    }
  }
  // 跨輪重複：同一個對象連按 N 次，有多少句跟「別次生成」的句子撞在一起。
  // 這是 Eric 真正在抱怨的東西（「連按五次拿到一樣的五題」），先前沒有指標在量。
  // 4 字連續片段＝實質同題；比對只跨輪，同一輪內五題重複由既有規則負責。
  const REPEAT_RUN = 4;
  let repeated = 0;
  for (let a = 0; a < runLines.length; a++) {
    for (const line of runLines[a]) {
      const c = Array.from(line.replace(/\s/g, ""));
      const hit = runLines.some((other, b) =>
        b !== a && other.some((ol) => {
          const oc = ol.replace(/\s/g, "");
          for (let i = 0; i + REPEAT_RUN <= c.length; i++) {
            if (oc.includes(c.slice(i, i + REPEAT_RUN).join(""))) return true;
          }
          return false;
        })
      );
      if (hit) repeated++;
    }
  }
  const total = runs * 5;
  if (useJudge && jAgg.n > 0) {
    console.log(
      `\n── ${label} judge 合計（${jAgg.n * 5} 句）：同骨架 ${jAgg.skeleton}｜複述 ${jAgg.echo}｜隨口 ${jAgg.casual}` +
        (judgeRepeat > 1
          ? `｜同一批句子重判 ${judgeRepeat} 次的複述極差平均 ${(jAgg.spread / jAgg.n).toFixed(1)}/5`
          : ""),
    );
  }
  console.log(`\n── ${label} 跨輪重複：${repeated}/${total} 句跟別次生成撞題`);
  console.log(`\n── ${label} 合計（${total} 句）：轉折骨架 ${agg.pivot}（那種句型 ${agg.thatType}）｜實質問句 ${agg.questionForm}（句末問號 ${agg.asks}）｜>30字 ${agg.over30}｜唸稿開頭 ${agg.quotesBio}｜分則 ${agg.multiline}｜句末句號 ${agg.periods}｜包裝 ${agg.wrapped}｜撞已知興趣 ${agg.sameInterest}｜grounding 洩漏 ${agg.leak}｜抄自 prompt ${agg.copied}｜你妳混用 ${agg.mixedYou}｜術語外洩 ${agg.jargon}｜最短 ${Math.min(...agg.lens)} 最長 ${Math.max(...agg.lens)}`);
}
