// conversation-agency-v1 Phase 2.7：flag-off 等價 harness（機器可檢查的休眠契約）。
//
// ── 這支在守什麼 ────────────────────────────────────────────────────────
// `PRACTICE_CONVERSATIONAL_AGENCY_ENABLED` 未設／`off`／`shadow` 時，
// practice-chat handler 對外的**每一個可觀測面**都必須跟接線前的 `7f1d6d6c`
// 逐位元組相同。Codex 連續三輪找出旗標關閉時的行為外洩，都是因為舊的 golden
// 只涵蓋「DeepSeek messages ＋ Response bytes ＋ 一個 RPC fixture」。這裡把
// 四個面一起釘死：
//
//   1. `messages`  ── 每一次 DeepSeek／Claude 呼叫的完整 messages（chat、
//                     分類器、hint、debrief 都在同一個陣列裡）。
//   2. `response`  ── 原始 Response bytes（status ＋ 排序後 headers ＋ body）。
//   3. `rpc`       ── 每一次 RPC 的 `fn` ＋ 完整 `params`（不只 p_recent_facts）。
//   4. `telemetry` ── 這一輪印出的每一行 `console.log`／`console.warn` JSON
//                     （完整形狀：多一個 key、少一個 key、key 順序不同都會炸）。
//
// ── 矩陣 ────────────────────────────────────────────────────────────────
// chat：模式（standard／beginner／game）× reply-style（關／開）
//     × thread 狀態（沒有 thread／有 replyStyle 狀態／有 agency key ＋未知 key）
//     × 分類器回覆（合法 JSON／partnerMood 是列舉外的 "confused"／根本不是 JSON）
//     × 聊天回覆（一般／原樣重複的 token／括號旁白）
//   ＝ 3 × 2 × 3 × 3 × 3 ＝ 162 案。
// hint／debrief：模式（3）× reply-style（2）× 兩種 mode ＝ 12 案。
// Phase 2.8 補的形態案（`extraCases()`，不再乘一輪組合，每個走不同分支）：
//   非空 herRecentMoments（standard／beginner）、hint prefetch、draw_status
//   request handler、配額 RPC 失敗 → 4xx 的錯誤路徑 ＝ 5 案。
// 合計 179 案 × 5 個環境值（未設／off／shadow／true／test）＝ 895 次 handler 呼叫。
//
// ── golden 出處與重新產生的程序 ─────────────────────────────────────────
// `AGENCY_FLAG_OFF_GOLDEN` 的每一筆都是在 `7f1d6d6c`（agency 接線前的最後一個
// commit）上跑本檔的 printer 印出來的。重新產生：
//
//   scratch=$(mktemp -d)
//   git archive 7f1d6d6c | tar -x -C "$scratch"
//   cp supabase/functions/practice-chat/handler_test_fake.ts \
//      supabase/functions/practice-chat/agency_flag_off_equivalence_test.ts \
//      "$scratch/supabase/functions/practice-chat/"
//   cd "$scratch" && AGENCY_EQUIV_PRINT_GOLDEN=1 deno test --allow-env \
//     --allow-read supabase/functions/practice-chat/agency_flag_off_equivalence_test.ts
//
// 把印出來的 TS 常數整段貼回本檔取代 `AGENCY_FLAG_OFF_GOLDEN`。
// `handler_test_fake.ts` 可以直接拷過去，是因為它是從 `index_test.ts` 原樣搬出
// 來的，而那幾段在 `7f1d6d6c` 與 HEAD **逐位元組相同**（本輪 diff 驗證）；本檔
// 本身也刻意不 import 任何 agency 專屬符號，才能在 `7f1d6d6c` 上編譯。
//
// **harness 抓到差異時要改的是程式，不是 golden。** 只有在 `7f1d6d6c` 之外的
// 正當 production 行為改動（旗標無關）落地時，才照上面的程序重跑 printer。
//
// Phase 2.8 新增的 5 個形態案就是照這個程序在 `7f1d6d6c` 上重跑 printer 產生
// 的；既有 174 案的 digest **一個位元都沒有變**（`statusText` 進 digest 時刻意
// 讓空字串不寫進 head，所以現況零位元差）。

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  chatBody,
  debriefBody,
  type FakeOptions,
  hintBody,
  ledger,
  makeFake,
  makeRequest,
  sha256HexOf,
} from "./handler_test_fake.ts";

const AGENCY_ENV = "PRACTICE_CONVERSATIONAL_AGENCY_ENABLED";
/** Phase 4.4 混合模型路由旗標（harness 多枚舉的一維環境值）。 */
const ROUTING_ENV = "PRACTICE_CHAT_MODEL_ROUTING";
const STYLE_ENV = "PRACTICE_REPLY_STYLE_ENABLED";
const TEST_ACCOUNT = { id: "user-1", email: "vibesync.test@gmail.com" };

/** 逐位元組比對用；截 16 hex（64 bit）只是為了讓 golden 表可讀。 */
async function digest(value: string | Uint8Array): Promise<string> {
  return (await sha256HexOf(value)).slice(0, 16);
}

// ── 固定 fixture ──────────────────────────────────────────────────────────
// 玩家丟片段、她問了、玩家又丟一個不相干的詞：agency 開時會介入的典型形狀。
const FRAGMENT_TURNS = [
  { role: "user", text: "東東" },
  { role: "ai", text: "東東是誰" },
  { role: "user", text: "阿布達比" },
];

// hint／debrief 要求逐字稿最後一則是她（`invalid_hint_last_turn_must_be_ai`），
// 所以這兩個 mode 用同一段片段再補一則她的回問。
const SIDE_TURNS = [
  ...FRAGMENT_TURNS,
  { role: "ai", text: "阿布達比？那是哪裡" },
];

const CLASSIFIER_VALID =
  `{"connection":"caught","impact":"medium","testHandling":"none","boundary":"safe","hintAlignment":"none"}`;
// partnerMood 是列舉外的值：`7f1d6d6c` 的 parser 會 throw → 走 fallback。
const CLASSIFIER_UNKNOWN_MOOD =
  `{"connection":"caught","impact":"medium","testHandling":"none","boundary":"safe","hintAlignment":"none","partnerMood":"confused"}`;
const CLASSIFIER_NON_JSON = "抱歉我不太確定";

const CHAT_REPLIES: Readonly<Record<string, string>> = {
  一般: "好啊",
  重複同一個詞: "阿布達比",
  括號旁白: "（冷淡）好啊",
};
const CLASSIFIER_REPLIES: Readonly<Record<string, string>> = {
  合法: CLASSIFIER_VALID,
  未知心情: CLASSIFIER_UNKNOWN_MOOD,
  非JSON: CLASSIFIER_NON_JSON,
};

const THREAD_RECENT_FACTS: Readonly<
  Record<string, Record<string, unknown> | null>
> = {
  無thread: null,
  有style狀態: {
    source: "practice_chat",
    aiTurnCount: 3,
    replyStyle: { version: 1, priorDecline: true, recentActs: ["acknowledge"] },
  },
  有agency與未知key: {
    source: "practice_chat",
    aiTurnCount: 3,
    conversationAgency: {
      version: 1,
      lastCoherence: "repetitive",
      unresolvedCount: 3,
      priorChallengeIssued: true,
      lastAgencyAct: "hold_position",
    },
    futureFeature: { nested: ["keep", 1], flag: true },
    unknownScalar: "keep-me",
  },
};

const MODES = ["standard", "beginner", "game"] as const;

// 非空 `herRecentMoments`：`list_practice_moment_posts` 回的一列。fake 的時鐘
// 釘在 `handler_test_fake.ts` 的 `NOW`（2026-06-28T04:00Z＝台北 12:00），所以
// 這個 post_date 永遠落在 7 天窗內、發文時刻也永遠已經過去，digest 可重現。
// 沒有這一列的話 fake 對未設定的 RPC 一律回 `{data:true}`，而
// `fetchHerRecentMoments()` 只吃陣列——舊矩陣其實只涵蓋「空貼文」那條路徑。
const MOMENT_ROWS: ReadonlyArray<Record<string, unknown>> = [{
  profile_id: "practice_girl_001",
  post_date: "2026-06-27",
  slot: 1,
  day_part: "evening",
  body: "剛加完班，只想吃碗麵",
}];

function threadRowFor(
  mode: typeof MODES[number],
  recentFacts: Record<string, unknown> | null,
): Record<string, unknown> | null {
  if (recentFacts === null) return null;
  return {
    profile_id: mode === "game" ? "practice_girl_004" : "practice_girl_001",
    temperature_score: 40,
    familiarity_score: 10,
    recent_facts: recentFacts,
  };
}

interface EquivalenceCase {
  readonly name: string;
  readonly options: FakeOptions;
  readonly body: unknown;
}

