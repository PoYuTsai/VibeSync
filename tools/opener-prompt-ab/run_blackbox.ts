// Opener 黑箱三臂比較（local-only 評測工具，不碰生產行為）。
//
// 三臂：
//   A：生產 OPENER_PROMPT 原樣（直接 import opener_prompt.ts）。
//   B：精簡「只出卡」prompt（openers 五句＋recommendation.pick，無教練欄位）。
//   C：每型先生 3 個候選，再用「只回編號」的選擇器挑一個——候選編號 0/1/2，
//      整體推薦也是 0-4 的風格編號（0=extend…4=coldRead），本地對映回
//      canonical OPENER_TYPES；選擇器沒有任何改寫權。被選中的候選再走生產
//      同一條 normalizeOpenerPayload 與完整性檢查，不生食比較。
// 三臂共用生產同一條解析鏈 parseJsonObjectFromText → normalizeOpenerPayload，
// 正規化後五卡不齊、或 recommendation.pick 不是在場合法風格，一律 fail-loud
// 停跑。user message 逐字鏡像 opener_handler.ts 的純文字編譯器，鏡像由三段
// SHA-256 digest guard 釘死（見 COMPILER_SEGMENTS）。
//
// 跑法（repo 根目錄）：
//   離線自檢（不讀 key、不打網路）：
//     deno run --allow-read tools/opener-prompt-ab/run_blackbox.ts --self-check
//   實跑（需 Eric 當次授權——會產生 Anthropic 費用）：
//     ANTHROPIC_API_KEY=... deno run --allow-read --allow-write --allow-env \
//       --allow-net=api.anthropic.com tools/opener-prompt-ab/run_blackbox.ts --live
//
// 呼叫上限：正常一輪 16 次（A=4、B=4、C=4×2），含重試全域硬上限 24 次
// HTTP attempt，超過直接 throw 停跑。模型固定 claude-sonnet-5、thinking
// disabled（同生產）。輸出：out/run-<ts>/checkpoint.json（每臂成功即整包
// 增量落盤：原始＋正規化＋usage/attempt——中途炸掉不丟已付費產出）、
// results.json（完跑全量）、blind/profile-*.md（臂標籤洗牌、推薦卡排最前）、
// answer-key.md（對照表，另檔存放）。不落任何金鑰。品質最終判定是人眼
// 盲評，不設 LLM judge。

import { OPENER_PROMPT } from "../../supabase/functions/analyze-chat/opener_prompt.ts";
import { parseJsonObjectFromText } from "../../supabase/functions/analyze-chat/json_text.ts";
import {
  normalizeOpenerPayload,
  OPENER_TYPES,
  type OpenerType,
} from "../../supabase/functions/analyze-chat/opener_payload.ts";
import {
  normalizeOpenerProfileInfo,
} from "../../supabase/functions/analyze-chat/opener_profile.ts";

const MODEL = "claude-sonnet-5";
const MAX_TOKENS = 3000; // 同生產 OPENER_MAX_TOKENS
const MAX_HTTP_ATTEMPTS = 24; // 全域硬上限，含重試
const RETRIES_PER_CALL = 2; // 每次呼叫最多 1+2 次 attempt

// ── 四份合成 profile（皆為虛構人物，涵蓋四種輸入形狀）─────────────
// 全部走純文字 profileInfo 路徑（name/bio/interests/meetingContext），
// 與真機文字輸入同構。名字取明顯非真人的測試名。
interface SyntheticProfile {
  id: string;
  shape: string;
  profileInfo: { name?: string; bio?: string; interests?: string; meetingContext?: string };
}

const PROFILES: SyntheticProfile[] = [
  {
    id: "rule-wall",
    shape: "規則牆：長自介、界線多、正向線索只有一句",
    profileInfo: {
      name: "測試甲",
      bio: [
        "喜歡把休假拿來學新東西",
        "",
        "在醫院輪大夜，作息跟大家相反",
        "不要問我薪水 也不要問科別",
        "不喝酒 不要約唱歌",
        "不聊色 不快速見面",
        "打字沒誠意的不會回",
        "看完自介再來聊 謝謝",
      ].join("\n"),
      meetingContext: "交友軟體",
    },
  },
  {
    id: "short-concrete",
    shape: "短而具體：三行、零規則、兩個具體線索",
    profileInfo: {
      name: "測試乙",
      bio: "養了一隻不給摸的柴犬\n假日固定去河堤練滑板",
      meetingContext: "交友軟體",
    },
  },
  {
    id: "sparse",
    shape: "稀疏：只有一個籠統興趣詞",
    profileInfo: {
      name: "測試丙",
      interests: "看電影",
      meetingContext: "交友軟體",
    },
  },
  {
    id: "multi-hook",
    shape: "多鉤子：多個彼此有反差的具體線索",
    profileInfo: {
      name: "測試丁",
      bio: "白天在會計事務所對數字\n晚上在 livehouse 打鼓\n最近在學調酒 家裡貓比我早睡",
      interests: "鼓、調酒、貓",
      meetingContext: "交友軟體",
    },
  },
];

