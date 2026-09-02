import {
  isStreamStyle,
  parseEventLine,
  type StreamEvent,
  type StreamStyle,
} from "./stream_events.ts";
import {
  type BallInventory,
  coveredIndependentBalls,
  parseBallInventory,
  segmentFloor,
  validateSelectedSegments,
} from "./ball_inventory.ts";
import {
  type RecommendationValidation,
  validateDecisionChargeEvent,
  validateRecommendationBackfill,
  validateRecommendationEvent,
  validateThinRecommendationEvent,
} from "./stream_recommendation_guardrail.ts";
import {
  isNoSendChargePayload,
  isNoSendDecisionKind,
  noSendDecisionEvent,
  type StreamNoSendRecommendationForCharge,
  validateNoSendDecisionEvent,
} from "./no_send_decision.ts";
import { STRETCH_LEVELS, type StretchLevel } from "./opener_payload.ts";
import {
  type DivergencePlanV1,
  parseDivergencePlanV1,
} from "./divergence_contract.ts";

function normalizeStretchLevel(value: unknown): StretchLevel {
  return typeof value === "string" &&
      (STRETCH_LEVELS as readonly string[]).includes(value)
    ? value as StretchLevel
    : "within";
}

export type StreamOutputEvent =
  | StreamEvent
  | (Record<string, unknown> & { type: string });

export interface StreamRecommendationForCharge {
  selectedStyle: StreamStyle;
  message: string;
  reason: string;
  quotedContext: string;
  warnings: string[];
  raw: StreamEvent | Record<string, unknown>;
  // Phase 0 only: additive snapshots. These never participate in charge
  // validation, stream ordering, or retry eligibility.
  analysisDecisionV2?: Record<string, unknown>;
  analysisInventory?: Record<string, unknown>;
  analysisEvidenceLinkage?: AnalysisEvidenceLinkage;
  // Phase 2a shadow: the model's divergence plan, shape-validated only.
  analysisDivergencePlan?: DivergencePlanV1;
}

/// Charge anchor union: a v1 send recommendation or a Phase 1b no-send
/// decision. Discriminate with isNoSendChargePayload.
export type StreamChargePayload =
  | StreamRecommendationForCharge
  | StreamNoSendRecommendationForCharge;

export interface AnalysisEvidenceVariant {
  sourceIndices?: number[];
  // Exact source order is additive Phase 0 evidence. sourceIndices remains a
  // unique coverage set for existing consumers and telemetry.
  sourceIndexSequence?: number[];
  sourceBallIds?: string[];
  action?: string;
  selectedBallIds?: string[];
  questionCount?: number;
  newTopicCount?: number;
  semanticDistance?: number;
  solutionMode?: boolean;
}

export interface AnalysisEvidenceLinkage {
  schemaVersion: 1;
  decisionId?: string;
  selectedStyle?: StreamStyle;
  selectedBallIds?: string[];
  inventorySourceIndices?: number[];
  variants?: Record<string, AnalysisEvidenceVariant>;
}

type Phase0ObservabilitySnapshot = Pick<
  StreamRecommendationForCharge,
  | "analysisDecisionV2"
  | "analysisInventory"
  | "analysisEvidenceLinkage"
  | "analysisDivergencePlan"
>;

export interface StreamChargeResult {
  charged: boolean;
  code?: string;
  message?: string;
  recoverable?: boolean;
}

export interface ReframerOptions {
  emit: (event: StreamOutputEvent) => void;
  onRecommendation: (
    recommendation: StreamChargePayload,
  ) => Promise<StreamChargeResult> | StreamChargeResult;
  prechargedRecommendation?: StreamChargePayload;
  requiredReplyStyles?: readonly StreamStyle[];
  /// Phase 1b: accept a no-send analysis.decision as the charge anchor.
  /// Off => v1 behaviour byte-for-byte (a style-less decision is malformed).
  noSendDecisions?: boolean;
}

export interface StreamReframer {
  pushText: (chunk: string) => void;
  drain: () => Promise<void>;
  flush: () => Promise<void>;
}

const DEFAULT_CHARGE_FAILURE_MESSAGE =
  "Streaming analysis could not continue. Please retry.";

const ANALYSIS_ACTIONS = new Set([
  "stop",
  "connect",
  "extend",
  "filter",
  "invite",
  "pause",
]);

function cloneRecord(value: unknown): Record<string, unknown> | null {
  if (!isRecord(value)) return null;
  try {
    const clone = JSON.parse(JSON.stringify(value)) as unknown;
    return isRecord(clone) ? clone : null;
  } catch {
    return null;
  }
}

function cloneDecisionV2(value: unknown): Record<string, unknown> | null {
  const clone = cloneRecord(value);
  return clone?.schemaVersion === 2 ? clone : null;
}

function cloneEvidenceLinkage(
  value: unknown,
): AnalysisEvidenceLinkage | null {
  const clone = cloneRecord(value);
  return clone?.schemaVersion === 1
    ? clone as unknown as AnalysisEvidenceLinkage
    : null;
}

function decisionV2SnapshotFrom(
  event: Record<string, unknown>,
): Record<string, unknown> | null {
  const nested = cloneDecisionV2(event.analysisDecisionV2);
  if (nested) return nested;
  if (event.schemaVersion !== 2) return null;

  const { type: _type, ...decision } = event;
  return cloneDecisionV2(decision);
}

function inventorySnapshotFrom(
  event: StreamEvent,
): Record<string, unknown> | null {
  return Array.isArray(event.balls) ? cloneRecord(event) : null;
}

function stringArrayFrom(value: unknown): string[] | undefined {
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
    return undefined;
  }
  const values = value.map((item) => item.trim());
  return values.every(Boolean) ? values : undefined;
}

function nonNegativeNumberFrom(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? value
    : undefined;
}

function sourceIndexSequenceFromSegments(
  segments: readonly Record<string, unknown>[],
): number[] | undefined {
  const indices = segments.flatMap((segment) => {
    const sourceIndex = segment.sourceIndex;
    return typeof sourceIndex === "number" &&
        Number.isInteger(sourceIndex) && sourceIndex > 0
      ? [sourceIndex]
      : [];
  });
  return indices.length > 0 ? indices : undefined;
}

function sourceIndicesFromSegments(
  segments: readonly Record<string, unknown>[],
): number[] | undefined {
  const sequence = sourceIndexSequenceFromSegments(segments);
  return sequence ? [...new Set(sequence)] : undefined;
}

function sourceIndicesFromInventory(
  inventory: Record<string, unknown> | null,
): number[] | undefined {
  if (!inventory || !Array.isArray(inventory.balls)) return undefined;
  const indices = [
    ...new Set(inventory.balls.flatMap((ball) => {
      if (!isRecord(ball)) return [];
      const sourceIndex = ball.sourceIndex;
      return typeof sourceIndex === "number" &&
          Number.isInteger(sourceIndex) && sourceIndex > 0
        ? [sourceIndex]
        : [];
    })),
  ].sort((left, right) => left - right);
  return indices.length > 0 ? indices : undefined;
}

function evidenceVariantFrom(
  event: StreamEvent,
  segments: readonly Record<string, unknown>[],
): AnalysisEvidenceVariant {
  const action = stringField(event.action);
  const sourceIndexSequence = sourceIndexSequenceFromSegments(segments);
  const sourceIndices = sourceIndicesFromSegments(segments);
  const sourceBallIds = stringArrayFrom(event.sourceBallIds);
  const selectedBallIds = stringArrayFrom(event.selectedBallIds);
  const questionCount = nonNegativeNumberFrom(event.questionCount);
  const newTopicCount = nonNegativeNumberFrom(event.newTopicCount);
  const semanticDistance = nonNegativeNumberFrom(event.semanticDistance);
  const solutionMode = typeof event.solutionMode === "boolean"
    ? event.solutionMode
    : undefined;

  return {
    ...(sourceIndices ? { sourceIndices } : {}),
    ...(sourceIndexSequence ? { sourceIndexSequence } : {}),
    ...(sourceBallIds ? { sourceBallIds } : {}),
    ...(ANALYSIS_ACTIONS.has(action) ? { action } : {}),
    ...(selectedBallIds ? { selectedBallIds } : {}),
    ...(questionCount !== undefined ? { questionCount } : {}),
    ...(newTopicCount !== undefined ? { newTopicCount } : {}),
    ...(semanticDistance !== undefined ? { semanticDistance } : {}),
    ...(solutionMode !== undefined ? { solutionMode } : {}),
  };
}

