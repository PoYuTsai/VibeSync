// v3 串流分析（協定版本 3、開關 ANALYZE_GUIDE_V3 允許時）：讀局面（非串流＋
// json_schema）→ 程式排卡 → 串流寫卡，一行一張、每張各自定稿。開關
// ANALYZE_GUIDE_V3_MEMORY 開時，讀完另打一次對象記憶（memory.ts），不擋判讀與出卡。
//
// 扣費（Eric 10/16）：第一張卡定稿、確定要送的那一刻扣一次；一張都沒送出不扣；
// 斷線時已送出的照留、算一次；先別回、停讀完就扣（不送型），也照字數（Bruce 10/18 維持 10/16
// 的規則，Eric 2026-10-19 照他改回）；固定訊息（自傷關心、涉及未成年）不扣。
// run：pending →（扣費）charged → done；沒扣費就 failed。扣過費一定以 done 結案
//（寫卡中途出錯就用已送出的卡）。不重生、不 retry；續看只重播（run_shape.ts）。
import { jsonResponse } from "../http_response.ts";
import { type NdjsonEmit, ndjsonStreamResponse } from "../ndjson_response.ts";
import { stripClientHiddenFinalResult } from "../divergence_contract.ts";
import { mapStreamChargeFailure } from "../stream_charge_failure.ts";
import type {
  AnalysisStreamRun,
  ChargeStreamRunV3Input,
} from "../stream_run_store.ts";
import {
  type CardChecks,
  cardChecks,
  charCount,
  createLineSplitter,
  parseWrittenCardLine,
  sameOpeningCount,
} from "./cards.ts";
import { GUIDE_V3_VERSION } from "./guide_text.ts";
import {
  type GuideV3Plan,
  planCareFromQuota,
  planTurn,
  planWithoutRead,
} from "./plan.ts";
import { finalizeCard, vetPlanText } from "./finalize.ts";
import {
  addTypingChanges,
  detectTypingHabits,
  NO_TYPING_CHANGES,
  styleCard,
} from "./typing_style.ts";
import {
  addPhraseTidyChanges,
  NO_PHRASE_TIDY_CHANGES,
  phraseTidyContext,
  tidyCard,
} from "./phrase_tidy.ts";
import {
  EXPLAIN_SCHEMA,
  explainSystemPrompt,
  explainUserPrompt,
  parseExplanations,
  TENSION_STYLE_EXPLAIN_SENTINELS,
  vetExplanation,
} from "./explain.ts";
import {
  NO_SAFETY_HITS,
  type SafetyKeywordHits,
  scanSafetyKeywords,
} from "./safety.ts";
import {
  type GuideV3MemoryTrace,
  MEMORY_SCHEMA,
  memorySystemPrompt,
  memoryUserPrompt,
  type PartnerMemory,
  partnerMemoryFrom,
  zeroMemoryCounts,
} from "./memory.ts";
import {
  type GuideV3RelationTrace,
  parseRelation,
  READ_TAGS_SCHEMA_WITH_RELATION,
  readSystemPromptWithRelation,
  RELATION_LEAK_SENTINELS,
} from "./relation.ts";
import {
  type GuideV3PreviousRound,
  type GuideV3PreviousRoundTrace,
  previousRoundTrace,
  traceWithoutText,
} from "./previous_round.ts";
import {
  type GuideV3Background,
  readSystemPrompt,
  readUserPrompt,
  writeSystemPrompt,
  writeUserPrompt,
} from "./prompts.ts";
import {
  parseReadTags,
  parseTwoStageTags,
  READ_TAGS_SCHEMA,
  READ_TAGS_SCHEMA_TWO_STAGE,
  READ_TAGS_SCHEMA_TWO_STAGE_SWEET,
  type ReadTags,
  type TwoStageTags,
} from "./read_tags.ts";
import { lightShortRun } from "./rules.ts";
import {
  READ_TAGS_SCHEMA_TWO_STAGE_SWEET_WITH_RELATION,
  READ_TAGS_SCHEMA_TWO_STAGE_WITH_RELATION,
  readSystemPromptTwoStage,
  readSystemPromptTwoStageWithRelation,
  readUserPromptTwoStage,
  SHORT_PRAISE_WRITER_SENTINELS,
  SWEET_READ_LEAK_SENTINELS,
  SWEET_SHORT_WRITER_SENTINELS,
  TENSION_STYLE_WRITER_SENTINELS,
  TWO_STAGE_READ_LEAK_SENTINELS,
  TWO_STAGE_WRITER_SENTINELS,
  writeSystemPromptTwoStage,
  writeUserPromptTwoStage,
} from "./two_stage_prompts.ts";
import {
  type GuideMessage,
  latestHerMessages,
  toTurns,
  type Turn,
} from "./turns.ts";
import {
  cardEvent,
  cardExplainEvent,
  cardView,
  finalResult,
  type GuideV3CardView,
  type GuideV3ExplainTrace,
  type GuideV3ReadView,
  type GuideV3Trace,
  readEvent,
  readView,
  relationView,
} from "./wire.ts";

/// 讀局面＋寫卡共用的模型期限（從請求開始算）。
export const GUIDE_V3_DEADLINE_MS = 90_000;
/// 結果其他部分都好了之後，最多再等對象記憶多久。出卡時記憶跟寫卡同時跑，到這裡
/// 早就好了；先別回、停只有讀局面，判讀先送出，done 最多晚這麼久。
export const GUIDE_V3_MEMORY_WAIT_MS = 2_500;
const DEFAULT_HEARTBEAT_INTERVAL_MS = 15_000;
/// 停（明確拒絕或封鎖）、自傷關心與未成年存進扣費紀錄的 stopCondition（RPC 要非空）。
export const STOP_CONDITION_STOP = "不再主動傳訊息";
export const STOP_CONDITION_CARE = "先確認安全";
export const STOP_CONDITION_MINOR = "涉及未成年，不給建議";
/// 讀完局面、開始寫卡前的中性進度（只有出卡、收尾才有；不帶判讀、不動扣費）。
export const GUIDE_V3_WRITING_LABEL = "看完了，正在寫回覆";
/// 兩段式實驗的說明步驟最多等多久（卡都送完才開始；done 最多晚這麼久）。
export const GUIDE_V3_EXPLAIN_WAIT_MS = 20_000;

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
  /// 只有還在 pending、而且沒扣過費才改成 failed；沒改到回 null（見 stream_run_store）。
  markFailedIfPending(args: {
    runId: string;
    userId: string;
    conversationHash: string;
    code: string;
  }): Promise<AnalysisStreamRun | null>;
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

