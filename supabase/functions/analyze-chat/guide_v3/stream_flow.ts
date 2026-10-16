// v3 串流分析（協定版本 3、開關 ANALYZE_GUIDE_V3 允許時）：讀局面（非串流＋
// json_schema）→ 程式排卡 → 串流寫卡，一行一張、每張各自定稿。
//
// 扣費（Eric 10/16）：第一張卡定稿、確定要送的那一刻扣一次；一張都沒送出不扣；
// 斷線時已送出的照留、算一次；先別回、停讀完就扣（不送型）；自傷關心不扣。
// run：pending →（扣費）charged → done；沒扣費就 failed。扣過費一定以 done 結案
//（寫卡中途出錯就用已送出的卡）。不重生、不 retry；續看只重播（run_shape.ts）。
import { jsonResponse } from "../http_response.ts";
import { type NdjsonEmit, ndjsonStreamResponse } from "../ndjson_response.ts";
import { stripClientHiddenFinalResult } from "../divergence_contract.ts";
import { mapStreamChargeFailure } from "../stream_charge_failure.ts";
import { handleStreamAnalysisResume } from "../stream_handler.ts";
import type {
  AnalysisStreamRun,
  ChargeStreamRunV3Input,
} from "../stream_run_store.ts";
import { createLineSplitter, parseWrittenCardLine } from "./cards.ts";
import { finalizeCard } from "./finalize.ts";
import { GUIDE_V3_VERSION } from "./guide_text.ts";
import { type GuideV3Plan, planTurn } from "./plan.ts";
import {
  type GuideV3Background,
  readSystemPrompt,
  readUserPrompt,
  writeSystemPrompt,
  writeUserPrompt,
} from "./prompts.ts";
import { parseReadTags, READ_TAGS_SCHEMA, type ReadTags } from "./read_tags.ts";
import { guideV3ResumeSnapshot, isGuideV3Run } from "./run_shape.ts";
import { type GuideMessage, toTurns, type Turn } from "./turns.ts";
import {
  cardEvent,
  cardView,
  finalResult,
  type GuideV3CardView,
  type GuideV3ReadView,
  type GuideV3Trace,
  readEvent,
  readView,
} from "./wire.ts";

/// 讀局面＋寫卡共用的模型期限（從請求開始算）。
export const GUIDE_V3_DEADLINE_MS = 90_000;
const DEFAULT_HEARTBEAT_INTERVAL_MS = 15_000;
/// 停（明確拒絕或封鎖）與自傷關心存進扣費紀錄的 stopCondition（RPC 要非空）。
export const STOP_CONDITION_STOP = "不再主動傳訊息";
export const STOP_CONDITION_CARE = "先確認安全";

export interface GuideV3RunPort {
  getRun(args: {
    runId: string;
    userId: string;
    conversationHash: string;
  }): Promise<AnalysisStreamRun>;
  createPendingRun(args: {
    userId: string;
    conversationHash: string;
    requestContext: Record<string, unknown>;
  }): Promise<AnalysisStreamRun>;
  chargeRunV3(input: ChargeStreamRunV3Input): Promise<unknown>;
  markDone(args: {
    runId: string;
    userId: string;
    conversationHash: string;
    finalResult: Record<string, unknown>;
  }): Promise<unknown>;
  markFailed(args: {
    runId: string;
    userId: string;
    conversationHash: string;
    code: string;
  }): Promise<unknown>;
}

export interface GuideV3ReadRequest {
  readonly runId: string;
  readonly system: string;
  readonly user: string;
  readonly schema: Record<string, unknown>;
  readonly deadlineAtMs: number;
}

export interface GuideV3WriteRequest {
  readonly runId: string;
  readonly system: string;
  readonly user: string;
  readonly deadlineAtMs: number;
}

export interface GuideV3Message {
  readonly isFromMe: boolean;
  readonly content: string;
  readonly quotedReplyPreview?: string;
}