function buildEvidenceLinkage({
  decision,
  inventory,
  selectedStyle,
  variants,
}: {
  decision: Record<string, unknown> | null;
  inventory: Record<string, unknown> | null;
  selectedStyle: StreamStyle | null;
  variants?: ReadonlyMap<StreamStyle, AnalysisEvidenceVariant>;
}): AnalysisEvidenceLinkage | null {
  const decisionId = decision ? stringField(decision.decisionId) : "";
  const selectedBallIds = decision
    ? stringArrayFrom(decision.selectedBallIds)
    : undefined;
  const inventorySourceIndices = sourceIndicesFromInventory(inventory);
  const linkage: AnalysisEvidenceLinkage = {
    schemaVersion: 1,
    ...(decisionId ? { decisionId } : {}),
    ...(selectedStyle ? { selectedStyle } : {}),
    ...(selectedBallIds ? { selectedBallIds } : {}),
    ...(inventorySourceIndices ? { inventorySourceIndices } : {}),
  };

  if (variants && variants.size > 0) {
    const entries = [...variants.entries()]
      .filter(([, variant]) => Object.keys(variant).length > 0)
      .map(([style, variant]) => [style, { ...variant }] as const);
    if (entries.length > 0) linkage.variants = Object.fromEntries(entries);
  }

  return Object.keys(linkage).length > 1 ? linkage : null;
}

function mergeEvidenceLinkageSnapshot(
  persisted: AnalysisEvidenceLinkage | null,
  derived: AnalysisEvidenceLinkage | null,
): AnalysisEvidenceLinkage | null {
  if (!persisted) return derived;
  if (!derived) return persisted;
  const variants = derived.variants ?? persisted.variants;
  return {
    ...persisted,
    ...derived,
    ...(variants ? { variants } : {}),
  } as AnalysisEvidenceLinkage;
}

