// supabase/functions/_shared/social/candidate_guard.ts
//
// Analyze Phase 3c（規格 §15.2 第一層 deterministic hard gates）：把候選集合的
// 結構性違規統一成一份 violation 清單。只看 enum／id／index／數量，永遠不輸出
// 對話內容；本刀只進 telemetry，不擋、不修（§15.3 repair-first 的降級策略等
// Eric 定案再接）。輸入是正規化後的候選集合：analyze-chat 的 phase0_observability
// 從 finalResult 組出來；之後 reframer 的 selected-candidate repair 可餵同一份。
// 每道 gate 證據不足就回 null（不算檢查過），跟 reframer 的球面 canary 一樣
// 絕不誤殺。

export const CANDIDATE_GUARD_CODES = [
  // replyMode variants 至少兩張卡。
  "reply_mode_card_count",
  // §12：send 配 connect／extend／filter／invite；三種 no-send 配 stop／pause。
  "decision_action_conflict",
  // variants 之間（含決策）action／selectedBallIds 漂移。
  "variant_action_drift",
  "variant_ball_drift",
  // 球面：段的 sourceIndex 不在盤點／用到「略」球／「併」球獨立成段／
  // 任一「接」球沒被某張卡覆蓋。
  "source_ball_unknown",
  "skipped_ball_used",
  "merge_ball_isolated",
  "caught_ball_uncovered",
  // 五卡 sourceIndex／sourceMessage／順序要跟選中卡一致。
  "card_source_mismatch",
  "placeholder",
  // 預算：計畫（或決策）的 questionBudget／newTopicBudget／semanticDistanceCap；
  // 距離也看卡實際用到的枝。
  "question_budget",
  "new_topic_budget",
  "semantic_distance_cap",
  // 用到的聯想枝必須有 associationPath。
  "association_without_path",
  // no-send（或 replyMode none）卻帶回覆卡。
  "no_send_with_cards",
] as const;
export type CandidateGuardCode = typeof CANDIDATE_GUARD_CODES[number];

export type GuardDisposition = "接" | "併" | "略";

export interface CandidateGuardDecision {
  readonly messageDecision?: string;
  readonly replyMode?: string;
  readonly action?: string;
  readonly selectedBallIds?: readonly string[];
  readonly selectedStyle?: string;
  readonly questionBudget?: number;
  readonly newTopicBudget?: number;
}

export interface CandidateGuardSegment {
  readonly sourceIndex?: number;
  readonly sourceMessage?: string;
}

export interface CandidateGuardCandidate {
  readonly style: string;
  /// 送出的整張卡文字；只在 guard 內部數問句／比對 placeholder，不會輸出。
  readonly text: string;
  readonly segments: readonly CandidateGuardSegment[];
  readonly action?: string;
  readonly selectedBallIds?: readonly string[];
  readonly newTopicCount?: number;
  readonly semanticDistance?: number;
  readonly selectedBranchIds?: readonly string[];
}

export interface CandidateGuardBranch {
  readonly id: string;
  readonly method: string;
  readonly semanticDistance: number;
  readonly associationPath: readonly string[];
}

export interface CandidateGuardPlan {
  readonly semanticDistanceCap: number;
  readonly questionBudget: number;
  readonly newTopicBudget: number;
  readonly branchPool: readonly CandidateGuardBranch[];
}

export interface CandidateGuardInput {
  readonly decision: CandidateGuardDecision | null;
  /// sourceIndex → 接／併／略；null＝沒有可驗盤點，球面四道不檢查。
  readonly dispositions: ReadonlyMap<number, GuardDisposition> | null;
  readonly plan: CandidateGuardPlan | null;
  readonly candidates: readonly CandidateGuardCandidate[];
}

export interface CandidateGuardViolation {
  readonly code: CandidateGuardCode;
  readonly style?: string;
  readonly sourceIndex?: number;
  readonly branchId?: string;
}

export interface CandidateGuardResult {
  readonly violations: readonly CandidateGuardViolation[];
  /// 證據足夠、真的跑過的 gate；沒列在這裡的不代表通過。
  readonly checked: readonly CandidateGuardCode[];
}

const NO_SEND_DECISIONS = new Set([
  "do_not_send",
  "acknowledge_and_stop",
  "need_context",
]);
const SEND_ACTIONS = new Set(["connect", "extend", "filter", "invite"]);
const NO_SEND_ACTIONS = new Set(["stop", "pause"]);
// ponytail: naive placeholder heuristic（括號填空、XX／〇〇／___、某某、（名字／地點…））；
// telemetry-only，dogfood 看到誤報再收。
const PLACEHOLDER =
  /[[【{<〈][^\]】}>〉\n]{1,12}[\]】}>〉]|[XxＸ×]{2,}|[〇○◯]{2,}|[＿_]{2,}|某某|[（(](?:名字|地點|時間|日期|店名)[）)]/u;

