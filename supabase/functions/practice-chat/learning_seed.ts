/**
 * 分數 seed 來源解析（PR 6）：把 handler 的多層 ternary 抽成純函式，
 * 行為與原邏輯逐項相同，只是多了 source 標籤供無逐字稿觀測。
 *
 * 優先序：ledger（已建檔一律為準，欄位 null 的舊列 fallback 難度起始值、
 * 不吃 client）＞ 同 thread 分數 ＞ client seed ＞ 難度預設。
 * thread profile 不符時 handler 在上游已把 threadState 設 null，這裡不重複驗。
 */

export type LearningSeedSource =
  | "ledger"
  | "relationship_thread"
  | "client"
  | "difficulty_default";

export interface LearningSeed {
  temperatureScore: number | null;
  familiarityScore: number | null;
  /**
   * temperatureScore 的來源（familiarity 逐欄位獨立 fallback，可能來自
   * 下一層；觀測以主分數溫度為準）。standard 無分數系統 → null。
   */
  source: LearningSeedSource | null;
}

export function resolveLearningSeed(opts: {
  assistedMode: boolean;
  ledger: {
    exists: boolean;
    temperatureScore?: number | null;
    familiarityScore?: number | null;
  };
  threadState:
    | { temperatureScore?: number | null; familiarityScore?: number | null }
    | null;
  clientTemperatureScore?: number | null;
  clientFamiliarityScore?: number | null;
  difficultyStartTemperature: number;
}): LearningSeed {
  if (!opts.assistedMode) {
    return { temperatureScore: null, familiarityScore: null, source: null };
  }
  if (opts.ledger.exists) {
    return {
      temperatureScore: opts.ledger.temperatureScore ??
        opts.difficultyStartTemperature,
      familiarityScore: opts.ledger.familiarityScore ?? 0,
      source: opts.ledger.temperatureScore != null
        ? "ledger"
        : "difficulty_default",
    };
  }
  return {
    temperatureScore: opts.threadState?.temperatureScore ??
      opts.clientTemperatureScore ?? opts.difficultyStartTemperature,
    familiarityScore: opts.threadState?.familiarityScore ??
      opts.clientFamiliarityScore ?? 0,
    source: opts.threadState?.temperatureScore != null
      ? "relationship_thread"
      : opts.clientTemperatureScore != null
      ? "client"
      : "difficulty_default",
  };
}