export function createStreamReframer(options: ReframerOptions): StreamReframer {
  const assembler = createLegacyAnalysisAssembler();
  let buffer = "";
  let pending = Promise.resolve();
  let closed = false;
  let sawValidEvent = false;
  let doneEmitted = false;
  const isResume = options.prechargedRecommendation != null;
  // A retry is causally anchored to the decision that was already charged.
  // Replayed provider events may differ, but must not relabel that anchor in
  // a Phase 0 snapshot. Older anchors can still recover a v2 snapshot from
  // their stored raw decision without affecting stream behavior.
  const frozenResumeDecision = options.prechargedRecommendation
    ? cloneDecisionV2(options.prechargedRecommendation.analysisDecisionV2) ??
      (options.prechargedRecommendation.raw.type === "analysis.decision"
        ? decisionV2SnapshotFrom(options.prechargedRecommendation.raw)
        : null)
    : null;
  let chargeCompleted = isResume;
  let resumeDecisionReplayPending = options.prechargedRecommendation?.raw
    ?.type === "analysis.decision";
  let officialRecommendationEmitted = options.prechargedRecommendation?.raw
    ?.type === "analysis.recommendation";
  let modelDoneHadFinalResult = false;
  // 件4 D2 瘦推薦卡：buffer 住的瘦 recommendation，等 selected
  // reply_option 到貨後回填全文再轉發（D3 契約凍結：App 看到的順序不變）。
  let pendingThinRecommendation:
    | Extract<RecommendationValidation, { ok: true }>
    | null = null;
  // 黑箱 r1 韌性網：記住已轉發的 reply_option 與 decision 的 selectedStyle，
  // 瘦卡晚到（option 已過）或整個沒來時可在終局 late-bind / 合成推薦卡。
  const seenReplyOptions = new Map<
    StreamStyle,
    { compat: StreamEvent; segments: Record<string, unknown>[] }
  >();
  let decisionSelectedStyle: StreamStyle | null = null;
  // Phase 1b: once a no-send decision is charged (or resumed) the stream is in
  // no-send mode: reply options and recommendations are dropped, later
  // decisions cannot retarget it, and done skips style completeness.
  let noSendDecision: StreamNoSendRecommendationForCharge | null =
    options.prechargedRecommendation &&
      isNoSendChargePayload(options.prechargedRecommendation)
      ? options.prechargedRecommendation
      : null;
  // 球數案硬版：保留模型最先 emit 的盤點 disposition map，等選中風格的
  // reply_option 到貨時驗「段⊆接/併」＋「段數達下限」。缺席/全略＝null＝退回
  // soft 不驗證（INV-H4 fallback，絕不誤殺）。
  let inventory: BallInventory | null = null;
  // Phase 0 observability is strictly additive. A legacy decision remains on
  // its existing streamingDecision path unless it explicitly declares v2.
  let analysisDecisionV2: Record<string, unknown> | null = frozenResumeDecision;
  let analysisInventory: Record<string, unknown> | null = null;
  let analysisEvidenceLinkage: AnalysisEvidenceLinkage | null = null;
  // Phase 2a shadow：第一個合法計畫勝出；後到的不覆蓋。
  let analysisDivergencePlan: DivergencePlanV1 | null = null;
  let observedSelectedStyle: StreamStyle | null =
    options.prechargedRecommendation?.selectedStyle ?? null;
  const evidenceVariants = new Map<StreamStyle, AnalysisEvidenceVariant>();
  const preChargeEvents: StreamEvent[] = [];
  const requiredReplyStyles = normalizeRequiredReplyStyles(
    options.requiredReplyStyles,
  );
  const requiredReplyStyleSet = new Set(requiredReplyStyles);

  const phase0Snapshot = (
    selectedStyle: StreamStyle | null,
    includeVariants: boolean,
  ): Phase0ObservabilitySnapshot => {
    const snapshot: Phase0ObservabilitySnapshot = {};
    const decision = cloneRecord(analysisDecisionV2);
    const inventory = cloneRecord(analysisInventory);
    if (decision) snapshot.analysisDecisionV2 = decision;
    if (inventory) snapshot.analysisInventory = inventory;

    const linkage = mergeEvidenceLinkageSnapshot(
      cloneEvidenceLinkage(analysisEvidenceLinkage),
      buildEvidenceLinkage({
        decision: analysisDecisionV2,
        inventory: analysisInventory,
        selectedStyle,
        variants: includeVariants ? evidenceVariants : undefined,
      }),
    );
    if (linkage) snapshot.analysisEvidenceLinkage = linkage;
    if (analysisDivergencePlan) {
      snapshot.analysisDivergencePlan = analysisDivergencePlan;
    }
    return snapshot;
  };

  if (options.prechargedRecommendation) {
    const raw = options.prechargedRecommendation.raw;
    // Every resume path, including a thin-card anchor, keeps the charged
    // style as the causal baseline. A replayed decision cannot retarget it.
    decisionSelectedStyle = options.prechargedRecommendation.selectedStyle;
    if (isNoSendChargePayload(options.prechargedRecommendation)) {
      // The charged decision is the completion anchor; the client already
      // received it from stream_handler's precharged replay.
      officialRecommendationEmitted = true;
      assembler.absorb(noSendDecisionEvent(options.prechargedRecommendation));
    } else if (isThinRecommendationEvent(raw)) {
      // resume 自 v2 瘦卡扣費：重掛 pending，由 replay 的 selected
      // reply_option 重新綁卡回填；瘦卡本身不可直接外流。revalidation
      // 失敗（ledger 損壞）也不得讓 officialRecommendationEmitted 卡成
      // true 靜默完成——交給 replay 的瘦卡重新走 fresh 驗證。
      officialRecommendationEmitted = false;
      const revalidated = validateThinRecommendationEvent(raw);
      if (revalidated.ok) {
        pendingThinRecommendation = revalidated;
      }
    } else {
      // legacy 全卡 officialRecommendationEmitted 已為 true，tryLateBind
      // 不會因此合成第二張卡，行為不變。
      assembler.absorb(toRecommendationEvent(options.prechargedRecommendation));
    }

    // A retry may start from a previously persisted charge anchor. Snapshot
    // fields are optional and must never become a retry requirement.
    analysisDecisionV2 = cloneDecisionV2(
      options.prechargedRecommendation.analysisDecisionV2,
    ) ?? analysisDecisionV2;
    analysisInventory = cloneRecord(
      options.prechargedRecommendation.analysisInventory,
    ) ?? analysisInventory;
    analysisEvidenceLinkage = cloneEvidenceLinkage(
      options.prechargedRecommendation.analysisEvidenceLinkage,
    ) ?? analysisEvidenceLinkage;
  }

  const emitError = (
    code: string,
    message: string,
    recoverable = true,
    extra: Record<string, unknown> = {},
  ) => {
    options.emit({
      type: "analysis.error",
      code,
      message,
      recoverable,
      ...extra,
    });
  };

  const emitDone = () => {
    if (doneEmitted || closed) return;
    if (noSendDecision) {
      // Zero reply cards by contract: whatever the model stuffed into
      // finalResult, the client must never see a reply next to a no-send.
      const finalResult: Record<string, unknown> = {
        ...assembler.build(),
        ...phase0Snapshot(null, false),
        replies: {},
        replyOptions: {},
      };
      // Other client-shape records that can carry reply text are not part
      // of a no-send result either.
      for (
        const key of [
          "finalRecommendation",
          "optimizedMessage",
          "myMessageAnalysis",
        ]
      ) {
        delete finalResult[key];
      }
      options.emit({ type: "analysis.done", finalResult });
      doneEmitted = true;
      closed = true;
      return;
    }
    tryLateBind();
    if (closed) return; // late-bind 的 safety 檢查可能擋下並關閉 stream。
    if (pendingThinRecommendation) {
      // 件4 測試重點：buffer 中的瘦卡（已扣費）不得造成「已扣費但無輸出」
      // 的靜默 done——selected reply_option 沒到就走既有 INCOMPLETE 路徑，
      // 模型在 finalResult 塞滿五風格（雙軌殘骸）也一樣。
      emitError(
        "STREAM_INCOMPLETE_REPLY_OPTIONS",
        "Streaming analysis ended before the selected reply option arrived.",
        true,
        { missingStyles: [pendingThinRecommendation.selectedStyle] },
      );
      closed = true;
      return;
    }
    const finalResult = {
      ...assembler.build(),
      ...phase0Snapshot(observedSelectedStyle, true),
    };
    const missingStyles = findMissingRequiredReplyStyles(
      finalResult,
      requiredReplyStyles,
    );
    if (missingStyles.length > 0) {
      emitError(
        "STREAM_INCOMPLETE_REPLY_OPTIONS",
        "Streaming analysis ended before every allowed reply style was generated.",
        true,
        { missingStyles },
      );
      closed = true;
      return;
    }
    options.emit({
      type: "analysis.done",
      finalResult,
    });
    doneEmitted = true;
    closed = true;
  };

  const hasCompletionAnchor = () =>
    officialRecommendationEmitted || modelDoneHadFinalResult;

  const emitMissingCompletionAnchor = () => {
    emitError(
      "STREAM_MISSING_COMPLETION_ANCHOR",
      "Streaming analysis ended before an official recommendation or final result.",
    );
    closed = true;
  };

  const absorbAndEmit = (event: StreamOutputEvent) => {
    assembler.absorb(event);
    options.emit(event);
  };

  const styleIsAllowed = (style: StreamStyle) =>
    requiredReplyStyleSet.size === 0 || requiredReplyStyleSet.has(style);

  const rejectUnavailableAnchorStyle = (style: StreamStyle) => {
    emitError(
      "STREAM_UNAVAILABLE_REPLY_STYLE",
      "Streaming analysis selected a reply style outside this user's plan.",
      true,
      { selectedStyle: style },
    );
    closed = true;
  };

  const flushPreChargeEvents = () => {
    for (const bufferedEvent of preChargeEvents) {
      if (closed) break;
      // No-send mode: an out-of-order reply_option / recommendation that
      // arrived before the decision must not leak through the buffer either.
      if (
        noSendDecision &&
        (bufferedEvent.type === "analysis.reply_option" ||
          bufferedEvent.type === "analysis.recommendation")
      ) {
        continue;
      }
      // pre-charge buffer 裡的 reply_option 也要過 bind（模型亂序時
      // selected option 可能先於瘦卡到貨）。
      if (bufferedEvent.type === "analysis.reply_option") {
        forwardReplyOption(bufferedEvent);
      } else {
        absorbAndEmit(bufferedEvent);
      }
    }
    preChargeEvents.length = 0;
  };

  // 選中風格＝扣費錨點的風格：瘦卡優先，否則 decision。
  const selectedStyleNow = (): StreamStyle | null =>
    pendingThinRecommendation?.selectedStyle ?? decisionSelectedStyle;

  // 件4 D4：reply_option 轉發前由 server 合成 flat message / quotedContext
  // 相容欄位（segments join），App 收到的形狀與今天相同。
  const forwardReplyOption = (event: StreamEvent) => {
    const segments = replySegmentsFrom(
      event.segments ?? event.messages ?? event.messageGroup ??
        event.replySegments,
    );
    const compat = withReplyOptionCompatFields(event, segments);
    const style = replyStyleFrom(compat);
    if (style) {
      const variant = evidenceVariantFrom(compat, segments);
      if (Object.keys(variant).length > 0) {
        evidenceVariants.set(style, variant);
      }
    }
    // 球數案閘 — 2026-06-13 改 fail-soft（log-only）。
    // 原硬擋（不達下限/取略球→丟 option→終局 INCOMPLETE）在 dogfood 造成真實
    // 分析失敗（「請重新分析」）＝guard 非 generator，模型不服從時倒楣的是用戶。
    // 定調（2026-06-13 dogfood 後）：只記錄、不擋，照出選中風格回覆；接球率由
    // (b)(c) prompt 提升，dogfood 第2/3張圖確認 prompt 單獨即達標。
    // 重設計（讓閘改丟略球段）已主動劃掉——重進丟段＋扣費高風險區去解一個
    // dogfood 已不存在的問題＝YAGNI。此處永久保留為 observability canary：
    // verdict.ok=false 的 log 是「prompt 接球率退步」的免費預警，不擋用戶。
    // ⚠️ 絕不把此 block 改回丟 option／終局 INCOMPLETE——那正是炸過的 guard。
    //
    // 2026-08-09 球數對齊批：檢查從「只驗選中風格」擴成每個 option 都驗（prompt
    // 同批改成 EVERY option 適用 floor），仍然 log-only。[ball_coverage] 每個
    // option 記一行覆蓋數，上線一週後對拍驗 prompt 成效（黑箱重驗）。
    if (inventory && style) {
      const verdict = validateSelectedSegments(inventory, segments);
      // 錨點（瘦卡/decision）還沒建立時標 unknown，不誤標 non-selected 污染
      // telemetry（Codex 雙審 P2；precharged legacy 路徑可能整條無錨）。
      const anchor = selectedStyleNow();
      const selectedLabel = anchor == null ? "unknown" : `${style === anchor}`;
      const covered = coveredIndependentBalls(inventory, segments);
      // indices 必記：same-set 對拍要比「集合」，只看 covered 數會把
      // {1,2,3} 與 {3,4,5} 都當 3/N（Codex 雙審 Spec P1）。
      const indices = [...covered].sort((a, b) => a - b).join(",");
      console.log(
        `[ball_coverage] style=${style} selected=${selectedLabel} ` +
          `covered=${covered.size}/${inventory.independentCount} ` +
          `indices=[${indices}] floor=${segmentFloor(inventory)} ` +
          `segments=${segments.length} ok=${verdict.ok}`,
      );
      if (!verdict.ok) {
        console.warn(
          `[ball_inventory] soft-pass ${
            anchor == null
              ? "unanchored"
              : style === anchor
              ? "selected"
              : "non-selected"
          } style ${style}: ${verdict.reason}`,
        );
      }
    }
    if (style) seenReplyOptions.set(style, { compat, segments });
    if (
      pendingThinRecommendation &&
      replyStyleFrom(compat) === pendingThinRecommendation.selectedStyle &&
      !bindPendingRecommendation(compat, segments)
    ) {
      return; // 回填後 safety 擋下，stream 已關。
    }
    if (closed) return;
    absorbAndEmit(compat);
  };

  // 件4 扣卡回填：join 後全文 + 原始段落塞回瘦推薦卡，先轉發 enriched
  // recommendation 再轉發 selected reply_option（D3 舊順序）。safety 檢查
  // 對象是 join 後全文——驗的內容跟今天相同，只是時機後移。
  const bindPendingRecommendation = (
    option: StreamEvent,
    segments: readonly Record<string, unknown>[],
  ): boolean => {
    const thin = pendingThinRecommendation!;
    const joined = stringField(option.message) || joinedSegmentReply(segments);
    if (!joined) return true; // 無文字可回填：留 pending，終局走 INCOMPLETE。

    const quotedContext = stringField(option.quotedContext) ||
      joinedSegmentSources(segments);
    const backfill = validateRecommendationBackfill(joined, quotedContext);
    if (!backfill.ok) {
      emitError(backfill.code, backfill.reason);
      closed = true;
      return false;
    }

    pendingThinRecommendation = null;
    officialRecommendationEmitted = true;
    absorbAndEmit({
      ...thin.raw,
      type: "analysis.recommendation",
      selectedStyle: thin.selectedStyle,
      message: joined,
      reason: thin.reason,
      quotedContext,
      warnings: [...thin.warnings, ...backfill.warnings],
      ...(segments.length > 0 ? { replySegments: [...segments] } : {}),
    });
    return true;
  };

  // 黑箱 r1 韌性網：瘦卡晚到（selected option 已轉發）→ 立即補綁；瘦卡
  // 整條 stream 沒來 → 用 decision 的 selectedStyle + 該風格 option 合成
  // 推薦卡（扣費語意不變，decision 仍是第一扣費錨點）。
  const tryLateBind = () => {
    if (closed || officialRecommendationEmitted || !chargeCompleted) return;
    if (!pendingThinRecommendation) {
      if (!decisionSelectedStyle) return;
      const stored = seenReplyOptions.get(decisionSelectedStyle);
      if (!stored) return;
      pendingThinRecommendation = {
        ok: true,
        selectedStyle: decisionSelectedStyle,
        message: "",
        reason: stringField(stored.compat.reason ?? stored.compat.approach),
        quotedContext: "",
        warnings: [],
        raw: {
          type: "analysis.recommendation",
          selectedStyle: decisionSelectedStyle,
          synthesizedFromDecision: true,
        },
      };
    }
    const stored = seenReplyOptions.get(
      pendingThinRecommendation.selectedStyle,
    );
    if (!stored) return;
    bindPendingRecommendation(stored.compat, stored.segments);
  };

  const chargeFromValidation = async (
    validation: Extract<RecommendationValidation, { ok: true }>,
  ): Promise<boolean> => {
    observedSelectedStyle = validation.selectedStyle;
    const chargeResult = await options.onRecommendation({
      ...toChargePayload(validation),
      // The charge anchor is immutable after this call. Later reply options
      // intentionally stay out of recommendation_json and appear only in the
      // completed finalResult snapshot.
      ...phase0Snapshot(validation.selectedStyle, false),
    });
    if (!chargeResult.charged) {
      emitError(
        chargeResult.code ?? "STREAM_CHARGE_FAILED",
        chargeResult.message ?? DEFAULT_CHARGE_FAILURE_MESSAGE,
        chargeResult.recoverable ?? true,
      );
      closed = true;
      return false;
    }

    chargeCompleted = true;
    flushPreChargeEvents();
    return true;
  };

  const handleDecision = async (event: StreamEvent) => {
    if (resumeDecisionReplayPending) {
      resumeDecisionReplayPending = false;
      return;
    }

    if (noSendDecision) return;

    // First anchor wins: once a send anchor (decision or thin card) has been
    // charged, a late no-send decision can neither retarget the charge nor
    // reach the client next to reply cards. Drop it.
    if (
      options.noSendDecisions && chargeCompleted &&
      isNoSendDecisionKind(event.messageDecision)
    ) {
      return;
    }

    if (
      options.noSendDecisions && !chargeCompleted &&
      isNoSendDecisionKind(event.messageDecision)
    ) {
      const validation = validateNoSendDecisionEvent(event);
      if (!validation.ok) {
        emitError(validation.code, validation.reason);
        closed = true;
        return;
      }
      analysisDecisionV2 = cloneRecord(validation.payload.analysisDecisionV2);
      const payload: StreamNoSendRecommendationForCharge = {
        ...validation.payload,
        ...phase0Snapshot(null, false),
      };
      const chargeResult = await options.onRecommendation(payload);
      if (!chargeResult.charged) {
        emitError(
          chargeResult.code ?? "STREAM_CHARGE_FAILED",
          chargeResult.message ?? DEFAULT_CHARGE_FAILURE_MESSAGE,
          chargeResult.recoverable ?? true,
        );
        closed = true;
        return;
      }
      noSendDecision = payload;
      chargeCompleted = true;
      officialRecommendationEmitted = true;
      flushPreChargeEvents();
      absorbAndEmit(noSendDecisionEvent(validation.payload));
      return;
    }

    if (!isResume && isStreamStyle(event.selectedStyle)) {
      decisionSelectedStyle = event.selectedStyle;
      observedSelectedStyle = event.selectedStyle;
    }

    if (chargeCompleted) {
      absorbAndEmit(event);
      return;
    }

    const validation = validateDecisionChargeEvent(event);
    if (!validation.ok) {
      emitError(validation.code, validation.reason);
      closed = true;
      return;
    }

    if (!styleIsAllowed(validation.selectedStyle)) {
      rejectUnavailableAnchorStyle(validation.selectedStyle);
      return;
    }

    if (!(await chargeFromValidation(validation))) return;
    absorbAndEmit(event);
  };

  // 件4：v2 瘦卡（無 message、帶 expectedReaction）→ buffer 等回填；
  // 帶 message 的 legacy 形狀照舊立即驗證+轉發（rollback 安全網）。
  const handleThinRecommendation = async (event: StreamEvent) => {
    const validation = validateThinRecommendationEvent(event);
    if (!validation.ok) {
      emitError(validation.code, validation.reason);
      closed = true;
      return;
    }

    if (!styleIsAllowed(validation.selectedStyle)) {
      rejectUnavailableAnchorStyle(validation.selectedStyle);
      return;
    }

    if (officialRecommendationEmitted || pendingThinRecommendation) {
      if (isResume) return;
      emitError(
        "STREAM_DUPLICATE_RECOMMENDATION",
        "Streaming analysis emitted more than one official recommendation.",
      );
      closed = true;
      return;
    }

    // 先掛 pending 再扣費：扣費成功的 flushPreChargeEvents 會把先到的
    // selected reply_option 路過 bind。
    pendingThinRecommendation = validation;
    if (!chargeCompleted && !(await chargeFromValidation(validation))) {
      pendingThinRecommendation = null;
      return;
    }
    // 瘦卡晚到：selected option 已轉發過 → 立即補綁。
    tryLateBind();
  };

  const handleRecommendation = async (event: StreamEvent) => {
    if (isThinRecommendationEvent(event)) {
      await handleThinRecommendation(event);
      return;
    }

    const validation = validateRecommendationEvent(event);
    if (!validation.ok) {
      emitError(validation.code, validation.reason);
      closed = true;
      return;
    }

    if (!styleIsAllowed(validation.selectedStyle)) {
      rejectUnavailableAnchorStyle(validation.selectedStyle);
      return;
    }

    if (officialRecommendationEmitted) {
      if (isResume) return;
      emitError(
        "STREAM_DUPLICATE_RECOMMENDATION",
        "Streaming analysis emitted more than one official recommendation.",
      );
      closed = true;
      return;
    }

    if (!chargeCompleted && !(await chargeFromValidation(validation))) return;

    officialRecommendationEmitted = true;
    const enriched = {
      ...event,
      selectedStyle: validation.selectedStyle,
      message: validation.message,
      reason: validation.reason,
      quotedContext: validation.quotedContext,
      warnings: validation.warnings,
    };
    absorbAndEmit(enriched);
  };

  const handleEvent = async (event: StreamEvent) => {
    if (closed) return;

    if (event.type === "analysis.divergence_plan") {
      // Phase 2a shadow。v1 從沒被要求吐這個事件：旗標關閉時把它當成過去
      // 的 unknown line——不算 valid event、不 buffer、不轉發。v2 只在「已
      // 扣費的 send 決策之後」收第一份合法計畫；decision 前或 no-send 一律
      // 丟掉，所以 no-send 的扣費快照永遠不會帶到計畫。
      if (!options.noSendDecisions) return;
      sawValidEvent = true;
      if (chargeCompleted && !noSendDecision && !analysisDivergencePlan) {
        analysisDivergencePlan = parseDivergencePlanV1(event);
      }
      return;
    }

    sawValidEvent = true;

    if (
      noSendDecision &&
      (event.type === "analysis.reply_option" ||
        event.type === "analysis.recommendation")
    ) {
      return;
    }

    if (event.type === "analysis.inventory") {
      // 硬版：保留 disposition map（軟版的純放行/buffer/emit 行為不變——
      // 不 return，讓事件照舊落到下方 buffer/emit）。
      const parsed = parseBallInventory(event);
      if (parsed) inventory = parsed;
      // Retries still parse replayed inventory for this stream's existing
      // fail-soft validation, but Phase 0 must retain only the charge-time
      // snapshot (or remain unknown when none was stored).
      if (!isResume) {
        const snapshot = inventorySnapshotFrom(event);
        if (snapshot) analysisInventory = snapshot;
      }
    }

    if (event.type === "analysis.decision" && !isResume && !noSendDecision) {
      const snapshot = decisionV2SnapshotFrom(event);
      if (snapshot) analysisDecisionV2 = snapshot;
    }

    if (event.type === "analysis.recommendation") {
      await handleRecommendation(event);
      return;
    }

    if (event.type === "analysis.decision") {
      await handleDecision(event);
      return;
    }

    if (event.type === "analysis.error") {
      options.emit(event);
      closed = true;
      return;
    }

    if (event.type === "analysis.reply_option") {
      const style = replyStyleFrom(event);
      if (style && !styleIsAllowed(style)) return;
      if (chargeCompleted) {
        forwardReplyOption(event);
        return;
      }
      // 未扣費：落到下方 pre-charge buffer，flush 時再過 bind。
    }

    if (!chargeCompleted) {
      if (event.type === "analysis.done") {
        emitError(
          "STREAM_MISSING_CHARGE_ANCHOR",
          "Streaming analysis ended before a chargeable decision or recommendation.",
        );
        closed = true;
        return;
      }

      preChargeEvents.push(event);
      return;
    }

    if (event.type === "analysis.done") {
      if (doneResultField(event)) {
        modelDoneHadFinalResult = true;
      }
      tryLateBind();
      if (closed) return;
      if (!hasCompletionAnchor()) {
        emitMissingCompletionAnchor();
        return;
      }
      assembler.absorb(event);
      emitDone();
      return;
    }

    absorbAndEmit(event);
  };

  const queueLine = (line: string) => {
    const trimmed = stripCarriageReturn(line).trim();
    if (!trimmed) return;
    pending = pending.then(async () => {
      if (closed) return;
      const event = parseEventLine(trimmed);
      if (!event) return;
      await handleEvent(event);
    }).catch((error) => {
      if (closed) return;
      emitError(
        "STREAM_REFRAMER_ERROR",
        error instanceof Error ? error.message : "Failed to process stream.",
      );
      closed = true;
    });
  };

  const drain = async () => {
    await pending;
  };

  return {
    pushText(chunk: string) {
      if (closed || chunk.length === 0) return;
      buffer += chunk;
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";
      for (const line of lines) queueLine(line);
    },

    drain,

    async flush() {
      if (buffer.trim()) queueLine(buffer);
      buffer = "";
      await drain();
      if (!closed && sawValidEvent) {
        if (chargeCompleted) tryLateBind();
        if (closed) return;
        if (chargeCompleted && hasCompletionAnchor()) {
          emitDone();
        } else if (chargeCompleted) {
          emitMissingCompletionAnchor();
        } else {
          emitError(
            "STREAM_MISSING_CHARGE_ANCHOR",
            "Streaming analysis ended before a chargeable decision or recommendation.",
          );
          closed = true;
        }
      }
    },
  };
}

