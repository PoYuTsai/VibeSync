// 第二段（寫卡）的輸出：一行一張卡的解析、預設口吻把「妳」換成「你」，以及說明書 C5
// 只記錄、不擋卡的字眼檢查。
import type { CardSpec } from "./rules.ts";

export interface WrittenCard {
  readonly card: number;
  readonly messages: readonly string[];
  readonly hasInventedDetail: boolean;
  readonly expectedReaction: string;
}

/// 一行一張卡的 JSON；不是合法的卡回 null。
export function parseWrittenCardLine(raw: string): WrittenCard | null {
  const line = raw.trim();
  if (!line) return null;
  try {
    // deno-lint-ignore no-explicit-any
    const v: any = JSON.parse(line);
    const messages = Array.isArray(v?.messages)
      ? v.messages.filter((m: unknown) =>
        typeof m === "string" && m.trim() !== ""
      )
      : [];
    if (!Number.isInteger(v?.card) || messages.length === 0) return null;
    return {
      card: v.card,
      messages,
      hasInventedDetail: v.hasInventedDetail === true,
      expectedReaction: typeof v.expectedReaction === "string"
        ? v.expectedReaction
        : "",
    };
  } catch {
    return null;
  }
}

/// 一行一張卡的 JSON；壞掉的行略過（記在 invalidLines）。
export function parseWrittenCards(
  text: string,
): { cards: WrittenCard[]; invalidLines: number } {
  const cards: WrittenCard[] = [];
  let invalidLines = 0;
  for (const raw of text.split(/\r?\n/)) {
    if (!raw.trim()) continue;
    const card = parseWrittenCardLine(raw);
    if (card) cards.push(card);
    else invalidLines++;
  }
  cards.sort((a, b) => a.card - b.card);
  return { cards, invalidLines };
}

/// 串流用：把文字片段切成完整的行；最後沒換行的那段由 flush 交出。
export function createLineSplitter(): {
  push(chunk: string): string[];
  flush(): string[];
} {
  let buffer = "";
  return {
    push(chunk) {
      buffer += chunk;
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop() ?? "";
      return lines.filter((line) => line.trim() !== "");
    },
    flush() {
      const rest = buffer;
      buffer = "";
      return rest.trim() ? [rest] : [];
    },
  };
}

/// v3 A5：預設口吻的稱呼一律用「你」。模型常照對話寫成「妳」（10/14 第一輪 41/108 張），
/// 由程式換掉；照他的卡跟他，不動。原文另存在 rawMessages。
export function applyVoice(
  card: WrittenCard,
  spec: Pick<CardSpec, "voice"> | undefined,
): WrittenCard & { rawMessages?: readonly string[] } {
  if (spec?.voice !== "預設" || !card.messages.some((m) => m.includes("妳"))) {
    return card;
  }
  return {
    ...card,
    messages: card.messages.map((m) => m.replaceAll("妳", "你")),
    rawMessages: card.messages,
  };
}

/// v3.2 C5（Bruce 10/14）：打分或考題字眼，只記錄、不擋。照他口吻的卡可能用「妳」，比對前換成「你」。
export const SCORING_WORDS = [
  "加分",
  "扣分",
  "及格",
  "跳級",
  "舉證",
  "證明給我看",
  "重答",
  "給你一次機會",
  "看表現",
] as const;

export function scoringWords(text: string): string[] {
  const t = text.replaceAll("妳", "你");
  return SCORING_WORDS.filter((w) => t.includes(w));
}

/// C5 的「欠」組（Bruce 第 6 節不收「欠我」「欠著」；Eric 2026-10-18 決定這組改成不送）：
/// 卡片讓她欠他一杯、先欠著，就拿掉那一張，其他卡照送。黑箱量過：舊版 1,799 張與 v3 1,401 張
/// 裡擋對 11 張、誤擋 0。「欠缺」「欠自己的覺」不算。照他口吻的「妳」比對前換成「你」。
export const DEBT_FRAME_WORDS = ["欠我", "欠著", "你欠"] as const;

export function debtFrameHits(text: string): string[] {
  const t = text.replaceAll("妳", "你").replaceAll("你欠缺", "");
  return DEBT_FRAME_WORDS.filter((w) => t.includes(w));
}