function chatCaseFor(
  mode: typeof MODES[number],
  styleOn: boolean,
  threadKey: string,
  classifierKey: string,
  chatKey: string,
): EquivalenceCase {
  const thread = threadRowFor(mode, THREAD_RECENT_FACTS[threadKey]);
  const env: Record<string, string> = {};
  if (styleOn) env[STYLE_ENV] = "true";
  const options: FakeOptions = {
    // standard 走 ledger、assisted（beginner／game）走 thread seed。
    ledger: mode === "standard" ? ledger({ practice_mode: "standard" }) : null,
    thread,
    ...(mode === "game"
      ? { drawEvents: [{ profile_id: "practice_girl_004" }] }
      : {}),
    env,
    deepSeekReplies: [CHAT_REPLIES[chatKey], CLASSIFIER_REPLIES[classifierKey]],
  };
  const body = chatBody({
    practiceMode: mode,
    turns: FRAGMENT_TURNS,
    ...(mode === "game" ? { profileId: "practice_girl_004" } : {}),
    ...(mode === "standard" ? {} : {
      visiblePracticeThreadId: "thread-visible-1",
      temperatureScore: 40,
      familiarityScore: 10,
    }),
  });
  return {
    name: `chat／${mode}／style${
      styleOn ? "開" : "關"
    }／${threadKey}／分類器${classifierKey}／回覆${chatKey}`,
    options,
    body,
  };
}

function validHint(): string {
  return JSON.stringify({
    warmUp: "聽起來這杯咖啡有任務，是想醒腦還是想放空？",
    steady: "咖啡念頭收到，我先押妳今天比較想放空，猜錯妳糾正我。",
    coaching:
      "她主動說突然想喝咖啡；先用醒腦或放空二選一接她的狀態，再沿她的答案分享。",
  });
}

function validDebrief(): string {
  return JSON.stringify({
    summary: "你說今天忙到剛下班，她接著分享只想散步放空。",
    strengths: ["你先分享自己今天忙到剛下班，讓對話有具體情境。"],
    watchouts: ["下一步要接住她想散步放空，不要只停在自己的忙碌。"],
    suggestedLine: "下班後散步很療癒，妳最常走哪一段？",
    vibe: "中性",
    dateChance: "medium",
    dateChanceReason: "她回覆自己剛下班，只想散步放空，但還沒提時間或見面。",
    nextInviteMove: "先問她最常去哪裡散步，等她多分享再看是否出現邀約窗口。",
    hintAssessment: { verdict: "preserved", revisedEvidenceQuote: null },
  });
}

function sideCaseFor(
  mode: typeof MODES[number],
  styleOn: boolean,
  kind: "hint" | "debrief",
): EquivalenceCase {
  const env: Record<string, string> = {};
  if (styleOn) env[STYLE_ENV] = "true";
  const build = kind === "hint" ? hintBody : debriefBody;
  return {
    name: `${kind}／${mode}／style${styleOn ? "開" : "關"}`,
    options: {
      // 這一場必須已經開始（ai_count>0、charged），不然 hint／debrief 會在
      // 配額層就回 403 `practice_session_not_started`，整組案例變成在對拍
      // 錯誤回應（舊 golden 就是這樣空洞地「相同」）。
      ledger: ledger({
        practice_mode: mode,
        ai_count: 1,
        charged: true,
        temperature_score: 30,
        familiarity_score: 0,
      }),
      env,
      claudeReplies: [kind === "hint" ? validHint() : validDebrief()],
    },
    body: build({
      practiceMode: mode,
      turns: SIDE_TURNS,
      ...(mode === "game" ? { profileId: "practice_girl_004" } : {}),
    }),
  };
}

// ── Phase 2.8：Codex round-1（新項）U 的 coverage 缺口 ────────────────────
// 舊矩陣的 174 案全部落在同一組成功路徑上，Codex 逐條列出的缺口是：空貼文以外
// 沒有 moments、hint 沒有 prefetch、沒有 draw request handler、沒有錯誤路徑。
// 這裡補五個**形態不同**的案例（不是再乘一輪組合）——每一個都走到別的分支，
// 也各自產生不同的 Response／RPC／telemetry 形狀。
function extraCases(): EquivalenceCase[] {
  const momentsRpc = {
    list_practice_moment_posts: [{ data: MOMENT_ROWS }],
  };
  return [
    // 1–2：非空貼文（standard 走 ledger、beginner 走 thread，兩條讀取路徑都覆蓋）。
    {
      name: "chat／standard／貼文非空",
      options: {
        ledger: ledger({ practice_mode: "standard" }),
        thread: null,
        env: {},
        rpc: momentsRpc,
        deepSeekReplies: [CHAT_REPLIES["一般"], CLASSIFIER_VALID],
      },
      body: chatBody({ practiceMode: "standard", turns: FRAGMENT_TURNS }),
    },
    {
      name: "chat／beginner／貼文非空",
      options: {
        ledger: null,
        thread: threadRowFor("beginner", THREAD_RECENT_FACTS["有style狀態"]),
        env: {},
        rpc: momentsRpc,
        deepSeekReplies: [CHAT_REPLIES["一般"], CLASSIFIER_VALID],
      },
      body: chatBody({
        practiceMode: "beginner",
        turns: FRAGMENT_TURNS,
        visiblePracticeThreadId: "thread-visible-1",
        temperatureScore: 40,
        familiarityScore: 10,
      }),
    },
    // 3：hint prefetch（`prefetch:true` ＋ 旗標開）——claim／settle 的 RPC 形狀
    // 與一般 hint 不同，而且不扣配額。
    {
      name: "hint／beginner／prefetch",
      options: {
        ledger: ledger({
          practice_mode: "beginner",
          ai_count: 1,
          charged: true,
          temperature_score: 30,
          familiarity_score: 0,
        }),
        env: { PRACTICE_HINT_PREFETCH_ENABLED: "true" },
        claudeReplies: [validHint()],
      },
      body: hintBody({
        practiceMode: "beginner",
        requestId: "equiv-prefetch-1",
        prefetch: true,
        turns: SIDE_TURNS,
      }),
    },
    // 4：draw request handler（`mode:"draw_status"`）——完全不碰 chat／agency，
    // 但它跟 chat 共用同一個 handler 進入點與 telemetry 管線。
    {
      name: "draw_status",
      options: {
        ledger: null,
        env: {},
        // fake 對未設定的 RPC 一律回 `{data:true}`，那只會走到
        // `practice_draw_status_malformed` 的 500；給一列真的資料才會走成功路徑。
        rpc: {
          get_practice_draw_status: [{
            data: [{ free_allowance: 3, free_used: 1, free_remaining: 2 }],
          }],
        },
      },
      body: { mode: "draw_status" },
    },
    // 5：錯誤路徑——配額 ledger RPC 直接回錯，handler 必須映射成 4xx，
    // 一個 provider 呼叫都不能發生。
    {
      name: "錯誤路徑／配額 RPC 失敗→4xx",
      options: {
        ledger: null,
        env: {},
        rpc: {
          prepare_practice_subscription_usage: [{
            error: "PRACTICE_SUBSCRIPTION_NOT_FOUND",
          }],
        },
        deepSeekReplies: [CHAT_REPLIES["一般"], CLASSIFIER_VALID],
      },
      body: chatBody({
        practiceMode: "beginner",
        turns: FRAGMENT_TURNS,
        visiblePracticeThreadId: "thread-visible-1",
        temperatureScore: 40,
        familiarityScore: 10,
      }),
    },
  ];
}

/**
 * Phase 4.1：旗標 `true` 時可觀測面會改變的 hint／debrief 案例。清單是白名單
 * ——名單外的 side case（例如 hint／standard 的 403）必須逐位元組不變。
 */
const PHASE41_CHANGED_SIDE_CASES: readonly string[] = [
  "hint／beginner／style關",
  "hint／beginner／style開",
  "hint／game／style關",
  "hint／game／style開",
  "hint／beginner／prefetch",
  "debrief／standard／style關",
  "debrief／standard／style開",
  "debrief／beginner／style關",
  "debrief／beginner／style開",
  "debrief／game／style關",
  "debrief／game／style開",
];

function equivalenceCases(): EquivalenceCase[] {
  const cases: EquivalenceCase[] = [];
  for (const mode of MODES) {
    for (const styleOn of [false, true]) {
      for (const threadKey of Object.keys(THREAD_RECENT_FACTS)) {
        for (const classifierKey of Object.keys(CLASSIFIER_REPLIES)) {
          for (const chatKey of Object.keys(CHAT_REPLIES)) {
            cases.push(
              chatCaseFor(mode, styleOn, threadKey, classifierKey, chatKey),
            );
          }
        }
      }
      for (const kind of ["hint", "debrief"] as const) {
        cases.push(sideCaseFor(mode, styleOn, kind));
      }
    }
  }
  cases.push(...extraCases());
  return cases;
}