export const createReframer = createStreamReframer;

// v2 瘦推薦卡判別：無 message + 帶 expectedReaction。message 缺但也沒
// expectedReaction 的事件仍走 legacy 驗證（維持 malformed 既有行為）。
export function isThinRecommendationEvent(
  event: StreamEvent | Record<string, unknown> | undefined,
): boolean {
  if (!event || event.type !== "analysis.recommendation") return false;
  return stringField(event.message) === "" &&
    stringField(event.expectedReaction) !== "";
}

function withReplyOptionCompatFields(
  event: StreamEvent,
  segments: readonly Record<string, unknown>[],
): StreamEvent {
  if (segments.length === 0) return event;
  const compat: StreamEvent = { ...event };
  if (stringField(compat.message) === "") {
    compat.message = joinedSegmentReply(segments);
  }
  if (stringField(compat.quotedContext) === "") {
    compat.quotedContext = joinedSegmentSources(segments);
  }
  return compat;
}

function joinedSegmentSources(
  segments: readonly Record<string, unknown>[],
): string {
  return segments
    .map((item) => stringField(item.sourceMessage))
    .filter((text) => text.length > 0)
    .join(" / ");
}

function stripCarriageReturn(line: string): string {
  return line.endsWith("\r") ? line.slice(0, -1) : line;
}