type Gate = (input: CandidateGuardInput) => CandidateGuardViolation[] | null;

function replyModeOf(decision: CandidateGuardDecision | null): string | null {
  if (!decision) return null;
  if (decision.replyMode) return decision.replyMode;
  const kind = decision.messageDecision;
  if (kind === "send") return "variants";
  if (kind === "acknowledge_and_stop") return "single";
  return NO_SEND_DECISIONS.has(kind ?? "") ? "none" : null;
}

function sameSet(left: readonly string[], right: readonly string[]): boolean {
  return left.length === right.length &&
    left.every((value) => right.includes(value)) &&
    right.every((value) => left.includes(value));
}

function sourceIndexSequence(
  candidate: CandidateGuardCandidate,
): number[] | null {
  if (candidate.segments.length === 0) return null;
  const indices = candidate.segments.map((segment) => segment.sourceIndex);
  return indices.every((index): index is number => typeof index === "number")
    ? indices
    : null;
}

/// 跨 variants 共用欄位（action／selectedBallIds）漂移；決策有值就以決策為準，
/// 否則以第一張帶值的卡為準；只有一張卡帶值又沒決策值時無從比較。
function drift<T>(
  code: CandidateGuardCode,
  input: CandidateGuardInput,
  read: (
    source: CandidateGuardDecision | CandidateGuardCandidate,
  ) => T | undefined,
  same: (left: T, right: T) => boolean,
): CandidateGuardViolation[] | null {
  const cards = input.candidates.filter((c) => read(c) !== undefined);
  const reference = (input.decision && read(input.decision)) ??
    (cards.length >= 2 ? read(cards[0]) : undefined);
  if (reference === undefined) return null;
  return cards
    .filter((card) => !same(read(card)!, reference))
    .map((card) => ({ code, style: card.style }));
}

/// 球面：每張卡逐段對盤點；同一張卡同一顆球只記一次。
function ballGate(
  code: CandidateGuardCode,
  input: CandidateGuardInput,
  violates: (
    disposition: GuardDisposition | undefined,
  ) => boolean,
): CandidateGuardViolation[] | null {
  const dispositions = input.dispositions;
  if (!dispositions) return null;
  const violations: CandidateGuardViolation[] = [];
  for (const candidate of input.candidates) {
    const seen = new Set<number>();
    for (const { sourceIndex } of candidate.segments) {
      if (sourceIndex === undefined || seen.has(sourceIndex)) continue;
      seen.add(sourceIndex);
      if (violates(dispositions.get(sourceIndex))) {
        violations.push({ code, style: candidate.style, sourceIndex });
      }
    }
  }
  return violations;
}

