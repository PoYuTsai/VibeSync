// supabase/functions/analyze-chat/analysis_baseline_telemetry.ts
//
// 第一階段（只觀測，不改行為）：把「這一輪分析長成什麼樣」量成一組結構化
// 指標，作為優化前的基線。純函式，不回寫結果、不影響任何判斷或生成。
//
// 量的是最終 payload——也就是使用者真的會看到的那份，不是中間狀態；
// 中間狀態再漂亮，使用者看到的才算數。
//
// 兩條紅線：
//   1. 不輸出任何訊息原文。指標只放索引與計數——log 不該帶走使用者的私人
//      對話內容。
//   2. 永遠不 throw。觀測程式炸掉不得害一次已扣費的分析失敗（與 reframer
//      的 [ball_coverage] canary 同一個 fail-soft 立場）。

/// 與 guardrails.getEnthusiasmLevel 同一條冷局線；量的是 post_process
/// 校準後、真的顯示給使用者的分數。
const COLD_SCORE_MAX = 30;

/// client 的放棄橫幅條件（analysis_models.dart）：level 為 cold 且 warnings
/// 提到放棄／開新對話。這裡原樣鏡像，才量得到使用者真正看到的矛盾。
const GIVE_UP_WARNING_MARKERS = ["建議放棄", "開新對話"] as const;

export interface InventoryCounts {
  catch: number;
  merge: number;
  skip: number;
  truncated: boolean;
}

export interface AnalysisBaselineSummary {
  /// 盤點各 disposition 的球數；沒有盤點時為 null（本身就是一個觀測結果）。
  inventory: InventoryCounts | null;
  /// 實際帶有可複製文字的風格數。
  cardsShown: number;
  /// 每個風格的段落覆蓋到哪些球（sourceIndex，已排序去重）。
  coverage: Record<string, number[]>;
  /// 五卡是否覆蓋同一組球。少於兩個風格時無從比較，為 null。
  sameBallSetAcrossStyles: boolean | null;
  /// 每個風格的問句數，以及其中最大值（「每球一問」的 beta 訊號）。
  questionCounts: Record<string, number>;
  maxQuestionCount: number;
  /// 顯示用的投入度分數（post_process 校準後）。
  enthusiasmScore: number | null;
  /// 冷局分數卻仍輸出回覆卡——規格要量的核心矛盾。
  coldScoreWithCards: boolean;
  /// client 會顯示放棄橫幅、同時又有回覆卡：使用者同一畫面看到互相打架的訊號。
  giveUpBannerWithCards: boolean;
}

export function summarizeAnalysisBaseline(
  result: unknown,
): AnalysisBaselineSummary {
  const record = asRecord(result) ?? {};
  const replyOptions = asRecord(record.replyOptions) ?? {};
  const replies = asRecord(record.replies) ?? {};

  const coverage: Record<string, number[]> = {};
  const questionCounts: Record<string, number> = {};
  let cardsShown = 0;
  let maxQuestionCount = 0;

  // 以 replyOptions 為主：那是 App 實際渲染的來源；replies 只是舊版備援，
  // 但風格只出現在 replies 時也要算進來，否則基線會低估。
  const styles = new Set<string>([
    ...Object.keys(replyOptions),
    ...Object.keys(replies),
  ]);

  for (const style of styles) {
    const segments = segmentsOf(replyOptions[style]);
    const texts = segments.length > 0
      ? segments.map((segment) => textOf(segment.reply))
      : [textOf(replies[style])];
    const joined = texts.filter((text) => text.length > 0).join("\n");

    if (joined.length === 0) continue;
    cardsShown += 1;

    coverage[style] = sortedIndices(segments);
    const questions = countQuestions(joined);
    questionCounts[style] = questions;
    if (questions > maxQuestionCount) maxQuestionCount = questions;
  }

  const enthusiasm = asRecord(record.enthusiasm);
  const enthusiasmScore = finiteNumber(enthusiasm?.score);
  const hasCards = cardsShown > 0;

  return {
    inventory: countInventory(record.ballInventory),
    cardsShown,
    coverage,
    sameBallSetAcrossStyles: compareBallSets(coverage),
    questionCounts,
    maxQuestionCount,
    enthusiasmScore,
    coldScoreWithCards: hasCards && enthusiasmScore !== null &&
      enthusiasmScore <= COLD_SCORE_MAX,
    giveUpBannerWithCards: hasCards && showsGiveUpBanner(record),
  };
}

