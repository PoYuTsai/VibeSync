// Prompt A/B：比較兩個版本的 system prompt 在同一份輸入下的輸出。
//
// 用途：prompt 瘦身／改寫時，證明「輸出有沒有變鬆」不是靠感覺。變因只有
// system prompt，user message 兩邊逐字相同、模型與參數相同。
//
// 跑法（repo 根目錄，需要 Eric 當次授權——會產生 Anthropic 費用）：
//   export ANTHROPIC_API_KEY="$(cat ~/.config/anthropic/key)"
//   deno run --allow-read --allow-env --allow-net --allow-run \
//     tools/opener-prompt-ab/run_ab.ts <baseline-git-ref> [runs] [--mode=opener|newtopic]
//
// baseline-git-ref 取該 commit 版本的原始檔當對照組，HEAD 工作區當實驗組。
// 想只量現況基準線（還沒有對照組）時用 --mode=xxx 搭 baseline ref = HEAD。
//
// 指標正則自檢（不打 API、不用金鑰）：
//   deno run --allow-read --allow-env --allow-run tools/opener-prompt-ab/run_ab.ts --self-check

// ── 客觀指標 ────────────────────────────────────────────────
/** 前提＋轉折骨架（「A 但 B」「A，其實 B」「妳感覺是那種…的人」…）。 */
const PIVOT = /[但不過其實可是然而]|感覺(?:妳|你)是那種|通常.{0,8}兩(?:種|個)/u;
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
/** 用戶自己的目標／備註被寫成「她的事」——grounding 破口，任何欄位都不准出現。 */
const LEAK = /(?:你|妳)(?:之前|上次)(?:說|提到)|(?:你|妳)想約|(?:聽起來|看來|感覺)(?:你|妳)是/u;

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
  console.log(bad.length === 0 ? `✓ 指標自檢 ${cases.length} 項全過` : `✗ ${bad.length} 項失敗`);
  Deno.exit(bad.length === 0 ? 0 : 1);
}

const apiKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
if (!apiKey) {
  console.error("缺 ANTHROPIC_API_KEY");
  Deno.exit(2);
}

const positional = Deno.args.filter((a) => !a.startsWith("--"));
const modeArg = Deno.args.find((a) => a.startsWith("--mode="))?.slice(7) ?? "opener";
const baselineRef = positional[0];
const runs = Number(positional[1] ?? "3");
if (!baselineRef) {
  console.error("用法：run_ab.ts <baseline-git-ref> [runs] [--mode=opener|newtopic]");
  Deno.exit(2);
}

// 生產端兩個功能都跑 claude-sonnet-5（index.ts openerModel / newTopicModel）。
const MODEL = "claude-sonnet-5";

interface Mode {
  path: string;
  constName: string;
  userContent: string;
  /** 從模型 JSON 取出「可直接傳出去的那一句」清單。 */
  lines: (parsed: Record<string, unknown>) => string[];
  /** 全欄位掃描用（grounding 洩漏檢查看得到 nextMove/reason）。 */
  allText: (parsed: Record<string, unknown>) => string;
  /** 被當開頭＝唸稿感的輸入原句。 */
  bioPhrases: string[];
  /** 判斷五題是不是換皮不換題用的已知興趣詞。 */
  knownInterests: string[];
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
- 你的備註：慢熱、聊得來還沒約、愛喝咖啡、上次互相叫對方鄰居、想約出來見面
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
    bioPhrases: ["熱愛學習", "熱愛學新", "喜歡認識新朋友", "講話直接", "微胖"],
    knownInterests: [],
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
    bioPhrases: ["慢熱", "幽默愛鬧", "愛喝咖啡", "聊得來"],
    knownInterests: ["旅行", "旅遊", "咖啡", "手沖", "看展", "展覽"],
  },
};

