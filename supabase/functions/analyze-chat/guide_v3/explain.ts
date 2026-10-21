// 兩段式「正常回覆」實驗的第三次呼叫（開關 ANALYZE_GUIDE_V3_TWO_STAGE，Eric 2026-10-19 兩段式實驗）：
// 卡都定稿送出之後，用說明書替每張卡寫一兩句「為什麼這樣回」給用戶看（Bruce 10/19「先生成回覆，
// 再用說明書的內容來教」；Eric「教用戶 Chris 的紅藥丸，說明為什麼」）。寫卡拿掉的 A1、「每張卡都要
// 有他的態度」、快檢「有他」與帶張力原本的定義，都在這一步看得到。失敗只是沒有說明：卡與扣費不變。
import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "../../_shared/prompt_leak_guard.ts";
import type { GuideV3Entry } from "./entries.ts";
import { GUIDE_V3_SECTIONS, type GuideV3SectionId } from "./guide_text.ts";
import { vetCoachText } from "./finalize.ts";
import type { LIGHTS, ReadTags } from "./read_tags.ts";
import type { CardSpec, HisMethod, PraiseStyle, Task } from "./rules.ts";
import { cardTaskText } from "./prompts.ts";
import {
  applyLineEdits,
  HAPPY_SHARE_TASK,
  praiseSection,
  specAnswerParts,
  TENSION_STYLE_A5_EDITS,
  TWO_STAGE_A5_EDITS,
  TWO_STAGE_METHOD_LABEL,
} from "./two_stage_prompts.ts";

/// 說明步驟的結構化輸出（json_schema）：每張卡一段。
export const EXPLAIN_SCHEMA: Record<string, unknown> = {
  type: "object",
  additionalProperties: false,
  required: ["explanations"],
  properties: {
    explanations: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["card", "text"],
        properties: {
          card: { type: "integer" },
          text: { type: "string" },
        },
      },
    },
  },
};

const EXPLAIN_ROLE =
  "你是 VibeSync 對話分析的「說明」步驟：回覆卡已經寫好、也給用戶看了，你替每張卡寫一段「為什麼這樣回」，讓用戶看懂這樣回的道理，下次自己也會。";

const EXPLAIN_RULES = `## 說明怎麼寫
- 寫給用戶本人看：稱他「你」，對象稱「她」。
- 每張卡寫 1–2 句白話的繁體中文：先講這張接住了她的哪一點，再講這樣回在兩人之間起什麼作用。
- 道理從下面的說明書來，但要換成一般人聽得懂的白話：不寫段落代號或條目編號，不整句照抄說明書；真的要用說明書裡的名稱，放在括號裡。
- 只講卡片實際寫到的東西：不改寫卡片、不另外建議怎麼回，也不替卡片多加意思。
- 她的話只在講清楚時才引，幾個字就好；不評斷她這個人，講她的意思時只講判讀看得出來的。
- 自己說收到、收下或記下，評她的語氣、用字、貼圖或表情，被她誇時順勢誇自己，該直接誇時還繞彎吊著她：這些都不算優點，說明不誇、也不替它們找理由；卡片剛好有的話，只講它其他做對的地方。`;

/// 帶張力改寫法 v2（Bruce 2026-10-21「改」）開時說明多的一條：說明跟寫卡用同一把尺（寫卡那三條不要），不把
/// 打分、說她用意、擺架子講成優點。
export const TENSION_STYLE_EXPLAIN_RULE =
  "- 帶張力的卡：替她打分、說她別有用意、把自己擺得比較厲害，都不算優點，說明不誇。";

/// 上面那一條的外洩哨兵（開關開才比）。
export const TENSION_STYLE_EXPLAIN_SENTINELS: readonly string[] = [
  "帶張力的卡：替她打分",
];

const EXPLAIN_FORMAT = `## 輸出格式
只輸出 JSON：{"explanations": [{"card": <卡片編號>, "text": "<這張的說明>"}]}，每張卡一項，照卡片編號。`;

/// 說明步驟自己的外洩哨兵（說明書每節第一行的哨兵另由 vetCoachText 一起查）。
export const EXPLAIN_SENTINELS: readonly string[] = [
  "VibeSync 對話分析的「說明」步驟",
  "道理從下面的說明書來",
  "說明書（道理的來源）",
  "也不替它們找理由",
];