export interface GuideV3StreamDeps {
  store: GuideV3RunPort;
  userId: string;
  analysisRunId: string | null;
  conversationHash: string;
  messages: readonly GuideV3Message[];
  background?: GuideV3Background;
  requestType: string;
  effectiveTier: string;
  accountIsTest: boolean;
  quotaUsage: {
    shouldChargeQuota: boolean;
    quotaReason: string;
    quotaUnit: string;
    chargedMessageCount: number;
    estimatedMessageCount: number;
  };
  monthlyLimit: number;
  dailyLimit: number;
  subMonthlyUsed: number;
  subDailyUsed: number;
  callRead(req: GuideV3ReadRequest): Promise<{ text: string; model: string }>;
  callWrite(
    req: GuideV3WriteRequest,
  ): Promise<{ model: string; textStream: AsyncIterable<string> }>;
  log(
    event: string,
    metadata: Record<string, unknown>,
    level?: "info" | "error",
  ): void;
  headers?: HeadersInit;
  now?: () => number;
  heartbeatIntervalMs?: number;
  resumePollIntervalMs?: number;
  resumeMaxWaitMs?: number;
  /// 讓 runtime 在 App 斷線後仍把這次流程跑完（production：EdgeRuntime.waitUntil）。
  waitUntil?: (task: Promise<unknown>) => void;
}

type ErrorEvent = Record<string, unknown> & {
  type: "analysis.error";
  code: string;
};

function errorEvent(
  code: string,
  message: string,
  recoverable: boolean,
): ErrorEvent {
  return { type: "analysis.error", code, message, recoverable };
}

function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/// 模型呼叫失敗（讀局面，或寫卡一張都還沒送出）→ App 看到的錯誤。都不扣額度。
export function upstreamErrorEvent(error: unknown): ErrorEvent {
  const code = typeof (error as { code?: unknown })?.code === "string"
    ? (error as { code: string }).code
    : "GUIDE_V3_UPSTREAM_FAILED";
  if (code === "MODEL_REFUSAL") {
    return errorEvent(
      code,
      "這段對話 AI 沒辦法分析，請調整內容後再試。本次不會扣額度。",
      false,
    );
  }
  return errorEvent(
    code,
    "分析暫時無法完成，請稍後重新分析。本次不會扣額度。",
    true,
  );
}

/// 引用回覆照 Eric 6/13 的中性寫法：不認是誰的訊息。
export function guideMessagesFrom(
  messages: readonly GuideV3Message[],
): GuideMessage[] {
  return messages.map((m) => {
    const quoted = m.quotedReplyPreview?.trim().replace(/\s+/g, " ");
    return {
      isFromMe: m.isFromMe,
      content: quoted ? `（引用：「${quoted}」）${m.content}` : m.content,
    };
  });
}

function parseTagsText(text: string): ReadTags | null {
  try {
    return parseReadTags(JSON.parse(text));
  } catch {
    return null;
  }
}

export async function handleGuideV3Stream(
  deps: GuideV3StreamDeps,
): Promise<Response> {
  if (deps.analysisRunId) return await resumeGuideV3(deps, deps.analysisRunId);
  const shouldCharge = deps.quotaUsage.shouldChargeQuota && !deps.accountIsTest;
  let run: AnalysisStreamRun;
  try {
    run = await deps.store.createPendingRun({
      userId: deps.userId,
      conversationHash: deps.conversationHash,
      requestContext: {
        responseMode: "stream",
        requestType: deps.requestType,
        guideVersion: GUIDE_V3_VERSION,
        tier: deps.effectiveTier,
        isTestAccount: deps.accountIsTest,
        estimatedMessageCount: deps.quotaUsage.estimatedMessageCount,
        chargedMessageCount: shouldCharge
          ? deps.quotaUsage.chargedMessageCount
          : 0,
      },
    });
  } catch (error) {
    deps.log(
      "guide_v3_run_create_failed",
      { error: errorText(error) },
      "error",
    );
    return jsonResponse({
      error: "STREAM_RUN_CREATE_FAILED",
      code: "STREAM_RUN_CREATE_FAILED",
      message: "串流分析暫時無法開始，請稍後再試。",
      retryable: false,
    }, 500);
  }
  const flow = new GuideV3Flow(deps, run.id, shouldCharge);
  return ndjsonStreamResponse((emit, close, _fail, isClosed) => {
    const task = flow.run(emit, isClosed).finally(close);
    deps.waitUntil?.(task.catch(() => undefined));
    return task;
  }, deps.headers);
}