/// 一行可 grep 的摘要。刻意不帶原文，只有計數與索引。
export function formatAnalysisBaseline(
  summary: AnalysisBaselineSummary,
): string {
  const inventory = summary.inventory
    ? `接${summary.inventory.catch}/併${summary.inventory.merge}/略${summary.inventory.skip}${
      summary.inventory.truncated ? "+" : ""
    }`
    : "none";
  const coverage = Object.entries(summary.coverage)
    .map(([style, indices]) => `${style}:[${indices.join(",")}]`)
    .join(" ");
  return [
    `[analysis_baseline] inventory=${inventory}`,
    `cards=${summary.cardsShown}`,
    `sameSet=${summary.sameBallSetAcrossStyles ?? "n/a"}`,
    `maxQuestions=${summary.maxQuestionCount}`,
    `score=${summary.enthusiasmScore ?? "n/a"}`,
    `coldWithCards=${summary.coldScoreWithCards}`,
    `giveUpWithCards=${summary.giveUpBannerWithCards}`,
    `coverage={${coverage}}`,
  ].join(" ");
}

function countInventory(value: unknown): InventoryCounts | null {
  const snapshot = asRecord(value);
  if (!snapshot) return null;
  const balls = Array.isArray(snapshot.balls) ? snapshot.balls : null;
  if (!balls || balls.length === 0) return null;

  const counts: InventoryCounts = {
    catch: 0,
    merge: 0,
    skip: 0,
    truncated: snapshot.truncated === true,
  };
  for (const ball of balls) {
    const disposition = asRecord(ball)?.disposition;
    if (disposition === "接") counts.catch += 1;
    else if (disposition === "併") counts.merge += 1;
    else if (disposition === "略") counts.skip += 1;
  }
  return counts;
}

function segmentsOf(option: unknown): Record<string, unknown>[] {
  const record = asRecord(option);
  const messages = record?.messages ?? record?.messageGroup ??
    record?.replySegments;
  if (!Array.isArray(messages)) return [];
  return messages.filter((item): item is Record<string, unknown> =>
    asRecord(item) !== null
  );
}

function sortedIndices(segments: readonly Record<string, unknown>[]): number[] {
  const indices = new Set<number>();
  for (const segment of segments) {
    const index = finiteNumber(segment.sourceIndex);
    if (index !== null) indices.add(index);
  }
  return [...indices].sort((a, b) => a - b);
}

/// 只比較「有出段落來源」的風格。沒有任何 sourceIndex 的卡片無從比較，
/// 拿它跟別人比會得到假的 false。
function compareBallSets(
  coverage: Record<string, number[]>,
): boolean | null {
  const sets = Object.values(coverage)
    .filter((indices) => indices.length > 0)
    .map((indices) => indices.join(","));
  if (sets.length < 2) return null;
  return sets.every((value) => value === sets[0]);
}

function countQuestions(text: string): number {
  const matches = text.match(/[?？]/gu);
  return matches ? matches.length : 0;
}

function showsGiveUpBanner(result: Record<string, unknown>): boolean {
  if (asRecord(result.enthusiasm)?.level !== "cold") return false;
  const warnings = result.warnings;
  if (!Array.isArray(warnings)) return false;
  return warnings.some((warning) => {
    const text = typeof warning === "string"
      ? warning
      : JSON.stringify(warning ?? "");
    return GIVE_UP_WARNING_MARKERS.some((marker) => text.includes(marker));
  });
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function textOf(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function finiteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}
