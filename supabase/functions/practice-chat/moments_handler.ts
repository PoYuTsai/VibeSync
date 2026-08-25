// 練習室「模擬社群動態」的 feed 與有界補生成。
//
// 自包含、回傳 { body, status }、可用 mock client 單元測試，與 chat/hint/
// debrief 路徑完全隔離（範式沿用 draw_handler.ts）。
//
// **no-canned 鐵則**：生成或驗證失敗時只做兩件事——release 掉 latch、
// 把那一則算進 pendingCount。永遠不寫罐頭內容進 practice_moment_posts，
// 也永遠不在回應裡塞預設文案。這條由 moments_generated_only_source_test.ts
// 逐字串守門（既有的 generated_only_source_test.ts 只讀 handler.ts，蓋不到這裡）。
//
// **隱私鐵則**：貼文是全域的。生成輸入只有 server profile + 日期 + 題材 +
// 候選 imageId；使用者的身分只用來決定「看得到誰」，不進 prompt 一個字。
//
// **成本上限**：全站每日 ≤ 600 次模型呼叫 = 100 位角色（Edge allowlist）
// × 2 slot × 3 attempts（DB CHECK）。這支檔案負責 allowlist 那一半：
// profile_id 只可能來自 getPracticeGirlProfile，post_date 只可能是
// taipeiTimeContextFor(now).isoDate。契約測試在 moments_edge_contract_test.ts。

import {
  classifyModelRateLimitError,
  MODEL_RATE_LIMITS,
} from "../_shared/model_rate_limit.ts";
import type { DeepSeekArgs } from "./deepseek.ts";
import { DEEPSEEK_MODEL } from "./deepseek.ts";
import { logInfo, logWarn, summarizeUser } from "./logger.ts";
import {
  getPracticeGirlProfile,
  type PracticeGirlProfile,
} from "./practice_persona.ts";
import {
  type MomentDayPlan,
  momentPlanFor,
  type MomentSlotPlan,
} from "./moments_schedule.ts";
import {
  resolveAvailableMomentImages,
  SELF_PORTRAIT_IMAGE_ID,
} from "./moments_image_catalog.ts";
import {
  generateMomentImage,
  type MomentImageGenDeps,
  type MomentImageJob,
} from "./moments_image_gen.ts";
import {
  type MomentImageSweepDeps,
  sweepExpiredMomentImages,
} from "./moments_image_sweep.ts";
import { momentPostedAtFor } from "./moments_time.ts";
import { buildMomentMessages } from "./moments_prompt.ts";
import { validateMomentDraft } from "./moments_validate.ts";
import {
  type TaipeiDayPart,
  type TaipeiTimeContext,
  taipeiTimeContextFor,
} from "./time_context.ts";
import {
  FEED_WINDOW_DAYS,
  MAX_MOMENT_ATTEMPTS,
  MOMENT_FILL_DEADLINE_MS,
  MOMENT_FILL_MAX_PER_REQUEST,
  MOMENT_MODEL_MAX_TOKENS,
  MOMENT_IMAGE_FILL_MAX_PER_REQUEST,
  MOMENT_MODEL_TEMPERATURE,
  MOMENT_MODEL_TIMEOUT_MS,
  MOMENT_RESERVE_LEASE_MS,
} from "./moments_constants.ts";

// ── 最小 supabase client 介面（真 client 結構上即滿足；test 注入 mock）──
type Row = Record<string, unknown>;

export interface MomentsPostgrestResult<T> {
  data: T | null;
  error: { message: string } | null;
}

export interface MomentsFilterBuilder
  extends PromiseLike<MomentsPostgrestResult<Row[]>> {
  eq(column: string, value: unknown): MomentsFilterBuilder;
}

export interface MomentsSupabaseClient {
  from(table: string): { select(columns: string): MomentsFilterBuilder };
  rpc(
    fn: string,
    params: Row,
  ): PromiseLike<MomentsPostgrestResult<unknown>>;
}