async function resumeGuideV3(
  deps: GuideV3StreamDeps,
  runId: string,
): Promise<Response> {
  const now = deps.now ?? Date.now;
  const key = {
    runId,
    userId: deps.userId,
    conversationHash: deps.conversationHash,
  };
  let run: AnalysisStreamRun;
  try {
    run = await deps.store.getRun(key);
    if (Date.parse(run.expires_at) <= now()) {
      throw new Error("STREAM_RUN_EXPIRED");
    }
    // v2 的 run（開關剛打開前建立的）不在這裡重播：形狀不同，請 App 重新分析。
    if (!isGuideV3Run(run)) throw new Error("STREAM_RUN_NOT_RETRYABLE");
    if (run.status === "done" && !run.final_result_json) {
      throw new Error("STREAM_DONE_RESULT_MISSING");
    }
  } catch (error) {
    deps.log("guide_v3_resume_unavailable", {
      analysisRunId: runId,
      error: errorText(error),
    });
    return jsonResponse({
      error: "STREAM_RUN_RETRY_UNAVAILABLE",
      code: "STREAM_RUN_RETRY_UNAVAILABLE",
      message: "這次串流分析無法接續，請重新分析。",
      retryable: false,
    }, 409);
  }
  return handleStreamAnalysisResume({
    runId,
    conversationHash: deps.conversationHash,
    headers: deps.headers,
    initialRun: guideV3ResumeSnapshot(run, now()),
    loadRun: async () =>
      guideV3ResumeSnapshot(await deps.store.getRun(key), now()),
    pollIntervalMs: deps.resumePollIntervalMs,
    maxWaitMs: deps.resumeMaxWaitMs,
    onOutcome: (outcome, details) =>
      deps.log("guide_v3_resume_outcome", {
        analysisRunId: runId,
        outcome,
        ...details,
      }),
  });
}

class GuideV3Flow {
  private readonly now: () => number;
  private readonly startedAt: number;
  private readModel: string | undefined;
  private writeModel: string | undefined;
  /// 這個 run 已經寫進扣費紀錄（包含自傷關心的免扣紀錄）。
  private charged = false;

  constructor(
    private readonly deps: GuideV3StreamDeps,
    private readonly runId: string,
    private readonly shouldCharge: boolean,
  ) {
    this.now = deps.now ?? Date.now;
    this.startedAt = this.now();
  }

  private get key() {
    return {
      runId: this.runId,
      userId: this.deps.userId,
      conversationHash: this.deps.conversationHash,
    };
  }

  async run(emit: NdjsonEmit, isClosed: () => boolean): Promise<void> {
    const deadlineAtMs = this.startedAt + GUIDE_V3_DEADLINE_MS;
    emit({
      type: "analysis.started",
      runId: this.runId,
      conversationHash: this.deps.conversationHash,
      etaSeconds: 6,
      guideVersion: GUIDE_V3_VERSION,
    });
    const stopHeartbeat = this.startHeartbeat(emit);
    try {
      const turns = toTurns(guideMessagesFrom(this.deps.messages));
      let text: string;
      try {
        const read = await this.deps.callRead({
          runId: this.runId,
          system: readSystemPrompt(),
          user: readUserPrompt(turns, this.deps.background),
          schema: READ_TAGS_SCHEMA,
          deadlineAtMs,
        });
        text = read.text;
        this.readModel = read.model;
      } catch (error) {
        return await this.fail(emit, upstreamErrorEvent(error), {
          stage: "read",
          error: errorText(error),
        });
      }
      const tags = parseTagsText(text);
      if (!tags) {
        return await this.fail(
          emit,
          errorEvent(
            "GUIDE_V3_READ_INVALID",
            "分析暫時無法完成，請稍後重新分析。本次不會扣額度。",
            true,
          ),
          { stage: "read" },
        );
      }
      const plan = planTurn(turns, tags);
      const view = readView(plan, tags.light);
      switch (plan.decision) {
        case "care":
          return await this.care(emit, plan, view, tags);
        case "hold":
        case "stop":
          return await this.noSend(emit, plan, view, tags, isClosed);
        case "send":
        case "close":
          return await this.send(
            emit,
            plan,
            view,
            tags,
            turns,
            deadlineAtMs,
            isClosed,
          );
      }
    } catch (error) {
      // 程式錯誤的最後防線。扣過費的 run 不記 failed：續看會在逾時後從扣費內容
      // 重組結果（run_shape.ts）。
      this.deps.log("guide_v3_unexpected_error", {
        analysisRunId: this.runId,
        charged: this.charged,
        error: errorText(error),
      }, "error");
      const event = errorEvent(
        "GUIDE_V3_INTERNAL_ERROR",
        this.charged
          ? "分析中途出了問題，請稍後重新整理結果。"
          : "分析暫時無法完成，請稍後重新分析。本次不會扣額度。",
        true,
      );
      if (this.charged) emit(event);
      else await this.fail(emit, event, { stage: "unexpected" });
    } finally {
      stopHeartbeat();
    }
  }