/// 對象記憶：跟讀局面一樣是非串流＋json_schema，提示詞與 schema 在 memory.ts。
export type GuideV3ExtractRequest = GuideV3ReadRequest;

/// 兩段式實驗的說明步驟：也是非串流＋json_schema，提示詞與 schema 在 explain.ts。
export type GuideV3ExplainRequest = GuideV3ReadRequest;

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
  /// 上一輪脈絡：開關 ANALYZE_GUIDE_V3_PREV_ROUND 允許、格式也對才有（handler 把關）；
  /// 沒有就跟今天一模一樣。
  previousRound?: GuideV3PreviousRound;
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
  /// 對象記憶（開關 ANALYZE_GUIDE_V3_MEMORY）；沒給就不多打這一次，結果也不帶。
  callExtract?(
    req: GuideV3ExtractRequest,
  ): Promise<{ text: string; model: string }>;
  /// 預設 GUIDE_V3_MEMORY_WAIT_MS（測試縮短用）。
  memoryWaitMs?: number;
  /// 關係訊號（開關 ANALYZE_GUIDE_V3_RELATION，handler 把關；Bruce 2026-10-19 路線二）：讀局面
  /// 在最後多要階段、熱度與四個維度，判讀多帶 relation。沒給或 false：提示詞、schema、事件、
  /// trace 與扣費都跟今天一樣。
  relation?: boolean;
  log(
    event: string,
    metadata: Record<string, unknown>,
    level?: "info" | "error",
  ): void;
  headers?: HeadersInit;
  now?: () => number;
  heartbeatIntervalMs?: number;
  /// 讓 runtime 在 App 斷線後仍把這次流程跑完（production：EdgeRuntime.waitUntil）。
  waitUntil?: (task: Promise<unknown>) => void;
  /// 額度不夠、她的訊息有自傷字眼（Eric 2026-10-18；入口在 analyze_chat_handler 的額度
  /// 預查）：不打任何模型，直接給自傷關心訊息，不扣。
  careOnlyFromQuota?: boolean;
  /// 兩段式「正常回覆」實驗（開關 ANALYZE_GUIDE_V3_TWO_STAGE，handler 把關；Eric 2026-10-19
  /// 兩段式實驗）。沒給或 false：提示詞、schema、事件、trace 與扣費都跟今天一樣。
  twoStage?: boolean;
  /// 口吻與斷句交給程式（開關 ANALYZE_GUIDE_V3_TYPING_STYLE，handler 把關；Bruce 2026-10-20 改法 3）：
  /// 每張卡定稿、檢查過之後，送出之前照他的打字習慣統一稱呼與斷句。沒給或 false：一字不變。
  typingStyle?: boolean;
  /// 短版稱讚（開關 ANALYZE_GUIDE_V3_SHORT_PRAISE，handler 把關；Bruce 2026-10-20「可以」）：只在 twoStage
  /// 開時有作用。程式照 runId 抽，抽到時一張卡的規格多寫短版的誇法。沒給或 false：一字不變。
  shortPraise?: boolean;
  /// 帶張力改寫法 v2（開關 ANALYZE_GUIDE_V3_TENSION_STYLE，handler 把關；Bruce 2026-10-21「改」：推拉換成三條不要）：只在 twoStage
  /// 開時有作用。排卡不變，寫卡與說明看到的帶張力寫法換新的。沒給或 false：一字不變。
  tensionStyle?: boolean;
  /// 「這題」「滿→蠻」交給程式（開關 ANALYZE_GUIDE_V3_PHRASE_TIDY，handler 把關；Bruce 2026-10-20 PR #97
  /// 再處理，2026-10-21 只用這兩條）：口吻與斷句之後、送出之前改這兩種字。沒給或 false：一字不變。
  phraseTidy?: boolean;
  /// 甜話短回（開關 ANALYZE_GUIDE_V3_SWEET_SHORT，handler 把關；Eric 2026-10-22「照預設」）：只在 twoStage 開時有作用。
  /// 讀局面 worthyLines 多一種「撒嬌」；她這一輪有標成撒嬌的很短的一則時，只有一張卡回那句、規格多短回的指示，其他卡回她
  /// 別的話，沒有別的話就少出幾張（至少 3 張）。沒給或 false：一字不變。
  sweetShort?: boolean;
  /// 兩段式實驗的說明步驟（卡都送完才打一次）；twoStage 開但沒給就不說明。
  callExplain?(
    req: GuideV3ExplainRequest,
  ): Promise<{ text: string; model: string }>;
  /// 預設 GUIDE_V3_EXPLAIN_WAIT_MS（測試縮短用）。
  explainWaitMs?: number;
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