export interface MomentsHandlerDeps {
  callDeepSeek: (args: DeepSeekArgs) => Promise<string>;
  apiKey: string;
  /** 測試注入用；預設 crypto.randomUUID。 */
  randomToken?: () => string;
  /**
   * 測試注入用：把 8 秒死線縮短，避免單元測試真的等 8 秒。
   * production 一律走 MOMENT_FILL_DEADLINE_MS。
   */
  fillDeadlineMs?: number;
  /**
   * 測試注入用：momentPlanFor 在職業安靜時段吃掉所有可發文時段時會丟
   * moment_schedule_empty_theme_pool，而正式名冊裡不存在那種職業，所以
   * 「一位角色炸掉不能讓整個 feed 500」這條只能靠注入來驗。
   */
  planFor?: (opts: {
    girl: PracticeGirlProfile;
    time: TaipeiTimeContext;
  }) => MomentDayPlan;
  /**
   * 生成配圖的注入點（PR-3）。undefined＝kill switch 關：wantsImage slot
   * 走現行 bundled 候選路徑，行為與導入前完全相同。
   */
  imageGen?: MomentImageGenDeps;
  /** 背景 job 排程；production 走 EdgeRuntime.waitUntil（handler.ts 注入）。 */
  waitUntil?: (task: Promise<void>) => void;
  /**
   * Storage public URL 前綴（…/object/public/<bucket>）。與 imageGen 開關
   * 獨立：已生成的圖在開關關閉後仍要露出。
   */
  storagePublicUrlBase?: string;
  /**
   * 過期清掃的注入點（PR-4）。與 imageGen 開關獨立：生成關掉之後，
   * 既有的圖出窗一樣要刪。undefined＝不清掃（測試環境）。
   */
  imageSweep?: MomentImageSweepDeps;
}

export interface MomentsHandlerResult {
  body: unknown;
  status: number;
}

export interface MomentFeedPost {
  profileId: string;
  postDate: string;
  slot: number;
  dayPart: TaipeiDayPart;
  postedAt: string;
  body: string;
  imageId: string | null;
  /** 生成配圖的 public URL；僅 image_status='ready' 時非 null。 */
  imageUrl: string | null;
}

interface MissingSlot {
  girl: PracticeGirlProfile;
  isoDate: string;
  plan: MomentSlotPlan;
  postedAt: Date;
  imageCandidates: readonly string[];
  /** true＝走生成配圖（候選清空、commit 標 pending、背景 job 以文生圖）。 */
  generatedImage: boolean;
  unlockedAt: number;
}

/** PostgREST 把 RETURNS TABLE 包成陣列；統一取第一列。 */
function firstRow(data: unknown): Row | null {
  const row = Array.isArray(data) ? data[0] : data;
  if (typeof row !== "object" || row === null || Array.isArray(row)) {
    return null;
  }
  return row as Row;
}

function isoDateOf(value: unknown): string | null {
  if (typeof value === "string") return value.slice(0, 10);
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return null;
}

/** 台北日往前推 N 天（feed 視窗的起點）。 */
function shiftIsoDate(isoDate: string, days: number): string {
  const shifted = new Date(`${isoDate}T00:00:00.000Z`);
  shifted.setUTCDate(shifted.getUTCDate() + days);
  return shifted.toISOString().slice(0, 10);
}

function slotKey(profileId: string, isoDate: string, slot: number): string {
  return `${profileId}|${isoDate}|${slot}`;
}

/**
 * feed + 有界補生成。
 *
 * 絕大多數請求走「零模型呼叫」那條路：貼文是全域的，第一個看到的人補完，
 * 之後所有人都只是讀。
 */
