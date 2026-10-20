// 對話分輪：連續同一方的訊息算一輪，給兩段提示詞看。

export interface GuideMessage {
  readonly isFromMe: boolean;
  readonly content: string;
}

export interface Turn {
  /// 1 起算。
  readonly index: number;
  readonly fromMe: boolean;
  readonly messages: readonly string[];
}

export function toTurns(messages: readonly GuideMessage[]): Turn[] {
  const turns: { index: number; fromMe: boolean; messages: string[] }[] = [];
  for (const m of messages) {
    const last = turns.at(-1);
    if (last && last.fromMe === m.isFromMe) last.messages.push(m.content);
    else {
      turns.push({
        index: turns.length + 1,
        fromMe: m.isFromMe,
        messages: [m.content],
      });
    }
  }
  return turns;
}

/// numberLatestHerTurn：她最新這一輪改成逐則編號（1. 2. …），讓讀局面回報要接哪幾則、
/// 卡片規格指定每張接哪一句（兩段式實驗，Eric 2026-10-19）。沒給就跟今天一字不差。
export function transcriptByTurn(
  turns: readonly Turn[],
  options: { readonly numberLatestHerTurn?: boolean } = {},
): string {
  const lines: string[] = [];
  const last = turns.at(-1);
  const numbered = options.numberLatestHerTurn && last && !last.fromMe
    ? last.index
    : null;
  for (const t of turns) {
    lines.push(`第 ${t.index} 輪・${t.fromMe ? "他" : "她"}：`);
    t.messages.forEach((m, i) =>
      lines.push(t.index === numbered ? `${i + 1}. ${m}` : `- ${m}`)
    );
  }
  if (last && !last.fromMe) lines.push("", `（她最新的是第 ${last.index} 輪）`);
  return lines.join("\n");
}

/// 她最新這一輪的訊息（最後一輪是他的就是空的）。編號照 transcriptByTurn 的 1 起算。
export function latestHerMessages(turns: readonly Turn[]): readonly string[] {
  const last = turns.at(-1);
  return last && !last.fromMe ? last.messages : [];
}