function toChargePayload(
  validation: Extract<RecommendationValidation, { ok: true }>,
): StreamRecommendationForCharge {
  return {
    selectedStyle: validation.selectedStyle,
    message: validation.message,
    reason: validation.reason,
    quotedContext: validation.quotedContext,
    warnings: validation.warnings,
    raw: validation.raw,
  };
}

export function toRecommendationEvent(
  recommendation: StreamChargePayload,
): StreamOutputEvent {
  if (isNoSendChargePayload(recommendation)) {
    return noSendDecisionEvent(recommendation);
  }
  if (recommendation.raw.type === "analysis.decision") {
    return {
      ...recommendation.raw,
      type: "analysis.decision",
      selectedStyle: recommendation.selectedStyle,
    };
  }

  return {
    ...recommendation.raw,
    type: "analysis.recommendation",
    selectedStyle: recommendation.selectedStyle,
    message: recommendation.message,
    reason: recommendation.reason,
    quotedContext: recommendation.quotedContext,
    warnings: recommendation.warnings,
  };
}

function createLegacyAnalysisAssembler() {
  const result: Record<string, unknown> = {
    // 對象卡互動階段閉環：不種 current/status 種子——模型整條 stream 沒給
    // 可映射 stage 時，finalResult 不得假裝「本次判定是 opening」。client
    // 端把缺 current 視為本次無有效 stage（保留上一個有效快照或問號）。
    gameStage: {
      nextStep: "",
    },
    enthusiasm: {
      score: 50,
    },
    topicDepth: {
      current: "facts",
      suggestion: "",
    },
    psychology: {
      subtext: "",
    },
    replies: {},
    replyOptions: {},
    stretchLevels: {},
    finalRecommendation: {
      pick: "",
      content: "",
      reason: "",
      psychology: "",
    },
    warnings: [],
    strategy: "",
    reminder: "",
  };

  // 件4 廢除雙軌：bind 過的 finalRecommendation（帶 segments）為權威，
  // 模型 done finalResult 不得 clobber。
  let finalRecommendationAuthoritative = false;

  // 2026-07-02 Codex 雙審 P2：metrics 給出可映射 gameStage 後為權威，
  // done/report_section 不得覆蓋 current/status。
  let gameStageAuthoritative = false;

  const absorbReply = (
    style: StreamStyle,
    message: string,
    reason: string,
    quotedContext: string,
    markFinal: boolean,
    segments?: readonly Record<string, unknown>[],
    stretchLevel?: StretchLevel,
  ) => {
    const replies = ensureRecord(result, "replies");
    replies[style] = message;

    const stretchLevels = ensureRecord(result, "stretchLevels");
    stretchLevels[style] = stretchLevel ?? "within";

    const replyOptions = ensureRecord(result, "replyOptions");
    replyOptions[style] = {
      approach: reason,
      messages: segments && segments.length > 0 ? [...segments] : [
        {
          label: "recommended",
          sourceMessage: quotedContext,
          reply: message,
          reason,
        },
      ],
    };

    if (markFinal) {
      const hasSegments = segments != null && segments.length > 0;
      result.finalRecommendation = {
        pick: style,
        content: message,
        reason,
        psychology: reason,
        ...(hasSegments ? { replySegments: [...segments] } : {}),
      };
      if (hasSegments) finalRecommendationAuthoritative = true;
    }
  };

  return {
    absorb(event: StreamOutputEvent) {
      if (event.type === "analysis.recommendation") {
        const style = streamStyleFrom(event.selectedStyle ?? event.style);
        const message = stringField(event.message);
        if (!style || !message) return;
        absorbReply(
          style,
          message,
          stringField(event.reason),
          stringField(event.quotedContext),
          true,
          // bind 回填的 enriched recommendation 帶原始段落陣列。
          replySegmentsFrom(event.replySegments ?? event.segments),
          normalizeStretchLevel(event.stretchLevel),
        );
        return;
      }

      if (event.type === "analysis.reply_option") {
        const style = streamStyleFrom(event.style ?? event.selectedStyle);
        // 2026-06-12 P0：#12 一球一回 prompt 下，多球對話的 reply_option
        // 常只帶 messages 段落陣列、無頂層 message 字串——必須回退到
        // segments join，否則該風格被靜默丟棄，emitDone 會誤判
        // STREAM_INCOMPLETE_REPLY_OPTIONS（與 findMissingRequiredReplyStyles
        // 的 segments 寬容度對齊）。
        const segments = replySegmentsFrom(
          event.segments ?? event.messages ?? event.messageGroup ??
            event.replySegments,
        );
        const message = stringField(event.message) ||
          joinedSegmentReply(segments);
        if (!style || !message) return;
        absorbReply(
          style,
          message,
          stringField(event.reason ?? event.approach),
          stringField(event.quotedContext ?? event.sourceMessage),
          event.isSelected === true,
          segments,
          normalizeStretchLevel(event.stretchLevel),
        );
        return;
      }

      if (event.type === "analysis.decision") {
        result.streamingDecision = omitType(event);
        const nextStep = stringField(
          event.nextStepBody ?? event.nextStep ?? event.doThis,
        );
        if (nextStep) {
          const gameStage = ensureRecord(result, "gameStage");
          gameStage.nextStep = nextStep;
        }
        return;
      }

      if (event.type === "analysis.metrics") {
        absorbMetrics(event);
        return;
      }

      if (event.type === "analysis.coach_hint") {
        const coerced = coerceClientShapeValue(
          result,
          "coachActionHint",
          event.coachActionHint ?? omitType(event),
        );
        if (coerced !== undefined) result.coachActionHint = coerced;
        return;
      }

      if (event.type === "analysis.report_section") {
        absorbReportSection(event);
        return;
      }

      if (event.type === "analysis.done") {
        const finalResult = doneResultField(event);
        if (finalResult) mergeFinalResult(finalResult);
      }
    },

    build(): Record<string, unknown> {
      return JSON.parse(JSON.stringify(result)) as Record<string, unknown>;
    },
  };

  function absorbMetrics(event: Record<string, unknown>) {
    const enthusiasm = recordField(event.enthusiasm);
    if (enthusiasm) {
      result.enthusiasm = normalizeRecordForClient("enthusiasm", enthusiasm);
    }

    const score = numberField(
      event.heat ?? event.enthusiasmScore ?? event.score,
    );
    if (score !== null) {
      const target = ensureRecord(result, "enthusiasm");
      target.score = Math.round(score);
    }

    const dimensions = recordField(event.dimensions);
    if (dimensions) {
      result.dimensions = normalizeRecordForClient("dimensions", dimensions);
    }

    const topicDepth = recordField(event.topicDepth);
    if (topicDepth) {
      result.topicDepth = normalizeRecordForClient("topicDepth", topicDepth);
    }

    // 2026-07-02 dogfood：stream 協議 v2 後沒有 required 事件承載 gameStage，
    // assembler 種子 opening 永遠外流 → UI 對話進度永遠卡破冰。stage 掛在
    // metrics（required、模型穩定會發），與 done merge 走同一條值域守門。
    const gameStage = recordField(event.gameStage);
    if (gameStage) {
      const coerced = coerceClientShapeValue(result, "gameStage", gameStage);
      if (coerced !== undefined) result.gameStage = coerced;
      // metrics 給出可映射 stage 後即為權威（Codex 雙審 P2）：base prompt
      // 的 legacy schema 範例仍含 gameStage，done/report_section 照抄殘骸
      //（opening/premise）不得反過來覆蓋 current/status。
      if (normalizeGameStageCurrent(gameStage.current)) {
        gameStageAuthoritative = true;
      }
    }
  }

  // done/report_section 寫 gameStage 前的權威守門：metrics 已定 stage 時
  // 只准補其他欄位（如 nextStep），current/status 回填 metrics 版本。
  function guardAuthoritativeGameStage(coerced: unknown): unknown {
    if (!gameStageAuthoritative || !isRecord(coerced)) return coerced;
    const existing = isRecord(result.gameStage)
      ? result.gameStage as Record<string, unknown>
      : {};
    return { ...coerced, current: existing.current, status: existing.status };
  }

  function absorbReportSection(event: Record<string, unknown>) {
    const section = stringField(event.section);
    if (!section) return;
    if (SERVER_DERIVED_PHASE0_FINAL_RESULT_KEYS.has(section)) return;

    const payload = event.payload ?? event.content;
    if (section === "strategy") {
      result.strategy = stringField(payload) || JSON.stringify(payload ?? "");
      return;
    }

    // 同一個 result 的另一條寫入路徑，必須走與 done merge 相同的形狀守門
    // （2026-06-13 queue 補強：section=gameStage/psychology 字串 payload 可
    // 繞過 mergeFinalResult 的 coerce）。
    let coerced = coerceClientShapeValue(
      result,
      section,
      payload ?? omitType(event),
    );
    if (section === "gameStage") {
      coerced = guardAuthoritativeGameStage(coerced);
    }
    if (coerced === undefined) return;
    result[section] = coerced;
  }

  function mergeFinalResult(finalResult: Record<string, unknown>) {
    for (const [key, value] of Object.entries(finalResult)) {
      if (SERVER_DERIVED_PHASE0_FINAL_RESULT_KEYS.has(key)) continue;
      // 廢除雙軌：finalRecommendation 一律以 selected reply_option 回填
      // 的版本為準，模型 done 殘骸不得覆蓋。
      if (key === "finalRecommendation" && finalRecommendationAuthoritative) {
        continue;
      }
      let coerced = coerceClientShapeValue(result, key, value);
      if (key === "gameStage") {
        coerced = guardAuthoritativeGameStage(coerced);
      }
      if (coerced === undefined) continue;
      result[key] = coerced;
    }
  }
}