export async function handlePracticeMoments(args: {
  supabase: MomentsSupabaseClient;
  userId: string;
  now: Date;
  isTestAccount: boolean;
  deps: MomentsHandlerDeps;
}): Promise<MomentsHandlerResult> {
  const { supabase, userId, now, isTestAccount, deps } = args;
  const startedAt = Date.now();
  const deadlineMs = deps.fillDeadlineMs ?? MOMENT_FILL_DEADLINE_MS;
  const time = taipeiTimeContextFor(now);
  const planFor = deps.planFor ?? momentPlanFor;

  // 1. 這個帳號翻到過誰。practice_profile_draw_events 是抽卡鏈路的權威紀錄。
  const { data: drawRows, error: drawError } = await supabase
    .from("practice_profile_draw_events")
    .select("profile_id, created_at")
    .eq("user_id", userId);
  if (drawError) {
    logWarn("practice_moments_unlocked_fetch_error", {
      user: summarizeUser(userId),
      error: drawError.message,
    });
    return { body: { error: "practice_moments_failed" }, status: 500 };
  }

  // **Edge allowlist**：只有名冊裡的 100 位角色進得了下面任何一個 RPC。
  // DB 不認識角色名冊，任意字串都會各自拿到自己的 6 次額度——這一步就是
  // 「每日 600 次上限」的另一半。
  const unlockedAtByProfile = new Map<string, number>();
  for (const row of drawRows ?? []) {
    const profileId = row.profile_id;
    if (typeof profileId !== "string") continue;
    if (!getPracticeGirlProfile(profileId)) continue;
    const createdAt = typeof row.created_at === "string"
      ? Date.parse(row.created_at)
      : NaN;
    const unlockedAt = Number.isFinite(createdAt) ? createdAt : 0;
    const previous = unlockedAtByProfile.get(profileId);
    if (previous === undefined || unlockedAt > previous) {
      unlockedAtByProfile.set(profileId, unlockedAt);
    }
  }
  const profileIds = [...unlockedAtByProfile.keys()].sort();
  if (profileIds.length === 0) {
    // 一張都沒抽到：不打 DB、不打模型。
    return {
      body: { posts: [], generatedCount: 0, pendingCount: 0 },
      status: 200,
    };
  }

  // 2. 既有的 ready 貼文。
  const since = shiftIsoDate(time.isoDate, -(FEED_WINDOW_DAYS - 1));
  const { data: listData, error: listError } = await supabase.rpc(
    "list_practice_moment_posts",
    { p_profile_ids: profileIds, p_since: since },
  );
  if (listError) {
    logWarn("practice_moments_list_error", {
      user: summarizeUser(userId),
      error: listError.message,
    });
    return { body: { error: "practice_moments_failed" }, status: 500 };
  }

  const posts: MomentFeedPost[] = [];
  const readySlots = new Set<string>();
  // 機會式接手：list 裡 image_status='pending' 的列（租約與 attempts 由
  // claim RPC 自行把關，這裡只負責把 job 丟進背景）。
  const pendingImageJobs: MomentImageJob[] = [];
  for (const raw of Array.isArray(listData) ? listData : []) {
    if (typeof raw !== "object" || raw === null) continue;
    const row = raw as Row;
    const profileId = row.profile_id;
    const postDate = isoDateOf(row.post_date);
    const slot = Number(row.slot);
    const dayPart = row.day_part;
    const bodyText = row.body;
    if (
      typeof profileId !== "string" || postDate === null ||
      !Number.isInteger(slot) || typeof dayPart !== "string" ||
      typeof bodyText !== "string" || bodyText.length === 0
    ) {
      continue;
    }
    if (!getPracticeGirlProfile(profileId)) continue;
    readySlots.add(slotKey(profileId, postDate, slot));
    let postedAt: Date;
    try {
      postedAt = momentPostedAtFor({
        profileId,
        isoDate: postDate,
        slot,
        dayPart: dayPart as TaipeiDayPart,
      });
    } catch {
      continue;
    }
    // 未到時間的一律不露出（即使 DB 裡已經是 ready）。
    if (postedAt.getTime() > now.getTime()) continue;
    const imageStatus = typeof row.image_status === "string"
      ? row.image_status
      : "none";
    const imagePath = typeof row.image_path === "string"
      ? row.image_path
      : null;
    if (imageStatus === "pending") {
      pendingImageJobs.push({ profileId, isoDate: postDate, slot });
    }
    posts.push({
      profileId,
      postDate,
      slot,
      dayPart: dayPart as TaipeiDayPart,
      postedAt: postedAt.toISOString(),
      body: bodyText,
      imageId: typeof row.image_id === "string" ? row.image_id : null,
      imageUrl: imageStatus === "ready" && imagePath !== null &&
          deps.storagePublicUrlBase
        ? `${deps.storagePublicUrlBase}/${imagePath}`
        : null,
    });
  }

  // 3-4. 今天該有、但 DB 裡還沒有的 slot。
  const missing: MissingSlot[] = [];
  for (const profileId of profileIds) {
    const girl = getPracticeGirlProfile(profileId);
    if (!girl) continue;
    let plan: MomentDayPlan;
    try {
      plan = planFor({ girl, time });
    } catch (e) {
      // 一位角色的排程炸掉只能讓「那一位」今天沒貼文，絕不讓整個 feed 500。
      logWarn("practice_moments_plan_failed", {
        profileId,
        error: e instanceof Error ? e.message : String(e),
      });
      continue;
    }
    for (const slotPlan of plan.slots) {
      if (readySlots.has(slotKey(profileId, plan.isoDate, slotPlan.slot))) {
        continue;
      }
      const postedAt = momentPostedAtFor({
        profileId,
        isoDate: plan.isoDate,
        slot: slotPlan.slot,
        dayPart: slotPlan.dayPart,
      });
      if (postedAt.getTime() > now.getTime()) continue;
      const resolvedCandidates = slotPlan.wantsImage
        ? resolveAvailableMomentImages(slotPlan.imageCandidates)
        : [];
      // 生成配圖判定（設計文件 §9）：開關開、slot 要圖，且候選不是「只剩
      // 自拍 sentinel」——自拍照舊走圖鑑照片，不生成人臉。
      const onlySelfPortrait = resolvedCandidates.length === 1 &&
        resolvedCandidates[0] === SELF_PORTRAIT_IMAGE_ID;
      const generatedImage = deps.imageGen !== undefined &&
        slotPlan.wantsImage && resolvedCandidates.length > 0 &&
        !onlySelfPortrait;
      missing.push({
        girl,
        isoDate: plan.isoDate,
        plan: slotPlan,
        postedAt,
        imageCandidates: generatedImage ? [] : resolvedCandidates,
        generatedImage,
        unlockedAt: unlockedAtByProfile.get(profileId) ?? 0,
      });
    }
  }

  // 5. 沒有缺口就直接回既有貼文——絕大多數請求走這條，零模型呼叫、零限流。
  //    生圖接手照排：pending 列多半正是在這條路上被補完的。
  if (missing.length === 0 || deps.apiKey.length === 0) {
    if (missing.length > 0) {
      logWarn("practice_moments_config_missing", {
        user: summarizeUser(userId),
        pending: missing.length,
      });
    }
    scheduleMomentImageJobs({
      supabase,
      deps,
      userId,
      isTestAccount,
      jobs: pendingImageJobs,
    });
    scheduleImageSweep({ supabase, deps, isoDate: time.isoDate });
    return {
      body: {
        posts: sortPosts(posts),
        generatedCount: 0,
        pendingCount: missing.length,
      },
      status: 200,
    };
  }

  // 6. 限流刻意「不在這裡」做，理由有兩個（2026-08-24 複審 BLOCK 1 與 2）：
  //
  //    a. 限流命中時不可以回 429。feed 已經讀到的既有貼文會整包消失，
  //       與設計稿「缺貼文時顯示既有內容、不塞罐頭、不報錯」直接衝突。
  //       正確行為是「跳過補生成」，仍回 200 + 既有 posts + generatedCount: 0。
  //    b. 在這裡只會記 1 次，但下面最多平行打 MOMENT_FILL_MAX_PER_REQUEST 次模型，
  //       6/min、60/day 會被放大成 18/min、180/day，宣稱的成本上界就是假的。
  //
  //    所以限流下放到 fillOneSlot，**每一次模型呼叫算一次**，語義才對得起數字。

  // 7. 取前 K 則平行補。排序：最新解鎖優先（她剛被抽到，最值得先有貼文），
  //    再用 profileId／slot 讓結果決定論。
  //    刻意不用「最近聊過」當排序鍵：那要多讀一張對話表，而且會把使用者
  //    對話資料拉到生成路徑旁邊，隱私鐵則上得不償失。
  missing.sort((a, b) =>
    b.unlockedAt - a.unlockedAt ||
    a.girl.profileId.localeCompare(b.girl.profileId) ||
    a.plan.slot - b.plan.slot
  );
  const batch = missing.slice(0, MOMENT_FILL_MAX_PER_REQUEST);

  const deadlineAt = startedAt + deadlineMs;
  const filled: MomentFeedPost[] = [];
  const committedImageJobs: MomentImageJob[] = [];
  const tasks = batch.map((item) =>
    fillOneSlot({ supabase, userId, item, deps, deadlineAt, isTestAccount }).then((post) => {
      if (post) {
        filled.push(post);
        if (item.generatedImage) {
          committedImageJobs.push({
            profileId: item.girl.profileId,
            isoDate: item.isoDate,
            slot: item.plan.slot,
          });
        }
      }
    })
  );

  // 8. 死線：到點就不等。未完成的列留著 token，由租約逾時或下次請求接手。
  let deadlineTimer: ReturnType<typeof setTimeout> | undefined;
  const deadlineReached = new Promise<void>((resolve) => {
    deadlineTimer = setTimeout(resolve, Math.max(0, deadlineAt - Date.now()));
  });
  try {
    await Promise.race([Promise.allSettled(tasks), deadlineReached]);
  } finally {
    // 全部提早完成時要把 timer 收掉，不留懸掛的 op。
    if (deadlineTimer !== undefined) clearTimeout(deadlineTimer);
  }

  // 新 commit 的優先（她剛發文，最值得先有圖），剩餘配額給 pending 接手。
  const imageJobsScheduled = scheduleMomentImageJobs({
    supabase,
    deps,
    userId,
    isTestAccount,
    jobs: [...committedImageJobs, ...pendingImageJobs],
  });
  scheduleImageSweep({ supabase, deps, isoDate: time.isoDate });

  logInfo("practice_moments_filled", {
    user: summarizeUser(userId),
    missing: missing.length,
    attempted: batch.length,
    generated: filled.length,
    imageJobsScheduled,
  });

  return {
    body: {
      posts: sortPosts([...posts, ...filled]),
      generatedCount: filled.length,
      pendingCount: missing.length - filled.length,
    },
    status: 200,
  };
}