/// 她最後一輪（最後面連續幾則她的訊息）的字數，不算空白；最後一則是他的就是 0。
function herLastTurnChars(messages: readonly GuideV3Message[]): number {
  let total = 0;
  for (let i = messages.length - 1; i >= 0 && !messages[i].isFromMe; i--) {
    total += charCount(messages[i].content);
  }
  return total;
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
  // 續看（帶 analysisRunId）一律交給 v2 handler：它認得 v3 的 run（只重播、不 retry），
  // 也接得住開關剛打開前建立的 v2 run。
  if (deps.analysisRunId) {
    throw new Error(
      "handleGuideV3Stream: resume requests belong to the v2 handler",
    );
  }
  // 額度不夠只給關心：入口只在她的訊息有自傷字眼時才這樣叫；對不上就是呼叫端的錯，不建
  // run、不打模型。這種 run 一律不扣。
  const quotaCare = deps.careOnlyFromQuota
    ? planCareFromQuota(scanSafetyKeywords(deps.messages))
    : null;
  if (deps.careOnlyFromQuota && !quotaCare) {
    throw new Error(
      "handleGuideV3Stream: careOnlyFromQuota needs self-harm words from her",
    );
  }
  const shouldCharge = !quotaCare && deps.quotaUsage.shouldChargeQuota &&
    !deps.accountIsTest;
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
  const flow = new GuideV3Flow(deps, run.id, shouldCharge, quotaCare);
  return ndjsonStreamResponse((emit, close, _fail, isClosed) => {
    const task = flow.run(emit, isClosed).finally(close);
    deps.waitUntil?.(task.catch(() => undefined));
    return task;
  }, deps.headers);
}

class GuideV3Flow {
  private readonly now: () => number;
  private readonly startedAt: number;
  private readModel: string | undefined;
  private writeModel: string | undefined;
  /// 這個 run 已經寫進扣費紀錄（包含自傷關心的免扣紀錄）。
  private charged = false;
  /// 扣費丟錯、失敗寫入與讀回都失敗：可能已經扣了（只記 log；續看在逾時後從扣費
  /// 內容重組或判失敗，見 run_shape.ts）。
  private chargeUnknown = false;
  /// 扣費出錯時已經用條件式寫入記成 failed，fail() 不用再寫一次。
  private markedFailed = false;
  /// 對象記憶那一次呼叫（沒開或自傷關心就是 null）；永遠不會 reject。
  private memory: Promise<PartnerMemory & { latencyMs: number }> | null = null;
  /// 程式關鍵字掃到的安全訊號（run 一開始就掃）。
  private hits: SafetyKeywordHits = NO_SAFETY_HITS;
  /// 關係訊號（開關開、讀局面成功才有）：通過檢查的值與拿掉的欄位，進 trace。
  private relation: GuideV3RelationTrace | null = null;
  /// 短版稱讚開著（兩段式也開）：卡片多比短版那段的哨兵。
  private shortPraiseOn = false;
  /// 帶張力改寫法開著（兩段式也開）：寫卡、說明的提示詞換帶張力那幾行，卡片與說明多比新寫法的哨兵。
  private tensionStyleOn = false;
  /// 甜話短回開著（兩段式也開）、而且這一輪真的排到（有卡的規格寫了短回的指示）：卡片多比那一段的哨兵（說明不比，見
  /// explainCards）。沒排到時寫卡看不到那一段，跟沒開一樣不比。
  private sweetShortPlanned = false;