interface ObservableDigest {
  readonly messages: string;
  readonly response: string;
  readonly rpc: string;
  readonly telemetry: string;
}

/** golden 表存成一行 `messages|response|rpc|telemetry`；比對時拆開才看得出哪一面漂。 */
function parseGolden(name: string): ObservableDigest {
  const raw = AGENCY_FLAG_OFF_GOLDEN.get(name);
  assert(raw, `golden 缺少案例：${name}`);
  const [messages, response, rpc, telemetry] = raw.split("|");
  return { messages, response, rpc, telemetry };
}

/**
 * 跑一個 case，回傳四個可觀測面各自的雜湊。
 *
 * `console.log`／`console.warn` 在 handler 回傳後才會被背景工作（ai_logs
 * 寫入等）補印，所以攔截視窗要一路撐到 `waitUntil` 的 promise 全部落地，
 * 不然下一個 case 會撿到上一個 case 的尾巴。
 */
/**
 * 側通道：`observableDigest` 把這一輪 telemetry 出現過的牆鐘欄位名收進來。
 * digest 只比欄位**形狀**（值被 scrub 成 0），所以「這些 key 真的存在」必須
 * 另外斷言，不然「一個 duration 欄位都沒印」跟「印了但值不同」在 golden 上
 * 長得一模一樣（Codex round-1 新項 U）。
 */
interface RunProbe {
  durationKeys: string[];
  /** Codex R1 P3：telemetry 原始行（要逐行比 key 集合，不只比 digest）。 */
  lines?: string[];
}

const DURATION_KEY_RE = /"(\w*(?:Duration|Latency|Elapsed|Wait))Ms":/g;

async function observableDigest(
  c: EquivalenceCase,
  agencyEnv: string | undefined,
  user?: { id: string; email?: string | null },
  probe?: RunProbe,
  routingEnv?: string,
): Promise<ObservableDigest> {
  const fake = makeFake({
    ...c.options,
    ...(user ? { user } : {}),
    // telemetry 有 `attemptDurationMs`／`totalDurationMs` 這種牆鐘欄位；
    // 不釘住單調時鐘的話 digest 每跑一次都不一樣。固定成常數 0＝所有 duration
    // 都是 0，deadline 也永遠不會到。
    monotonicNowValues: [0],
    env: {
      ...c.options.env,
      ...(agencyEnv === undefined ? {} : { [AGENCY_ENV]: agencyEnv }),
      ...(routingEnv === undefined ? {} : { [ROUTING_ENV]: routingEnv }),
    },
  });
  const lines: string[] = [];
  const originalLog = console.log;
  const originalWarn = console.warn;
  const capture = (...args: unknown[]) => {
    lines.push(
      args.map((a) => typeof a === "string" ? a : String(a)).join(" "),
    );
  };
  let response: Response;
  try {
    console.log = capture;
    console.warn = capture;
    response = await fake.handler(makeRequest(c.body));
    await Promise.allSettled(fake.state.backgroundTasks);
  } finally {
    console.log = originalLog;
    console.warn = originalWarn;
  }
  const headers = [...response.headers.entries()].sort().map(([k, v]) =>
    `${k}:${v}`
  ).join("\n");
  const bodyBytes = new Uint8Array(await response.arrayBuffer());
  // Codex round-1（新項）U：`statusText` 也進 digest。handler 一路都用
  // `new Response(body, { status })`，Deno 不會自動補預設字串，所以現況每一個
  // 案例的 statusText 都是空字串——空字串一律不寫進 head，既有 golden 因此
  // **逐位元組不變**，而任何一天有人開始送自訂 statusText 就會被抓到。
  const statusText = response.statusText === ""
    ? ""
    : ` ${response.statusText}`;
  const head = new TextEncoder().encode(
    `${response.status}${statusText}\n${headers}\n\n`,
  );
  const raw = new Uint8Array(head.length + bodyBytes.length);
  raw.set(head, 0);
  raw.set(bodyBytes, head.length);
  const text = lines.join("\n");
  if (probe) {
    probe.lines = lines.slice();
    probe.durationKeys = [
      ...new Set([...text.matchAll(DURATION_KEY_RE)].map((m) => m[1])),
    ].sort();
  }
  return {
    messages: await digest(
      JSON.stringify([
        fake.state.deepSeekCalls.map((call) => call.messages),
        fake.state.claudeCalls.map((call) => call.messages),
      ]),
    ),
    response: await digest(raw),
    rpc: await digest(
      JSON.stringify(
        fake.state.rpcCalls.map((call) => ({
          fn: call.fn,
          params: call.params,
        })),
      ),
    ),
    telemetry: await digest(scrubWallClock(text)),
  };
}

/**
 * telemetry 裡的牆鐘欄位（`attemptDurationMs`／`totalDurationMs`…）每跑一次都
 * 不一樣，而且不是全部都走得到注入的 `monotonicNow`。把**值**歸零、**key 留著**
 * ——多一個或少一個 duration 欄位仍然會被 golden 抓到，只有數字本身不比。
 */
function scrubWallClock(text: string): string {
  return text.replace(
    /"(\w*(?:Duration|Latency|Elapsed|Wait))Ms":\s*-?\d+(?:\.\d+)?/g,
    '"$1Ms":0',
  );
}

function digestLine(d: ObservableDigest): string {
  return [d.messages, d.response, d.rpc, d.telemetry].join("|");
}