  private startHeartbeat(emit: NdjsonEmit): () => void {
    const intervalMs = this.deps.heartbeatIntervalMs ??
      DEFAULT_HEARTBEAT_INTERVAL_MS;
    if (!Number.isFinite(intervalMs) || intervalMs <= 0) return () => {};
    const timer = setInterval(() => {
      emit({
        type: "analysis.progress",
        phase: "heartbeat",
        runId: this.runId,
        conversationHash: this.deps.conversationHash,
        label: "分析仍在進行",
        detail: "請保持連線。",
      });
    }, intervalMs);
    return () => clearInterval(timer);
  }

  /// 沒扣費的失敗：run 記 failed、送錯誤事件。
  private async fail(
    emit: NdjsonEmit,
    event: ErrorEvent,
    details: Record<string, unknown>,
  ): Promise<void> {
    try {
      await this.deps.store.markFailed({ ...this.key, code: event.code });
    } catch (error) {
      this.deps.log("guide_v3_mark_failed_failed", {
        analysisRunId: this.runId,
        error: errorText(error),
      }, "error");
    }
    this.deps.log("guide_v3_outcome", {
      analysisRunId: this.runId,
      outcome: "failed",
      code: event.code,
      charged: false,
      latencyMs: this.now() - this.startedAt,
      ...details,
    });
    emit(event);
  }

  /// 扣費（v3 RPC）。丟錯時先讀回 run：其實已扣（回應掉了）就當成功。
  private async charge(
    input: Omit<
      ChargeStreamRunV3Input,
      "runId" | "userId" | "conversationHash"
    >,
  ): Promise<{ ok: true } | { ok: false; event: ErrorEvent }> {
    try {
      await this.deps.store.chargeRunV3({ ...this.key, ...input });
      this.charged = true;
      return { ok: true };
    } catch (error) {
      try {
        const run = await this.deps.store.getRun(this.key);
        if (run.charged_at !== null && isGuideV3Run(run)) {
          this.deps.log("guide_v3_charge_confirmed_after_error", {
            analysisRunId: this.runId,
            error: errorText(error),
          }, "error");
          this.charged = true;
          return { ok: true };
        }
      } catch {
        // 讀不回來就照扣費失敗處理。
      }
      const mapped = mapStreamChargeFailure(error);
      this.deps.log("guide_v3_charge_failed", {
        analysisRunId: this.runId,
        code: mapped.code,
        error: errorText(error),
      }, "error");
      return {
        ok: false,
        event: errorEvent(mapped.code, mapped.message, true),
      };
    }
  }

