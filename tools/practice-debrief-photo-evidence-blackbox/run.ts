// 黑箱：debrief 卡會不會把「NPC 自己講錯大頭照細節」的責任反過來扣在使用者
// 頭上（watchouts/summary 出現「質疑對方」「咄咄逼人」之類字眼）。
//
// 10 個合成劇本：user 正確引用該 profile 的 photoScene 細節，NPC 的台詞否認／
// 反駁（劇本手寫，不靠真模型生成聊天——這裡只測 debrief 這一層，跟
// production 的 buildDebriefMessages／callClaude 完全同款）。
//
// 用法：
//   export CLAUDE_API_KEY=$(cat ~/.config/anthropic/key)
//   deno run --allow-env --allow-read --allow-net=api.anthropic.com --allow-write \
//     tools/practice-debrief-photo-evidence-blackbox/run.ts
import { buildDebriefMessages } from "../../supabase/functions/practice-chat/prompt.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
import { callClaude, CLAUDE_SONNET_MODEL } from "../../supabase/functions/practice-chat/claude.ts";

interface Scenario {
  id: string;
  profileId: string;
  photoDetail: string; // 引用的 photoScene 原句，供人工核對
  turns: PracticeTurn[];
}

const SCENARIOS: Scenario[] = [
  {
    id: "alice-shirt-scarf",
    profileId: "practice_girl_001",
    photoDetail: "在飯店大廳拍的自拍，還穿著上班的白襯衫和領巾",
    turns: [
      { role: "ai", text: "嗨～今天過得如何" },
      { role: "user", text: "還不錯。妳大頭照那件白襯衫配領巾看起來很正式，是上班拍的嗎？" },
      { role: "ai", text: "沒有欸，我照片沒有穿那個，你是不是認錯人了。" },
      { role: "user", text: "喔真的假的，我記得滿清楚的說，妳照片背景看起來像飯店大廳。" },
      { role: "ai", text: "才沒有，你亂講。" },
    ],
  },
  {
    id: "ivy-night-market",
    profileId: "practice_girl_002",
    photoDetail: "晚上在夜市拍的，一手烤串一手飲料杯，笑到瞇眼",
    turns: [
      { role: "ai", text: "欸你也太晚才回我" },
      { role: "user", text: "抱歉在忙。妳大頭照是在夜市拍的吧，手上還拿著烤串跟飲料，笑得很開心。" },
      { role: "ai", text: "我沒去過夜市拍照啦，你記錯了。" },
    ],
  },
  {
    id: "zoe-hospital-hallway",
    profileId: "practice_girl_003",
    photoDetail: "在醫院走廊穿淺藍刷手服拍的，手上還拿著平板，上班空檔",
    turns: [
      { role: "ai", text: "剛下班，累爆" },
      { role: "user", text: "辛苦了！妳照片是上班空檔在醫院走廊拍的吧，還穿著淺藍刷手服、拿著平板？" },
      { role: "ai", text: "你認錯人了吧，我沒有那張照片。" },
      { role: "user", text: "應該沒認錯，妳頭像我看好幾次了。" },
      { role: "ai", text: "反正不是我，不要再講了。" },
    ],
  },
  {
    id: "chloe-studio-swatches",
    profileId: "practice_girl_005",
    photoDetail: "在工作室桌邊拍的，戴粗框眼鏡，後面牆上貼滿色票和材質樣本",
    turns: [
      { role: "ai", text: "在改稿改到懷疑人生" },
      { role: "user", text: "妳大頭照背景那些色票牆是妳工作室吧？戴粗框眼鏡那張。" },
      { role: "ai", text: "哪有，我從來沒有戴眼鏡拍過照。" },
    ],
  },
  {
    id: "emma-palm-cafe",
    profileId: "practice_girl_006",
    photoDetail: "在一間有棕櫚樹的戶外咖啡座拍的，手上一杯冰拿鐵",
    turns: [
      { role: "ai", text: "剛爬完山，好累" },
      { role: "user", text: "妳照片背景有棕櫚樹的那間咖啡廳看起來很好拍，手上拿的是冰拿鐵嗎？" },
      { role: "ai", text: "沒有棕櫚樹啊，你看錯照片了吧。" },
      { role: "user", text: "咦，我印象中滿清楚有棕櫚樹的。" },
      { role: "ai", text: "就說沒有了。" },
    ],
  },
  {
    id: "ava-office-vest",
    profileId: "practice_girl_007",
    photoDetail: "在辦公室座位拍的自拍，穿灰色西裝背心、抱著一本筆記本",
    turns: [
      { role: "ai", text: "又要加班了" },
      { role: "user", text: "辛苦～妳大頭照是在辦公室座位拍的吧，穿灰色西裝背心、抱著筆記本？" },
      { role: "ai", text: "我沒有那件背心，你記錯了。" },
    ],
  },
  {
    id: "ella-gym-vest",
    profileId: "practice_girl_011",
    photoDetail: "在健身房拍的自拍，穿墨綠運動背心、靠著器材",
    turns: [
      { role: "ai", text: "剛練完，滿爽的" },
      { role: "user", text: "妳照片是在健身房拍的吧，穿墨綠色運動背心、靠著器材？" },
      { role: "ai", text: "才沒有，我沒在健身房拍過照。" },
      { role: "user", text: "喔好，可能我記錯背景了，不過衣服顏色我印象滿深的。" },
      { role: "ai", text: "反正你就是記錯了。" },
    ],
  },
  {
    id: "rina-nail-studio",
    profileId: "practice_girl_013",
    photoDetail: "在美甲工作室拍的自拍，後面一排指甲油，手擺在臉旁露出自己做的指甲",
    turns: [
      { role: "ai", text: "今天客人有點多" },
      { role: "user", text: "妳大頭照背景那排指甲油是妳工作室拍的吧？手擺臉旁那張，指甲也是妳自己做的？" },
      { role: "ai", text: "沒有欸，那不是我的照片背景。" },
    ],
  },
  {
    id: "vivian-bar-door",
    profileId: "practice_girl_019",
    photoDetail: "晚上在一間酒吧門口拍的，穿全黑、深紅唇膏，下班後的樣子",
    turns: [
      { role: "ai", text: "下班了，站一整天" },
      { role: "user", text: "妳照片是晚上在酒吧門口拍的吧，全身黑配深紅唇膏，下班後那樣？" },
      { role: "ai", text: "什麼酒吧，我沒去過那種地方拍照。" },
      { role: "user", text: "是喔，那張看起來真的滿像的，我記錯了嗎。" },
      { role: "ai", text: "你就是記錯了啊，很奇怪耶一直講。" },
    ],
  },
  {
    id: "fiona-paris-tower",
    profileId: "practice_girl_023",
    photoDetail: "去年去巴黎上瑜珈進修課，在鐵塔前草地野餐時拍的，穿運動內衣、旁邊有野餐籃",
    turns: [
      { role: "ai", text: "今天上完瑜珈課，整個人很放鬆" },
      { role: "user", text: "妳大頭照是去巴黎鐵塔前野餐拍的吧？記得妳說是去上瑜珈進修課。" },
      { role: "ai", text: "巴黎？我沒去過巴黎啊，那是淡水河邊拍的。" },
      { role: "user", text: "咦，可是背景真的很像鐵塔跟野餐籃耶。" },
      { role: "ai", text: "你看錯了吧，就淡水河邊而已。" },
    ],
  },
];