// ── golden（在 7f1d6d6c 上由本檔 printer 印出；見檔頭程序）──────────────
const AGENCY_FLAG_OFF_GOLDEN = new Map<string, string>([
  [
    "chat／standard／style關／無thread／分類器合法／回覆一般",
    "977d447453b6e105|444e4e27dafce2e0|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／無thread／分類器合法／回覆重複同一個詞",
    "977d447453b6e105|ac22540ca79bb4f1|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／無thread／分類器合法／回覆括號旁白",
    "977d447453b6e105|89b8cbf201db1169|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／無thread／分類器未知心情／回覆一般",
    "977d447453b6e105|444e4e27dafce2e0|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／無thread／分類器未知心情／回覆重複同一個詞",
    "977d447453b6e105|ac22540ca79bb4f1|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／無thread／分類器未知心情／回覆括號旁白",
    "977d447453b6e105|89b8cbf201db1169|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／無thread／分類器非JSON／回覆一般",
    "977d447453b6e105|444e4e27dafce2e0|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／無thread／分類器非JSON／回覆重複同一個詞",
    "977d447453b6e105|ac22540ca79bb4f1|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／無thread／分類器非JSON／回覆括號旁白",
    "977d447453b6e105|89b8cbf201db1169|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有style狀態／分類器合法／回覆一般",
    "977d447453b6e105|444e4e27dafce2e0|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有style狀態／分類器合法／回覆重複同一個詞",
    "977d447453b6e105|ac22540ca79bb4f1|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有style狀態／分類器合法／回覆括號旁白",
    "977d447453b6e105|89b8cbf201db1169|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有style狀態／分類器未知心情／回覆一般",
    "977d447453b6e105|444e4e27dafce2e0|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有style狀態／分類器未知心情／回覆重複同一個詞",
    "977d447453b6e105|ac22540ca79bb4f1|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有style狀態／分類器未知心情／回覆括號旁白",
    "977d447453b6e105|89b8cbf201db1169|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有style狀態／分類器非JSON／回覆一般",
    "977d447453b6e105|444e4e27dafce2e0|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有style狀態／分類器非JSON／回覆重複同一個詞",
    "977d447453b6e105|ac22540ca79bb4f1|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有style狀態／分類器非JSON／回覆括號旁白",
    "977d447453b6e105|89b8cbf201db1169|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有agency與未知key／分類器合法／回覆一般",
    "977d447453b6e105|444e4e27dafce2e0|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有agency與未知key／分類器合法／回覆重複同一個詞",
    "977d447453b6e105|ac22540ca79bb4f1|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有agency與未知key／分類器合法／回覆括號旁白",
    "977d447453b6e105|89b8cbf201db1169|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有agency與未知key／分類器未知心情／回覆一般",
    "977d447453b6e105|444e4e27dafce2e0|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有agency與未知key／分類器未知心情／回覆重複同一個詞",
    "977d447453b6e105|ac22540ca79bb4f1|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有agency與未知key／分類器未知心情／回覆括號旁白",
    "977d447453b6e105|89b8cbf201db1169|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有agency與未知key／分類器非JSON／回覆一般",
    "977d447453b6e105|444e4e27dafce2e0|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有agency與未知key／分類器非JSON／回覆重複同一個詞",
    "977d447453b6e105|ac22540ca79bb4f1|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／standard／style關／有agency與未知key／分類器非JSON／回覆括號旁白",
    "977d447453b6e105|89b8cbf201db1169|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "hint／standard／style關",
    "643d5437104296e2|c9ee7a8a99515434|ca158647bff92ea8|e3b0c44298fc1c14",
  ],
  [
    "debrief／standard／style關",
    "d4701d05fa547f11|4d813cf67931a647|e4208f69770442ed|095d922cbcfcb8a0",
  ],
  [
    "chat／standard／style開／無thread／分類器合法／回覆一般",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／無thread／分類器合法／回覆重複同一個詞",
    "9e701c59644cbd42|ac22540ca79bb4f1|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／無thread／分類器合法／回覆括號旁白",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|96f5d87abc539bea",
  ],
  [
    "chat／standard／style開／無thread／分類器未知心情／回覆一般",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／無thread／分類器未知心情／回覆重複同一個詞",
    "9e701c59644cbd42|ac22540ca79bb4f1|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／無thread／分類器未知心情／回覆括號旁白",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|96f5d87abc539bea",
  ],
  [
    "chat／standard／style開／無thread／分類器非JSON／回覆一般",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／無thread／分類器非JSON／回覆重複同一個詞",
    "9e701c59644cbd42|ac22540ca79bb4f1|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／無thread／分類器非JSON／回覆括號旁白",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|96f5d87abc539bea",
  ],
  [
    "chat／standard／style開／有style狀態／分類器合法／回覆一般",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／有style狀態／分類器合法／回覆重複同一個詞",
    "9e701c59644cbd42|ac22540ca79bb4f1|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／有style狀態／分類器合法／回覆括號旁白",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|96f5d87abc539bea",
  ],
  [
    "chat／standard／style開／有style狀態／分類器未知心情／回覆一般",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／有style狀態／分類器未知心情／回覆重複同一個詞",
    "9e701c59644cbd42|ac22540ca79bb4f1|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／有style狀態／分類器未知心情／回覆括號旁白",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|96f5d87abc539bea",
  ],
  [
    "chat／standard／style開／有style狀態／分類器非JSON／回覆一般",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／有style狀態／分類器非JSON／回覆重複同一個詞",
    "9e701c59644cbd42|ac22540ca79bb4f1|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／有style狀態／分類器非JSON／回覆括號旁白",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|96f5d87abc539bea",
  ],
  [
    "chat／standard／style開／有agency與未知key／分類器合法／回覆一般",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／有agency與未知key／分類器合法／回覆重複同一個詞",
    "9e701c59644cbd42|ac22540ca79bb4f1|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／有agency與未知key／分類器合法／回覆括號旁白",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|96f5d87abc539bea",
  ],
  [
    "chat／standard／style開／有agency與未知key／分類器未知心情／回覆一般",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／有agency與未知key／分類器未知心情／回覆重複同一個詞",
    "9e701c59644cbd42|ac22540ca79bb4f1|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／有agency與未知key／分類器未知心情／回覆括號旁白",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|96f5d87abc539bea",
  ],
  [
    "chat／standard／style開／有agency與未知key／分類器非JSON／回覆一般",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／有agency與未知key／分類器非JSON／回覆重複同一個詞",
    "9e701c59644cbd42|ac22540ca79bb4f1|942147acce9b12da|0b2a7749d177823a",
  ],
  [
    "chat／standard／style開／有agency與未知key／分類器非JSON／回覆括號旁白",
    "9e701c59644cbd42|444e4e27dafce2e0|942147acce9b12da|96f5d87abc539bea",
  ],
  [
    "hint／standard／style開",
    "643d5437104296e2|c9ee7a8a99515434|ca158647bff92ea8|e3b0c44298fc1c14",
  ],
  [
    "debrief／standard／style開",
    "5e090d4d530ba291|4d813cf67931a647|e4208f69770442ed|6eb96f9a61ff2471",
  ],
  [
    "chat／beginner／style關／無thread／分類器合法／回覆一般",
    "546baee1c4d4dc32|40607d6481b9863d|09c051cca196ddf7|695119c35918587a",
  ],
  [
    "chat／beginner／style關／無thread／分類器合法／回覆重複同一個詞",
    "61f39f5eb058d597|cc1a6ff91c109fc7|09c051cca196ddf7|695119c35918587a",
  ],
  [
    "chat／beginner／style關／無thread／分類器合法／回覆括號旁白",
    "839967b9b4cec5e5|43a4c47dd5092a4e|09c051cca196ddf7|695119c35918587a",
  ],
  [
    "chat／beginner／style關／無thread／分類器未知心情／回覆一般",
    "546baee1c4d4dc32|771738033fc40fc9|f718717ccd430dbb|f2786a86c1bd1326",
  ],
  [
    "chat／beginner／style關／無thread／分類器未知心情／回覆重複同一個詞",
    "61f39f5eb058d597|c740fbbcf3075a76|f718717ccd430dbb|f2786a86c1bd1326",
  ],
  [
    "chat／beginner／style關／無thread／分類器未知心情／回覆括號旁白",
    "839967b9b4cec5e5|8d3b95566cc02221|f718717ccd430dbb|f2786a86c1bd1326",
  ],
  [
    "chat／beginner／style關／無thread／分類器非JSON／回覆一般",
    "546baee1c4d4dc32|771738033fc40fc9|f718717ccd430dbb|ee253c0a85171108",
  ],
  [
    "chat／beginner／style關／無thread／分類器非JSON／回覆重複同一個詞",
    "61f39f5eb058d597|c740fbbcf3075a76|f718717ccd430dbb|ee253c0a85171108",
  ],
  [
    "chat／beginner／style關／無thread／分類器非JSON／回覆括號旁白",
    "839967b9b4cec5e5|8d3b95566cc02221|f718717ccd430dbb|ee253c0a85171108",
  ],
  [
    "chat／beginner／style關／有style狀態／分類器合法／回覆一般",
    "546baee1c4d4dc32|40607d6481b9863d|dcbcb65fd81efe3e|ed466986989d2834",
  ],
  [
    "chat／beginner／style關／有style狀態／分類器合法／回覆重複同一個詞",
    "61f39f5eb058d597|cc1a6ff91c109fc7|dcbcb65fd81efe3e|ed466986989d2834",
  ],
  [
    "chat／beginner／style關／有style狀態／分類器合法／回覆括號旁白",
    "839967b9b4cec5e5|43a4c47dd5092a4e|dcbcb65fd81efe3e|ed466986989d2834",
  ],
  [
    "chat／beginner／style關／有style狀態／分類器未知心情／回覆一般",
    "546baee1c4d4dc32|771738033fc40fc9|c47d6bd61d2a942d|ed045785e2adb7fe",
  ],
  [
    "chat／beginner／style關／有style狀態／分類器未知心情／回覆重複同一個詞",
    "61f39f5eb058d597|c740fbbcf3075a76|c47d6bd61d2a942d|ed045785e2adb7fe",
  ],
  [
    "chat／beginner／style關／有style狀態／分類器未知心情／回覆括號旁白",
    "839967b9b4cec5e5|8d3b95566cc02221|c47d6bd61d2a942d|ed045785e2adb7fe",
  ],
  [
    "chat／beginner／style關／有style狀態／分類器非JSON／回覆一般",
    "546baee1c4d4dc32|771738033fc40fc9|c47d6bd61d2a942d|3b4ebe06d1eb1d69",
  ],
  [
    "chat／beginner／style關／有style狀態／分類器非JSON／回覆重複同一個詞",
    "61f39f5eb058d597|c740fbbcf3075a76|c47d6bd61d2a942d|3b4ebe06d1eb1d69",
  ],
  [
    "chat／beginner／style關／有style狀態／分類器非JSON／回覆括號旁白",
    "839967b9b4cec5e5|8d3b95566cc02221|c47d6bd61d2a942d|3b4ebe06d1eb1d69",
  ],
  [
    "chat／beginner／style關／有agency與未知key／分類器合法／回覆一般",
    "546baee1c4d4dc32|40607d6481b9863d|09c051cca196ddf7|ed466986989d2834",
  ],
  [
    "chat／beginner／style關／有agency與未知key／分類器合法／回覆重複同一個詞",
    "61f39f5eb058d597|cc1a6ff91c109fc7|09c051cca196ddf7|ed466986989d2834",
  ],
  [
    "chat／beginner／style關／有agency與未知key／分類器合法／回覆括號旁白",
    "839967b9b4cec5e5|43a4c47dd5092a4e|09c051cca196ddf7|ed466986989d2834",
  ],
  [
    "chat／beginner／style關／有agency與未知key／分類器未知心情／回覆一般",
    "546baee1c4d4dc32|771738033fc40fc9|f718717ccd430dbb|ed045785e2adb7fe",
  ],
  [
    "chat／beginner／style關／有agency與未知key／分類器未知心情／回覆重複同一個詞",
    "61f39f5eb058d597|c740fbbcf3075a76|f718717ccd430dbb|ed045785e2adb7fe",
  ],
  [
    "chat／beginner／style關／有agency與未知key／分類器未知心情／回覆括號旁白",
    "839967b9b4cec5e5|8d3b95566cc02221|f718717ccd430dbb|ed045785e2adb7fe",
  ],
  [
    "chat／beginner／style關／有agency與未知key／分類器非JSON／回覆一般",
    "546baee1c4d4dc32|771738033fc40fc9|f718717ccd430dbb|3b4ebe06d1eb1d69",
  ],
  [
    "chat／beginner／style關／有agency與未知key／分類器非JSON／回覆重複同一個詞",
    "61f39f5eb058d597|c740fbbcf3075a76|f718717ccd430dbb|3b4ebe06d1eb1d69",
  ],
  [
    "chat／beginner／style關／有agency與未知key／分類器非JSON／回覆括號旁白",
    "839967b9b4cec5e5|8d3b95566cc02221|f718717ccd430dbb|3b4ebe06d1eb1d69",
  ],
  [
    "hint／beginner／style關",
    "8098d9e5e50d12f1|d964e260a498d58b|af3645bfecbe6a8f|13a3f26fa8f3a7ea",
  ],
  [
    "debrief／beginner／style關",
    "b0931594d7294bf7|4d813cf67931a647|d4c5e22bdcc3d87f|5347e22f68380f8f",
  ],
  [
    "chat／beginner／style開／無thread／分類器合法／回覆一般",
    "abb65d1f2db14489|40607d6481b9863d|34ea2bc77d7e7356|cb280360a0e27917",
  ],
  [
    "chat／beginner／style開／無thread／分類器合法／回覆重複同一個詞",
    "f1394b53f5439903|cc1a6ff91c109fc7|34ea2bc77d7e7356|cb280360a0e27917",
  ],
  [
    "chat／beginner／style開／無thread／分類器合法／回覆括號旁白",
    "abb65d1f2db14489|40607d6481b9863d|34ea2bc77d7e7356|f624b5de3cf913a9",
  ],
  [
    "chat／beginner／style開／無thread／分類器未知心情／回覆一般",
    "abb65d1f2db14489|771738033fc40fc9|44ef31491b15f391|0bbc2f0a07dc88ae",
  ],
  [
    "chat／beginner／style開／無thread／分類器未知心情／回覆重複同一個詞",
    "f1394b53f5439903|c740fbbcf3075a76|44ef31491b15f391|0bbc2f0a07dc88ae",
  ],
  [
    "chat／beginner／style開／無thread／分類器未知心情／回覆括號旁白",
    "abb65d1f2db14489|771738033fc40fc9|44ef31491b15f391|b66af858c571ae3e",
  ],
  [
    "chat／beginner／style開／無thread／分類器非JSON／回覆一般",
    "abb65d1f2db14489|771738033fc40fc9|44ef31491b15f391|86d13c1c9bc78084",
  ],
  [
    "chat／beginner／style開／無thread／分類器非JSON／回覆重複同一個詞",
    "f1394b53f5439903|c740fbbcf3075a76|44ef31491b15f391|86d13c1c9bc78084",
  ],
  [
    "chat／beginner／style開／無thread／分類器非JSON／回覆括號旁白",
    "abb65d1f2db14489|771738033fc40fc9|44ef31491b15f391|e23acbd1cabc2041",
  ],
  [
    "chat／beginner／style開／有style狀態／分類器合法／回覆一般",
    "abb65d1f2db14489|40607d6481b9863d|377707428ee52024|28d803cbf9d54f7e",
  ],
  [
    "chat／beginner／style開／有style狀態／分類器合法／回覆重複同一個詞",
    "f1394b53f5439903|cc1a6ff91c109fc7|377707428ee52024|28d803cbf9d54f7e",
  ],
  [
    "chat／beginner／style開／有style狀態／分類器合法／回覆括號旁白",
    "abb65d1f2db14489|40607d6481b9863d|377707428ee52024|6e689fb98ec5e093",
  ],
  [
    "chat／beginner／style開／有style狀態／分類器未知心情／回覆一般",
    "abb65d1f2db14489|771738033fc40fc9|1a257feadb5d897d|f83f80e0577fbb18",
  ],
  [
    "chat／beginner／style開／有style狀態／分類器未知心情／回覆重複同一個詞",
    "f1394b53f5439903|c740fbbcf3075a76|1a257feadb5d897d|f83f80e0577fbb18",
  ],
  [
    "chat／beginner／style開／有style狀態／分類器未知心情／回覆括號旁白",
    "abb65d1f2db14489|771738033fc40fc9|1a257feadb5d897d|f33fe36826c4fcb1",
  ],
  [
    "chat／beginner／style開／有style狀態／分類器非JSON／回覆一般",
    "abb65d1f2db14489|771738033fc40fc9|1a257feadb5d897d|9f6a5cfcc2232b9b",
  ],
  [
    "chat／beginner／style開／有style狀態／分類器非JSON／回覆重複同一個詞",
    "f1394b53f5439903|c740fbbcf3075a76|1a257feadb5d897d|9f6a5cfcc2232b9b",
  ],
  [
    "chat／beginner／style開／有style狀態／分類器非JSON／回覆括號旁白",
    "abb65d1f2db14489|771738033fc40fc9|1a257feadb5d897d|1b63002188813343",
  ],
  [
    "chat／beginner／style開／有agency與未知key／分類器合法／回覆一般",
    "abb65d1f2db14489|40607d6481b9863d|34ea2bc77d7e7356|28d803cbf9d54f7e",
  ],
  [
    "chat／beginner／style開／有agency與未知key／分類器合法／回覆重複同一個詞",
    "f1394b53f5439903|cc1a6ff91c109fc7|34ea2bc77d7e7356|28d803cbf9d54f7e",
  ],
  [
    "chat／beginner／style開／有agency與未知key／分類器合法／回覆括號旁白",
    "abb65d1f2db14489|40607d6481b9863d|34ea2bc77d7e7356|6e689fb98ec5e093",
  ],
  [
    "chat／beginner／style開／有agency與未知key／分類器未知心情／回覆一般",
    "abb65d1f2db14489|771738033fc40fc9|44ef31491b15f391|f83f80e0577fbb18",
  ],
  [
    "chat／beginner／style開／有agency與未知key／分類器未知心情／回覆重複同一個詞",
    "f1394b53f5439903|c740fbbcf3075a76|44ef31491b15f391|f83f80e0577fbb18",
  ],
  [
    "chat／beginner／style開／有agency與未知key／分類器未知心情／回覆括號旁白",
    "abb65d1f2db14489|771738033fc40fc9|44ef31491b15f391|f33fe36826c4fcb1",
  ],
  [
    "chat／beginner／style開／有agency與未知key／分類器非JSON／回覆一般",
    "abb65d1f2db14489|771738033fc40fc9|44ef31491b15f391|9f6a5cfcc2232b9b",
  ],
  [
    "chat／beginner／style開／有agency與未知key／分類器非JSON／回覆重複同一個詞",
    "f1394b53f5439903|c740fbbcf3075a76|44ef31491b15f391|9f6a5cfcc2232b9b",
  ],
  [
    "chat／beginner／style開／有agency與未知key／分類器非JSON／回覆括號旁白",
    "abb65d1f2db14489|771738033fc40fc9|44ef31491b15f391|1b63002188813343",
  ],
  [
    "hint／beginner／style開",
    "f26b5e7b78a96c7a|d964e260a498d58b|af3645bfecbe6a8f|a135331d4653b69e",
  ],
  [
    "debrief／beginner／style開",
    "dbd7713e6e5cb241|4d813cf67931a647|d4c5e22bdcc3d87f|d7a47ab509c13b12",
  ],
  [
    "chat／game／style關／無thread／分類器合法／回覆一般",
    "5f4720d7ee3bddbf|71c3ea675347f481|d7ea9dd154dbe86f|dff5191374fbc5e2",
  ],
  [
    "chat／game／style關／無thread／分類器合法／回覆重複同一個詞",
    "5695348ab64da966|453a8fccf0d76e60|d7ea9dd154dbe86f|dff5191374fbc5e2",
  ],
  [
    "chat／game／style關／無thread／分類器合法／回覆括號旁白",
    "8ab38465cfbce5dc|40b3b798c6599ee8|d7ea9dd154dbe86f|dff5191374fbc5e2",
  ],
  [
    "chat／game／style關／無thread／分類器未知心情／回覆一般",
    "5f4720d7ee3bddbf|771738033fc40fc9|6aa4900cc0dc3d45|1e10de695c881a09",
  ],
  [
    "chat／game／style關／無thread／分類器未知心情／回覆重複同一個詞",
    "5695348ab64da966|c740fbbcf3075a76|6aa4900cc0dc3d45|1e10de695c881a09",
  ],
  [
    "chat／game／style關／無thread／分類器未知心情／回覆括號旁白",
    "8ab38465cfbce5dc|8d3b95566cc02221|6aa4900cc0dc3d45|1e10de695c881a09",
  ],
  [
    "chat／game／style關／無thread／分類器非JSON／回覆一般",
    "5f4720d7ee3bddbf|771738033fc40fc9|6aa4900cc0dc3d45|bb7183fd9729780c",
  ],
  [
    "chat／game／style關／無thread／分類器非JSON／回覆重複同一個詞",
    "5695348ab64da966|c740fbbcf3075a76|6aa4900cc0dc3d45|bb7183fd9729780c",
  ],
  [
    "chat／game／style關／無thread／分類器非JSON／回覆括號旁白",
    "8ab38465cfbce5dc|8d3b95566cc02221|6aa4900cc0dc3d45|bb7183fd9729780c",
  ],
  [
    "chat／game／style關／有style狀態／分類器合法／回覆一般",
    "5f4720d7ee3bddbf|71c3ea675347f481|473525537c0f2426|f074631265286d89",
  ],
  [
    "chat／game／style關／有style狀態／分類器合法／回覆重複同一個詞",
    "5695348ab64da966|453a8fccf0d76e60|473525537c0f2426|f074631265286d89",
  ],
  [
    "chat／game／style關／有style狀態／分類器合法／回覆括號旁白",
    "8ab38465cfbce5dc|40b3b798c6599ee8|473525537c0f2426|f074631265286d89",
  ],
  [
    "chat／game／style關／有style狀態／分類器未知心情／回覆一般",
    "5f4720d7ee3bddbf|771738033fc40fc9|812445e4061ea2f1|fe2c8804af37b86a",
  ],
  [
    "chat／game／style關／有style狀態／分類器未知心情／回覆重複同一個詞",
    "5695348ab64da966|c740fbbcf3075a76|812445e4061ea2f1|fe2c8804af37b86a",
  ],
  [
    "chat／game／style關／有style狀態／分類器未知心情／回覆括號旁白",
    "8ab38465cfbce5dc|8d3b95566cc02221|812445e4061ea2f1|fe2c8804af37b86a",
  ],
  [
    "chat／game／style關／有style狀態／分類器非JSON／回覆一般",
    "5f4720d7ee3bddbf|771738033fc40fc9|812445e4061ea2f1|68912e73b776d029",
  ],
  [
    "chat／game／style關／有style狀態／分類器非JSON／回覆重複同一個詞",
    "5695348ab64da966|c740fbbcf3075a76|812445e4061ea2f1|68912e73b776d029",
  ],
  [
    "chat／game／style關／有style狀態／分類器非JSON／回覆括號旁白",
    "8ab38465cfbce5dc|8d3b95566cc02221|812445e4061ea2f1|68912e73b776d029",
  ],
  [
    "chat／game／style關／有agency與未知key／分類器合法／回覆一般",
    "5f4720d7ee3bddbf|71c3ea675347f481|d7ea9dd154dbe86f|f074631265286d89",
  ],
  [
    "chat／game／style關／有agency與未知key／分類器合法／回覆重複同一個詞",
    "5695348ab64da966|453a8fccf0d76e60|d7ea9dd154dbe86f|f074631265286d89",
  ],
  [
    "chat／game／style關／有agency與未知key／分類器合法／回覆括號旁白",
    "8ab38465cfbce5dc|40b3b798c6599ee8|d7ea9dd154dbe86f|f074631265286d89",
  ],
  [
    "chat／game／style關／有agency與未知key／分類器未知心情／回覆一般",
    "5f4720d7ee3bddbf|771738033fc40fc9|6aa4900cc0dc3d45|fe2c8804af37b86a",
  ],
  [
    "chat／game／style關／有agency與未知key／分類器未知心情／回覆重複同一個詞",
    "5695348ab64da966|c740fbbcf3075a76|6aa4900cc0dc3d45|fe2c8804af37b86a",
  ],
  [
    "chat／game／style關／有agency與未知key／分類器未知心情／回覆括號旁白",
    "8ab38465cfbce5dc|8d3b95566cc02221|6aa4900cc0dc3d45|fe2c8804af37b86a",
  ],
  [
    "chat／game／style關／有agency與未知key／分類器非JSON／回覆一般",
    "5f4720d7ee3bddbf|771738033fc40fc9|6aa4900cc0dc3d45|68912e73b776d029",
  ],
  [
    "chat／game／style關／有agency與未知key／分類器非JSON／回覆重複同一個詞",
    "5695348ab64da966|c740fbbcf3075a76|6aa4900cc0dc3d45|68912e73b776d029",
  ],
  [
    "chat／game／style關／有agency與未知key／分類器非JSON／回覆括號旁白",
    "8ab38465cfbce5dc|8d3b95566cc02221|6aa4900cc0dc3d45|68912e73b776d029",
  ],
  [
    "hint／game／style關",
    "94594a449edf11b2|6e3fab2b0dd43d2d|af3645bfecbe6a8f|5b921f0e04d43bfb",
  ],
  [
    "debrief／game／style關",
    "4e362d22b99f650e|2f97a095d1d75e7a|b7fe848d8efa0772|6eeab4f5c503597d",
  ],
  [
    "chat／game／style開／無thread／分類器合法／回覆一般",
    "accd3778119664c2|71c3ea675347f481|c7d46592c69c7bda|171f3bc79866ac3b",
  ],
  [
    "chat／game／style開／無thread／分類器合法／回覆重複同一個詞",
    "73da416d8acf59ac|453a8fccf0d76e60|c7d46592c69c7bda|171f3bc79866ac3b",
  ],
  [
    "chat／game／style開／無thread／分類器合法／回覆括號旁白",
    "accd3778119664c2|71c3ea675347f481|c7d46592c69c7bda|e5e8fe1066fcb14d",
  ],
  [
    "chat／game／style開／無thread／分類器未知心情／回覆一般",
    "accd3778119664c2|771738033fc40fc9|5fd5c4dc4dbcc960|1b3484b28f126fd2",
  ],
  [
    "chat／game／style開／無thread／分類器未知心情／回覆重複同一個詞",
    "73da416d8acf59ac|c740fbbcf3075a76|5fd5c4dc4dbcc960|1b3484b28f126fd2",
  ],
  [
    "chat／game／style開／無thread／分類器未知心情／回覆括號旁白",
    "accd3778119664c2|771738033fc40fc9|5fd5c4dc4dbcc960|627306de72613414",
  ],
  [
    "chat／game／style開／無thread／分類器非JSON／回覆一般",
    "accd3778119664c2|771738033fc40fc9|5fd5c4dc4dbcc960|731034ddb037c175",
  ],
  [
    "chat／game／style開／無thread／分類器非JSON／回覆重複同一個詞",
    "73da416d8acf59ac|c740fbbcf3075a76|5fd5c4dc4dbcc960|731034ddb037c175",
  ],
  [
    "chat／game／style開／無thread／分類器非JSON／回覆括號旁白",
    "accd3778119664c2|771738033fc40fc9|5fd5c4dc4dbcc960|26ac51b0fff2fe45",
  ],
  [
    "chat／game／style開／有style狀態／分類器合法／回覆一般",
    "accd3778119664c2|71c3ea675347f481|3c741abd428d85ef|1154425ec523b806",
  ],
  [
    "chat／game／style開／有style狀態／分類器合法／回覆重複同一個詞",
    "73da416d8acf59ac|453a8fccf0d76e60|3c741abd428d85ef|1154425ec523b806",
  ],
  [
    "chat／game／style開／有style狀態／分類器合法／回覆括號旁白",
    "accd3778119664c2|71c3ea675347f481|3c741abd428d85ef|401708ecf4c096dc",
  ],
  [
    "chat／game／style開／有style狀態／分類器未知心情／回覆一般",
    "accd3778119664c2|771738033fc40fc9|3252807dc04fd05b|ee6470462c0a5faa",
  ],
  [
    "chat／game／style開／有style狀態／分類器未知心情／回覆重複同一個詞",
    "73da416d8acf59ac|c740fbbcf3075a76|3252807dc04fd05b|ee6470462c0a5faa",
  ],
  [
    "chat／game／style開／有style狀態／分類器未知心情／回覆括號旁白",
    "accd3778119664c2|771738033fc40fc9|3252807dc04fd05b|811b00f85af95f8e",
  ],
  [
    "chat／game／style開／有style狀態／分類器非JSON／回覆一般",
    "accd3778119664c2|771738033fc40fc9|3252807dc04fd05b|59ae7becdd79f2ab",
  ],
  [
    "chat／game／style開／有style狀態／分類器非JSON／回覆重複同一個詞",
    "73da416d8acf59ac|c740fbbcf3075a76|3252807dc04fd05b|59ae7becdd79f2ab",
  ],
  [
    "chat／game／style開／有style狀態／分類器非JSON／回覆括號旁白",
    "accd3778119664c2|771738033fc40fc9|3252807dc04fd05b|bec45d995531e0c3",
  ],
  [
    "chat／game／style開／有agency與未知key／分類器合法／回覆一般",
    "accd3778119664c2|71c3ea675347f481|c7d46592c69c7bda|1154425ec523b806",
  ],
  [
    "chat／game／style開／有agency與未知key／分類器合法／回覆重複同一個詞",
    "73da416d8acf59ac|453a8fccf0d76e60|c7d46592c69c7bda|1154425ec523b806",
  ],
  [
    "chat／game／style開／有agency與未知key／分類器合法／回覆括號旁白",
    "accd3778119664c2|71c3ea675347f481|c7d46592c69c7bda|401708ecf4c096dc",
  ],
  [
    "chat／game／style開／有agency與未知key／分類器未知心情／回覆一般",
    "accd3778119664c2|771738033fc40fc9|5fd5c4dc4dbcc960|ee6470462c0a5faa",
  ],
  [
    "chat／game／style開／有agency與未知key／分類器未知心情／回覆重複同一個詞",
    "73da416d8acf59ac|c740fbbcf3075a76|5fd5c4dc4dbcc960|ee6470462c0a5faa",
  ],
  [
    "chat／game／style開／有agency與未知key／分類器未知心情／回覆括號旁白",
    "accd3778119664c2|771738033fc40fc9|5fd5c4dc4dbcc960|811b00f85af95f8e",
  ],
  [
    "chat／game／style開／有agency與未知key／分類器非JSON／回覆一般",
    "accd3778119664c2|771738033fc40fc9|5fd5c4dc4dbcc960|59ae7becdd79f2ab",
  ],
  [
    "chat／game／style開／有agency與未知key／分類器非JSON／回覆重複同一個詞",
    "73da416d8acf59ac|c740fbbcf3075a76|5fd5c4dc4dbcc960|59ae7becdd79f2ab",
  ],
  [
    "chat／game／style開／有agency與未知key／分類器非JSON／回覆括號旁白",
    "accd3778119664c2|771738033fc40fc9|5fd5c4dc4dbcc960|bec45d995531e0c3",
  ],
  [
    "hint／game／style開",
    "457d9f49ff6b4ff0|6e3fab2b0dd43d2d|af3645bfecbe6a8f|b7d92dbf94687c04",
  ],
  [
    "debrief／game／style開",
    "2d2aeebde778e3eb|2f97a095d1d75e7a|b7fe848d8efa0772|30caeb474cf26d9e",
  ],
  [
    "chat／standard／貼文非空",
    "9a922e2a8babda2d|444e4e27dafce2e0|942147acce9b12da|d60d39d9f4d069b7",
  ],
  [
    "chat／beginner／貼文非空",
    "dd12e21e32e08445|40607d6481b9863d|dcbcb65fd81efe3e|ed466986989d2834",
  ],
  [
    "hint／beginner／prefetch",
    "8098d9e5e50d12f1|464c81fdd6e63728|977cd06362f719d8|782965b055b18e01",
  ],
  [
    "draw_status",
    "643d5437104296e2|c0a5588abf29c85c|2789d496c3a61e53|e3b0c44298fc1c14",
  ],
  [
    "錯誤路徑／配額 RPC 失敗→4xx",
    "643d5437104296e2|bb8e10a14b94897f|ca158647bff92ea8|0fd66168cb4c5218",
  ],
]);

