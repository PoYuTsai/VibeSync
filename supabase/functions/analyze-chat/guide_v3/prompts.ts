// 兩段的提示詞組裝。說明書原文在 guide_text.ts、entries.ts；這裡只排順序與帶入這一輪的資料，
// 輸出格式只有佔位符、沒有可以照抄的中文句子。
import { GUIDE_V3_ENTRIES, type GuideV3Entry } from "./entries.ts";
import { GUIDE_V3_SECTIONS, type GuideV3SectionId } from "./guide_text.ts";
import type { ReadTags } from "./read_tags.ts";
import type { CardSpec, PushAction } from "./rules.ts";
import { transcriptByTurn, type Turn } from "./turns.ts";
import { SAFETY_RULES } from "../guardrails.ts";
import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "../../_shared/prompt_leak_guard.ts";

const READ_FIELD_NOTES = `## 要輸出的欄位
- light：照上面的燈號表。
- herMove：她最新這一輪在做什麼，照上面的十一類擇一。
- inviteReadiness：照上面的邀約準備度；另外加「猶豫」：邀約後她說不確定、還在想、看情況。
- cancelHasAlternative：她取消約會時有沒有給別的時間；沒取消就 false。
- declinedOrBoundary：她這一輪婉拒邀約、說忙或改天但沒給時間，或說了界線。
- explicitRejection：她明確拒絕（說法客氣、但意思明確也算）。「先當朋友」「最近不想談感情」不算；她只是說自己有男友也不算（照情境條目 B18 接）。
- blocked：用戶說了被封鎖，或對話看得出來。
- risk：上面說的風險（剛認識就熱得不合理，或只在要他花錢、送禮、幫忙時才熱）。
- selfHarmSignal：對話裡有人（她或他）認真表達想自殺、自傷或不想活了；「笑死」「累死了」「熱到想死」這類誇張說法不算。
- retreating：她有沒有在退、說不或要放慢。
- needsHisFacts：要回好這一輪，需要他本人的事實。
- identityQuestion：她問的是工作、年紀、身高、感情狀態、住哪。
- hisStatedFacts：他在對話裡自己說過的事，逐字摘出；沒有就空陣列。
- hasHisVoiceSample：對話裡有他自己傳的訊息，可以當口吻參考。
- replyWillingness：只看她有沒有延伸、反問、補內容。
- worthyBallCount：她最新這一輪值得接的球有幾顆。
- herTurnsPerfunctory：她最近最多 4 輪，每輪是不是只回敷衍的字（例如只回哈哈、嗯）；turn 用對話裡的輪次編號。
- matchedEntries：下面情境條目的觸發，符合的填編號；都不符合就空陣列。
- readForUser：給用戶看的局面判讀，一兩句白話。
- waitFor：如果這一輪該先等她，要等她做什麼才回，一句；不用等就空字串。`;

export function readSystemPrompt(
  sections: Readonly<Record<GuideV3SectionId, string>> = GUIDE_V3_SECTIONS,
  entries: readonly GuideV3Entry[] = GUIDE_V3_ENTRIES,
  leakDirective: string = PROMPT_LEAK_DEFENSE_DIRECTIVE,
): string {
  const triggers = entries.filter((e) => e.enabled).map((e) =>
    `- ${e.id}：${e.trigger}`
  ).join("\n");
  return [
    "你是 VibeSync 對話分析的「讀局面」步驟：只讀對話、輸出標記，不寫回覆。要不要回、要不要約由程式決定。",
    sections.A3,
    sections.A4,
    READ_FIELD_NOTES,
    `## 情境條目的觸發（只回符合的編號）\n${triggers}`,
    // readForUser、waitFor 是直接給用戶看的文字。
    leakDirective.trim(),
  ].join("\n\n");
}

/// App 送來的背景（A3：都不是她這次說的話，只拿來判斷局面）。空的欄位不放。
export interface GuideV3Background {
  readonly meetingContext?: string;
  readonly duration?: string;
  readonly goal?: string;
  readonly targetDescription?: string;
  readonly analysisContextNote?: string;
  readonly partnerSummary?: string;
  readonly conversationSummary?: string;
}