/**
 * 把生圖 job 丟進背景（EdgeRuntime.waitUntil 範式照 handler.ts 的 telemetry）。
 * 回傳實際排入數。generateMomentImage 自己永不 throw；排程失敗只記錄，
 * 絕不把 feed 回應變成 5xx。
 */
function scheduleMomentImageJobs(args: {
  supabase: MomentsSupabaseClient;
  deps: MomentsHandlerDeps;
  userId: string;
  isTestAccount: boolean;
  jobs: readonly MomentImageJob[];
}): number {
  const imageGen = args.deps.imageGen;
  if (!imageGen || args.jobs.length === 0) return 0;
  const batch = args.jobs.slice(0, MOMENT_IMAGE_FILL_MAX_PER_REQUEST);
  for (const job of batch) {
    const task = generateMomentImage({
      supabase: args.supabase,
      deps: imageGen,
      job,
      userId: args.userId,
      isTestAccount: args.isTestAccount,
    });
    try {
      if (args.deps.waitUntil) {
        args.deps.waitUntil(task);
        continue;
      }
      const edgeRuntime = (globalThis as unknown as {
        EdgeRuntime?: { waitUntil(task: Promise<void>): void };
      }).EdgeRuntime;
      if (edgeRuntime?.waitUntil) {
        edgeRuntime.waitUntil(task);
        continue;
      }
    } catch {
      // 排程器失敗不得影響 feed 回應。
    }
    // 本機測試沒有 EdgeRuntime；job 自吞錯誤，detach 不會 unhandled rejection。
    void task;
  }
  logInfo("practice_moment_image_jobs", { scheduled: batch.length });
  return batch.length;
}