// ── printer：`AGENCY_EQUIV_PRINT_GOLDEN=1` 時印出可貼回的 TS 常數 ─────────
const PRINT_GOLDEN = Deno.env.get("AGENCY_EQUIV_PRINT_GOLDEN") === "1";

Deno.test({
  name:
    "agency flag-off 等價 harness：印出 golden（只在 AGENCY_EQUIV_PRINT_GOLDEN=1 時跑）",
  ignore: !PRINT_GOLDEN,
  fn: async () => {
    const rows: string[] = [];
    for (const c of equivalenceCases()) {
      rows.push(
        `  [${JSON.stringify(c.name)}, ${
          JSON.stringify(digestLine(await observableDigest(c, undefined)))
        }],`,
      );
    }
    console.log(`\n[\n${rows.join("\n")}\n]\n`);
  },
});

Deno.test({
  name:
    "agency 旗標未設／off／shadow：messages、Response bytes、完整 RPC params、telemetry 全部逐位元組等於 7f1d6d6c golden",
  ignore: PRINT_GOLDEN,
  fn: async () => {
    const cases = equivalenceCases();
    assertEquals(
      new Set(cases.map((c) => c.name)).size,
      cases.length,
      "case 名稱必須唯一",
    );
    assertEquals(
      cases.map((c) => c.name).sort(),
      [...AGENCY_FLAG_OFF_GOLDEN.keys()].sort(),
      "golden 的案例集合與矩陣不一致（新增／刪除案例要重跑 printer）",
    );
    for (const c of cases) {
      const expected = parseGolden(c.name);
      // 未設／off／亂填（＝`agencyModeFor` 一律解析成 off）：四面全等。
      for (const env of [undefined, "off", "亂填"]) {
        assertEquals(
          await observableDigest(c, env),
          expected,
          `${c.name} / env=${env}`,
        );
      }
      // shadow 的契約是「只多記 telemetry，不動任何對外行為」，所以
      // messages／Response bytes／RPC params 三面必須全等，telemetry 是它
      // **唯一**被允許不同的地方（下一條測試會反過來要求它真的不同）。
      const shadow = await observableDigest(c, "shadow");
      assertEquals(
        {
          messages: shadow.messages,
          response: shadow.response,
          rpc: shadow.rpc,
        },
        {
          messages: expected.messages,
          response: expected.response,
          rpc: expected.rpc,
        },
        `${c.name} / env=shadow（telemetry 以外三面必須全等）`,
      );
    }
  },
});