const GATES: Record<CandidateGuardCode, Gate> = {
  reply_mode_card_count: (input) =>
    replyModeOf(input.decision) !== "variants"
      ? null
      : input.candidates.length >= 2
      ? []
      : [{ code: "reply_mode_card_count" }],

  decision_action_conflict: ({ decision }) => {
    const kind = decision?.messageDecision;
    const action = decision?.action;
    if (!kind || !action) return null;
    const allowed = kind === "send"
      ? SEND_ACTIONS
      : NO_SEND_DECISIONS.has(kind)
      ? NO_SEND_ACTIONS
      : null;
    if (!allowed) return null;
    return allowed.has(action) ? [] : [{ code: "decision_action_conflict" }];
  },

  variant_action_drift: (input) =>
    drift(
      "variant_action_drift",
      input,
      (source) => source.action,
      (left, right) => left === right,
    ),

  variant_ball_drift: (input) =>
    drift(
      "variant_ball_drift",
      input,
      (source) => source.selectedBallIds,
      sameSet,
    ),

  source_ball_unknown: (input) =>
    ballGate("source_ball_unknown", input, (d) => d === undefined),
  skipped_ball_used: (input) =>
    ballGate("skipped_ball_used", input, (d) => d === "略"),
  merge_ball_isolated: (input) =>
    ballGate("merge_ball_isolated", input, (d) => d === "併"),

  caught_ball_uncovered: ({ dispositions, candidates }) => {
    if (!dispositions) return null;
    const caught = [...dispositions.entries()]
      .filter(([, disposition]) => disposition === "接")
      .map(([sourceIndex]) => sourceIndex);
    const violations: CandidateGuardViolation[] = [];
    let checked = false;
    for (const candidate of candidates) {
      const covered = sourceIndexSequence(candidate);
      if (!covered) continue; // 段缺 sourceIndex：這張卡的覆蓋無從判定。
      checked = true;
      for (const sourceIndex of caught) {
        if (!covered.includes(sourceIndex)) {
          violations.push({
            code: "caught_ball_uncovered",
            style: candidate.style,
            sourceIndex,
          });
        }
      }
    }
    return checked ? violations : null;
  },

  card_source_mismatch: ({ decision, candidates }) => {
    if (candidates.length < 2) return null;
    const sequences = candidates.map((candidate) => ({
      candidate,
      indices: sourceIndexSequence(candidate),
      messages:
        candidate.segments.every((segment) =>
            typeof segment.sourceMessage === "string" &&
            segment.sourceMessage.trim() !== ""
          )
          ? candidate.segments.map((segment) => segment.sourceMessage!)
          : null,
    }));
    if (sequences.some((entry) => entry.indices === null)) return null;
    const baseline =
      sequences.find((entry) =>
        entry.candidate.style === decision?.selectedStyle
      ) ?? sequences[0];
    return sequences
      .filter((entry) =>
        entry !== baseline && (
          entry.indices!.join(",") !== baseline.indices!.join(",") ||
          (entry.messages !== null && baseline.messages !== null &&
            entry.messages.join("\n") !== baseline.messages.join("\n"))
        )
      )
      .map((entry) => ({
        code: "card_source_mismatch" as const,
        style: entry.candidate.style,
      }));
  },

  placeholder: ({ candidates }) =>
    candidates.length === 0 ? null : candidates
      .filter((candidate) => PLACEHOLDER.test(candidate.text))
      .map((candidate) => ({
        code: "placeholder" as const,
        style: candidate.style,
      })),

  question_budget: ({ plan, decision, candidates }) => {
    const budget = plan?.questionBudget ?? decision?.questionBudget;
    if (budget === undefined || candidates.length === 0) return null;
    return candidates
      .filter((candidate) =>
        (candidate.text.match(/[?？]/g)?.length ?? 0) > budget
      )
      .map((candidate) => ({
        code: "question_budget" as const,
        style: candidate.style,
      }));
  },

  new_topic_budget: ({ plan, decision, candidates }) => {
    const budget = plan?.newTopicBudget ?? decision?.newTopicBudget;
    const counted = candidates.filter((c) => c.newTopicCount !== undefined);
    if (budget === undefined || counted.length === 0) return null;
    return counted
      .filter((candidate) => candidate.newTopicCount! > budget)
      .map((candidate) => ({
        code: "new_topic_budget" as const,
        style: candidate.style,
      }));
  },

  semantic_distance_cap: ({ plan, candidates }) => {
    if (!plan) return null;
    const distance = new Map(
      plan.branchPool.map((branch) => [branch.id, branch.semanticDistance]),
    );
    const violations: CandidateGuardViolation[] = [];
    let checked = false;
    for (const candidate of candidates) {
      if (candidate.semanticDistance !== undefined) {
        checked = true;
        if (candidate.semanticDistance > plan.semanticDistanceCap) {
          violations.push({
            code: "semantic_distance_cap",
            style: candidate.style,
          });
        }
      }
      for (const branchId of candidate.selectedBranchIds ?? []) {
        checked = true;
        if ((distance.get(branchId) ?? 0) > plan.semanticDistanceCap) {
          violations.push({
            code: "semantic_distance_cap",
            style: candidate.style,
            branchId,
          });
        }
      }
    }
    return checked ? violations : null;
  },

  association_without_path: ({ plan, candidates }) => {
    if (!plan) return null;
    const pathless = new Set(
      plan.branchPool
        .filter((branch) =>
          branch.method === "association" && branch.associationPath.length === 0
        )
        .map((branch) => branch.id),
    );
    const violations: CandidateGuardViolation[] = [];
    let checked = false;
    for (const candidate of candidates) {
      for (const branchId of candidate.selectedBranchIds ?? []) {
        checked = true;
        if (pathless.has(branchId)) {
          violations.push({
            code: "association_without_path",
            style: candidate.style,
            branchId,
          });
        }
      }
    }
    return checked ? violations : null;
  },

  no_send_with_cards: ({ decision, candidates }) => {
    const kind = decision?.messageDecision;
    if (!kind && decision?.replyMode === undefined) return null;
    const noSend = NO_SEND_DECISIONS.has(kind ?? "") ||
      decision?.replyMode === "none";
    return noSend && candidates.length > 0
      ? [{ code: "no_send_with_cards" }]
      : [];
  },
};

export function runCandidateGuard(
  input: CandidateGuardInput,
): CandidateGuardResult {
  const violations: CandidateGuardViolation[] = [];
  const checked: CandidateGuardCode[] = [];
  for (const code of CANDIDATE_GUARD_CODES) {
    const found = GATES[code](input);
    if (found === null) continue;
    checked.push(code);
    violations.push(...found);
  }
  return { violations, checked };
}
