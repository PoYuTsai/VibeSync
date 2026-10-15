// 第二段（寫卡）的輸出：一行一張卡的解析、預設口吻把「妳」換成「你」，以及說明書 C5
// 只記錄、不擋卡的字眼檢查。
import type { CardSpec } from "./rules.ts";

export interface WrittenCard {
  readonly card: number;
  readonly messages: readonly string[];
  readonly hasInventedDetail: boolean;
  readonly expectedReaction: string;
}

/// 一行一張卡的 JSON；壞掉的行略過（記在 invalidLines）。
export function parseWrittenCards(
  text: string,
): { cards: WrittenCard[]; invalidLines: number } {
  const cards: WrittenCard[] = [];
  let invalidLines = 0;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    try {
      // deno-lint-ignore no-explicit-any
      const v: any = JSON.parse(line);
      const messages = Array.isArray(v.messages)
        ? v.messages.filter((m: unknown) =>
          typeof m === "string" && m.trim() !== ""
        )
        : [];
      if (!Number.isInteger(v.card) || messages.length === 0) {
        invalidLines++;
        continue;
      }
      cards.push({
        card: v.card,
        messages,
        hasInventedDetail: v.hasInventedDetail === true,
        expectedReaction: typeof v.expectedReaction === "string"
          ? v.expectedReaction
          : "",
      });
    } catch {
      invalidLines++;
    }
  }
  cards.sort((a, b) => a.card - b.card);
  return { cards, invalidLines };
}

/// v3 A5：預設口吻的稱呼一律用「你」。模型常照對話寫成「妳」（10/14 第一輪 41/108 張），
/// 由程式換掉；照他的卡跟他，不動。原文另存在 rawMessages。
export function applyVoice(
  card: WrittenCard,
  spec: CardSpec | undefined,
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