Deno.test({
  name:
    "agency 旗標 test：一般帳號等於 golden，測試帳號必須真的不一樣（非空洞檢查）",
  ignore: PRINT_GOLDEN,
  fn: async () => {
    for (const c of equivalenceCases()) {
      assertEquals(
        await observableDigest(c, "test"),
        parseGolden(c.name),
        c.name,
      );
    }
  },
});

Deno.test({
  name: "agency shadow：telemetry 必須真的多記東西（不然 shadow 模式是空的）",
  ignore: PRINT_GOLDEN,
  fn: async () => {
    const chatCases = equivalenceCases().filter((c) =>
      c.name.startsWith("chat／")
    );
    for (const c of chatCases) {
      const shadow = await observableDigest(c, "shadow");
      assert(
        shadow.telemetry !== parseGolden(c.name).telemetry,
        `${c.name}：shadow 的 telemetry 必須與 flag-off golden 不同`,
      );
    }
  },
});

Deno.test({
  name:
    "非空洞檢查：旗標 true／test＋測試帳號時，chat 案例的可觀測面必須與 golden 不同",
  ignore: PRINT_GOLDEN,
  fn: async () => {
    // Phase 4.1 之前 hint／debrief 不讀 agency 旗標，本來就該相同；4.1 之後
    // 兩者都吃結構化教練證據，所以它們的「必須不同」另外一支測試釘住（下面
    // 那支列出確切會變的案例名單，因為有些 hint／debrief 案例根本走不到
    // Claude——hint 是 beginner 專用，standard 會在 403 就返回）。
    const chatCases = equivalenceCases().filter((c) =>
      c.name.startsWith("chat／")
    );
    for (const c of chatCases) {
      const expected = digestLine(parseGolden(c.name));
      const on = digestLine(await observableDigest(c, "true"));
      assert(
        on !== expected,
        `${c.name}：旗標開時必須與 flag-off golden 不同（不然 harness 是空洞的）`,
      );
      // `test` 對測試帳號＝`on`：兩條路徑必須逐位元組同一個結果。
      assertEquals(
        await observableDigest(c, "test", TEST_ACCOUNT),
        await observableDigest(c, "true", TEST_ACCOUNT),
        `${c.name}：test＋測試帳號應與 true 同路徑`,
      );
    }
  },
});