// ── 生產 user-content 編譯器鏡像（純文字路徑）───────────────────
// 逐字鏡像 opener_handler.ts「Build user prompt」區塊在
// imageCount=0、無 styleContext 時的行為。下方 digest guard 對 handler
// 原始碼三個關鍵區段整段釘 SHA-256，handler 改了這裡沒跟上就整場停跑。
function compileTextOnlyUserContent(
  rawProfileInfo: SyntheticProfile["profileInfo"],
): string {
  const normalizedProfile = normalizeOpenerProfileInfo(rawProfileInfo);
  const userContent: string[] = [];
  {
    const { name, bio, interests, meetingContext } = normalizedProfile;
    const parts: string[] = [];
    if (name) parts.push(`對方名字：${name}`);
    if (bio) parts.push(`自我介紹：${bio}`);
    if (interests) parts.push(`興趣：${interests}`);
    if (meetingContext) parts.push(`認識場景：${meetingContext}`);
    if (parts.length > 0) {
      userContent.push("用戶提供的對方資訊：\n" + parts.join("\n"));
    }
  }
  if (!userContent.length) {
    userContent.push(
      "用戶沒有提供對方資料。請明確標示可見線索不足，生成低風險、自然、不油、不假裝洞察的開場白。",
    );
  } else {
    userContent.push(
      "\n請根據以上可見資訊生成 5 種風格的開場白；只使用明確線索，不要補不存在的人格或共同點。",
    );
  }
  return userContent.join("\n");
}

// ── Parity/source guard（fail-loud，digest 版）─────────────────
// 上面的鏡像是手抄的，handler 一改就會悄悄量到不是生產的行為。舊版逐字面值
// 查「有沒有出現」抓不到插入、刪除、換序；這裡改把 opener_handler.ts 三個
// 關鍵區段用唯一起迄 marker 切出來，整段釘 SHA-256——段內任何插入、刪除、
// 換序、改字都會讓 digest 對不上而 throw，寧可停跑也不出錯數據。
// handler 合法改版時：先人工核對並更新上面的鏡像，再更新對應 sha256。
interface GuardSegment {
  label: string;
  start: string;
  end: string;
  sha256: string;
}

const COMPILER_SEGMENTS: GuardSegment[] = [
  {
    label: "normalize 鎖喉點",
    start: "  const normalizedProfile = normalizeOpenerProfileInfo(deps.rawProfileInfo);",
    end: "  const normalizedProfile = normalizeOpenerProfileInfo(deps.rawProfileInfo);",
    sha256: "d4a619d65e99fbcdee279c41c0bde71123ed017cbb173ba968dea279ff71e9ae",
  },
  {
    label: "user prompt 編譯器",
    start: "  // Build user prompt",
    end: '  const openerModel = "claude-sonnet-5";',
    sha256: "716ad10b7ae7d5286acb95793f3e4c78891bc722ddbc88540efbc440159e2ada",
  },
  {
    label: "messages 組裝",
    start: "  // Build messages for Claude API",
    end: '      content: userContent.join("\\n"),',
    sha256: "35dff6dbe14cc3c871c988ea510fad4150eeecb8359873f1028274ea5b71a3c0",
  },
];

async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** 純函式核心：對任一 handler 原始碼字串驗段落 digest（自檢可餵變異源碼）。 */
async function assertCompilerParity(src: string): Promise<void> {
  let prevStart = -1;
  for (const seg of COMPILER_SEGMENTS) {
    const startIdx = src.indexOf(seg.start);
    if (startIdx < 0) {
      throw new Error(`parity guard 失敗：找不到「${seg.label}」起點 marker`);
    }
    if (seg.start !== seg.end && src.indexOf(seg.start, startIdx + 1) >= 0) {
      throw new Error(`parity guard 失敗：「${seg.label}」起點 marker 不唯一`);
    }
    const endIdx = src.indexOf(seg.end, startIdx);
    if (endIdx < 0) {
      throw new Error(`parity guard 失敗：找不到「${seg.label}」迄點 marker`);
    }
    if (src.indexOf(seg.end, endIdx + seg.end.length) >= 0) {
      throw new Error(`parity guard 失敗：「${seg.label}」迄點 marker 不唯一`);
    }
    if (startIdx <= prevStart) {
      throw new Error(`parity guard 失敗：「${seg.label}」區段相對順序異動`);
    }
    prevStart = startIdx;
    const digest = await sha256Hex(src.slice(startIdx, endIdx + seg.end.length));
    if (digest !== seg.sha256) {
      throw new Error(
        `parity guard 失敗：「${seg.label}」區段 digest 不符` +
          `（expected ${seg.sha256}，actual ${digest}）。` +
          "opener_handler.ts 已漂移，請先核對並更新 run_blackbox.ts 的鏡像與 sha256 再跑。",
      );
    }
  }
}

async function sourceParityGuard(): Promise<void> {
  const src = await Deno.readTextFile(
    new URL(
      "../../supabase/functions/analyze-chat/opener_handler.ts",
      import.meta.url,
    ),
  );
  await assertCompilerParity(src);
}

// ── B 臂：精簡只出卡 prompt ─────────────────────────────────────
const CARDS_ONLY_PROMPT = `你在幫台灣的交友軟體用戶寫開場白。根據對方資料，生成 5 種風格各一句：
- extend（延展）：抓一個可見細節延伸成她能順手回答的東西
- resonate（共鳴）：有真的共同處境才共鳴，不硬說「我也」
- tease（調情）：輕輕戳她資料裡的反差，不碰身材外貌、不冒犯
- humor（幽默）：貼著她的資料可愛地怪，不是表演段子
- coldRead（冷讀）：一個可被她反駁的互動風格猜測，不複述她的原文

規則：繁體中文台灣用語；每句 10-25 字、像真人隨手打的、句末不要句號；
不虛構她沒寫的事；她明寫的禁忌不要碰也不要唸出來；五句句式彼此不同。
只輸出 JSON，不要 code fence：
{"openers":{"extend":"...","resonate":"...","tease":"...","humor":"...","coldRead":"..."},"recommendation":{"pick":"五種其中之一"}}`;

