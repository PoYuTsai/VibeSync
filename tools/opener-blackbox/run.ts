// 開場救星黑箱（local-only，付費）：同一份生產 OPENER_PROMPT 打純文字 profile，
// 兩個用途：
//   1. --tag=before|after：prompt 改版前後，看篩選型自介的五句還踩不踩她的抱怨。
//   2. --supplement：同一 profile 多跑一臂「用戶補充一句」，量兩段式假設——
//      用戶原料真的會讓五句變不一樣嗎（bigram Jaccard，越低越不同）。
// 跑法（repo 根目錄；讀 ~/.config/anthropic/key）：
//   deno run --allow-read --allow-write --allow-env --allow-net=api.anthropic.com \
//     tools/opener-blackbox/run.ts --tag=before [--supplement] [--repeat=2] [--only=id,id] \
//     [--prompt=supabase/functions/analyze-chat/<舊版 opener_prompt 副本>.ts]  # 修前對照
// 輸出 tools/opener-blackbox/out/<tag>/<profile>[.sup].json 與 summary.md。
// ponytail: 不鏡像 handler 的圖片路徑，只鏡像純文字 user content；圖片版靠真機。

import { parseJsonObjectFromText } from "../../supabase/functions/analyze-chat/json_text.ts";
import { normalizeOpenerProfileInfo } from "../../supabase/functions/analyze-chat/opener_profile.ts";

const MODEL = "claude-sonnet-5";
const OPENER_TYPES = ["extend", "resonate", "tease", "humor", "coldRead"] as const;

interface Profile {
  id: string;
  shape: "filter_heavy" | "mixed" | "hooks" | "sparse";
  profileInfo: { name?: string; bio?: string; interests?: string; meetingContext?: string };
  /** 她抱怨／篩選句裡的字眼：五句裡出現就算踩雷。 */
  forbidden: string[];
  /** 兩段式模擬：用戶補的一句（方向或一手事實）。 */
  supplement: string;
  /** 正向線索字眼：混合型／線索型至少要有幾句從這裡長（覆蓋數，防「零踩雷但線索全丟」）。 */
  anchors?: string[];
  /** 用戶（發訊者）風格設定原文；有給就照 handler 的包裝注入，驗「合法的我也」。 */
  styleContext?: string;
}