Deno.test({
  name:
    "牆鐘欄位只 scrub 值不 scrub key：duration 欄位真的存在，而且旗標不改變它們（Codex R1 新項 U）",
  ignore: PRINT_GOLDEN,
  fn: async () => {
    // `scrubWallClock()` 把值歸零、key 留著，所以 golden 驗的是**欄位形狀**。
    // 「key 一個都沒印」跟「印了但值不同」在 digest 上長得一樣，因此「這些 key
    // 真的存在」必須另外斷言。實測只有真的走到 Claude 的 hint／debrief 會印
    // `attemptDurationMs`／`totalDurationMs`；chat 與被配額擋掉的案例一個都不印
    // （那也被 golden 釘住——哪天開始印，scrub 後的文字就會多出 key，digest 立刻變）。
    const union = new Set<string>();
    for (const c of equivalenceCases()) {
      let baseline: string | null = null;
      for (const env of [undefined, "off", "shadow", "true"]) {
        const probe: RunProbe = { durationKeys: [] };
        await observableDigest(c, env, undefined, probe);
        for (const key of probe.durationKeys) union.add(key);
        const joined = probe.durationKeys.join(",");
        if (baseline === null) baseline = joined;
        assertEquals(joined, baseline, `${c.name} / env=${env}`);
      }
    }
    // 至少有案例真的印出這兩個欄位，scrub 才不是在保護空集合。
    for (const key of ["attemptDuration", "totalDuration"]) {
      assert(union.has(key), `整個矩陣都沒有印出 "${key}Ms"，scrub 是死碼`);
    }
    // 新增的 prefetch 案例走 Claude，必須兩個都有。
    const prefetch = equivalenceCases().find((c) =>
      c.name === "hint／beginner／prefetch"
    )!;
    const probe: RunProbe = { durationKeys: [] };
    await observableDigest(prefetch, undefined, undefined, probe);
    assertEquals(probe.durationKeys, ["attemptDuration", "totalDuration"]);
  },
});

