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

export function transcriptByTurn(turns: readonly Turn[]): string {
  const lines: string[] = [];
  for (const t of turns) {
    lines.push(`第 ${t.index} 輪・${t.fromMe ? "他" : "她"}：`);
    for (const m of t.messages) lines.push(`- ${m}`);
  }
  const last = turns.at(-1);
  if (last && !last.fromMe) lines.push("", `（她最新的是第 ${last.index} 輪）`);
  return lines.join("\n");
}