const apiKey = Deno.env.get("CLAUDE_API_KEY") ?? Deno.env.get("ANTHROPIC_API_KEY");
if (!apiKey) {
  console.error("缺 CLAUDE_API_KEY / ANTHROPIC_API_KEY");
  Deno.exit(1);
}

interface ResultRow {
  id: string;
  profileId: string;
  photoDetail: string;
  turns: PracticeTurn[];
  raw?: string;
  error?: string;
}

function extractField(raw: string, key: string): unknown {
  try {
    const obj = JSON.parse(raw.slice(raw.indexOf("{"), raw.lastIndexOf("}") + 1));
    return obj[key] ?? null;
  } catch {
    return null;
  }
}

const results: ResultRow[] = [];
for (const s of SCENARIOS) {
  const profile = resolvePracticeProfile({ profileId: s.profileId, difficulty: "normal" });
  const messages = buildDebriefMessages(s.turns, profile, { practiceMode: "standard" });
  try {
    const raw = await callClaude({
      apiKey,
      model: CLAUDE_SONNET_MODEL,
      messages,
      maxTokens: 1200,
      temperature: 0.4,
      timeoutMs: 25000,
    });
    results.push({ id: s.id, profileId: s.profileId, photoDetail: s.photoDetail, turns: s.turns, raw });
    console.log(`${s.id} OK`);
  } catch (error) {
    results.push({
      id: s.id,
      profileId: s.profileId,
      photoDetail: s.photoDetail,
      turns: s.turns,
      error: error instanceof Error ? error.message : String(error),
    });
    console.log(`${s.id} ERROR ${String(error)}`);
  }
}

const md = results.map((r) => {
  if (r.error) return `## ${r.id}\nprofile: ${r.profileId} | photoScene: ${r.photoDetail}\nERROR ${r.error}\n`;
  const summary = extractField(r.raw!, "summary");
  const strengths = extractField(r.raw!, "strengths");
  const watchouts = extractField(r.raw!, "watchouts");
  const suggestedLine = extractField(r.raw!, "suggestedLine");
  const vibe = extractField(r.raw!, "vibe");
  const dateChance = extractField(r.raw!, "dateChance");
  const dateChanceReason = extractField(r.raw!, "dateChanceReason");
  return [
    `## ${r.id}`,
    `profile: ${r.profileId} | photoScene: ${r.photoDetail}`,
    "turns:",
    ...r.turns.map((t) => `- [${t.role}] ${t.text}`),
    "",
    `**summary**: ${JSON.stringify(summary)}`,
    `**strengths**: ${JSON.stringify(strengths)}`,
    `**watchouts**: ${JSON.stringify(watchouts)}`,
    `**suggestedLine**: ${JSON.stringify(suggestedLine)}`,
    `**vibe**: ${JSON.stringify(vibe)}`,
    `**dateChance**: ${JSON.stringify(dateChance)}`,
    `**dateChanceReason**: ${JSON.stringify(dateChanceReason)}`,
    "",
    "**raw**:",
    "```json",
    r.raw!,
    "```",
    "",
  ].join("\n");
}).join("\n");

await Deno.writeTextFile(
  new URL("./results.md", import.meta.url),
  `# debrief 照片證據黑箱結果\n\n${results.length} 場，人工複核見各卡 verdict（此檔案由腳本產生 verdict 前的原始卡）。\n\n${md}`,
);
console.log(`\n寫入 tools/practice-debrief-photo-evidence-blackbox/results.md`);