Deno.test({
  name:
    "Phase 4.1 非空洞檢查：旗標 true 時，真的走到 Claude 的 hint／debrief 案例 messages 必須與 golden 不同",
  ignore: PRINT_GOLDEN,
  fn: async () => {
    // hint 是 beginner／game 專用（standard 直接 403），debrief 三個模式都走
    // 得到；`hint／beginner／prefetch` 也走 Claude。走不到 Claude 的案例
    // （403 錯誤回應）旗標開關本來就不該有差別，這裡把兩邊都釘住：名單以外
    // 的 hint／debrief 案例必須**逐位元組相同**。
    // Codex R1 P2：舊版比的是**合成 digest**，而 on 一律會多一行
    // `conversationAgency` telemetry，所以就算 `agencyCoaching`／`agencyLedger`
    // 根本沒接進 builder，整體 digest 照樣會不同——測試名稱宣稱的事歸因不到
    // prompt。改成分欄比 `messages`（送進 Claude 的每一則訊息），telemetry 不
    // 參與判定。
    const changed: string[] = [];
    const sideCases = equivalenceCases().filter((c) =>
      !c.name.startsWith("chat／")
    );
    for (const c of sideCases) {
      const on = await observableDigest(c, "true");
      const golden = parseGolden(c.name);
      if (on.messages !== golden.messages) changed.push(c.name);
      // 名單外的案例（走不到 Claude 的 403）四面都必須不變；名單內的案例
      // Response 與 RPC 也不該因為 agency 而改變（只有 prompt 與 telemetry 會）。
      assertEquals(on.response, golden.response, `${c.name} / Response`);
      assertEquals(on.rpc, golden.rpc, `${c.name} / RPC`);
    }
    assertEquals(changed.sort(), PHASE41_CHANGED_SIDE_CASES.slice().sort());
  },
});

Deno.test({
  name:
    "Phase 4.4：PRACTICE_CHAT_MODEL_ROUTING 未設／off／亂填時四面等價；mixed 只多 telemetry 允許的 key，沒有 Anthropic key 就不換模型",
  ignore: PRINT_GOLDEN,
  fn: async () => {
    for (const c of equivalenceCases()) {
      const expected = parseGolden(c.name);
      // 認不得的值一律 off（`chatModelFor` fail-closed）：四面全等 golden。
      for (const routing of ["off", "亂填", "true"]) {
        assertEquals(
          await observableDigest(c, undefined, undefined, undefined, routing),
          expected,
          `${c.name} / routing=${routing}`,
        );
      }
      // `mixed` 但 agency 未設（＝off）：路由不可能生效，messages／Response／RPC
      // 三面必須全等；telemetry 是它唯一被允許不同的地方（多允許的那幾個 key，
      // 逐欄位比對見下一支測試）。
      const mixedOff = await observableDigest(
        c,
        undefined,
        undefined,
        undefined,
        "mixed",
      );
      assertEquals(
        {
          messages: mixedOff.messages,
          response: mixedOff.response,
          rpc: mixedOff.rpc,
        },
        {
          messages: expected.messages,
          response: expected.response,
          rpc: expected.rpc,
        },
        `${c.name} / routing=mixed（telemetry 以外三面必須全等）`,
      );
      // `mixed` ＋ agency on，但 fake 的 `CLAUDE_API_KEY` 是空字串（chat 案例沒有
      // `claudeReplies`）：沒有 key 就必須退回 DeepSeek，三面等於「agency on ＋
      // routing 未設」。真的換模型的正向案例在 `chat_model_routing_test.ts`。
      const agencyOn = await observableDigest(c, "true");
      const mixedOn = await observableDigest(
        c,
        "true",
        undefined,
        undefined,
        "mixed",
      );
      assertEquals(
        {
          messages: mixedOn.messages,
          response: mixedOn.response,
          rpc: mixedOn.rpc,
        },
        {
          messages: agencyOn.messages,
          response: agencyOn.response,
          rpc: agencyOn.rpc,
        },
        `${c.name} / routing=mixed＋agency=true（沒有 Anthropic key 就不換模型）`,
      );
    }
  },
});

/** routing=mixed 時 telemetry 唯一被允許多出來的 key（Codex R1 P3）。 */
const ROUTING_ALLOWED_KEYS = [
  "chatModel",
  "chatModelCalls",
  "chatModelFallback",
  "chatModelUsage",
];

Deno.test({
  name:
    "Phase 4.4（Codex R1 P3）：routing=mixed 的 telemetry 只多允許的 key——事件數／事件名／其餘欄位逐位元組相同，且真的多記東西",
  ignore: PRINT_GOLDEN,
  fn: async () => {
    const chatCases = equivalenceCases().filter((c) =>
      c.name.startsWith("chat／")
    );
    for (const c of chatCases) {
      const offProbe: RunProbe = { durationKeys: [] };
      const mixedProbe: RunProbe = { durationKeys: [] };
      const off = await observableDigest(c, undefined, undefined, offProbe);
      await observableDigest(c, undefined, undefined, mixedProbe, "mixed");
      // 這個 case 的 flag-off 執行本身已被上面的 golden 測試釘成 7f1d6d6c bytes，
      // 所以拿它當基準等同拿 golden 當基準（但比得到欄位，不只比雜湊）。
      assertEquals(off.telemetry, parseGolden(c.name).telemetry, c.name);
      const offLines = offProbe.lines ?? [];
      const mixedLines = mixedProbe.lines ?? [];
      assertEquals(mixedLines.length, offLines.length, `${c.name}：事件數`);
      const eventNames = (lines: string[]) =>
        lines.map((l) => (JSON.parse(l) as { event?: string }).event);
      assertEquals(
        eventNames(mixedLines),
        eventNames(offLines),
        `${c.name}：事件名與順序`,
      );
      let extra = 0;
      for (let i = 0; i < mixedLines.length; i++) {
        const mixedJson = JSON.parse(mixedLines[i]) as Record<string, unknown>;
        for (const key of ROUTING_ALLOWED_KEYS) {
          if (Object.hasOwn(mixedJson, key)) {
            delete mixedJson[key];
            extra++;
          }
        }
        // 刪掉允許的 key 之後，整行（含 key 順序）必須與 flag-off 那一行相同。
        assertEquals(
          scrubWallClock(JSON.stringify(mixedJson)),
          scrubWallClock(offLines[i]),
          `${c.name}：第 ${i + 1} 行除了允許的 key 之外必須逐位元組相同`,
        );
      }
      // 非空洞：真的多記了東西（chat 成功事件一定有 chatModel＋chatModelCalls）。
      assert(extra >= 2, `${c.name}：routing=mixed 沒有多記任何允許的 key`);
    }
  },
});