/// A5 以粗體小標分段（任務、「有他」做法、口吻、她丟來的球、曖昧、每張卡都要做到）。
export function a5Blocks(
  a5: string = GUIDE_V3_SECTIONS.A5,
): ReadonlyMap<string, string> {
  const blocks = new Map<string, string[]>();
  let current: string[] | null = null;
  for (const line of a5.split("\n")) {
    const header = line.match(/^\*\*(.+)\*\*$/)?.[1];
    if (header) {
      current = [line];
      blocks.set(header, current);
    } else if (current) current.push(line);
  }
  return new Map(
    [...blocks].map(([k, v]) => [k, v.join("\n").trim()] as const),
  );
}

/// 不分卡都用得到的 A5 段落（放系統提示詞，可以快取）；任務與「有他」做法放使用者訊息，
/// 只帶這一輪的卡用到的。
const EXPLAIN_A5_BLOCKS = ["她丟來的球，接法和理由", "曖昧", "每張卡都要做到"];

function requiredBlock(
  blocks: ReadonlyMap<string, string>,
  name: string,
): string {
  const block = blocks.get(name);
  if (!block) throw new Error(`explain: A5 block missing: ${name}`);
  return block;
}

export function explainSystemPrompt(
  sections: Readonly<Record<GuideV3SectionId, string>> = GUIDE_V3_SECTIONS,
  leakDirective: string = PROMPT_LEAK_DEFENSE_DIRECTIVE,
  /// 帶張力改寫法開時，說明怎麼寫多一條（TENSION_STYLE_EXPLAIN_RULE）。
  options: { readonly tensionStyle?: boolean } = {},
): string {
  const blocks = a5Blocks(sections.A5);
  return [
    EXPLAIN_ROLE,
    options.tensionStyle
      ? `${EXPLAIN_RULES}\n${TENSION_STYLE_EXPLAIN_RULE}`
      : EXPLAIN_RULES,
    "## 說明書（道理的來源）",
    sections.A1,
    [
      "### A5 寫句子（節錄）",
      ...EXPLAIN_A5_BLOCKS.map((name) => requiredBlock(blocks, name)),
    ].join("\n\n"),
    sections.A6,
    EXPLAIN_FORMAT,
    leakDirective.trim(),
  ].join("\n\n");
}

/// A5 裡以「- **名稱**：」開頭的那一條，連同底下縮排的子項目。
export function a5Bullet(
  name: Task | HisMethod,
  a5: string = GUIDE_V3_SECTIONS.A5,
): string {
  const lines = a5.split("\n");
  const at = lines.findIndex((l) => l.startsWith(`- **${name}**：`));
  if (at === -1) throw new Error(`explain: A5 bullet missing: ${name}`);
  const out = [lines[at]];
  for (let i = at + 1; i < lines.length && lines[i].startsWith("  - "); i++) {
    out.push(lines[i]);
  }
  return out.join("\n");
}

const LIGHT_TEXT: Record<typeof LIGHTS[number], string> = {
  green: "綠燈",
  yellow: "黃燈",
  red: "紅燈",
};

export interface ExplainCard {
  /// 送給 App 的卡片編號（analysis.card 的 slot）。
  readonly slot: number;
  readonly spec: CardSpec;
  readonly messages: readonly string[];
}

