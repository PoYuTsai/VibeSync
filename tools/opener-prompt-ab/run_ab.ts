// Opener prompt A/B：比較兩個版本的 OPENER_PROMPT 在同一份對方資料下的輸出。
//
// 用途：prompt 瘦身／改寫時，證明「輸出有沒有變鬆」不是靠感覺。變因只有
// system prompt，user message 兩邊逐字相同、模型與參數相同。
//
// 跑法（repo 根目錄，需要 Eric 當次授權——會產生 Anthropic 費用）：
//   export ANTHROPIC_API_KEY="$(cat ~/.config/anthropic/key)"
//   deno run --allow-read --allow-env --allow-net --allow-run \
//     tools/opener-prompt-ab/run_ab.ts <baseline-git-ref> [runs]
//
// baseline-git-ref 取該 commit 版本的 index.ts 當對照組，HEAD 工作區當實驗組。

const apiKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
if (!apiKey) {
  console.error("缺 ANTHROPIC_API_KEY");
  Deno.exit(2);
}

const baselineRef = Deno.args[0];
const runs = Number(Deno.args[1] ?? "3");
if (!baselineRef) {
  console.error("用法：run_ab.ts <baseline-git-ref> [runs]");
  Deno.exit(2);
}

const INDEX_PATH = "supabase/functions/analyze-chat/index.ts";

/** 從 index.ts 原始碼抽出 OPENER_PROMPT 樣板字串的內容。 */
function extractOpenerPrompt(source: string): string {
  const start = source.indexOf("const OPENER_PROMPT =");
  if (start < 0) throw new Error("找不到 OPENER_PROMPT");
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

// grace（2026-08-19 真機案例）：長自介、規則牆、唯一正向線索是「熱愛學習
// 嘗試新事物」。刻意用純文字路徑——變因要只有 system prompt。
const USER_CONTENT = `對方資料：
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

async function generate(systemPrompt: string): Promise<string[]> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-5",
      max_tokens: 3000,
      system: systemPrompt,
      messages: [{ role: "user", content: USER_CONTENT }],
    }),
  });
  const json = await res.json();
  const text = json?.content?.[0]?.text;
  if (typeof text !== "string") {
    throw new Error(`API 回覆異常：${JSON.stringify(json).slice(0, 300)}`);
  }
  const match = text.match(/\{[\s\S]*\}/);
  if (!match) throw new Error("回覆沒有 JSON");
  const parsed = JSON.parse(match[0]);
  const openers = parsed.openers ?? {};
  return ["extend", "resonate", "tease", "humor", "coldRead"]
    .map((k) => String(openers[k] ?? ""))
    .filter((v) => v.length > 0);
}

// ── 客觀指標 ────────────────────────────────────────────────
/** 前提＋轉折骨架（「A 但 B」「A，其實 B」「妳感覺是那種…的人」…）。 */
const PIVOT = /[但不過其實可是然而]|感覺(?:妳|你)是那種|通常.{0,8}兩(?:種|個)/u;
/** 問號收尾。 */
const ASKS = /[?？]\s*$/u;
/** 她自介裡的原句片語——被當開頭＝唸稿感。 */
const BIO_PHRASES = ["熱愛學習", "熱愛學新", "喜歡認識新朋友", "講話直接", "微胖"];

function metrics(lines: string[]) {
  const lens = lines.map((l) => Array.from(l.replace(/\n/g, "")).length);
  return {
    n: lines.length,
    lenMin: Math.min(...lens),
    lenMax: Math.max(...lens),
    lenAvg: Math.round(lens.reduce((a, b) => a + b, 0) / lens.length),
    over30: lens.filter((l) => l > 30).length,
    pivot: lines.filter((l) => PIVOT.test(l)).length,
    asks: lines.filter((l) => ASKS.test(l)).length,
    quotesBio: lines.filter((l) =>
      BIO_PHRASES.some((p) => l.slice(0, 12).includes(p))
    ).length,
    multiline: lines.filter((l) => l.includes("\n")).length,
  };
}

const baselineSource = await gitShow(baselineRef, INDEX_PATH);
const currentSource = await Deno.readTextFile(INDEX_PATH);
const arms: Array<[string, string]> = [
  [`baseline(${baselineRef})`, extractOpenerPrompt(baselineSource)],
  ["current(worktree)", extractOpenerPrompt(currentSource)],
];

for (const [label, prompt] of arms) {
  console.log(`\n═══ ${label} — prompt ${prompt.length} 字元 ═══`);
  const agg = { pivot: 0, asks: 0, over30: 0, quotesBio: 0, multiline: 0, lens: [] as number[] };
  for (let r = 1; r <= runs; r++) {
    const lines = await generate(prompt);
    const m = metrics(lines);
    agg.pivot += m.pivot; agg.asks += m.asks; agg.over30 += m.over30;
    agg.quotesBio += m.quotesBio; agg.multiline += m.multiline;
    agg.lens.push(m.lenMin, m.lenMax);
    console.log(`\n[run ${r}] 長度 ${m.lenMin}-${m.lenMax}（均 ${m.lenAvg}）｜轉折骨架 ${m.pivot}/5｜問號 ${m.asks}/5｜>30字 ${m.over30}/5｜唸稿開頭 ${m.quotesBio}/5｜分則 ${m.multiline}/5`);
    lines.forEach((l) => console.log("   ", l.replace(/\n/g, " ⏎ ")));
  }
  const total = runs * 5;
  console.log(`\n── ${label} 合計（${total} 句）：轉折骨架 ${agg.pivot}｜問號 ${agg.asks}｜>30字 ${agg.over30}｜唸稿開頭 ${agg.quotesBio}｜分則 ${agg.multiline}｜最短 ${Math.min(...agg.lens)} 最長 ${Math.max(...agg.lens)}`);
}