// ── C 臂：3 候選＋index-only 選擇器 ─────────────────────────────
const CANDIDATES_PROMPT = `你在幫台灣的交友軟體用戶寫開場白。根據對方資料，五種風格各寫 3 個彼此不同的候選：
- extend（延展）：抓一個可見細節延伸成她能順手回答的東西
- resonate（共鳴）：有真的共同處境才共鳴，不硬說「我也」
- tease（調情）：輕輕戳她資料裡的反差，不碰身材外貌、不冒犯
- humor（幽默）：貼著她的資料可愛地怪，不是表演段子
- coldRead（冷讀）：一個可被她反駁的互動風格猜測，不複述她的原文

規則：繁體中文台灣用語；每句 10-25 字、像真人隨手打的、句末不要句號；
不虛構她沒寫的事；她明寫的禁忌不要碰也不要唸出來；同型 3 個候選切入點要不同。
只輸出 JSON，不要 code fence：
{"extend":["...","...","..."],"resonate":["...","...","..."],"tease":["...","...","..."],"humor":["...","...","..."],"coldRead":["...","...","..."]}`;

const SELECTOR_PROMPT = `你是開場白挑選器。給你對方資料與五種風格各 3 個候選（候選編號 0/1/2）。
風格編號固定：0=extend、1=resonate、2=tease、3=humor、4=coldRead。
每種風格挑「最不像罐頭、她最有理由回」的候選編號，再挑一個整體最推薦的風格編號。
你只能輸出數字編號，不能改寫、不能輸出句子或風格名稱。
只輸出 JSON，不要 code fence：
{"extend":0,"resonate":0,"tease":0,"humor":0,"coldRead":0,"recommend":0}`;

/** 候選 JSON 形狀檢查：五型各恰好 3 個非空字串。壞形直接 throw（fail-loud）。 */
function parseCandidates(
  parsed: Record<string, unknown> | null,
): Record<OpenerType, string[]> {
  if (!parsed) throw new Error("C 臂候選：無法解析 JSON");
  const out = {} as Record<OpenerType, string[]>;
  for (const type of OPENER_TYPES) {
    const arr = parsed[type];
    if (
      !Array.isArray(arr) || arr.length !== 3 ||
      !arr.every((s) => typeof s === "string" && s.trim().length > 0)
    ) {
      throw new Error(`C 臂候選：${type} 不是 3 個非空字串`);
    }
    out[type] = arr.map((s) => s.trim());
  }
  return out;
}

/**
 * 選擇器輸出→逐字取回候選字串。全部欄位只收數字編號：五型候選 0/1/2，
 * recommend 是 0-4 的風格編號，本地對映 canonical OPENER_TYPES——選擇器
 * 回傳的任何字串（含風格名稱、改寫句）一律拒收，index 不合法直接 throw，
 * 不做默默 fallback。
 */
function applySelection(
  candidates: Record<OpenerType, string[]>,
  parsed: Record<string, unknown> | null,
): { openers: Record<OpenerType, string>; pick: OpenerType } {
  if (!parsed) throw new Error("C 臂選擇器：無法解析 JSON");
  const openers = {} as Record<OpenerType, string>;
  for (const type of OPENER_TYPES) {
    const idx = parsed[type];
    if (idx !== 0 && idx !== 1 && idx !== 2) {
      throw new Error(`C 臂選擇器：${type} 的候選編號不是 0/1/2：${JSON.stringify(idx)}`);
    }
    openers[type] = candidates[type][idx];
  }
  const recIdx = parsed.recommend;
  if (recIdx !== 0 && recIdx !== 1 && recIdx !== 2 && recIdx !== 3 && recIdx !== 4) {
    throw new Error(
      `C 臂選擇器：recommend 不是 0-4 的風格編號：${JSON.stringify(recIdx)}`,
    );
  }
  return { openers, pick: OPENER_TYPES[recIdx] };
}

// ── HTTP 層：全域 attempt 硬上限＋暫時性錯誤重試 ────────────────
interface Usage {
  inputTokens: number;
  outputTokens: number;
}

interface CallResult {
  text: string;
  usage: Usage;
}

type Transport = (body: Record<string, unknown>) => Promise<Record<string, unknown>>;

const TRANSIENT = new Set(["overloaded_error", "rate_limit_error", "api_error"]);

class AttemptBudget {
  used = 0;
  constructor(readonly max: number) {}
  take(): void {
    if (this.used >= this.max) {
      throw new Error(
        `已達全域 HTTP attempt 上限 ${this.max} 次，停跑（正常一輪應為 16 次呼叫）`,
      );
    }
    this.used++;
  }
}