  private usage(charged: boolean): Record<string, unknown> {
    const used = charged && this.shouldCharge
      ? this.deps.quotaUsage.chargedMessageCount
      : 0;
    return {
      messagesUsed: used,
      estimatedMessages: this.deps.quotaUsage.estimatedMessageCount,
      monthlyRemaining: this.deps.accountIsTest ? 999999 : Math.max(
        0,
        this.deps.monthlyLimit - this.deps.subMonthlyUsed - used,
      ),
      dailyRemaining: this.deps.accountIsTest ? 999999 : Math.max(
        0,
        this.deps.dailyLimit - this.deps.subDailyUsed - used,
      ),
      model: this.writeModel ?? this.readModel,
      tierUsed: this.deps.effectiveTier,
      isTestAccount: this.deps.accountIsTest,
      requestType: this.deps.requestType,
      shouldChargeQuota: used > 0,
      quotaReason: this.deps.quotaUsage.quotaReason,
      quotaUnit: this.deps.quotaUsage.quotaUnit,
    };
  }

  private telemetry(extra: Record<string, unknown>): Record<string, unknown> {
    return {
      requestType: this.deps.requestType,
      responseMode: "stream",
      guideVersion: GUIDE_V3_VERSION,
      serverAiLatencyMs: this.now() - this.startedAt,
      readModel: this.readModel,
      writeModel: this.writeModel,
      estimatedMessageCount: this.deps.quotaUsage.estimatedMessageCount,
      ...extra,
    };
  }

  private trace(
    tags: ReadTags,
    plan: GuideV3Plan,
    extra: Partial<GuideV3Trace> = {},
  ): GuideV3Trace {
    return {
      tags,
      push: plan.push,
      specs: plan.specs,
      entries: plan.entries.map((e) => e.id),
      removed: [],
      invalidLines: 0,
      scoringWords: [],
      rawMessages: [],
      models: { read: this.readModel, write: this.writeModel },
      firstCardMs: null,
      ...extra,
    };
  }

  /// 寫進 DB（失敗只記 log；persist=false 時不寫），再把剝掉伺服器專用欄位的
  /// 結果送給 App。
  private async finish(
    emit: NdjsonEmit,
    result: Record<string, unknown>,
    outcome: Record<string, unknown>,
    persist = true,
  ): Promise<void> {
    let persisted = persist;
    if (persist) {
      try {
        await this.deps.store.markDone({ ...this.key, finalResult: result });
      } catch (error) {
        persisted = false;
        this.deps.log("guide_v3_persist_failed", {
          analysisRunId: this.runId,
          error: errorText(error),
        }, "error");
      }
    }
    this.deps.log("guide_v3_outcome", {
      analysisRunId: this.runId,
      outcome: "done",
      persisted,
      latencyMs: this.now() - this.startedAt,
      ...outcome,
    });
    const client = stripClientHiddenFinalResult(result);
    emit({
      type: "analysis.done",
      runId: this.runId,
      finalResult: client,
      result: client,
    });
  }

  /// 自傷訊號：不出卡、不扣額度，顯示固定的關心訊息。存不進資料庫也照樣顯示。
  private async care(
    emit: NdjsonEmit,
    plan: GuideV3Plan,
    view: GuideV3ReadView,
    tags: ReadTags,
  ): Promise<void> {
    let recorded = true;
    try {
      // CHECK：done 一定要有 charged_at，所以走不扣額度的不送型扣費紀錄。
      await this.deps.store.chargeRunV3({
        ...this.key,
        decisionKind: "do_not_send",
        cardTask: null,
        recommendationJson: {
          decisionKind: "do_not_send",
          action: "care",
          reason: plan.reason,
          stopCondition: STOP_CONDITION_CARE,
          guideVersion: GUIDE_V3_VERSION,
          read: view,
        },
        chargeQuota: false,
        messageCount: 0,
      });
      this.charged = true;
    } catch (error) {
      recorded = false;
      this.deps.log("guide_v3_care_record_failed", {
        analysisRunId: this.runId,
        error: errorText(error),
      }, "error");
    }
    emit(readEvent(view));
    await this.finish(
      emit,
      finalResult({
        read: view,
        cards: [],
        partial: false,
        usage: this.usage(false),
        telemetry: this.telemetry({
          shouldChargeQuota: false,
          chargedMessageCount: 0,
        }),
        trace: this.trace(tags, plan),
      }),
      { decision: "care", charged: false },
      recorded,
    );
  }

