// 上次有效階段（partner-scoped 弱先驗）的合法值與正規化。獨立成小模組，
// 讓 knowledge_adapter 與 stream_prompt 都能用，而不必讓 adapter 反向依賴
// prompt builder。
const LEGAL_GAME_STAGES = [
  "opening",
  "premise",
  "qualification",
  "narrative",
  "close",
] as const;

export function normalizeStagePrior(previousStage: unknown): string | null {
  if (typeof previousStage !== "string") return null;
  const trimmed = previousStage.trim();
  return (LEGAL_GAME_STAGES as readonly string[]).includes(trimmed)
    ? trimmed
    : null;
}