async function callModel(
  transport: Transport,
  budget: AttemptBudget,
  system: string,
  userContent: string,
  usageTally: Usage,
): Promise<CallResult> {
  for (let attempt = 0; ; attempt++) {
    budget.take();
    const json = await transport({
      model: MODEL,
      max_tokens: MAX_TOKENS,
      thinking: { type: "disabled" },
      system,
      messages: [{ role: "user", content: userContent }],
    });
    const errType = (json?.error as { type?: string } | undefined)?.type;
    if (errType && TRANSIENT.has(errType) && attempt < RETRIES_PER_CALL) {
      const wait = (attempt + 1) * 5000;
      console.log(`    [API ${errType}，${wait / 1000}s 後重試（attempt ${budget.used}/${budget.max}）]`);
      await new Promise((r) => setTimeout(r, wait));
      continue;
    }
    if (json?.error) {
      throw new Error(`API 失敗：${JSON.stringify(json.error)}`);
    }
    const text = (json?.content as Array<{ type: string; text?: string }> ?? [])
      .find((b) => b?.type === "text")?.text;
    if (typeof text !== "string") {
      throw new Error(`API 回覆異常：${JSON.stringify(json).slice(0, 300)}`);
    }
    const usage = json?.usage as { input_tokens?: number; output_tokens?: number } | undefined;
    const u = { inputTokens: usage?.input_tokens ?? 0, outputTokens: usage?.output_tokens ?? 0 };
    usageTally.inputTokens += u.inputTokens;
    usageTally.outputTokens += u.outputTokens;
    return { text, usage: u };
  }
}

// ── 三臂執行 ───────────────────────────────────────────────────
interface ArmResult {
  arm: "A" | "B" | "C";
  rawTexts: string[]; // C 臂有兩段（候選＋選擇器）
  openers: Record<string, string>;
  pick: string | null;
  normalized: Record<string, unknown> | null; // 三臂都是生產 normalizer 的完整輸出
}

/**
 * 正規化後完整性檢查（三臂共用，fail-loud）：五卡俱全且
 * recommendation.pick 是在場合法風格，缺一即 throw——sanitizer 清掉的
 * 超長／壞形內容不得靜默降級成殘卡比較。
 */
function assertCompleteNormalized(
  arm: string,
  normalized: Record<string, unknown> | null,
  rawText?: string,
): {
  openers: Record<OpenerType, string>;
  pick: OpenerType;
  normalized: Record<string, unknown>;
} {
  if (!normalized) {
    throw new Error(
      `${arm} 臂：生產 normalizer 回 null` +
        (rawText ? `，原文尾段：${rawText.slice(-300)}` : ""),
    );
  }
  const openers = (normalized.openers ?? {}) as Record<string, string>;
  const missing = OPENER_TYPES.filter(
    (t) => typeof openers[t] !== "string" || openers[t].length === 0,
  );
  if (missing.length > 0) {
    throw new Error(
      `${arm} 臂：正規化後五卡不齊，缺 ${missing.join("、")}` +
        "（生產 sanitizer 可能清掉了超長或壞形內容，不得生食比較）",
    );
  }
  const pick = (normalized.recommendation as { pick?: unknown } | undefined)?.pick;
  if (
    typeof pick !== "string" ||
    !(OPENER_TYPES as readonly string[]).includes(pick) ||
    !openers[pick]
  ) {
    throw new Error(
      `${arm} 臂：recommendation.pick 不是在場合法風格：${JSON.stringify(pick)}`,
    );
  }
  return {
    openers: openers as Record<OpenerType, string>,
    pick: pick as OpenerType,
    normalized,
  };
}

/** A/B 臂共用：一次呼叫→生產解析鏈→完整性檢查。 */
async function runSingleCallArm(
  arm: "A" | "B",
  system: string,
  transport: Transport,
  budget: AttemptBudget,
  userContent: string,
  usageTally: Usage,
): Promise<ArmResult> {
  const { text } = await callModel(transport, budget, system, userContent, usageTally);
  const { openers, pick, normalized } = assertCompleteNormalized(
    arm,
    normalizeOpenerPayload(parseJsonObjectFromText(text)),
    text,
  );
  return { arm, rawTexts: [text], openers, pick, normalized };
}

async function runArmC(
  transport: Transport,
  budget: AttemptBudget,
  userContent: string,
  usageTally: Usage,
): Promise<ArmResult> {
  const gen = await callModel(transport, budget, CANDIDATES_PROMPT, userContent, usageTally);
  const candidates = parseCandidates(parseJsonObjectFromText(gen.text));
  const selectorUser = userContent + "\n\n候選清單：\n" +
    JSON.stringify(candidates, null, 2);
  const sel = await callModel(transport, budget, SELECTOR_PROMPT, selectorUser, usageTally);
  const selected = applySelection(candidates, parseJsonObjectFromText(sel.text));
  // 被選中的候選不得生食比較：走 A/B 同一條 normalizeOpenerPayload，再過
  // 同一個五卡/pick 完整性檢查，比較與落盤都用正規化後的輸出。
  const { openers, pick, normalized } = assertCompleteNormalized(
    "C",
    normalizeOpenerPayload({
      openers: selected.openers,
      recommendation: { pick: selected.pick },
    }),
  );
  return { arm: "C", rawTexts: [gen.text, sel.text], openers, pick, normalized };
}

// ── 主迴圈：四 profile × 三臂，每臂成功即 checkpoint ────────────
interface RunSnapshot {
  model: string;
  httpAttempts: number;
  maxHttpAttempts: number;
  usage: Usage;
  completedArms: number;
  profiles: Record<string, unknown>[];
}