/** 把過期清掃丟進背景；deps.imageSweep 缺席（測試）就不掃。 */
function scheduleImageSweep(args: {
  supabase: MomentsSupabaseClient;
  deps: MomentsHandlerDeps;
  isoDate: string;
}): void {
  const sweep = args.deps.imageSweep;
  if (!sweep) return;
  const task = sweepExpiredMomentImages({
    supabase: args.supabase,
    deps: sweep,
    isoDate: args.isoDate,
  }).then(() => {});
  try {
    if (args.deps.waitUntil) {
      args.deps.waitUntil(task);
      return;
    }
    const edgeRuntime = (globalThis as unknown as {
      EdgeRuntime?: { waitUntil(task: Promise<void>): void };
    }).EdgeRuntime;
    if (edgeRuntime?.waitUntil) {
      edgeRuntime.waitUntil(task);
      return;
    }
  } catch {
    // 排程器失敗不得影響 feed 回應。
  }
  void task;
}

function sortPosts(posts: MomentFeedPost[]): MomentFeedPost[] {
  return [...posts].sort((a, b) =>
    Date.parse(b.postedAt) - Date.parse(a.postedAt) ||
    a.profileId.localeCompare(b.profileId) ||
    a.slot - b.slot
  );
}

/**
 * 補一則貼文：reserve → DeepSeek → validate → commit，失敗就 release。
 *
 * 回傳成功寫入的貼文；任何失敗一律回 null，**絕不回罐頭內容**。
 */