const mode = MODES[modeArg];
if (!mode) {
  console.error(`未知 --mode=${modeArg}（可用：${Object.keys(MODES).join("／")}）`);
  Deno.exit(2);
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

async function generate(systemPrompt: string): Promise<{ lines: string[]; all: string }> {
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
      messages: [{ role: "user", content: mode.userContent }],
    }),
  });
  const json = await res.json();
  // content[0] 不保證是 text（同 fallback.ts extractClaudeText 的理由）。
  const text = (json?.content as Array<{ type: string; text?: string }> ?? [])
    .find((b) => b?.type === "text")?.text;
  if (typeof text !== "string") {
    throw new Error(`API 回覆異常：${JSON.stringify(json).slice(0, 300)}`);
  }
  const match = text.match(/\{[\s\S]*\}/);
  if (!match) throw new Error("回覆沒有 JSON");
  const parsed = JSON.parse(match[0]);
  return { lines: mode.lines(parsed), all: mode.allText(parsed) };
}

function metrics(lines: string[], all: string) {
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
    quotesBio: lines.filter((l) =>
      mode.bioPhrases.some((p) => l.slice(0, 12).includes(p))
    ).length,
    multiline: lines.filter((l) => l.includes("\n")).length,
    // 換皮不換題：五題各自有沒有踩在同一組已知興趣詞上。
    sameInterest: mode.knownInterests.length === 0 ? 0 : lines.filter((l) =>
      mode.knownInterests.some((k) => l.includes(k))
    ).length,
    // grounding 洩漏掃全欄位（含 nextMove / reason），不只可見訊息。
    leak: (all.match(new RegExp(LEAK, "gu")) ?? []).length,
  };
}

const baselineSource = await gitShow(baselineRef, mode.path);
const currentSource = await Deno.readTextFile(mode.path);
const baselinePrompt = extractPrompt(baselineSource, mode.constName);
const currentPrompt = extractPrompt(currentSource, mode.constName);
// 兩邊一字不差時（例如量基準線用 baseline=HEAD）只跑一組，不白花一半的錢。
const arms: Array<[string, string]> = baselinePrompt === currentPrompt
  ? [["current(worktree)＝baseline，只跑一組", currentPrompt]]
  : [
    [`baseline(${baselineRef})`, baselinePrompt],
    ["current(worktree)", currentPrompt],
  ];

for (const [label, prompt] of arms) {
  console.log(`\n═══ ${modeArg} ${label} — prompt ${prompt.length} 字元 ═══`);
  const agg = { pivot: 0, thatType: 0, asks: 0, questionForm: 0, over30: 0, quotesBio: 0, multiline: 0, periods: 0, wrapped: 0, sameInterest: 0, leak: 0, lens: [] as number[] };
  for (let r = 1; r <= runs; r++) {
    const { lines, all } = await generate(prompt);
    const m = metrics(lines, all);
    agg.pivot += m.pivot; agg.thatType += m.thatType;
    agg.asks += m.asks; agg.questionForm += m.questionForm; agg.over30 += m.over30;
    agg.quotesBio += m.quotesBio; agg.multiline += m.multiline;
    agg.periods += m.periods; agg.wrapped += m.wrapped;
    agg.sameInterest += m.sameInterest; agg.leak += m.leak;
    agg.lens.push(m.lenMin, m.lenMax);
    console.log(`\n[run ${r}] 長度 ${m.lenMin}-${m.lenMax}（均 ${m.lenAvg}）｜轉折骨架 ${m.pivot}/5（那種句型 ${m.thatType}）｜實質問句 ${m.questionForm}/5（句末問號 ${m.asks}）｜>30字 ${m.over30}/5｜唸稿開頭 ${m.quotesBio}/5｜分則 ${m.multiline}/5｜句末句號 ${m.periods}/5｜包裝 ${m.wrapped}/5｜撞已知興趣 ${m.sameInterest}/5｜grounding 洩漏 ${m.leak}`);
    lines.forEach((l) => console.log("   ", l.replace(/\n/g, " ⏎ ")));
  }
  const total = runs * 5;
  console.log(`\n── ${label} 合計（${total} 句）：轉折骨架 ${agg.pivot}（那種句型 ${agg.thatType}）｜實質問句 ${agg.questionForm}（句末問號 ${agg.asks}）｜>30字 ${agg.over30}｜唸稿開頭 ${agg.quotesBio}｜分則 ${agg.multiline}｜句末句號 ${agg.periods}｜包裝 ${agg.wrapped}｜撞已知興趣 ${agg.sameInterest}｜grounding 洩漏 ${agg.leak}｜最短 ${Math.min(...agg.lens)} 最長 ${Math.max(...agg.lens)}`);
}