  /// 先別回、停：讀完就扣一次（不送型），沒有卡。
  private async noSend(
    emit: NdjsonEmit,
    plan: GuideV3Plan,
    view: GuideV3ReadView,
    tags: ReadTags,
    isClosed: () => boolean,
  ): Promise<void> {
    if (isClosed()) {
      return await this.fail(
        emit,
        errorEvent("GUIDE_V3_CLIENT_GONE", "連線已中斷。", true),
        { stage: "before_charge", decision: plan.decision },
      );
    }
    const hold = plan.decision === "hold";
    const decisionKind = hold ? "do_not_send" : "acknowledge_and_stop";
    const charged = await this.charge({
      decisionKind,
      cardTask: null,
      recommendationJson: {
        decisionKind,
        action: hold ? "wait" : "stop",
        reason: plan.reason,
        stopCondition: hold ? plan.waitFor : STOP_CONDITION_STOP,
        guideVersion: GUIDE_V3_VERSION,
        read: view,
      },
      chargeQuota: this.shouldCharge,
      messageCount: this.shouldCharge
        ? this.deps.quotaUsage.chargedMessageCount
        : 0,
    });
    if (!charged.ok) {
      return await this.fail(emit, charged.event, {
        stage: "charge",
        decision: plan.decision,
      });
    }
    emit(readEvent(view));
    await this.finish(
      emit,
      finalResult({
        read: view,
        cards: [],
        partial: false,
        usage: this.usage(true),
        telemetry: this.telemetry({
          shouldChargeQuota: this.shouldCharge,
          chargedMessageCount: this.shouldCharge
            ? this.deps.quotaUsage.chargedMessageCount
            : 0,
        }),
        trace: this.trace(tags, plan),
      }),
      { decision: plan.decision, charged: this.shouldCharge },
    );
  }