// client AnalysisResult.fromJson 對這些 key 是硬 cast Map<String, dynamic>，
// 收到字串會 throw INVALID_STREAM_RESULT（dogfood P0 2026-06-13：Haiku 常把
// gameStage/psychology 攤平成字串，Sonnet 偶發）。merge 時必須守門：能語意
// 映射的塞回正確欄位，不能的丟棄保留 assembler 既有值，絕不原樣 clobber。
const RECORD_ONLY_FINAL_RESULT_KEYS = new Set([
  "gameStage",
  "psychology",
  "topicDepth",
  "enthusiasm",
  "replies",
  "replyOptions",
  "finalRecommendation",
  "usage",
  "targetProfile",
  "healthCheck",
  "optimizedMessage",
  "myMessageAnalysis",
  "recognizedConversation",
  "coachActionHint",
  "dimensions",
  "dogfoodComparison",
  // Phase 0 additive fields are records. Scalar/array model output must not
  // clobber a valid snapshot or reach a client that assumes object shape.
  "analysisDecisionV2",
  "analysisInventory",
  "analysisEvidenceLinkage",
  "analysisDivergencePlan",
]);

// Phase 0 snapshots are captured only from their typed stream events (or a
// persisted charge anchor on retry). A model's generic finalResult/report
// payload must never manufacture or replace that server-derived evidence.
const SERVER_DERIVED_PHASE0_FINAL_RESULT_KEYS = new Set([
  "analysisDecisionV2",
  "analysisInventory",
  "analysisEvidenceLinkage",
  "analysisDivergencePlan",
]);

// client 是 List<String>.from(json[key])，字串/物件 clobber 都會 throw。
export const ARRAY_ONLY_FINAL_RESULT_KEYS = new Set([
  "warnings",
]);

// client 是 json[key] as String?（或直塞 String 欄位），物件/數字 clobber
// 都會 throw。非字串丟棄保留 assembler 預設值。
export const STRING_ONLY_FINAL_RESULT_KEYS = new Set([
  "strategy",
  "reminder",
]);