async function runAllProfiles(
  transport: Transport,
  budget: AttemptBudget,
  tally: Usage,
  onArmDone: (snapshot: RunSnapshot) => Promise<void>,
): Promise<{
  results: Record<string, unknown>[];
  blindSheets: Array<{ id: string; sheet: string }>;
  answerKey: string[];
}> {
  const results: Record<string, unknown>[] = [];
  const blindSheets: Array<{ id: string; sheet: string }> = [];
  const answerKey: string[] = [];
  let completedArms = 0;
  for (const profile of PROFILES) {
    const userContent = compileTextOnlyUserContent(profile.profileInfo);
    const armRecords: Record<string, unknown>[] = [];
    results.push({
      profile: profile.id,
      shape: profile.shape,
      userContent,
      arms: armRecords,
    });
    const arms: ArmResult[] = [];
    // 付費證據增量保全：每臂成功當下就把「原始＋正規化＋usage/attempt」
    // 全量快照交給 onArmDone 落盤，後面 parse/provider/cap 炸掉不丟前臂。
    const finishArm = async (a: ArmResult) => {
      arms.push(a);
      armRecords.push({
        arm: a.arm,
        rawTexts: a.rawTexts,
        openers: a.openers,
        pick: a.pick,
        normalized: a.normalized,
      });
      completedArms++;
      await onArmDone({
        model: MODEL,
        httpAttempts: budget.used,
        maxHttpAttempts: budget.max,
        usage: { ...tally },
        completedArms,
        profiles: results,
      });
    };
    await finishArm(
      await runSingleCallArm("A", OPENER_PROMPT, transport, budget, userContent, tally),
    );
    await finishArm(
      await runSingleCallArm("B", CARDS_ONLY_PROMPT, transport, budget, userContent, tally),
    );
    await finishArm(await runArmC(transport, budget, userContent, tally));
    const { sheet, keyLines } = buildBlindSheet(profile, arms);
    blindSheets.push({ id: profile.id, sheet });
    answerKey.push(...keyLines);
  }
  return { results, blindSheets, answerKey };
}