  /// 出卡：讀局面先送；寫卡串流，每張定稿；第一張確定要送時扣費。
  private async send(
    emit: NdjsonEmit,
    plan: GuideV3Plan,
    view: GuideV3ReadView,
    tags: ReadTags,
    turns: readonly Turn[],
    deadlineAtMs: number,
    isClosed: () => boolean,
  ): Promise<void> {
    emit(readEvent(view));
    const sourceText = this.deps.messages.map((m) => m.content).join("\n");
    const delivered: GuideV3CardView[] = [];
    const removed: { slot: number; reason: string }[] = [];
    const scoring: { slot: number; words: readonly string[] }[] = [];
    const raws: { slot: number; messages: readonly string[] }[] = [];
    const seen = new Set<number>();
    const state: {
      invalidLines: number;
      firstCardMs: number | null;
      stop: { kind: "charge_failed"; event: ErrorEvent } | {
        kind: "client_gone";
      } | null;
      upstreamError: unknown;
    } = { invalidLines: 0, firstCardMs: null, stop: null, upstreamError: null };

    /// 回 false＝停止讀串流（扣費失敗或 App 已斷線）。
    const handleLine = async (line: string): Promise<boolean> => {
      const card = parseWrittenCardLine(line);
      const spec = card ? plan.specs[card.card - 1] : undefined;
      if (!card || !spec || seen.has(card.card)) {
        state.invalidLines++;
        return true;
      }
      seen.add(card.card);
      const out = finalizeCard(card, spec, sourceText);
      if (!out.ok) {
        removed.push({ slot: card.card, reason: out.reason });
        return true;
      }
      const shown = cardView(
        card.card,
        spec,
        out.messages,
        out.hasInventedDetail,
      );
      if (delivered.length === 0) {
        // 「送到才扣」：App 已經斷線就不扣、不再生成。
        if (isClosed()) {
          state.stop = { kind: "client_gone" };
          return false;
        }
        const charged = await this.charge({
          decisionKind: "send",
          cardTask: shown.task,
          recommendationJson: {
            decisionKind: "send",
            cardTask: shown.task,
            guideVersion: GUIDE_V3_VERSION,
            read: view,
            firstCard: shown,
          },
          chargeQuota: this.shouldCharge,
          messageCount: this.shouldCharge
            ? this.deps.quotaUsage.chargedMessageCount
            : 0,
        });
        if (!charged.ok) {
          state.stop = { kind: "charge_failed", event: charged.event };
          return false;
        }
        state.firstCardMs = this.now() - this.startedAt;
      }
      // 先記成已送出再送：送出那一步就算出錯，扣過費的這張也會進結果。
      delivered.push(shown);
      emit(cardEvent(shown));
      if (out.scoringWords.length > 0) {
        scoring.push({ slot: card.card, words: out.scoringWords });
      }
      if (out.rawMessages) {
        raws.push({ slot: card.card, messages: out.rawMessages });
      }
      return true;
    };

    try {
      const write = await this.deps.callWrite({
        runId: this.runId,
        system: writeSystemPrompt(),
        user: writeUserPrompt({
          turns,
          tags,
          entries: plan.entries,
          cards: plan.specs,
          background: this.deps.background,
        }),
        deadlineAtMs,
      });
      this.writeModel = write.model;
      const splitter = createLineSplitter();
      let keepGoing = true;
      for await (const chunk of write.textStream) {
        for (const line of splitter.push(chunk)) {
          keepGoing = await handleLine(line);
          if (!keepGoing) break;
        }
        if (!keepGoing) break;
      }
      if (keepGoing) {
        for (const line of splitter.flush()) {
          if (!await handleLine(line)) break;
        }
      }
    } catch (error) {
      state.upstreamError = error;
    }

    const { invalidLines, firstCardMs, stop, upstreamError } = state;
    const traceExtra = {
      removed,
      invalidLines,
      scoringWords: scoring,
      rawMessages: raws,
      firstCardMs,
    };
    if (stop?.kind === "charge_failed") {
      return await this.fail(emit, stop.event, {
        stage: "charge",
        decision: plan.decision,
        cardsRemoved: removed.length,
      });
    }
    if (stop?.kind === "client_gone") {
      return await this.fail(
        emit,
        errorEvent("GUIDE_V3_CLIENT_GONE", "連線已中斷。", true),
        { stage: "before_charge", decision: plan.decision },
      );
    }
    if (delivered.length === 0) {
      const event = upstreamError !== null
        ? upstreamErrorEvent(upstreamError)
        : errorEvent(
          "GUIDE_V3_NO_CARDS",
          "這次沒有產生可以用的回覆，請重新分析。本次不會扣額度。",
          true,
        );
      return await this.fail(emit, event, {
        stage: "write",
        decision: plan.decision,
        cardsPlanned: plan.specs.length,
        cardsRemoved: removed.length,
        removedReasons: removed.map((r) => r.reason),
        invalidLines,
        ...(upstreamError !== null ? { error: errorText(upstreamError) } : {}),
      });
    }

    const interruptedCode = upstreamError === null
      ? undefined
      : upstreamErrorEvent(upstreamError).code;
    const partial = upstreamError !== null ||
      delivered.length < plan.specs.length;
    await this.finish(
      emit,
      finalResult({
        read: view,
        cards: delivered,
        partial,
        usage: this.usage(true),
        telemetry: this.telemetry({
          shouldChargeQuota: this.shouldCharge,
          chargedMessageCount: this.shouldCharge
            ? this.deps.quotaUsage.chargedMessageCount
            : 0,
          firstCardMs,
          cardsPlanned: plan.specs.length,
          cardsDelivered: delivered.length,
          ...(interruptedCode ? { writeInterruptedCode: interruptedCode } : {}),
        }),
        trace: this.trace(tags, plan, traceExtra),
      }),
      {
        decision: plan.decision,
        charged: this.shouldCharge,
        firstCardMs,
        cardsPlanned: plan.specs.length,
        cardsDelivered: delivered.length,
        cardsRemoved: removed.length,
        removedReasons: removed.map((r) => r.reason),
        invalidLines,
        scoringWordCards: scoring.length,
        ...(interruptedCode ? { writeInterruptedCode: interruptedCode } : {}),
      },
    );
  }
}