const PROFILES: Profile[] = [
  {
    id: "screenshot-filter",
    shape: "filter_heavy",
    profileInfo: {
      name: "小可愛",
      bio: [
        "本人是肉肉的～不能接受請不要滑右邊～",
        "滑了聊天又叫我改變…我就是長這樣…",
        "不是都寫清楚了嗎…到底哪一隻眼睛沒看到🙄",
        "騙色騙財 真的先不要～",
        "麻煩可以多一點正常人嗎？🤣🤣🤣",
        "真的不要玩玩～很不喜歡～很累～想約的麻煩左滑謝謝🙏～有女朋友的也不要滑右邊～不想浪費時間～麻煩先看自傳在滑清楚～真心想找認真的🤭",
        "想找情緒穩定～有耐心的男生～可以長長久久～步入婚姻☺️",
      ].join("\n"),
      interests: "職業：美容師；地區：新北，距離 4 公里；不喝酒",
      meetingContext: "交友軟體",
    },
    forbidden: ["累", "訊息", "正常人", "規則", "肉", "婚", "穩定", "改變", "玩玩", "騙", "滑", "認真", "條件", "自介", "自傳", "耐心"],
    supplement: "想從她的職業開",
  },
  {
    id: "filter-no-fields",
    shape: "filter_heavy",
    profileInfo: {
      name: "測試戊",
      bio: "不約 不聊色 不要問三圍\n已讀不回就是不想聊\n不要一開始就要 LINE\n請看完自介再來 謝謝\n玩玩的不要浪費彼此時間",
      interests: "地區：台中",
      meetingContext: "交友軟體",
    },
    forbidden: ["約", "色", "三圍", "已讀", "LINE", "自介", "玩玩", "浪費", "規則", "條件"],
    supplement: "我也住台中，想從同城生活圈開",
  },
  {
    id: "rule-wall",
    shape: "mixed",
    profileInfo: {
      name: "測試甲",
      bio: "喜歡把休假拿來學新東西\n\n在醫院輪大夜，作息跟大家相反\n不要問我薪水 也不要問科別\n不喝酒 不要約唱歌\n不聊色 不快速見面\n打字沒誠意的不會回\n看完自介再來聊 謝謝",
      meetingContext: "交友軟體",
    },
    forbidden: ["薪水", "科別", "喝酒", "唱歌", "色", "誠意", "自介", "規則"],
    supplement: "我對「休假學新東西」有興趣，我自己最近在學木工",
    anchors: ["休假", "學", "大夜", "作息"],
  },
  {
    id: "filter-plus-one-hook",
    shape: "mixed",
    profileInfo: {
      name: "測試庚",
      bio: "不約 不聊色\n有女友的不要來\n玩玩的左滑\n已讀不回就是沒興趣\n不要一直問住哪\n不要一開始就要 LINE\n沒誠意的不回\n看完自介再滑\n週末在家烤司康 養一隻很吵的玄鳳",
      meetingContext: "交友軟體",
    },
    forbidden: ["約", "色", "女友", "玩玩", "已讀", "住哪", "LINE", "誠意", "自介", "規則"],
    supplement: "我對玄鳳有興趣",
    anchors: ["司康", "烤", "玄鳳", "鳥"],
  },
  {
    id: "mixed-rules-hobby",
    shape: "mixed",
    profileInfo: {
      name: "測試己",
      bio: "週末在家烤司康 失敗率很高\n不約 不要一直問住哪\n有女友的請自重\n養一隻很吵的玄鳳",
      meetingContext: "交友軟體",
    },
    forbidden: ["約", "住哪", "女友", "自重", "規則"],
    supplement: "我對玄鳳有興趣，我家以前養過",
    anchors: ["司康", "烤", "玄鳳", "鳥"],
  },
  {
    id: "short-concrete",
    shape: "hooks",
    profileInfo: {
      name: "測試乙",
      bio: "養了一隻不給摸的柴犬\n假日固定去河堤練滑板",
      meetingContext: "交友軟體",
    },
    forbidden: [],
    supplement: "想從柴犬開，我沒養狗但很怕狗",
    anchors: ["柴犬", "狗", "滑板", "河堤"],
  },
  {
    id: "multi-hook",
    shape: "hooks",
    profileInfo: {
      name: "測試丁",
      bio: "白天在會計事務所對數字\n晚上在 livehouse 打鼓\n最近在學調酒 家裡貓比我早睡",
      interests: "鼓、調酒、貓",
      meetingContext: "交友軟體",
    },
    forbidden: [],
    supplement: "我對打鼓有興趣，我玩過三年樂團",
    anchors: ["鼓", "調酒", "貓", "數字", "會計"],
  },
  {
    id: "style-legit-common",
    shape: "hooks",
    profileInfo: {
      name: "測試辛",
      bio: "養了一隻不給摸的柴犬\n假日固定去河堤練滑板",
      meetingContext: "交友軟體",
    },
    forbidden: [],
    supplement: "想從柴犬開",
    anchors: ["柴犬", "狗", "滑板", "河堤"],
    styleContext: "語氣偏好：輕鬆直接\n我的興趣：養了一隻柴犬、週末爬山\n自我備註：不太會講幹話，怕被當油",
  },
  {
    id: "sparse",
    shape: "sparse",
    profileInfo: { name: "測試丙", interests: "看電影", meetingContext: "交友軟體" },
    forbidden: [],
    supplement: "隨口的新話題就好",
  },
];