// ── 盲評輸出 ───────────────────────────────────────────────────
function shuffled<T>(items: T[]): T[] {
  const arr = [...items];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

/** 推薦卡排最前，其餘依 canonical 序。 */
function orderedCards(result: ArmResult): Array<[string, string]> {
  const types = [...OPENER_TYPES] as string[];
  if (result.pick && types.includes(result.pick)) {
    types.splice(types.indexOf(result.pick), 1);
    types.unshift(result.pick);
  }
  return types
    .filter((t) => typeof result.openers[t] === "string")
    .map((t) => [t, result.openers[t]]);
}

function buildBlindSheet(
  profile: SyntheticProfile,
  arms: ArmResult[],
): { sheet: string; keyLines: string[] } {
  const order = shuffled(arms);
  const labels = ["甲", "乙", "丙"];
  const lines: string[] = [
    `# 盲評：${profile.id}`,
    "",
    `輸入形狀：${profile.shape}`,
    "",
    "```",
    compileTextOnlyUserContent(profile.profileInfo),
    "```",
    "",
    "每組第一張是該組自己的推薦卡。只評內容，組別標籤已洗牌。",
    "",
  ];
  const keyLines: string[] = [];
  order.forEach((result, i) => {
    const label = labels[i];
    keyLines.push(`${profile.id}：組${label} = ${result.arm} 臂`);
    lines.push(`## 組${label}`, "");
    for (const [type, text] of orderedCards(result)) {
      const star = type === result.pick ? "★推薦 " : "";
      lines.push(`- ${star}${text.replace(/\n/g, " ⏎ ")}`);
    }
    lines.push("");
  });
  return { sheet: lines.join("\n"), keyLines };
}

// ── 離線自檢（不讀 key、不打網路）──────────────────────────────
async function selfCheck(): Promise<void> {
  const handlerSrc = await Deno.readTextFile(
    new URL(
      "../../supabase/functions/analyze-chat/opener_handler.ts",
      import.meta.url,
    ),
  );
  await assertCompilerParity(handlerSrc);
  console.log("✓ parity guard：opener_handler.ts 三段 compiler 區段 digest 全符");

  // digest guard 負自檢：對真實源碼做插入／刪除／換序三種變異，全都要被抓
  const bioLine = "    if (bio) parts.push(`自我介紹：${bio}`);";
  const interestsLine = "    if (interests) parts.push(`興趣：${interests}`);";
  const mutations: Array<[string, string]> = [
    ["插入", handlerSrc.replace(bioLine, `${bioLine}\n    parts.push("注入的新行");`)],
    ["刪除", handlerSrc.replace(`${bioLine}\n`, "")],
    ["換序", handlerSrc.replace(
      `${bioLine}\n${interestsLine}`,
      `${interestsLine}\n${bioLine}`,
    )],
  ];
  for (const [kind, mutated] of mutations) {
    if (mutated === handlerSrc) {
      throw new Error(`digest guard 自檢：${kind}變異沒生效，自檢本身壞了`);
    }
    let caught = false;
    try {
      await assertCompilerParity(mutated);
    } catch {
      caught = true;
    }
    if (!caught) {
      throw new Error(`digest guard 沒抓到 compiler 區段的${kind}變異`);
    }
  }
  console.log("✓ digest guard 負自檢：插入／刪除／換序變異全數被擋");

  // 編譯器輸出形狀
  const compiled = compileTextOnlyUserContent(PROFILES[0].profileInfo);
  if (
    !compiled.startsWith("用戶提供的對方資訊：\n對方名字：測試甲\n自我介紹：") ||
    !compiled.endsWith("\n\n請根據以上可見資訊生成 5 種風格的開場白；只使用明確線索，不要補不存在的人格或共同點。")
  ) {
    throw new Error(`編譯器輸出形狀不符：\n${compiled}`);
  }
  const compiledSparse = compileTextOnlyUserContent(PROFILES[2].profileInfo);
  if (!compiledSparse.includes("興趣：看電影")) {
    throw new Error("sparse profile 沒把 interests 編進 user content");
  }
  console.log("✓ user-content 編譯器：規則牆與稀疏兩形狀輸出正確");

  // 假 transport：驗 16 次正常流程、每臂 checkpoint、C 臂 index-only
  const fakeOpeners = Object.fromEntries(
    OPENER_TYPES.map((t) => [t, `${t} 假開場白十個字`]),
  );
  const fakeBody = (text: string) => ({
    content: [{ type: "text", text }],
    usage: { input_tokens: 100, output_tokens: 50 },
  });
  const okTransport: Transport = (body) => {
    const sys = String(body.system);
    if (sys === SELECTOR_PROMPT) {
      return Promise.resolve(fakeBody(
        // recommend: 2 → OPENER_TYPES[2] = "tease"（數字編號，本地對映）
        JSON.stringify({ extend: 1, resonate: 0, tease: 2, humor: 0, coldRead: 1, recommend: 2 }),
      ));
    }
    if (sys === CANDIDATES_PROMPT) {
      return Promise.resolve(fakeBody(JSON.stringify(
        Object.fromEntries(
          OPENER_TYPES.map((t) => [t, [0, 1, 2].map((i) => `${t} 候選${i} 假字串`)]),
        ),
      )));
    }
    return Promise.resolve(fakeBody(
      JSON.stringify({ openers: fakeOpeners, recommendation: { pick: "extend", reason: "測試" } }),
    ));
  };

  const budget = new AttemptBudget(MAX_HTTP_ATTEMPTS);
  const tally: Usage = { inputTokens: 0, outputTokens: 0 };
  const checkpoints: RunSnapshot[] = [];
  const { results } = await runAllProfiles(okTransport, budget, tally, (snap) => {
    // 深拷貝：驗的是「當下落盤內容」，不是跑完後的同一參照
    checkpoints.push(JSON.parse(JSON.stringify(snap)));
    return Promise.resolve();
  });
  if (budget.used !== 16) {
    throw new Error(`正常一輪應為 16 次呼叫，實際 ${budget.used}`);
  }
  if (tally.inputTokens !== 1600 || tally.outputTokens !== 800) {
    throw new Error(`token 統計不符：${JSON.stringify(tally)}`);
  }
  const firstArms = (results[0] as { arms: Array<Record<string, unknown>> }).arms;
  const [a, b, c] = firstArms;
  if (a.pick !== "extend" || !(a.openers as Record<string, string>).coldRead) {
    throw new Error("A 臂假流程解析失敗");
  }
  if (b.pick !== "extend" || !b.normalized) throw new Error("B 臂假流程解析失敗");
  // index-only 逐字保留：乾淨候選經生產 normalizer 應原樣；recommend 編號對映 canonical
  if ((c.openers as Record<string, string>).extend !== "extend 候選1 假字串") {
    throw new Error(`C 臂選擇未逐字保留：${JSON.stringify((c.openers as Record<string, string>).extend)}`);
  }
  if (c.pick !== "tease") {
    throw new Error(`C 臂 recommend 編號未對映到 canonical OPENER_TYPES：${JSON.stringify(c.pick)}`);
  }
  if (!c.normalized) throw new Error("C 臂沒保留 normalizeOpenerPayload 輸出");
  console.log("✓ 三臂假流程：16 次呼叫、C 臂 index-only 逐字保留＋recommend 編號對映、token 統計正確");

  // checkpoint：每臂一個、內容含原始＋正規化＋usage/attempt、鍵面固定無金鑰欄位
  if (checkpoints.length !== 12) {
    throw new Error(`應有 12 個 checkpoint（4 profile × 3 臂），實際 ${checkpoints.length}`);
  }
  const first = checkpoints[0];
  const firstArm = (first.profiles[0] as { arms: Array<Record<string, unknown>> }).arms[0];
  if (
    first.completedArms !== 1 || first.profiles.length !== 1 ||
    !Array.isArray(firstArm.rawTexts) || firstArm.rawTexts.length === 0 ||
    !firstArm.normalized || first.usage.inputTokens !== 100 || first.httpAttempts !== 1
  ) {
    throw new Error(`第 1 個 checkpoint 內容不完整：${JSON.stringify(first).slice(0, 200)}`);
  }
  const last = checkpoints[11];
  if (last.completedArms !== 12 || last.profiles.length !== 4 || last.httpAttempts !== 16) {
    throw new Error("最後一個 checkpoint 未含全量資料");
  }
  const allowedKeys = ["model", "httpAttempts", "maxHttpAttempts", "usage", "completedArms", "profiles"];
  const extraneous = Object.keys(last).filter((k) => !allowedKeys.includes(k));
  if (extraneous.length > 0) {
    throw new Error(`checkpoint 出現非白名單頂層鍵（金鑰外洩防線）：${extraneous.join(", ")}`);
  }
  console.log("✓ checkpoint：每臂成功即快照、含原始＋正規化＋usage/attempt、頂層鍵面固定");

  // 中途失敗不丟已完成臂：第 5 次呼叫（profile 2 的 A 臂）炸掉，前 3 臂 checkpoint 要在
  {
    let calls = 0;
    const failingTransport: Transport = (body) => {
      calls++;
      if (calls > 4) return Promise.resolve({ error: { type: "invalid_request_error" } });
      return okTransport(body);
    };
    const partial: RunSnapshot[] = [];
    let failed = false;
    try {
      await runAllProfiles(
        failingTransport,
        new AttemptBudget(MAX_HTTP_ATTEMPTS),
        { inputTokens: 0, outputTokens: 0 },
        (snap) => {
          partial.push(JSON.parse(JSON.stringify(snap)));
          return Promise.resolve();
        },
      );
    } catch {
      failed = true;
    }
    if (!failed) throw new Error("中途失敗自檢：預期第 5 次呼叫失敗卻沒失敗");
    if (partial.length !== 3 || partial[2].completedArms !== 3) {
      throw new Error(`中途失敗後前 3 臂 checkpoint 沒保住：${partial.length} 個`);
    }
  }
  console.log("✓ checkpoint 中途失敗自檢：後臂炸掉不丟前臂已落盤快照");

  // A/B 完整性負自檢：正規化後缺卡／超長被清／pick 不合法都必須炸
  const negativeBodies: Array<[string, Record<string, unknown>]> = [
    ["缺一卡", {
      openers: Object.fromEntries(
        OPENER_TYPES.filter((t) => t !== "coldRead").map((t) => [t, `${t} 假開場白`]),
      ),
      recommendation: { pick: "extend" },
    }],
    // 超長卡（>180 字）會被生產 sanitizer 清掉：黑箱不得拿原文生食比較
    ["超長卡被清", {
      openers: { ...fakeOpeners, humor: "超".repeat(200) },
      recommendation: { pick: "extend" },
    }],
    ["pick 不合法", { openers: fakeOpeners, recommendation: { pick: "banana" } }],
    ["缺 recommendation", { openers: fakeOpeners }],
  ];
  for (const [kind, payload] of negativeBodies) {
    const t: Transport = () => Promise.resolve(fakeBody(JSON.stringify(payload)));
    let caught = false;
    try {
      await runSingleCallArm("A", OPENER_PROMPT, t, new AttemptBudget(3), "x", {
        inputTokens: 0,
        outputTokens: 0,
      });
    } catch {
      caught = true;
    }
    if (!caught) throw new Error(`A/B 完整性負自檢沒擋住：${kind}`);
  }
  console.log("✓ A/B 完整性負自檢：缺卡／超長被清／pick 不合法全數被擋");

  // C 臂負自檢：被選中的超長候選會被生產 sanitizer 清掉→必須炸（不生食）
  {
    const longCandidates = Object.fromEntries(
      OPENER_TYPES.map((t) => [t, [0, 1, 2].map((i) => `${t} 候選${i} 假字串`)]),
    ) as Record<string, string[]>;
    longCandidates.humor[0] = "長".repeat(200);
    const t: Transport = (body) => {
      if (String(body.system) === CANDIDATES_PROMPT) {
        return Promise.resolve(fakeBody(JSON.stringify(longCandidates)));
      }
      return Promise.resolve(fakeBody(
        JSON.stringify({ extend: 0, resonate: 0, tease: 0, humor: 0, coldRead: 0, recommend: 0 }),
      ));
    };
    let caught = false;
    try {
      await runArmC(t, new AttemptBudget(4), "x", { inputTokens: 0, outputTokens: 0 });
    } catch {
      caught = true;
    }
    if (!caught) throw new Error("C 臂超長候選未被完整性檢查擋下（生食比較風險）");
  }
  // C 臂正自檢：待清洗內容（連續空行）比較用的是 normalizer 輸出，不是原文
  {
    const dirtyCandidates = Object.fromEntries(
      OPENER_TYPES.map((t) => [t, [0, 1, 2].map((i) => `${t} 候選${i} 假字串`)]),
    ) as Record<string, string[]>;
    dirtyCandidates.extend[0] = "線索一\n\n\n線索二";
    const t: Transport = (body) => {
      if (String(body.system) === CANDIDATES_PROMPT) {
        return Promise.resolve(fakeBody(JSON.stringify(dirtyCandidates)));
      }
      return Promise.resolve(fakeBody(
        JSON.stringify({ extend: 0, resonate: 0, tease: 0, humor: 0, coldRead: 0, recommend: 0 }),
      ));
    };
    const cDirty = await runArmC(t, new AttemptBudget(4), "x", { inputTokens: 0, outputTokens: 0 });
    if (cDirty.openers.extend !== "線索一\n線索二") {
      throw new Error(`C 臂比較內容未經生產 normalizer（生食）：${JSON.stringify(cDirty.openers.extend)}`);
    }
  }
  console.log("✓ C 臂 normalizer 自檢：超長候選被擋、待清洗內容以正規化後版本比較");

  // 選擇器負自檢：任何字串（風格名稱、改寫句）或越界編號一律拒收
  {
    const cands = Object.fromEntries(
      OPENER_TYPES.map((t) => [t, ["候選零", "候選一", "候選二"]]),
    ) as Record<OpenerType, string[]>;
    const badSelections: Record<string, unknown>[] = [
      { extend: 0, resonate: 0, tease: 0, humor: 0, coldRead: 0, recommend: "tease" },
      { extend: 0, resonate: 0, tease: 0, humor: 0, coldRead: 0, recommend: 5 },
      { extend: 3, resonate: 0, tease: 0, humor: 0, coldRead: 0, recommend: 0 },
      { extend: "改寫過的句子", resonate: 0, tease: 0, humor: 0, coldRead: 0, recommend: 0 },
    ];
    for (const parsed of badSelections) {
      let caught = false;
      try {
        applySelection(cands, parsed);
      } catch {
        caught = true;
      }
      if (!caught) {
        throw new Error(`選擇器負自檢沒擋住：${JSON.stringify(parsed)}`);
      }
    }
  }
  console.log("✓ 選擇器負自檢：字串 recommend／越界編號／改寫句全數拒收");

  // 24 上限：永遠回 overloaded 的 transport 必須在硬上限處 throw
  const alwaysOverloaded: Transport = () =>
    Promise.resolve({ error: { type: "overloaded_error" } });
  // 預算 2 小於單一呼叫的最大 attempt 數 3：第三次 take 必撞硬上限。
  const smallBudget = new AttemptBudget(2);
  const origSetTimeout = globalThis.setTimeout;
  // 自檢不真等 5 秒：立即觸發
  // deno-lint-ignore no-explicit-any
  (globalThis as any).setTimeout = (fn: () => void) => origSetTimeout(fn, 0);
  let capHit = false;
  try {
    await callModel(alwaysOverloaded, smallBudget, "x", "y", { inputTokens: 0, outputTokens: 0 });
  } catch (e) {
    capHit = String(e).includes("上限");
  } finally {
    globalThis.setTimeout = origSetTimeout;
  }
  if (!capHit || smallBudget.used !== 2) {
    throw new Error(`attempt 上限未生效：used=${smallBudget.used}`);
  }
  console.log("✓ 全域 attempt 硬上限：連續暫時性錯誤在上限處停跑");

  // 盲評表：三組都在、推薦卡在最前、answer key 分開
  const fakeResults: ArmResult[] = [
    { arm: "A", rawTexts: ["r"], openers: { ...fakeOpeners }, pick: "humor", normalized: null },
    { arm: "B", rawTexts: ["r"], openers: { ...fakeOpeners }, pick: "tease", normalized: null },
    { arm: "C", rawTexts: ["r", "s"], openers: { ...fakeOpeners }, pick: null, normalized: null },
  ];
  const { sheet, keyLines } = buildBlindSheet(PROFILES[1], fakeResults);
  if (!sheet.includes("## 組甲") || !sheet.includes("## 組丙")) throw new Error("盲評表缺組");
  if (sheet.includes(" A 臂") || sheet.includes("= B")) throw new Error("盲評表洩漏臂標籤");
  const humorFirst = sheet.split("★推薦 humor")[0];
  if (keyLines.length !== 3) throw new Error("answer key 行數不對");
  if (humorFirst === sheet) throw new Error("推薦卡未標星");
  console.log("✓ 盲評表：標籤洗牌不洩漏、推薦卡標星、answer key 另存");

  console.log("\n✓ 離線自檢全過（0 次網路呼叫、未讀任何金鑰）");
}

// ── 實跑 ───────────────────────────────────────────────────────
async function liveRun(): Promise<void> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
  if (!apiKey) {
    console.error("實跑需要 ANTHROPIC_API_KEY（以及 --live 旗標）");
    Deno.exit(2);
  }
  await sourceParityGuard();

  const transport: Transport = async (body) => {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify(body),
    });
    return await res.json();
  };

  const budget = new AttemptBudget(MAX_HTTP_ATTEMPTS);
  const tally: Usage = { inputTokens: 0, outputTokens: 0 };
  const ts = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const outDir = new URL(`out/run-${ts}/`, import.meta.url);
  await Deno.mkdir(new URL("blind/", outDir), { recursive: true });
  const checkpointUrl = new URL("checkpoint.json", outDir);

  const { results, blindSheets, answerKey } = await runAllProfiles(
    transport,
    budget,
    tally,
    async (snap) => {
      // 每臂成功即整包落盤（原始＋正規化＋usage/attempt，無金鑰欄位）：
      // 後面炸掉，已付費的產出都還在 checkpoint.json。
      await Deno.writeTextFile(checkpointUrl, JSON.stringify(snap, null, 2));
      console.log(
        `  checkpoint：${snap.completedArms}/12 臂完成（attempt ${snap.httpAttempts}/${snap.maxHttpAttempts}）已落盤`,
      );
    },
  );

  for (const { id, sheet } of blindSheets) {
    await Deno.writeTextFile(new URL(`blind/${id}.md`, outDir), sheet);
  }
  await Deno.writeTextFile(
    new URL("results.json", outDir),
    JSON.stringify(
      {
        model: MODEL,
        httpAttempts: budget.used,
        maxHttpAttempts: budget.max,
        usage: tally,
        profiles: results,
      },
      null,
      2,
    ),
  );
  await Deno.writeTextFile(
    new URL("answer-key.md", outDir),
    ["# Answer key（盲評後再看）", "", ...answerKey, ""].join("\n"),
  );
  console.log(
    `\n完成：${budget.used} 次 HTTP attempt（上限 ${budget.max}）、` +
      `input ${tally.inputTokens} tokens、output ${tally.outputTokens} tokens`,
  );
  console.log(`輸出：${outDir.pathname}（blind/ 先看、answer-key.md 評完再看）`);
}

// ── 入口 ───────────────────────────────────────────────────────
if (import.meta.main) {
  if (Deno.args.includes("--self-check")) {
    await selfCheck();
  } else if (Deno.args.includes("--live")) {
    await liveRun();
  } else {
    console.error(
      "用法：--self-check（離線，不讀 key）或 --live（需 ANTHROPIC_API_KEY，會產生費用）",
    );
    Deno.exit(2);
  }
}