// client GameStage.fromString / GameStageStatus.fromString（game_stage.dart）
// 是大小寫敏感的 enum 名精確比對，match 不到就「靜默」fallback opening/normal
// ——垃圾值不會 throw，只會讓 UI 永遠顯示破冰。所以 server 端必須把模型的
// 中文標籤、大寫變體正規化成 client enum 名；映射不到就丟棄保留既有值。
const GAME_STAGE_CURRENT_SYNONYMS: ReadonlyArray<
  readonly [string, readonly string[]]
> = [
  ["opening", ["opening", "破冰", "打開"]],
  ["premise", ["premise", "升溫", "前提", "曖昧"]],
  ["qualification", ["qualification", "評估", "深入", "篩選"]],
  ["narrative", ["narrative", "敘事", "連結", "說故事"]],
  ["close", ["close", "收尾", "邀約"]],
];

const GAME_STAGE_STATUS_SYNONYMS: ReadonlyArray<
  readonly [string, readonly string[]]
> = [
  ["normal", ["normal", "正常進行", "正常", "進展順利"]],
  ["stuckFriend", ["stuckfriend", "stuck_friend", "偏向朋友", "朋友感"]],
  [
    "canAdvance",
    ["canadvance", "can_advance", "可以推進", "時機成熟", "可以更進一步"],
  ],
  ["shouldRetreat", ["shouldretreat", "should_retreat", "放慢", "退回"]],
];

function normalizeFromSynonyms(
  value: unknown,
  table: ReadonlyArray<readonly [string, readonly string[]]>,
): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim().toLowerCase();
  if (!text) return null;
  for (const [canonical, keys] of table) {
    if (keys.includes(text)) return canonical;
  }
  // 複合寫法（"Qualification (評估)"、"升溫階段"）走包含比對；命中超過
  // 一個 canonical（否定/跨階段句如「升溫之後，接近評估」）＝歧義，
  // 拒絕映射保留既有值（Codex 雙審 P3）。
  let hit: string | null = null;
  for (const [canonical, keys] of table) {
    if (keys.some((key) => text.includes(key))) {
      if (hit !== null && hit !== canonical) return null;
      hit = canonical;
    }
  }
  return hit;
}

function normalizeGameStageCurrent(value: unknown): string | null {
  return normalizeFromSynonyms(value, GAME_STAGE_CURRENT_SYNONYMS);
}

function normalizeGameStageStatus(value: unknown): string | null {
  return normalizeFromSynonyms(value, GAME_STAGE_STATUS_SYNONYMS);
}

function coerceGameStageValue(
  result: Record<string, unknown>,
  value: unknown,
): Record<string, unknown> | undefined {
  const existing = isRecord(result.gameStage)
    ? result.gameStage as Record<string, unknown>
    : {};
  if (isRecord(value)) {
    const conformed = normalizeRecordForClient("gameStage", value);
    // merge 而非整顆替換：decision 事件先填的 nextStep 不能被 compact
    // finalResult 的 gameStage 蓋掉。
    const merged: Record<string, unknown> = { ...existing, ...conformed };
    const current = normalizeGameStageCurrent(conformed.current);
    if (current) merged.current = current;
    else if ("current" in existing) merged.current = existing.current;
    else delete merged.current;
    const status = normalizeGameStageStatus(conformed.status);
    if (status) merged.status = status;
    else if ("status" in existing) merged.status = existing.status;
    else delete merged.status;
    return merged;
  }
  const text = typeof value === "string" ? value.trim() : "";
  if (!text) return undefined;
  const current = normalizeGameStageCurrent(text);
  if (!current) return undefined;
  return { ...existing, current };
}

function coerceClientShapeValue(
  result: Record<string, unknown>,
  key: string,
  value: unknown,
): unknown | undefined {
  if (ARRAY_ONLY_FINAL_RESULT_KEYS.has(key)) {
    return coerceStringArray(value);
  }
  if (STRING_ONLY_FINAL_RESULT_KEYS.has(key)) {
    return typeof value === "string" ? value : undefined;
  }
  if (key === "gameStage") return coerceGameStageValue(result, value);
  if (!RECORD_ONLY_FINAL_RESULT_KEYS.has(key)) return value;
  if (isRecord(value)) return normalizeRecordForClient(key, value);

  const existing = isRecord(result[key])
    ? result[key] as Record<string, unknown>
    : {};
  const text = typeof value === "string" ? value.trim() : "";

  if (key === "psychology" && text) return { ...existing, subtext: text };
  if (key === "topicDepth" && text) {
    return { ...existing, current: normalizeTopicDepthCurrent(text) };
  }
  if (key === "enthusiasm") {
    const score = numberField(value);
    if (score !== null) return { ...existing, score: Math.round(score) };
  }
  return undefined;
}

// record 形狀正確不代表欄位安全——client fromJson 對巢狀欄位一樣硬 cast
// （as String? / as bool? / as int? / List<String>.from），錯型必 throw。
// 這張表是 client 契約（analysis_models.dart + analysis_result.dart 的
// fromJson）的 server 端轉錄：宣告每個 key 下 client 會硬 cast 的欄位形狀，
// 不符就丟欄位讓 client 走預設值，不在表上的欄位原樣放行。
export type ClientFieldShape =
  | "string"
  | "boolean"
  | "int"
  | "number"
  | "stringArray"
  | { record: Record<string, ClientFieldShape> }
  | { recordArray: Record<string, ClientFieldShape> };

// client ReplySegment.fromJson：label/sourceMessage/reply/reason 全
// as String?（sourceIndex 是 is num 檢查，client 端寬容不用守）。
const REPLY_SEGMENT_FIELD_SHAPES: Record<string, ClientFieldShape> = {
  label: "string",
  sourceMessage: "string",
  reply: "string",
  reason: "string",
};

const FINAL_RECOMMENDATION_FIELD_SHAPES: Record<string, ClientFieldShape> = {
  pick: "string",
  content: "string",
  reason: "string",
  psychology: "string",
  replySegments: { recordArray: REPLY_SEGMENT_FIELD_SHAPES },
};

// client ReplyOption.fromJson 的 fallback 路徑 sourceMessage/reason
// as String?；messages/messageGroup/replySegments 走 ReplySegment 硬 cast。
// approach/reply/content 走 _normalizeRecommendationText，client 端寬容。
export const REPLY_OPTION_FIELD_SHAPES: Record<string, ClientFieldShape> = {
  sourceMessage: "string",
  reason: "string",
  messages: { recordArray: REPLY_SEGMENT_FIELD_SHAPES },
  messageGroup: { recordArray: REPLY_SEGMENT_FIELD_SHAPES },
  replySegments: { recordArray: REPLY_SEGMENT_FIELD_SHAPES },
};

export const CLIENT_RECORD_FIELD_SHAPES: Record<
  string,
  Record<string, ClientFieldShape>
> = {
  gameStage: { current: "string", status: "string", nextStep: "string" },
  topicDepth: { current: "string", suggestion: "string" },
  psychology: {
    subtext: "string",
    qualificationSignal: "boolean",
    shitTest: {
      record: { detected: "boolean", type: "string", suggestion: "string" },
    },
  },
  // stream client 另有 enthusiasm?['level'] as String?。
  enthusiasm: { score: "int", level: "string" },
  healthCheck: {
    issues: "stringArray",
    suggestions: "stringArray",
    hasNeedySignals: "boolean",
    hasInterviewStyle: "boolean",
    speakingRatio: "number",
  },
  finalRecommendation: FINAL_RECOMMENDATION_FIELD_SHAPES,
  coachActionHint: {
    catchablePoint: "string",
    read: "string",
    microMove: "string",
    avoid: "string",
    actionType: "string",
    confidence: "string",
  },
  usage: { imagesUsed: "int" },
  optimizedMessage: {
    original: "string",
    optimized: "string",
    reason: "string",
  },
  myMessageAnalysis: {
    sentMessage: "string",
    ifColdResponse: {
      record: { prediction: "string", suggestion: "string" },
    },
    ifWarmResponse: {
      record: { prediction: "string", suggestion: "string" },
    },
    backupTopics: "stringArray",
    warnings: "stringArray",
  },
  recognizedConversation: {
    contactName: "string",
    messageCount: "int",
    summary: "string",
    classification: "string",
    importPolicy: "string",
    confidence: "string",
    sideConfidence: "string",
    uncertainSideCount: "int",
    warning: "string",
    // client 是 (json['messages'] as List).map((m) => fromJson(m as Map))
    // ——非物件元素必 throw，過濾掉。
    messages: {
      recordArray: {
        side: "string",
        isFromMe: "boolean",
        content: "string",
        quotedReplyPreview: "string",
        quotedReplyPreviewIsFromMe: "boolean",
      },
    },
  },
  // client _parseDimensions 五鍵 as num?。
  dimensions: {
    heat: "number",
    engagement: "number",
    topicDepth: "number",
    replyWillingness: "number",
    emotionalConnection: "number",
  },
  // dogfood 比對卡內層走 FinalRecommendation.fromJson 同一套硬 cast。
  dogfoodComparison: {
    rawFullRecommendation: { record: FINAL_RECOMMENDATION_FIELD_SHAPES },
    officialFullRecommendation: { record: FINAL_RECOMMENDATION_FIELD_SHAPES },
  },
};