  constructor(
    private readonly deps: GuideV3StreamDeps,
    private readonly runId: string,
    private readonly shouldCharge: boolean,
    /// 額度不夠時直接給的自傷關心（careOnlyFromQuota 才有）。
    private readonly quotaCare: GuideV3Plan | null = null,
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

  /// 有帶上一輪脈絡時，trace 與 outcome log 只記數量（不放任何字）。
  private get previousRoundCounts(): {
    previousRound?: GuideV3PreviousRoundTrace;
  } {
    return this.deps.previousRound
      ? { previousRound: previousRoundTrace(this.deps.previousRound) }
      : {};
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
      // 程式自己掃的安全訊號（safety.ts）：讀局面失敗或拒答時也要用，所以先掃。
      this.hits = scanSafetyKeywords(this.deps.messages, this.deps.background);
      // 額度不夠：不讀局面、不寫卡、不打記憶，直接給關心訊息（Eric 2026-10-18）。
      if (this.quotaCare) return await this.care(emit, this.quotaCare, null);
      // 關係訊號（Bruce 2026-10-19 路線二）：讀局面在最後多要三欄；沒開照舊。
      const withRelation = this.deps.relation === true;
      let text: string;
      // 兩段式實驗（Eric 2026-10-19）：讀局面多要幾個標記、她最新這一輪逐則編號；沒開照舊。
      // 兩個開關都開：欄位說明兩段都放、關係那段在最後；schema 是兩段式的，再把關係三欄接在最後
      //（模型照 schema 順序輸出，前面的標記先寫完；Eric 2026-10-20 兩邊都上線）。
      const twoStage = this.deps.twoStage === true;
      // 甜話短回（Eric 2026-10-22「照預設」；Codex 主審第 1 輪 P2）：讀局面 worthyLines 多一種「撒嬌」（提示詞那一條、schema、
      // 檢查都換），排卡在她撒嬌的很短的一則上改排（plan.ts）。沒開照舊。
      const sweetShortOn = twoStage && this.deps.sweetShort === true;
      const sweetRead = { sweetShort: sweetShortOn };
      try {
        const read = await this.deps.callRead({
          runId: this.runId,
          system: twoStage
            ? withRelation
              ? readSystemPromptTwoStageWithRelation(
                undefined,
                undefined,
                undefined,
                sweetRead,
              )
              : readSystemPromptTwoStage(
                undefined,
                undefined,
                undefined,
                sweetRead,
              )
            : withRelation
            ? readSystemPromptWithRelation()
            : readSystemPrompt(),
          user: (twoStage ? readUserPromptTwoStage : readUserPrompt)(
            turns,
            this.deps.background,
            this.deps.previousRound,
          ),
          schema: twoStage
            ? withRelation
              ? sweetShortOn
                ? READ_TAGS_SCHEMA_TWO_STAGE_SWEET_WITH_RELATION
                : READ_TAGS_SCHEMA_TWO_STAGE_WITH_RELATION
              : sweetShortOn
              ? READ_TAGS_SCHEMA_TWO_STAGE_SWEET
              : READ_TAGS_SCHEMA_TWO_STAGE
            : withRelation
            ? READ_TAGS_SCHEMA_WITH_RELATION
            : READ_TAGS_SCHEMA,
          deadlineAtMs,
        });
        text = read.text;
        this.readModel = read.model;
      } catch (error) {
        const event = upstreamErrorEvent(error);
        // 讀局面失敗或拒答，但程式關鍵字看得出要給固定訊息：給固定訊息，不給錯誤。
        const fallback = planWithoutRead(this.hits);
        if (fallback) {
          return await this.care(emit, fallback, null, {
            code: event.code,
            error: errorText(error),
          });
        }
        return await this.fail(emit, event, {
          stage: "read",
          error: errorText(error),
        });
      }
      const parsed = parseTagsText(text);
      // 兩段式多要的四欄在同一份 JSON 裡；壞了跟其他欄位壞了一樣算讀局面失敗。
      const twoStageTags: TwoStageTags | null = twoStage && parsed
        ? parseTwoStageTags(parsed, sweetRead)
        : null;
      const tags = twoStage && !twoStageTags ? null : parsed;
      if (!tags) {
        const fallback = planWithoutRead(this.hits);
        if (fallback) {
          return await this.care(emit, fallback, null, {
            code: "GUIDE_V3_READ_INVALID",
          });
        }
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
      if (withRelation) {
        // 三欄各自檢查：不合格的拿掉、記 log，其他標記、決定、卡與扣費都不受影響。
        this.relation = parseRelation(tags);
        if (this.relation.dropped.length > 0) {
          this.deps.log("guide_v3_relation_dropped", {
            analysisRunId: this.runId,
            dropped: this.relation.dropped,
          }, "error");
        }
      }
      // 短版稱讚（Bruce 2026-10-20「可以」）：照 runId 抽，重播一致；沒開照舊。
      this.shortPraiseOn = twoStage && this.deps.shortPraise === true;
      // 帶張力改寫法（Bruce 2026-10-20「改」）：排卡不變，寫卡與說明的帶張力寫法換新的；沒開照舊。
      this.tensionStyleOn = twoStage && this.deps.tensionStyle === true;
      const plan = vetPlanText(
        planTurn(
          turns,
          tags,
          this.hits,
          undefined,
          twoStageTags ?? undefined,
          {
            ...(this.shortPraiseOn
              ? { lightShortPraise: lightShortRun(this.runId) }
              : {}),
            ...(sweetShortOn ? { sweetShort: true } : {}),
          },
        ),
        (field) =>
          this.deps.log("guide_v3_coach_text_removed", {
            analysisRunId: this.runId,
            field,
          }, "error"),
        // 讀局面多了關係狀態那一段：判讀照抄那一段也不給（主審第 1 輪 P2）；兩段式多的欄位說明也一樣
        //（兩段式主審第 1 輪 P2），兩個都開就兩份一起比。甜話短回開時 worthyLines 那一條新加的說法也比。都沒開照舊。
        [
          ...(twoStage ? TWO_STAGE_READ_LEAK_SENTINELS : []),
          ...(withRelation ? RELATION_LEAK_SENTINELS : []),
          ...(sweetShortOn ? SWEET_READ_LEAK_SENTINELS : []),
        ],
      );
      this.sweetShortPlanned = sweetShortOn &&
        plan.specs.some((s) => s.sweetShort === true);
      // 關係狀態排在判讀最後，跟判讀一起在扣費之後才送；扣費內容、結果與續看都帶得到。
      const view = readView(
        plan,
        tags.light,
        this.relation ? relationView(this.relation, tags) : undefined,
      );
      // 自傷訊號要讀完才知道，所以記憶在讀局面之後才開始；關心訊息不打這一次。
      if (plan.decision !== "care") this.startMemory(turns, deadlineAtMs);
      switch (plan.decision) {
        case "care":
          return await this.care(emit, plan, tags);
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
    // 寫入只在 pending 而且沒扣過費時生效，不會蓋掉扣過費、可以續看的列；扣費狀態
    // 不明時也照寫，等於再確認一次（扣過的就寫不進去）。
    if (!this.charged && !this.markedFailed) {
      try {
        const failed = await this.deps.store.markFailedIfPending({
          ...this.key,
          code: event.code,
        });
        if (!failed) {
          this.deps.log("guide_v3_mark_failed_skipped", {
            analysisRunId: this.runId,
            code: event.code,
          }, "error");
        }
      } catch (error) {
        this.deps.log("guide_v3_mark_failed_failed", {
          analysisRunId: this.runId,
          error: errorText(error),
        }, "error");
      }
    }
    this.deps.log("guide_v3_outcome", {
      analysisRunId: this.runId,
      outcome: "failed",
      code: event.code,
      charged: this.charged,
      chargeUnknown: this.chargeUnknown,
      latencyMs: this.now() - this.startedAt,
      ...this.previousRoundCounts,
      ...details,
    });
    emit(event);
  }

  /// 扣費（v3 RPC）。扣費內容另記實際扣了幾則（chargedMessageCount），續看重組時用。
  /// 丟錯時先用條件式寫入記失敗；沒寫到就讀回：其實已扣就當成功，都不成就是「不明」。
  private async charge(
    input: Omit<
      ChargeStreamRunV3Input,
      "runId" | "userId" | "conversationHash"
    >,
  ): Promise<{ ok: true } | { ok: false; event: ErrorEvent }> {
    const recorded = {
      ...input,
      recommendationJson: {
        ...input.recommendationJson,
        chargedMessageCount: input.chargeQuota ? input.messageCount : 0,
      },
    };
    try {
      await this.deps.store.chargeRunV3({ ...this.key, ...recorded });
      this.charged = true;
      return { ok: true };
    } catch (error) {
      const mapped = mapStreamChargeFailure(error);
      // 先用條件式寫入把 run 記成失敗：寫到了＝確定沒扣，之後也扣不到（扣費要
      // pending）；沒寫到＝已經扣了（或交易剛提交），讀回確認。
      let state: "charged" | "not_charged" | "unknown" = "unknown";
      try {
        const failed = await this.deps.store.markFailedIfPending({
          ...this.key,
          code: mapped.code,
        });
        if (failed) {
          state = "not_charged";
          this.markedFailed = true;
        } else {
          const run = await this.deps.store.getRun(this.key);
          state = run.charged_at !== null
            ? "charged"
            : run.status === "pending"
            ? "unknown"
            : "not_charged";
        }
      } catch {
        // 資料庫連不上：狀態不明。
      }
      if (state === "charged") {
        this.deps.log("guide_v3_charge_confirmed_after_error", {
          analysisRunId: this.runId,
          error: errorText(error),
        }, "error");
        this.charged = true;
        return { ok: true };
      }
      this.deps.log("guide_v3_charge_failed", {
        analysisRunId: this.runId,
        code: mapped.code,
        state,
        error: errorText(error),
      }, "error");
      if (state === "unknown") {
        this.chargeUnknown = true;
        return {
          ok: false,
          event: errorEvent(
            "GUIDE_V3_CHARGE_UNCONFIRMED",
            "分析結果還在確認，請稍後重新整理。",
            true,
          ),
        };
      }
      return {
        ok: false,
        event: errorEvent(mapped.code, mapped.message, true),
      };
    }
  }

  /// used：這次實際扣的則數（出卡、先別回與停照字數，固定訊息 0）。
  private usage(used: number): Record<string, unknown> {
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
    tags: ReadTags | null,
    plan: GuideV3Plan,
    extra: Partial<GuideV3Trace> = {},
  ): GuideV3Trace {
    const trace: GuideV3Trace = {
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
      ...(Object.values(this.hits).some(Boolean)
        ? { keywordHits: this.hits }
        : {}),
      ...this.previousRoundCounts,
      ...(this.relation ? { relation: this.relation } : {}),
      ...extra,
    };
    // 帶了上一輪的那次，trace 不放任何模型寫的字（主審第 1 輪 P1，previous_round.ts）。
    return this.deps.previousRound ? traceWithoutText(trace, tags) : trace;
  }

  /// 對象記憶跟寫卡（或不送型的扣費）同時跑；結案前才用 settleMemory 等。
  private startMemory(turns: readonly Turn[], deadlineAtMs: number): void {
    const callExtract = this.deps.callExtract;
    if (!callExtract) return;
    const startedAt = this.now();
    // 用 executor 包起來：callExtract 同步丟錯也變成 reject，交給下面的 catch。
    const task = new Promise<{ text: string; model: string }>((resolve) =>
      resolve(callExtract({
        runId: this.runId,
        system: memorySystemPrompt(),
        user: memoryUserPrompt(turns),
        schema: MEMORY_SCHEMA,
        deadlineAtMs,
      }))
    )
      // 出處只認 App 送來的原始訊息，不是帶引用前綴的對話稿。
      .then((res) => partnerMemoryFrom(res.text, this.deps.messages))
      .catch((error): PartnerMemory => {
        const code = (error as { code?: unknown })?.code;
        this.deps.log("guide_v3_memory_failed", {
          analysisRunId: this.runId,
          code: typeof code === "string" ? code : "UNKNOWN",
        });
        return {
          ok: false,
          kept: zeroMemoryCounts(),
          dropped: zeroMemoryCounts(),
        };
      })
      .then((memory) => ({ ...memory, latencyMs: this.now() - startedAt }));
    this.memory = task;
    // 等不到就先結案，但這次呼叫還是要跑完、寫完 ai_logs。
    this.deps.waitUntil?.(task);
  }

  /// 最多再等 memoryWaitMs；等不到、失敗或沒有通過檢查的項目，結果就不帶 targetProfile
  ///（App 沿用上一份）。trace 只放計數。
  private async settleMemory(): Promise<{
    targetProfile?: Record<string, unknown>;
    trace?: GuideV3MemoryTrace;
  }> {
    if (!this.memory) return {};
    let timer: ReturnType<typeof setTimeout> | undefined;
    const late = new Promise<null>((resolve) => {
      timer = setTimeout(
        () => resolve(null),
        this.deps.memoryWaitMs ?? GUIDE_V3_MEMORY_WAIT_MS,
      );
    });
    const memory = await Promise.race([this.memory, late]).finally(() =>
      clearTimeout(timer)
    );
    if (!memory) {
      return {
        trace: {
          ok: false,
          timedOut: true,
          latencyMs: null,
          kept: zeroMemoryCounts(),
          dropped: zeroMemoryCounts(),
        },
      };
    }
    return {
      ...(memory.targetProfile ? { targetProfile: memory.targetProfile } : {}),
      trace: {
        ok: memory.ok,
        timedOut: false,
        latencyMs: memory.latencyMs,
        kept: memory.kept,
        dropped: memory.dropped,
      },
    };
  }

  /// 寫進 DB（失敗只記 log；persist=false 時不寫），再把剝掉伺服器專用欄位的
  /// 結果送給 App。
  private async finish(
    emit: NdjsonEmit,
    built: Record<string, unknown>,
    outcome: Record<string, unknown>,
    persist = true,
  ): Promise<void> {
    // 結案時間（ISO 8601 UTC）跟結果一起存：續看重播回的是這個原本的時間，不是重播當下；App 拿來
    // 排哪一次分析比較新（Eric 2026-10-20「直接修好上線」）。資料表沒有結案時間的欄位，不加 migration。
    const completedAt = new Date(this.now()).toISOString();
    const result = { ...built, completedAt };
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
      ...this.previousRoundCounts,
      ...outcome,
    });
    const client = stripClientHiddenFinalResult(result);
    emit({
      type: "analysis.done",
      runId: this.runId,
      finalResult: client,
      result: client,
      completedAt,
    });
  }

  /// 不出卡、不扣額度，顯示固定訊息：自傷關心，或涉及未成年（plan.careKind）。讀局面失敗、
  /// 只靠程式關鍵字判出來時 tags 是 null（沒有燈號），readFailure 記失敗的原因；額度不夠
  /// 直接給的另標 insufficientQuota。存不進資料庫也照樣顯示。
  private async care(
    emit: NdjsonEmit,
    plan: GuideV3Plan,
    tags: ReadTags | null,
    readFailure?: { code: string; error?: string },
  ): Promise<void> {
    const view = readView(plan, tags?.light ?? null);
    const care = {
      kind: plan.careKind ?? "self_harm",
      trigger: plan.careTrigger ?? "model",
      ...(readFailure ? { readFailedCode: readFailure.code } : {}),
      ...(this.quotaCare ? { insufficientQuota: true } : {}),
    } as const;
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
          stopCondition: care.kind === "minor"
            ? STOP_CONDITION_MINOR
            : STOP_CONDITION_CARE,
          careKind: care.kind,
          careTrigger: care.trigger,
          guideVersion: GUIDE_V3_VERSION,
          read: view,
          chargedMessageCount: 0,
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
        usage: this.usage(0),
        telemetry: this.telemetry({
          shouldChargeQuota: false,
          chargedMessageCount: 0,
        }),
        trace: this.trace(tags, plan, { care }),
      }),
      {
        decision: "care",
        careKind: care.kind,
        careTrigger: care.trigger,
        charged: false,
        ...(this.quotaCare ? { insufficientQuota: true } : {}),
        ...(readFailure
          ? {
            readFailedCode: readFailure.code,
            ...(readFailure.error ? { readError: readFailure.error } : {}),
          }
          : {}),
      },
      recorded,
    );
  }

  /// 先別回、停：讀完就扣一次（不送型），照字數，沒有卡。
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
    const messageCount = this.shouldCharge
      ? this.deps.quotaUsage.chargedMessageCount
      : 0;
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
      messageCount,
    });
    if (!charged.ok) {
      return await this.fail(emit, charged.event, {
        stage: "charge",
        decision: plan.decision,
      });
    }
    emit(readEvent(view));
    // 判讀已經送出，記憶只會讓 done 晚一點（最多 memoryWaitMs）。
    const memory = await this.settleMemory();
    await this.finish(
      emit,
      finalResult({
        read: view,
        cards: [],
        partial: false,
        usage: this.usage(messageCount),
        telemetry: this.telemetry({
          shouldChargeQuota: this.shouldCharge,
          chargedMessageCount: messageCount,
        }),
        trace: this.trace(
          tags,
          plan,
          memory.trace ? { memory: memory.trace } : {},
        ),
        targetProfile: memory.targetProfile,
      }),
      {
        decision: plan.decision,
        charged: this.shouldCharge,
        chargedMessageCount: messageCount,
        ...(memory.trace ? { memory: memory.trace } : {}),
      },
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
    // 每個方案都寫、都送排好的全部卡（免費也看全部：Bruce 10/18，Eric 2026-10-19）。
    const deliverable = plan.specs;
    const sourceText = this.deps.messages.map((m) => m.content).join("\n");
    const hisMessages = this.deps.messages.filter((m) => m.isFromMe).map((m) =>
      m.content
    );
    // 口吻與斷句（Bruce 2026-10-20 改法 3）：只看他的訊息定習慣；沒開就不算、卡一字不變。
    const typing = this.deps.typingStyle === true
      ? detectTypingHabits(hisMessages)
      : null;
    let typingChanges = NO_TYPING_CHANGES;
    // 「這題」「滿→蠻」（Bruce 2026-10-20 PR #97；「不怪」那條 Bruce 2026-10-21 決定不用）：她是不是自己在講
    // 題目，只看她的訊息、看一次；沒開就不算、卡一字不變。
    const tidy = this.deps.phraseTidy === true
      ? phraseTidyContext({
        herMessages: this.deps.messages.filter((m) => !m.isFromMe).map((m) =>
          m.content
        ),
      })
      : null;
    let tidyChanges = NO_PHRASE_TIDY_CHANGES;
    const delivered: GuideV3CardView[] = [];
    const removed: GuideV3Trace["removed"][number][] = [];
    const scoring: { slot: number; words: readonly string[] }[] = [];
    const raws: { slot: number; messages: readonly string[] }[] = [];
    const checks: CardChecks[] = [];
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
      const spec = card ? deliverable[card.card - 1] : undefined;
      if (!card || !spec || seen.has(card.card)) {
        state.invalidLines++;
        return true;
      }
      seen.add(card.card);
      // 兩段式實驗：寫卡提示詞新加的段落也當外洩哨兵；沒開照舊。
      const out = this.deps.twoStage === true
        ? finalizeCard(
          card,
          spec,
          sourceText,
          // 短版稱讚、帶張力改寫法開時：規格裡短版那段、帶張力的新寫法抄進卡片也拿掉；甜話短回排到時，規格裡短回的
          // 指示也一樣。都沒開照舊。
          this.shortPraiseOn || this.tensionStyleOn || this.sweetShortPlanned
            ? [
              ...TWO_STAGE_WRITER_SENTINELS,
              ...(this.shortPraiseOn ? SHORT_PRAISE_WRITER_SENTINELS : []),
              ...(this.tensionStyleOn ? TENSION_STYLE_WRITER_SENTINELS : []),
              ...(this.sweetShortPlanned ? SWEET_SHORT_WRITER_SENTINELS : []),
            ]
            : TWO_STAGE_WRITER_SENTINELS,
        )
        : finalizeCard(card, spec, sourceText);
      if (!out.ok) {
        // 原文留在伺服器紀錄，誤擋時查得到；outcome log 只記原因。
        removed.push({
          slot: card.card,
          reason: out.reason,
          messages: card.messages,
          ...(out.detail ? { detail: out.detail } : {}),
        });
        return true;
      }
      // 外洩與安全檢查之後、扣費與送出之前改：送出的卡、扣費內容、存的結果與說明步驟都看同一份字。
      const styled = typing ? styleCard(out.messages, typing) : null;
      if (styled) {
        typingChanges = addTypingChanges(typingChanges, styled.changes);
      }
      const typed = styled ? styled.messages : out.messages;
      // 緊接在口吻與斷句之後、同一個位置改，送出、扣費、存的結果與說明步驟一樣看同一份字。
      const tidied = tidy ? tidyCard(typed, tidy) : null;
      if (tidied) {
        tidyChanges = addPhraseTidyChanges(tidyChanges, tidied.changes);
      }
      const messages = tidied ? tidied.messages : typed;
      const shown = cardView(
        card.card,
        spec,
        messages,
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
        // 判讀跟第一張卡一起、在扣費之後才送：一張卡都沒有就不會白拿判讀。
        emit(readEvent(view));
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
      checks.push(cardChecks(card.card, messages, spec, hisMessages));
      return true;
    };

    // 「送到才扣」：讀局面期間 App 就斷線了，不扣、也不開始寫卡。
    if (isClosed()) {
      return await this.fail(
        emit,
        errorEvent("GUIDE_V3_CLIENT_GONE", "連線已中斷。", true),
        { stage: "before_write", decision: plan.decision },
      );
    }
    // 讀完到第一張卡還要約 2 秒、中間沒有事件：先送一則中性進度，App 照常顯示
    // 進度文字（Eric 2026-10-18）。判讀照舊等第一張卡扣費後才送。
    emit({
      type: "analysis.progress",
      phase: "writing",
      runId: this.runId,
      conversationHash: this.deps.conversationHash,
      label: GUIDE_V3_WRITING_LABEL,
    });
    try {
      // 兩段式實驗（Eric 2026-10-19）：寫卡不帶說明書的立場與表態段，規格多「這張接」；第 2 輪
      // 另放程式挑的稱讚那一句（Bruce 10/19 盲選理由）。沒開照舊。
      const twoStage = this.deps.twoStage === true;
      const userArgs = {
        turns,
        tags,
        entries: plan.entries,
        cards: deliverable,
        background: this.deps.background,
        previousRound: this.deps.previousRound,
      };
      const write = await this.deps.callWrite({
        runId: this.runId,
        system: twoStage
          ? writeSystemPromptTwoStage(undefined, undefined, undefined, {
            tensionStyle: this.tensionStyleOn,
          })
          : writeSystemPrompt(),
        user: twoStage
          ? writeUserPromptTwoStage({ ...userArgs, praise: plan.praise })
          : writeUserPrompt(userArgs),
        deadlineAtMs,
      });
      this.writeModel = write.model;
      const splitter = createLineSplitter();
      let keepGoing = true;
      for await (const chunk of write.textStream) {
        // 第一張卡扣費前 App 就斷線：停止讀串流（取消上游），不扣。
        if (delivered.length === 0 && isClosed()) {
          state.stop = { kind: "client_gone" };
          keepGoing = false;
          break;
        }
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
    const herChars = herLastTurnChars(this.deps.messages);
    // C4 開頭重複要等整組送完才算（Eric 2026-10-18 只記錄）：只有張數。
    const sameOpening = sameOpeningCount(delivered.map((c) => c.messages));
    const traceExtra = {
      removed,
      invalidLines,
      scoringWords: scoring,
      rawMessages: raws,
      firstCardMs,
      checks,
      sameOpening,
      herLastTurnChars: herChars,
      ...(typing
        ? { typingStyle: { habits: typing, changes: typingChanges } }
        : {}),
      // 只記次數與她在不在講題目，不放她或卡片的字。
      ...(tidy
        ? {
          phraseTidy: {
            herQuizWords: tidy.herQuizWords,
            changes: tidyChanges,
          },
        }
        : {}),
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
        cardsPlanned: deliverable.length,
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
      delivered.length < deliverable.length;
    // 兩段式實驗：卡都定稿送出之後才說明，事件排在最後一張卡之後、done 之前；失敗、逾時或
    // 斷線只是沒有說明，卡與扣費不變（Eric 2026-10-19 兩段式實驗）。
    const explain = this.deps.twoStage === true
      ? await this.explainCards(emit, plan, tags, turns, delivered, isClosed)
      : null;
    // 送出的說明也存進結果（照卡號）：續看只重播結果，App 才拿得回說明（主審第 1 輪 P2）。
    const cardExplains = [...(explain?.texts ?? [])].sort((a, b) =>
      a.card - b.card
    );
    // 卡都送完了才等記憶（通常早就好了）。
    const memory = await this.settleMemory();
    await this.finish(
      emit,
      finalResult({
        read: view,
        cards: delivered,
        cardExplains,
        partial,
        usage: this.usage(
          this.shouldCharge ? this.deps.quotaUsage.chargedMessageCount : 0,
        ),
        telemetry: this.telemetry({
          shouldChargeQuota: this.shouldCharge,
          chargedMessageCount: this.shouldCharge
            ? this.deps.quotaUsage.chargedMessageCount
            : 0,
          firstCardMs,
          cardsPlanned: deliverable.length,
          cardsDelivered: delivered.length,
          ...(interruptedCode ? { writeInterruptedCode: interruptedCode } : {}),
        }),
        trace: this.trace(tags, plan, {
          ...traceExtra,
          ...(memory.trace ? { memory: memory.trace } : {}),
          ...(explain ? { twoStage: { explain } } : {}),
        }),
        targetProfile: memory.targetProfile,
      }),
      {
        decision: plan.decision,
        charged: this.shouldCharge,
        firstCardMs,
        cardsPlanned: deliverable.length,
        cardsDelivered: delivered.length,
        cardsRemoved: removed.length,
        removedReasons: removed.map((r) => r.reason),
        invalidLines,
        scoringWordCards: scoring.length,
        // C5 只記錄的檢查：數字與真假，不放卡片或她的字。
        cardChecks: checks,
        sameOpening,
        herLastTurnChars: herChars,
        ...(interruptedCode ? { writeInterruptedCode: interruptedCode } : {}),
        ...(memory.trace ? { memory: memory.trace } : {}),
        // 說明只記狀態、張數與原因，不放原文。
        ...(explain
          ? {
            explain: {
              status: explain.status,
              ...(explain.code ? { code: explain.code } : {}),
              latencyMs: explain.latencyMs,
              delivered: explain.delivered.length,
              removed: explain.removed,
            },
          }
          : {}),
      },
    );
  }

  /// 兩段式實驗的說明步驟：替送出的每張卡要一段「為什麼這樣回」，過檢查的照卡片順序送出。
  /// 永遠不丟錯；結果只進 trace（App 的 done 不帶）。
  private async explainCards(
    emit: NdjsonEmit,
    plan: GuideV3Plan,
    tags: ReadTags,
    turns: readonly Turn[],
    delivered: readonly GuideV3CardView[],
    isClosed: () => boolean,
  ): Promise<GuideV3ExplainTrace> {
    const none = { delivered: [], removed: [] };
    const callExplain = this.deps.callExplain;
    if (!callExplain) {
      return { status: "skipped", code: "NO_CALL", latencyMs: null, ...none };
    }
    // App 已經斷線：說明沒人看，不打這一次。
    if (isClosed()) {
      return {
        status: "skipped",
        code: "CLIENT_GONE",
        latencyMs: null,
        ...none,
      };
    }
    const startedAt = this.now();
    const waitMs = this.deps.explainWaitMs ?? GUIDE_V3_EXPLAIN_WAIT_MS;
    const herLatest = latestHerMessages(turns);
    const cards = delivered.map((card) => ({
      slot: card.slot,
      spec: plan.specs[card.slot - 1],
      messages: card.messages,
    }));
    // 用 executor 包起來：callExplain 同步丟錯也變成 reject。
    const task = new Promise<{ text: string; model: string }>((resolve) =>
      resolve(callExplain({
        runId: this.runId,
        system: explainSystemPrompt(undefined, undefined, {
          tensionStyle: this.tensionStyleOn,
        }),
        user: explainUserPrompt({
          tensionStyle: this.tensionStyleOn,
          tags,
          herLatest,
          entries: plan.entries,
          cards,
          ...(plan.praise ? { praise: plan.praise } : {}),
        }),
        schema: EXPLAIN_SCHEMA,
        deadlineAtMs: startedAt + waitMs,
      }))
    );
    // 等不到就先結案，但這次呼叫還是要跑完、寫完 ai_logs。
    this.deps.waitUntil?.(task.catch(() => undefined));
    let timer: ReturnType<typeof setTimeout> | undefined;
    const late = new Promise<"timeout">((resolve) => {
      timer = setTimeout(() => resolve("timeout"), waitMs);
    });
    let res: { text: string; model: string } | "timeout";
    try {
      res = await Promise.race([task, late]);
    } catch (error) {
      const code = (error as { code?: unknown })?.code;
      const failure = typeof code === "string" ? code : "UNKNOWN";
      this.deps.log("guide_v3_explain_failed", {
        analysisRunId: this.runId,
        code: failure,
      }, "error");
      return {
        status: "failed",
        code: failure,
        latencyMs: this.now() - startedAt,
        ...none,
      };
    } finally {
      clearTimeout(timer);
    }
    if (res === "timeout") {
      this.deps.log("guide_v3_explain_failed", {
        analysisRunId: this.runId,
        code: "EXPLAIN_TIMEOUT",
      }, "error");
      return {
        status: "failed",
        code: "EXPLAIN_TIMEOUT",
        latencyMs: this.now() - startedAt,
        ...none,
      };
    }
    const latencyMs = this.now() - startedAt;
    const parsed = parseExplanations(res.text);
    if (!parsed) {
      this.deps.log("guide_v3_explain_failed", {
        analysisRunId: this.runId,
        code: "EXPLAIN_INVALID",
      }, "error");
      return { status: "invalid", model: res.model, latencyMs, ...none };
    }
    const sent: number[] = [];
    const removed: { card: number; reason: string }[] = [];
    const texts: { card: number; text: string }[] = [];
    for (const card of delivered) {
      const raw = parsed.get(card.slot);
      if (raw === undefined) {
        removed.push({ card: card.slot, reason: "missing" });
        continue;
      }
      // 說明看得到的新字（短版那段、帶張力的新寫法）照抄進說明也不給，跟卡片同一份哨兵；帶張力改寫法另加
      // 說明規則那一條（主審第 1 輪 P2）。都沒開照舊。甜話短回的短回指示只比卡片、不比說明：說明講這張「短短回她一句就好」
      // 是自然的白話，拿掉反而少了那張的說明；照抄規格的結構仍由說明自己的哨兵擋。
      const vetted = vetExplanation(raw, [
        ...(this.tensionStyleOn
          ? [
            ...TENSION_STYLE_EXPLAIN_SENTINELS,
            ...TENSION_STYLE_WRITER_SENTINELS,
          ]
          : []),
        ...(this.shortPraiseOn ? SHORT_PRAISE_WRITER_SENTINELS : []),
      ]);
      if (!vetted.ok) {
        removed.push({ card: card.slot, reason: vetted.reason });
        continue;
      }
      emit(cardExplainEvent(card.slot, vetted.text));
      sent.push(card.slot);
      texts.push({ card: card.slot, text: vetted.text });
    }
    return {
      status: "ok",
      model: res.model,
      latencyMs,
      delivered: sent,
      removed,
      texts,
    };
  }
}