export function explainUserPrompt(args: {
  readonly tags: Pick<ReadTags, "light" | "herMove" | "readForUser">;
  readonly herLatest: readonly string[];
  readonly entries: readonly GuideV3Entry[];
  readonly cards: readonly ExplainCard[];
  readonly a5?: string;
  /// 寫卡看到的那一句稱讚（第 2 輪）：說明跟寫卡用同一把尺，不會把直接誇講成給太滿。
  readonly praise?: PraiseStyle;
  /// 帶張力改寫法開時：帶張力那一條改用寫卡看到的新寫法（其他任務與做法照說明書原文）。
  readonly tensionStyle?: boolean;
}): string {
  const a5 = args.a5 ?? GUIDE_V3_SECTIONS.A5;
  const her = args.herLatest.length > 0
    ? args.herLatest.map((m, i) => `${i + 1}. ${m}`).join("\n")
    : "（沒有）";
  // 條目不帶編號（不讓編號出現在說明裡）。
  const entries = args.entries.length > 0
    ? args.entries.map((e) => `- ${e.trigger}：${e.writing}`).join("\n")
    : "（這一輪沒有）";
  const cards = args.cards.map(({ slot, spec, messages }) => {
    const head = [
      `任務：${
        spec.note === "happy_share" ? HAPPY_SHARE_TASK : cardTaskText(spec)
      }`,
      `${TWO_STAGE_METHOD_LABEL}：${spec.method}`,
      ...specAnswerParts(spec, args.herLatest),
    ].join("｜");
    return [
      `### 第 ${slot} 張`,
      head,
      ...messages.map((m) => `- ${m}`),
    ].join("\n");
  });
  const used = [
    ...new Set(args.cards.flatMap(({ spec }) => [spec.task, spec.method])),
  ];
  return [
    [
      "## 這一輪的局面",
      `- 燈號：${LIGHT_TEXT[args.tags.light]}`,
      `- 她這一輪在做什麼：${args.tags.herMove}`,
      `- 判讀：${args.tags.readForUser.trim() || "（沒有）"}`,
    ].join("\n"),
    ...(args.praise ? [praiseSection(args.praise)] : []),
    `## 她最新這一輪\n${her}`,
    `## 這一輪的情境做法\n${entries}`,
    `## 寫好的卡（一共 ${args.cards.length} 張）\n\n${cards.join("\n\n")}`,
    `## 這幾張卡用到的任務與做法（說明書原文）\n${
      used.map((name) =>
        args.tensionStyle && name === "帶張力"
          ? a5Bullet(
            name,
            applyLineEdits(
              applyLineEdits(a5, TWO_STAGE_A5_EDITS),
              TENSION_STYLE_A5_EDITS,
            ),
          )
          : a5Bullet(name, a5)
      ).join("\n")
    }`,
  ].join("\n\n");
}

/// 結構化輸出照理不會壞；壞了回 null（整次沒有說明）。同一張出現兩次只用第一段。
export function parseExplanations(text: string): Map<number, string> | null {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return null;
  }
  const list = (value as { explanations?: unknown } | null)?.explanations;
  if (!Array.isArray(list)) return null;
  const out = new Map<number, string>();
  for (const item of list) {
    const card = (item as { card?: unknown } | null)?.card;
    const body = (item as { text?: unknown } | null)?.text;
    if (!Number.isInteger(card) || typeof body !== "string") return null;
    if (!out.has(card as number)) out.set(card as number, body);
  }
  return out;
}

export type ExplainRemovalReason =
  | "missing"
  | "empty"
  | "blocked"
  | "internal_id"
  | "too_long";

/// 一兩句的上限（字數照 code point 算）；超過就這張不給說明。
export const EXPLAIN_MAX_CHARS = 140;
/// 說明書的段落、條目、規則代號（A1、B22、C4 這類）。
const INTERNAL_ID = /(?<![A-Za-z0-9])[A-D]\d{1,2}(?![0-9])/;

/// 跟判讀一樣過外洩、注入與不安全樣式的檢查（vetCoachText，含說明書每節的哨兵），再加說明
/// 步驟自己的哨兵、內部代號與長度。
export function vetExplanation(
  raw: string,
  /// 開關開了才多的說明規則的哨兵（帶張力改寫法：TENSION_STYLE_EXPLAIN_SENTINELS）；沒給就跟今天一樣。
  extraSentinels: readonly string[] = [],
): { ok: true; text: string } | { ok: false; reason: ExplainRemovalReason } {
  if (!raw.trim()) return { ok: false, reason: "empty" };
  const vetted = vetCoachText(
    raw,
    extraSentinels.length > 0
      ? [...EXPLAIN_SENTINELS, ...extraSentinels]
      : EXPLAIN_SENTINELS,
  );
  if (!vetted.ok) return { ok: false, reason: "blocked" };
  if (!vetted.text) return { ok: false, reason: "empty" };
  if (INTERNAL_ID.test(raw) || INTERNAL_ID.test(vetted.text)) {
    return { ok: false, reason: "internal_id" };
  }
  if ([...vetted.text].length > EXPLAIN_MAX_CHARS) {
    return { ok: false, reason: "too_long" };
  }
  return { ok: true, text: vetted.text };
}