// 鏡像 opener_handler.ts 純文字 user content（imageCount=0、無風格設定）。
function compileUserContent(p: Profile, supplement: string | null): string {
  const { name, bio, interests, meetingContext } = normalizeOpenerProfileInfo(p.profileInfo);
  const parts: string[] = [];
  if (name) parts.push(`對方名字：${name}`);
  if (bio) parts.push(`自我介紹：${bio}`);
  if (interests) parts.push(`興趣：${interests}`);
  if (meetingContext) parts.push(`認識場景：${meetingContext}`);
  const out = ["用戶提供的對方資訊：\n" + parts.join("\n")];
  if (supplement) {
    out.push(
      `\n用戶補充（他本人的一手資訊，只用來決定開場方向與可用素材；不得寫成對方說過的話、不得假造共同點）：${supplement}`,
    );
  }
  out.push("\n請根據以上可見資訊生成 5 種風格的開場白；只使用明確線索，不要補不存在的人格或共同點。");
  if (p.styleContext) {
    out.push(
      "用戶（發訊者本人）的風格設定：\n" + p.styleContext +
        "\n這些不是對方的資料；只用來調整開場白語氣，絕不當成對方的興趣或共同點。",
    );
  }
  return out.join("\n");
}

async function callModel(apiKey: string, user: string) {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 3000,
      thinking: { type: "disabled" },
      system: OPENER_PROMPT,
      messages: [{ role: "user", content: user }],
    }),
  });
  const json = await res.json();
  if (json.error) throw new Error(`API 失敗：${JSON.stringify(json.error)}`);
  const text = (json.content as Array<{ type: string; text?: string }>).find((b) => b.type === "text")?.text ?? "";
  return { text, usage: json.usage };
}

function bigrams(s: string): Set<string> {
  const t = s.replace(/[\s，。、！？!?~～「」『』]/g, "");
  const out = new Set<string>();
  for (let i = 0; i + 1 < t.length; i++) out.add(t.slice(i, i + 2));
  return out;
}
function jaccard(a: string, b: string): number {
  const A = bigrams(a), B = bigrams(b);
  let inter = 0;
  for (const x of A) if (B.has(x)) inter++;
  const union = A.size + B.size - inter;
  return union === 0 ? 1 : inter / union;
}

// 第一人稱事實：用戶沒給的自身經歷／物件（我也養、我家那隻、我試過…）。
// ponytail: 子字串啟發式會誤判（「我懂」「我覺得」不算事實），所以句子全列出來給人眼核。
const FIRST_PERSON_FACT = /我(也|家|自己|朋友|養|有|試過|做過|以前|最近|平常|上|每次|常|認識|媽|妹|哥|姐|弟|狗|貓|週末|假日|下班|是那種|的(狗|貓|鳥|柴|朋友|同事|室友|家人))/;
function firstPersonFacts(openers: Record<string, string>): string[] {
  return OPENER_TYPES.filter((t) => FIRST_PERSON_FACT.test(openers[t] ?? "")).map((t) => `${t}：${openers[t]}`);
}

function arg(name: string): string | null {
  const hit = Deno.args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : null;
}

const tag = arg("tag") ?? "adhoc";
// 修前對照：--prompt 指到同目錄下的舊版副本（它 import ./prompt_leak.ts，所以要放在 analyze-chat/ 內）。
const promptPath = arg("prompt") ?? "supabase/functions/analyze-chat/opener_prompt.ts";
const OPENER_PROMPT: string = (await import(new URL(`../../${promptPath}`, import.meta.url).href)).OPENER_PROMPT;
const wantSupplement = Deno.args.includes("--supplement");
const only = arg("only")?.split(",") ?? null;
const apiKey = (await Deno.readTextFile(`${Deno.env.get("HOME")}/.config/anthropic/key`)).trim();
const outDir = new URL(`./out/${tag}/`, import.meta.url);
await Deno.mkdir(outDir, { recursive: true });

const summary: string[] = [`# opener blackbox · ${tag} · ${MODEL} · ${new Date().toISOString()}`, ""];
let inTok = 0, outTok = 0, fpTotal = 0, callTotal = 0;