async function fillOneSlot(opts: {
  supabase: MomentsSupabaseClient;
  userId: string;
  item: MissingSlot;
  deps: MomentsHandlerDeps;
  deadlineAt: number;
  isTestAccount: boolean;
}): Promise<MomentFeedPost | null> {
  const { supabase, userId, item, deps, deadlineAt, isTestAccount } = opts;
  const { girl, isoDate, plan, imageCandidates, generatedImage } = item;

  // 死線守門必須在原子 reserve gate 之前。gate 只在成功認領 slot 時，
  // 同一筆交易內一起計入 attempts 與 per-user model usage。
  if (Date.now() >= deadlineAt) return null;

  const generationToken = (deps.randomToken ?? (() => crypto.randomUUID()))();
  const rateLimits = MODEL_RATE_LIMITS.practice_moment;
  const slotParams = {
    p_profile_id: girl.profileId,
    p_post_date: isoDate,
    p_slot: plan.slot,
  };

  const { data: reserveData, error: reserveError } = await supabase.rpc(
    "reserve_practice_moment_slot",
    {
      ...slotParams,
      p_day_part: plan.dayPart,
      p_theme_id: plan.themeId,
      p_generation_token: generationToken,
      p_user_id: userId,
      p_minute_limit: rateLimits.perMinute,
      p_daily_limit: rateLimits.perDay,
      p_count_user_usage: !isTestAccount,
      p_max_attempts: MAX_MOMENT_ATTEMPTS,
      p_lease_seconds: MOMENT_RESERVE_LEASE_MS / 1000,
    },
  );
  if (reserveError) {
    if (classifyModelRateLimitError(reserveError.message)) {
      // 背景補生成撞限流只跳過這格；呼叫端仍回 200 + 既有 feed。
      return null;
    }
    logWarn("practice_moments_reserve_error", {
      user: summarizeUser(userId),
      profileId: girl.profileId,
      error: reserveError.message,
    });
    return null;
  }
  const reserved = firstRow(reserveData);
  if (!reserved || reserved.claimed !== true) {
    // 別人正在跑、已經 ready、或 attempts 用完轉 exhausted：不打模型。
    return null;
  }
  const token = typeof reserved.token === "string"
    ? reserved.token
    : generationToken;

  let raw: string;
  try {
    const remainingMs = deadlineAt - Date.now();
    if (remainingMs <= 0) {
      // 死線已過：不打模型，也不 release（token 留給租約）。
      return null;
    }
    raw = await deps.callDeepSeek({
      apiKey: deps.apiKey,
      messages: buildMomentMessages({
        girl,
        themeId: plan.themeId,
        brief: plan.brief,
        dayPart: plan.dayPart,
        isoDate,
        slot: plan.slot,
        isWeekend: taipeiTimeContextFor(new Date(`${isoDate}T04:00:00.000Z`))
          .isWeekend,
        imageCandidates,
        generatedImage,
      }),
      maxTokens: MOMENT_MODEL_MAX_TOKENS,
      temperature: MOMENT_MODEL_TEMPERATURE,
      jsonMode: true,
      // thinking 不傳 → 沿用 deepseek.ts 的預設 disabled。
      timeoutMs: Math.min(MOMENT_MODEL_TIMEOUT_MS, remainingMs),
    });
  } catch (e) {
    // 死線中止不 release：release 會讓下一個請求立刻接手並多燒一次
    // attempts，等於用死線換成本。留著 token 由租約逾時自然接手。
    if (Date.now() >= deadlineAt) {
      logWarn("practice_moments_generation_deadline", {
        profileId: girl.profileId,
        slot: plan.slot,
      });
      return null;
    }
    await releaseSlot(supabase, slotParams, token, girl.profileId);
    logWarn("practice_moments_generation_failed", {
      user: summarizeUser(userId),
      profileId: girl.profileId,
      failureClass: e instanceof Error ? e.message : "unknown",
    });
    return null;
  }

  let draft;
  try {
    draft = validateMomentDraft({ raw, imageCandidates });
  } catch (e) {
    await releaseSlot(supabase, slotParams, token, girl.profileId);
    logWarn("practice_moments_validation_rejected", {
      profileId: girl.profileId,
      failureClass: e instanceof Error ? e.message : "unknown",
    });
    return null;
  }

  const { data: commitData, error: commitError } = await supabase.rpc(
    "commit_practice_moment_post",
    {
      ...slotParams,
      p_generation_token: token,
      p_body: draft.body,
      p_image_id: draft.imageId,
      p_model: DEEPSEEK_MODEL,
      // 部署窗相容：合併到 main 會先自動部署 Edge、migration 才手動套。
      // 開關關時**省略**這個鍵（而不是傳 false），舊 DB 的 7-arg commit
      // 才能繼續以 named args 匹配；傳了 false 會在 migration 套上前
      // 讓所有文字補生成 PGRST202 全掛。開關開是 Eric 在 migration 套完
      // 之後的手動動作，屆時 8-arg 已存在。
      ...(generatedImage ? { p_wants_image: true } : {}),
    },
  );
  if (commitError || firstRow(commitData)?.committed !== true) {
    // token fencing 打回（被別人接手）或 DB 錯誤：不 release（token 已經不是
    // 我的了），也不回內容。
    logWarn("practice_moments_commit_rejected", {
      profileId: girl.profileId,
      error: commitError?.message ?? "not_committed",
    });
    return null;
  }

  return {
    profileId: girl.profileId,
    postDate: isoDate,
    slot: plan.slot,
    dayPart: plan.dayPart,
    postedAt: item.postedAt.toISOString(),
    body: draft.body,
    imageId: draft.imageId,
    // 圖在背景生成中，本回應永遠給 null；ready 後由下次 feed 讀出。
    imageUrl: null,
  };
}

async function releaseSlot(
  supabase: MomentsSupabaseClient,
  slotParams: Row,
  token: string,
  profileId: string,
): Promise<void> {
  const { error } = await supabase.rpc("release_practice_moment_slot", {
    ...slotParams,
    p_generation_token: token,
    p_max_attempts: MAX_MOMENT_ATTEMPTS,
  });
  if (error) {
    logWarn("practice_moments_release_error", {
      profileId,
      error: error.message,
    });
  }
}