function normalizeRecordForClient(
  key: string,
  record: Record<string, unknown>,
): Record<string, unknown> {
  // legacy client 是 Map<String, String>.from(json['replies'])，非字串
  // value 必 throw——值全量過濾（key 是動態風格名，無法入欄位表）。
  if (key === "replies") return filterRecordToStringValues(record);
  // replyOptions 同樣是動態風格 key——每個 record value 各自 conform，
  // 非 record value 放行（client ReplyOption.fromJson 對非 Map 寬容）。
  if (key === "replyOptions") {
    let next: Record<string, unknown> | null = null;
    for (const [style, option] of Object.entries(record)) {
      if (!isRecord(option)) continue;
      const conformed = conformRecordFields(option, REPLY_OPTION_FIELD_SHAPES);
      if (conformed === option) continue;
      next ??= { ...record };
      next[style] = conformed;
    }
    return next ?? record;
  }
  const shapes = CLIENT_RECORD_FIELD_SHAPES[key];
  if (!shapes) return record;
  const conformed = conformRecordFields(record, shapes);
  if (key !== "topicDepth" || typeof conformed.current !== "string") {
    return conformed;
  }
  const current = normalizeTopicDepthCurrent(conformed.current);
  return current === conformed.current ? conformed : { ...conformed, current };
}

function normalizeTopicDepthCurrent(value: string): string {
  switch (value.trim().toLowerCase()) {
    case "event-oriented":
      return "event";
    case "personal-oriented":
      return "personal";
    case "intimate-oriented":
      return "intimate";
    default:
      return value;
  }
}

function conformRecordFields(
  record: Record<string, unknown>,
  shapes: Record<string, ClientFieldShape>,
): Record<string, unknown> {
  let next: Record<string, unknown> | null = null;
  for (const [field, shape] of Object.entries(shapes)) {
    if (!(field in record)) continue;
    const original = record[field];
    const conformed = conformFieldShape(shape, original);
    if (conformed === original) continue;
    next ??= { ...record };
    if (conformed === undefined) delete next[field];
    else next[field] = conformed;
  }
  return next ?? record;
}

function conformFieldShape(
  shape: ClientFieldShape,
  value: unknown,
): unknown | undefined {
  if (typeof shape === "object") {
    if ("recordArray" in shape) {
      if (!Array.isArray(value)) return undefined;
      return value
        .filter(isRecord)
        .map((item) => conformRecordFields(item, shape.recordArray));
    }
    return isRecord(value)
      ? conformRecordFields(value, shape.record)
      : undefined;
  }
  switch (shape) {
    case "string":
      return typeof value === "string" ? value : undefined;
    case "boolean":
      return typeof value === "boolean" ? value : undefined;
    case "number":
      return typeof value === "number" && Number.isFinite(value)
        ? value
        : undefined;
    case "int": {
      // client as int? 收到 float 也 throw——一律取整；數字字串（"72.6"）
      // 語意可靠可 parse，垃圾值丟欄位走 client 預設。
      const parsed = typeof value === "number"
        ? value
        : typeof value === "string" && value.trim() !== ""
        ? Number(value)
        : NaN;
      return Number.isFinite(parsed) ? Math.round(parsed) : undefined;
    }
    case "stringArray":
      return coerceStringArray(value);
  }
}

function filterRecordToStringValues(
  record: Record<string, unknown>,
): Record<string, unknown> {
  const entries = Object.entries(record).filter(
    ([, value]) => typeof value === "string",
  );
  if (entries.length === Object.keys(record).length) return record;
  return Object.fromEntries(entries);
}

// client 是 List<String>.from——非陣列 clobber 與混型元素都會 throw。
// 字串語意映射成單元素陣列，其餘丟棄。
function coerceStringArray(value: unknown): string[] | undefined {
  if (Array.isArray(value)) {
    return value.filter((item): item is string => typeof item === "string");
  }
  const text = typeof value === "string" ? value.trim() : "";
  return text ? [text] : undefined;
}

function ensureRecord(
  target: Record<string, unknown>,
  key: string,
): Record<string, unknown> {
  const value = target[key];
  if (isRecord(value)) return value;
  const next: Record<string, unknown> = {};
  target[key] = next;
  return next;
}

function streamStyleFrom(value: unknown): StreamStyle | null {
  return isStreamStyle(value) ? value : null;
}

function replyStyleFrom(event: Record<string, unknown>): StreamStyle | null {
  return streamStyleFrom(event.style ?? event.selectedStyle);
}

function stringField(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function numberField(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function recordField(value: unknown): Record<string, unknown> | null {
  return isRecord(value) ? value : null;
}

function normalizeRequiredReplyStyles(
  values: readonly StreamStyle[] | undefined,
): StreamStyle[] {
  if (!values) return [];

  const normalized: StreamStyle[] = [];
  for (const value of values) {
    if (isStreamStyle(value) && !normalized.includes(value)) {
      normalized.push(value);
    }
  }
  return normalized;
}

function findMissingRequiredReplyStyles(
  result: Record<string, unknown>,
  requiredStyles: readonly StreamStyle[],
): StreamStyle[] {
  if (requiredStyles.length === 0) return [];

  const replies = recordField(result.replies) ?? {};
  const replyOptions = recordField(result.replyOptions) ?? {};

  return requiredStyles.filter((style) =>
    !hasUsableReplyValue(replies[style]) &&
    !hasUsableReplyOption(replyOptions[style])
  );
}

function hasUsableReplyValue(value: unknown): boolean {
  if (stringField(value).length > 0) return true;
  if (!isRecord(value)) return false;

  return [
    value.reply,
    value.content,
    value.text,
    value.message,
  ].some((candidate) => stringField(candidate).length > 0) ||
    hasUsableReplySegments(
      value.messages ?? value.messageGroup ?? value.replySegments,
    );
}

function hasUsableReplyOption(value: unknown): boolean {
  if (!isRecord(value)) return false;

  return [
    value.reply,
    value.content,
    value.text,
    value.message,
  ].some((candidate) => stringField(candidate).length > 0) ||
    hasUsableReplySegments(
      value.messages ?? value.messageGroup ?? value.replySegments,
    );
}

function replySegmentsFrom(value: unknown): Record<string, unknown>[] {
  if (!Array.isArray(value)) return [];
  const segments: Record<string, unknown>[] = [];
  for (const item of value) {
    if (!isRecord(item)) continue;
    if (stringField(item.reply ?? item.content ?? item.text).length === 0) {
      continue;
    }
    // 段落會經 replyOptions[].messages 與 finalRecommendation.replySegments
    // 進 client ReplySegment.fromJson 硬 cast——入口即 conform。
    segments.push(conformRecordFields(item, REPLY_SEGMENT_FIELD_SHAPES));
  }
  return segments;
}

function joinedSegmentReply(
  segments: readonly Record<string, unknown>[],
): string {
  return segments
    .map((item) => stringField(item.reply ?? item.content ?? item.text))
    .filter((text) => text.length > 0)
    .join("\n");
}

function hasUsableReplySegments(value: unknown): boolean {
  if (!Array.isArray(value)) return false;
  return value.some((item) =>
    isRecord(item) &&
    stringField(item.reply ?? item.content ?? item.text).length > 0
  );
}

function doneResultField(event: Record<string, unknown>) {
  return recordField(event.finalResult) ?? recordField(event.result);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function omitType(event: Record<string, unknown>): Record<string, unknown> {
  const { type: _type, ...rest } = event;
  return rest;
}