function filled(value: string | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

export function backgroundSections(
  background: GuideV3Background | undefined,
): string[] {
  if (!background) return [];
  const tagLines = ([
    ["怎麼認識", background.meetingContext],
    ["認識多久", background.duration],
    ["他的目標", background.goal],
    ["對象描述", background.targetDescription],
    ["他補充的情況", background.analysisContextNote],
  ] as const).flatMap(([label, value]) => {
    const text = filled(value);
    return text ? [`- ${label}：${text}`] : [];
  });
  const partner = filled(background.partnerSummary);
  const earlier = filled(background.conversationSummary);
  return [
    ...(tagLines.length > 0 ? [`## 作戰板標籤\n${tagLines.join("\n")}`] : []),
    ...(partner ? [`## 對象背景\n${partner}`] : []),
    ...(earlier ? [`## 更早的對話摘要\n${earlier}`] : []),
  ];
}

export function readUserPrompt(
  turns: readonly Turn[],
  background?: GuideV3Background,
): string {
  return [
    ...backgroundSections(background),
    `## 對話\n${transcriptByTurn(turns)}`,
  ].join("\n\n");
}

export const WRITE_OUTPUT_FORMAT = `## 輸出格式
每張卡輸出一行 JSON，照卡片編號順序，一行一張，不要其他文字、不要 Markdown：
{"card": <卡片編號>, "messages": ["<第 1 則>", "<第 2 則，可省略>"], "hasInventedDetail": <true 或 false>}
- messages 1–3 則；需要他填的地方用「＿＿」。
- 只有「照樣寫＋標示」和「留空格」的卡可以寫他的經歷或狀態，編出來的細節要把 hasInventedDetail 設成 true；其他卡一律 false，也不能編。`;

export function writeSystemPrompt(
  sections: Readonly<Record<GuideV3SectionId, string>> = GUIDE_V3_SECTIONS,
  safetyRules: string = SAFETY_RULES,
  leakDirective: string = PROMPT_LEAK_DEFENSE_DIRECTIVE,
): string {
  return [
    "你是 VibeSync 對話分析的「寫句子」步驟：照使用者訊息裡每張卡的規格，寫他可以直接傳給她的訊息。",
    sections.A1,
    sections.A2,
    sections.A3,
    sections.A5,
    sections.A6,
    WRITE_OUTPUT_FORMAT,
    safetyRules.trim(),
    leakDirective.trim(),
  ].join("\n\n");
}

const PUSH_NOTE: Record<PushAction, string> = {
  種子: "推進（種子）",
  具體邀約: "推進（具體邀約）",
  說定: "推進（她答應了，把時間地點說定）",
  改天: "推進（她取消了、沒給別的時間：輕鬆接受，提一次改天，不用馬上給時間）",
  換地方:
    "推進（她堅持要去她指定的店：由他提別的時間、地點，不答應去那家；用陳述句收尾，不問她方不方便、可不可以）",
};

export function cardSpecLine(spec: CardSpec, n: number): string {
  const task = spec.push ? PUSH_NOTE[spec.push] : spec.task;
  // v3.2（Bruce 10/14）：留空格的卡也可以編別的細節，但要標示；身分資料仍只能留空格。
  const method = spec.method === "留空格"
    ? "留空格（需要他的事實用＿＿；工作、年紀、身高、感情狀態、住哪只能留空格；空格以外編出來的細節要標示）"
    : spec.method;
  const parts = [
    `${n}. 任務：${task}`,
    `「有他」做法：${method}`,
    `口吻：${spec.voice}`,
    spec.questionBudget === 0 ? "不問問題" : "問句最多 1 個",
  ];
  if (spec.angle > 0) parts.push("切入點要跟前面同規格的卡不同");
  return parts.join("｜");
}

export function writeUserPrompt(args: {
  readonly turns: readonly Turn[];
  readonly tags: ReadTags;
  readonly entries: readonly GuideV3Entry[];
  readonly cards: readonly CardSpec[];
  readonly background?: GuideV3Background;
}): string {
  const facts = args.tags.hisStatedFacts.length > 0
    ? args.tags.hisStatedFacts.map((f) => `- ${f}`).join("\n")
    : "（沒有）";
  const entries = args.entries.length > 0
    ? args.entries.map((e) => `- ${e.id}（${e.trigger}）：${e.writing}`).join(
      "\n",
    )
    : "（這一輪沒有）";
  return [
    ...backgroundSections(args.background),
    `## 對話\n${transcriptByTurn(args.turns)}`,
    `## 他在對話裡說過的自己的事\n${facts}`,
    `## 這一輪的情境做法\n${entries}`,
    `## 卡片規格（照順序寫，一共 ${args.cards.length} 張）\n${
      args.cards.map((c, i) => cardSpecLine(c, i + 1)).join("\n")
    }`,
  ].join("\n\n");
}