for (const p of PROFILES) {
  if (only && !only.includes(p.id)) continue;
  const repeat = Number(arg("repeat") ?? "1");
  const arms: Array<[string, string | null]> = [["skip", null]];
  for (let i = 2; i <= repeat; i++) arms.push([`skip${i}`, null]); // 雜訊帶：同 prompt 重抽
  if (wantSupplement) arms.push(["sup", p.supplement]);
  const openersByArm: Record<string, Record<string, string>> = {};
  for (const [arm, sup] of arms) {
    const user = compileUserContent(p, sup);
    const { text, usage } = await callModel(apiKey, user);
    callTotal++;
    inTok += usage?.input_tokens ?? 0;
    outTok += usage?.output_tokens ?? 0;
    const parsed = parseJsonObjectFromText(text) as Record<string, unknown> | null;
    const openers = (parsed?.openers ?? {}) as Record<string, string>;
    await Deno.writeTextFile(new URL(`${p.id}.${arm}.json`, outDir), JSON.stringify({ user, raw: text, usage }, null, 2));
    const missing = OPENER_TYPES.filter((t) => typeof openers[t] !== "string" || !openers[t].trim());
    if (missing.length) throw new Error(`${p.id}.${arm}：五句不齊（${missing.join(",")}），原文見 out/${tag}/${p.id}.${arm}.json`);
    const rec = (parsed?.recommendation ?? {}) as Record<string, string>;
    openersByArm[arm] = openers;
    const hits = OPENER_TYPES.flatMap((t) =>
      p.forbidden.filter((w) => (openers[t] ?? "").includes(w)).map((w) => `${t}:${w}`)
    );
    summary.push(`## ${p.id} [${p.shape}] · ${arm}${sup ? `（補充：${sup}）` : ""}`);
    for (const t of OPENER_TYPES) summary.push(`- ${t}${rec.pick === t ? " ★" : ""}：${openers[t] ?? "（缺）"}`);
    summary.push(`- 踩雷：${hits.length ? hits.join("、") : "0"}`);
    const fp = firstPersonFacts(openers);
    fpTotal += fp.length;
    summary.push(`- 第一人稱事實：${fp.length}${fp.length ? "\n  - " + fp.join("\n  - ") : ""}`);
    if (p.anchors) {
      const covered = OPENER_TYPES.filter((t) => p.anchors!.some((w) => openers[t].includes(w))).length;
      summary.push(`- 正向線索覆蓋：${covered}/5 句`);
    }
    const bio = /bioComposition"\s*:\s*"([a-z_]+)/.exec(text)?.[1] ?? "?";
    summary.push(`- bioComposition：${bio}`);
    summary.push(`- reason：${rec.reason ?? ""}`, "");
    console.log(`${p.id}.${arm} 踩雷=${hits.length}`);
  }
  if (repeat > 1) {
    const names = arms.map(([a]) => a).filter((a) => a.startsWith("skip"));
    const sims: number[] = [];
    for (let i = 0; i < names.length; i++) for (let j = i + 1; j < names.length; j++) {
      for (const t of OPENER_TYPES) sims.push(jaccard(openersByArm[names[i]][t], openersByArm[names[j]][t]));
    }
    const mean = sims.reduce((a, b) => a + b, 0) / sims.length;
    summary.push(`- 雜訊帶（${names.length} 抽兩兩比對）相似度平均 ${mean.toFixed(2)}`, "");
  }
  if (wantSupplement) {
    const sims = OPENER_TYPES.map((t) => jaccard(openersByArm.skip[t] ?? "", openersByArm.sup[t] ?? ""));
    const mean = sims.reduce((a, b) => a + b, 0) / sims.length;
    summary.push(`- skip vs sup 相似度（bigram Jaccard，0=完全不同）：${sims.map((s) => s.toFixed(2)).join(" / ")}，平均 ${mean.toFixed(2)}`, "");
  }
}
summary.push(`第一人稱事實合計：${fpTotal} / ${callTotal * 5} 句`, `tokens：in ${inTok} / out ${outTok}`);
await Deno.writeTextFile(new URL("summary.md", outDir), summary.join("\n"));
console.log(summary.join("\n"));
