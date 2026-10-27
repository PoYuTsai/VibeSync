// 寫卡瘦身（開關 ANALYZE_GUIDE_V3_WRITER_TRIM，Bruce 2026-10-26「看B43-B47感覺可以從寫卡prompt 移除 他們對自然度會有影響」；
// Eric 2026-10-27「照預設」）從正式入口走（guide_v3/v3_stream_harness.ts：假 Supabase、假模型）：env 每次請求設定。開著時寫卡的
// 使用者訊息不帶 B43、B45、B46、B47 的觸發與寫法、系統提示詞 A5「讓她也投入」少一句；B44 留給寫卡（Bruce 2026-10-27 盲選：B44
// 舊版 4 比 1；Eric 同日「照預設」），只標到 B44 時寫卡的使用者訊息一字不差。讀局面與說明的請求、卡片的任務一字不差；B47 照樣給
// 酒托提醒與三張固定排法，換地方的卡片規格還在，中間那張收卡補固定說明（不答應去那家）。沒設、off、test 但不是測試帳號、打錯、
// 兩段式沒開時一字不變。對話全部新寫，事件照種類找。
//
// 寫卡的 streaming_fallback.ts 一載入就存下 fetch：轉接器要放第一個 import，入口模組也要在 env 裝好
// 之後才動態載入（STREAM_ANALYZE_ENABLED 是載入時讀的常數）。
import "../test_fetch_dispatcher.ts";
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { BILLING_PROTOCOL_VERSION } from "../billing.ts";
import { ANALYSIS_CONTRACT_VERSION_V3 } from "../no_send_decision.ts";
import { TEST_EMAILS } from "../../_shared/quota.ts";
import { GUIDE_V3_ENTRIES } from "./entries.ts";
import { cardTaskText } from "./prompts.ts";
import { SCAM_VENUE_WARNING } from "./rules.ts";
import {
  WRITER_TRIM_A5_SENTENCE,
  WRITER_TRIM_VENUE_CLOSE_SENTINELS,
  WRITER_TRIM_VENUE_CLOSE_TASK,
} from "./two_stage_prompts.ts";
import {
  fakeExplainResponse,
  fakeReadResponse,
  fakeWriteResponse,
  runGuideV3StreamThroughHandler,
  type V3HarnessOutcome,
  v3HarnessStage,
} from "./v3_stream_harness.ts";

const IMPORT_ENV: Record<string, string> = {
  SUPABASE_URL: "http://supabase.test",
  SUPABASE_SERVICE_ROLE_KEY: "fake-service-key",
  CLAUDE_API_KEY: "fake-claude-key",
  STREAM_ANALYZE_ENABLED: "true",
};
const savedEnv = Object.keys(IMPORT_ENV).map((k) => [k, Deno.env.get(k)]);
for (const [k, v] of Object.entries(IMPORT_ENV)) Deno.env.set(k, v);
const { createAnalyzeChatHandler } = await import("../index.ts");
for (const [k, v] of savedEnv) {
  if (v === undefined) Deno.env.delete(k!);
  else Deno.env.set(k!, v);
}

/// 還沒交往：他說剛看完一部老電影，她說自己也在補老片，接著問他喜歡什麼樣的女生、也問他她適不適合留短髮（句子全新）。他傳過兩則。
const MESSAGES = [
  { isFromMe: true, content: "剛看完一部老電影 後勁好強" },
  { isFromMe: false, content: "我最近也在補老片欸" },
  { isFromMe: true, content: "那下次換你推一部" },
  { isFromMe: false, content: "先說 你喜歡什麼樣的女生😏" },
  { isFromMe: false, content: "你覺得我適合留短髮嗎" },
];

/// 讀局面：標到 B45（她問他喜歡怎樣的人，寫卡看不到）與 B21（她問他意見）。
const READ = {
  light: "green",
  herMove: "問他意見",
  herMoodBad: false,
  drunkOrLateNight: false,
  inviteReadiness: "沒機會",
  cancelHasAlternative: false,
  retreating: false,
  declinedOrBoundary: false,
  explicitRejection: false,
  blocked: false,
  risk: false,
  selfHarmSignal: false,
  minorSignal: false,
  needsHisFacts: false,
  identityQuestion: false,
  hisStatedFacts: [],
  hasHisVoiceSample: true,
  replyWillingness: "high",
  worthyBallCount: 2,
  herTurnsPerfunctory: [],
  matchedEntries: ["B45", "B21"],
  readForUser:
    "她也在補老片，問你喜歡什麼樣的女生，也想聽你覺得她適不適合留短髮。",
  waitFor: "",
  establishedCouple: false,
  herAffection: false,
  herHappyShare: false,
  worthyLines: [
    { line: 1, label: "問他喜歡什麼樣的女生", kind: "問他" },
    { line: 2, label: "問適不適合短髮", kind: "問他" },
  ],
};

/// 還沒交往：她說自己一個人去爬山，他說很敢，她問這樣有沒有加分、也問他下次該挑哪座（句子全新）。他傳過兩則。
const B44_MESSAGES = [
  { isFromMe: true, content: "連假去哪玩" },
  { isFromMe: false, content: "自己背包去爬雪山" },
  { isFromMe: true, content: "一個人上雪山 很敢欸" },
  { isFromMe: false, content: "這樣有加分嗎😏" },
  { isFromMe: false, content: "你覺得我下次該挑哪座" },
];

/// 讀局面：標到 B44（她討他的看法，留給寫卡）與 B21（她問他意見）。
const B44_READ = {
  ...READ,
  matchedEntries: ["B44", "B21"],
  readForUser: "她一個人去爬雪山，問你這樣有沒有加分，也想聽你推薦下一座山。",
  worthyLines: [
    { line: 1, label: "問有沒有加分", kind: "問他" },
    { line: 2, label: "問下次挑哪座", kind: "問他" },
  ],
};

/// 第一次約：她指定一間酒吧，他提議換地方，她還是不肯（句子全新）。
const VENUE_MESSAGES = [
  { isFromMe: true, content: "這週六有空見個面嗎" },
  { isFromMe: false, content: "好啊 去東區那間威士忌吧" },
  { isFromMe: true, content: "換間咖啡廳如何" },
  { isFromMe: false, content: "不要啦 就那間 我姊妹都說讚" },
];
const VENUE_READ = {
  ...READ,
  herMove: "生活",
  inviteReadiness: "她自己提見面",
  worthyBallCount: 1,
  matchedEntries: ["B47"],
  readForUser: "她堅持要去她指定的那間酒吧，換地方也不肯。",
  worthyLines: [{ line: 1, label: "堅持去那間", kind: "其他" }],
};

type Rec = Record<string, unknown>;

function userText(body: Rec): string {
  return (body.messages as { content: string }[])[0].content;
}

function systemOf(body: Rec): string {
  return typeof body.system === "string"
    ? body.system
    : (body.system as { text?: string }[]).map((b) => b.text ?? "").join("");
}

function analyze(args: {
  readonly env: Record<string, string | undefined>;
  readonly messages?: readonly { isFromMe: boolean; content: string }[];
  readonly read?: Rec;
  readonly email?: string;
  /// 假寫卡第幾張要寫的字（沒給照預設）：測哨兵。
  readonly cardText?: (card: number) => string | undefined;
}): Promise<V3HarnessOutcome> {
  return runGuideV3StreamThroughHandler({
    createHandler: createAnalyzeChatHandler,
    body: {
      responseMode: "stream",
      messages: args.messages ?? MESSAGES,
      billingProtocolVersion: BILLING_PROTOCOL_VERSION,
      analysisContractVersion: ANALYSIS_CONTRACT_VERSION_V3,
    },
    ...(args.email ? { email: args.email } : {}),
    env: {
      ANALYZE_GUIDE_V3: "on",
      ANALYZE_GUIDE_V3_MEMORY: undefined,
      ANALYZE_GUIDE_V3_PREV_ROUND: undefined,
      ANALYZE_GUIDE_V3_RELATION: undefined,
      ANALYZE_GUIDE_V3_TWO_STAGE: "on",
      ANALYZE_GUIDE_V3_TYPING_STYLE: undefined,
      ANALYZE_GUIDE_V3_SHORT_PRAISE: undefined,
      ANALYZE_GUIDE_V3_TENSION_STYLE: undefined,
      ANALYZE_GUIDE_V3_PHRASE_TIDY: undefined,
      ANALYZE_GUIDE_V3_SWEET_SHORT: undefined,
      ANALYZE_GUIDE_V3_NO_IOU: undefined,
      ANALYZE_GUIDE_V3_WRITER_TRIM: undefined,
      ...args.env,
    },
    model: (body) => {
      switch (v3HarnessStage(body)) {
        case "write": {
          const n = Number(userText(body).match(/一共 (\d+) 張/)?.[1] ?? 0);
          return Promise.resolve(fakeWriteResponse(
            Array.from({ length: n }, (_, i) =>
              JSON.stringify({
                card: i + 1,
                messages: [args.cardText?.(i + 1) ?? `有啊 第 ${i + 1} 張`],
                hasInventedDetail: false,
              })),
          ));
        }
        case "explain": {
          const slots = [...userText(body).matchAll(/### 第 (\d+) 張/g)].map((
            m,
          ) => Number(m[1]));
          return Promise.resolve(
            fakeExplainResponse(
              slots.map((card) => ({ card, text: `第 ${card} 張的道理。` })),
            ),
          );
        }
        default:
          return Promise.resolve(fakeReadResponse(args.read ?? READ));
      }
    },
  });
}

const bodyOf = (out: V3HarnessOutcome, stage: string) =>
  out.modelBodies.find((b) => v3HarnessStage(b) === stage);
const traceOf = (out: V3HarnessOutcome) =>
  out.finalResult?.guideV3Trace as {
    push: string | null;
    entries: string[];
    specs: { task: string }[];
    removed: { slot: number; reason: string }[];
  };
const specLines = (write: string) =>
  write.split("\n").filter((l) => /^\d\. 任務：/.test(l));
const planned = (out: V3HarnessOutcome) =>
  (out.events.find((e) => e.type === "analysis.read")!.plannedCards as {
    task: string;
  }[]).map((p) => p.task);
const judgmentOf = (out: V3HarnessOutcome) =>
  out.events.find((e) => e.type === "analysis.read")!.judgment;
const entryOf = (id: string) => GUIDE_V3_ENTRIES.find((e) => e.id === id)!;
/// 寫卡使用者訊息裡那一條的樣子（「編號（觸發）：寫法」；B21、B44、B45、B47 的寫法沒有要改名的字）。
const entryLine = (id: string) =>
  `- ${id}（${entryOf(id).trigger}）：${entryOf(id).writing}`;
const sameBody = (a: V3HarnessOutcome, b: V3HarnessOutcome, stage: string) =>
  JSON.stringify(bodyOf(a, stage)) === JSON.stringify(bodyOf(b, stage));

/// 開著的寫卡請求跟沒開比：系統提示詞只少 A5 那一句；使用者訊息只少 B45 那一行（B21 照樣在）。
function assertTrimmedWrite(on: V3HarnessOutcome, off: V3HarnessOutcome) {
  const onWrite = bodyOf(on, "write")!;
  const offWrite = bodyOf(off, "write")!;
  assertEquals(systemOf(offWrite).split(WRITER_TRIM_A5_SENTENCE).length - 1, 1);
  assertEquals(
    systemOf(onWrite),
    systemOf(offWrite).replace(WRITER_TRIM_A5_SENTENCE, ""),
  );
  const b45 = entryOf("B45");
  assert(
    userText(offWrite).includes(`${entryLine("B45")}\n${entryLine("B21")}`),
  );
  assertEquals(userText(onWrite).includes(b45.trigger), false);
  assertEquals(userText(onWrite).includes(b45.writing), false);
  assert(
    userText(onWrite).includes(`## 這一輪的情境做法\n${entryLine("B21")}`),
  );
  assertEquals(
    userText(onWrite),
    userText(offWrite).replace(`${entryLine("B45")}\n`, ""),
  );
}

Deno.test("從正式入口：ANALYZE_GUIDE_V3_WRITER_TRIM=on：讀局面與說明的請求一字不差、卡片任務一樣；寫卡的系統提示詞只少那一句、使用者訊息沒有 B45 的觸發與寫法（B21 照樣在）；trace 的條目照舊", async () => {
  const on = await analyze({ env: { ANALYZE_GUIDE_V3_WRITER_TRIM: "on" } });
  const off = await analyze({ env: {} });
  assertEquals(on.status, 200);
  assertEquals(on.events.some((e) => e.type === "analysis.error"), false);
  assert(sameBody(on, off, "read"));
  assert(sameBody(on, off, "explain"));
  // 卡片任務一樣：她直接問他，第一張接住；B45 不排帶張力。
  assertEquals(planned(on), planned(off));
  assertEquals(planned(on), ["accept", "push", "accept", "accept", "accept"]);
  assertEquals(
    specLines(userText(bodyOf(on, "write")!)),
    specLines(userText(bodyOf(off, "write")!)),
  );
  assertEquals(traceOf(on).specs, traceOf(off).specs);
  assertTrimmedWrite(on, off);
  // 說明與 trace 照舊用原本那一份條目（有 B45）。
  assertEquals(traceOf(on).entries, ["B45", "B21"]);
  assert(userText(bodyOf(on, "explain")!).includes(entryOf("B45").writing));
  // 送出的卡、判讀一樣。
  assertEquals(
    on.events.filter((e) => e.type === "analysis.card"),
    off.events.filter((e) => e.type === "analysis.card"),
  );
  assertEquals(judgmentOf(on), judgmentOf(off));
});

Deno.test("從正式入口：寫卡瘦身開、B44（她討他的看法）：寫卡照樣看得到 B44（Bruce 2026-10-27 盲選留下）——使用者訊息跟沒開一字不差、系統提示詞只少 A5 那一句；讀局面與說明的請求、卡片任務一樣", async () => {
  const run = (env: Record<string, string>) =>
    analyze({ env, messages: B44_MESSAGES, read: B44_READ });
  const on = await run({ ANALYZE_GUIDE_V3_WRITER_TRIM: "on" });
  const off = await run({});
  assertEquals(on.status, 200);
  assertEquals(on.events.some((e) => e.type === "analysis.error"), false);
  assert(sameBody(on, off, "read"));
  assert(sameBody(on, off, "explain"));
  // 她直接問他，第一張接住；B44 不排帶張力（開不開都一樣）。
  assertEquals(planned(on), ["accept", "push", "accept", "accept", "accept"]);
  assertEquals(planned(on), planned(off));
  assertEquals(traceOf(on).entries, ["B44", "B21"]);
  const onWrite = bodyOf(on, "write")!;
  const offWrite = bodyOf(off, "write")!;
  assert(
    userText(onWrite).includes(
      `## 這一輪的情境做法\n${entryLine("B44")}\n${entryLine("B21")}`,
    ),
  );
  assertEquals(userText(onWrite), userText(offWrite));
  assertEquals(systemOf(offWrite).split(WRITER_TRIM_A5_SENTENCE).length - 1, 1);
  assertEquals(
    systemOf(onWrite),
    systemOf(offWrite).replace(WRITER_TRIM_A5_SENTENCE, ""),
  );
  assertEquals(
    on.events.filter((e) => e.type === "analysis.card"),
    off.events.filter((e) => e.type === "analysis.card"),
  );
});

Deno.test("從正式入口：寫卡瘦身沒設、off、test 但不是測試帳號、打錯（true）：每一個請求都跟沒設一字不差；test 加測試帳號就開", async () => {
  const unset = await analyze({ env: {} });
  for (const flag of ["off", "test", "true"]) {
    const out = await analyze({ env: { ANALYZE_GUIDE_V3_WRITER_TRIM: flag } });
    assertEquals(out.status, 200, flag);
    for (const stage of ["read", "write", "explain"]) {
      assert(sameBody(out, unset, stage), `${flag}/${stage}`);
    }
    assert(systemOf(bodyOf(out, "write")!).includes(WRITER_TRIM_A5_SENTENCE));
    assert(userText(bodyOf(out, "write")!).includes(entryLine("B45")));
  }
  const testAccount = await analyze({
    env: { ANALYZE_GUIDE_V3_WRITER_TRIM: "test" },
    email: TEST_EMAILS[0],
  });
  const testAccountOff = await analyze({ env: {}, email: TEST_EMAILS[0] });
  assertEquals(testAccount.status, 200);
  assert(sameBody(testAccount, testAccountOff, "read"));
  assert(sameBody(testAccount, testAccountOff, "explain"));
  assertTrimmedWrite(testAccount, testAccountOff);
});

Deno.test("從正式入口：寫卡瘦身開、兩段式沒開：不作用（只在兩段式開時有作用），讀局面與寫卡的請求跟都沒開一字不差、沒有說明", async () => {
  const twoStageOff = { ANALYZE_GUIDE_V3_TWO_STAGE: undefined };
  const on = await analyze({
    env: { ...twoStageOff, ANALYZE_GUIDE_V3_WRITER_TRIM: "on" },
  });
  const off = await analyze({ env: twoStageOff });
  assertEquals(on.status, 200);
  for (const stage of ["read", "write"]) {
    assert(sameBody(on, off, stage), stage);
  }
  assertEquals(bodyOf(on, "explain"), undefined);
  // 舊的一步寫卡照舊看得到 B45。
  assert(userText(bodyOf(on, "write")!).includes(entryOf("B45").writing));
  assertEquals(traceOf(on).entries, traceOf(off).entries);
});

Deno.test("從正式入口：寫卡瘦身開、B47（她堅持去她指定的店）：判讀照樣是酒托提醒、三張固定排法（推進、收、推進）；寫卡看不到 B47 的觸發與寫法，換地方的卡片規格還在，收卡補固定說明；讀局面與說明的請求一字不差", async () => {
  const run = (env: Record<string, string>) =>
    analyze({ env, messages: VENUE_MESSAGES, read: VENUE_READ });
  const on = await run({ ANALYZE_GUIDE_V3_WRITER_TRIM: "on" });
  const off = await run({});
  assertEquals(on.status, 200);
  for (const out of [on, off]) {
    assertEquals(judgmentOf(out), SCAM_VENUE_WARNING);
    assertEquals(planned(out), ["push", "close", "push"]);
    assertEquals(traceOf(out).push, "換地方");
    assertEquals(traceOf(out).entries, ["B47"]);
  }
  assert(sameBody(on, off, "read"));
  assert(sameBody(on, off, "explain"));
  const onUser = userText(bodyOf(on, "write")!);
  const offUser = userText(bodyOf(off, "write")!);
  const b47 = entryOf("B47");
  assert(offUser.includes(entryLine("B47")));
  assertEquals(onUser.includes(b47.trigger), false);
  assertEquals(onUser.includes(b47.writing), false);
  assert(onUser.includes("## 這一輪的情境做法\n（這一輪沒有）"));
  // 換地方的規格（prompts.ts PUSH_NOTE.換地方，裡面自己就寫「不答應去那家」）照樣在兩張推進卡上。
  const venueSpec = cardTaskText({
    task: "推進",
    method: "只用反應",
    voice: "照他",
    questionBudget: 1,
    push: "換地方",
    angle: 0,
  });
  assert(venueSpec.includes("不答應去那家"));
  assertEquals(onUser.split(venueSpec).length - 1, 2);
  // 中間那張收卡：沒開只寫「收」（不答應去那家原本只在 B47 的條目裡）；開著換成固定說明（Eric 2026-10-27「照預設，跑」）。
  const offLines = specLines(offUser);
  assert(offLines[1].startsWith("2. 任務：收｜"));
  assertEquals(
    specLines(onUser),
    [
      offLines[0],
      offLines[1].replace(
        "任務：收｜",
        `任務：${WRITER_TRIM_VENUE_CLOSE_TASK}｜`,
      ),
      offLines[2],
    ],
  );
  assertEquals(onUser.split(WRITER_TRIM_VENUE_CLOSE_TASK).length - 1, 1);
  assertEquals(offUser.includes(WRITER_TRIM_VENUE_CLOSE_TASK), false);
  assertEquals(
    onUser,
    offUser
      .replace(entryLine("B47"), "（這一輪沒有）")
      .replace("2. 任務：收｜", `2. 任務：${WRITER_TRIM_VENUE_CLOSE_TASK}｜`),
  );
  assertEquals(
    systemOf(bodyOf(on, "write")!),
    systemOf(bodyOf(off, "write")!).replace(WRITER_TRIM_A5_SENTENCE, ""),
  );
});

Deno.test("從正式入口：寫卡瘦身開、B47：卡片照抄收卡那句固定說明就拿掉那張（沒開不比）；不是 B47 時不比；正常的收尾照送", async () => {
  const run = (
    env: Record<string, string>,
    cardText: (card: number) => string | undefined,
    venue = true,
  ) =>
    analyze({
      env,
      cardText,
      ...(venue ? { messages: VENUE_MESSAGES, read: VENUE_READ } : {}),
    });
  const leaky = (card: number) =>
    card === 2
      ? `這次先不約了 ${WRITER_TRIM_VENUE_CLOSE_SENTINELS[0]}`
      : undefined;
  const on = await run({ ANALYZE_GUIDE_V3_WRITER_TRIM: "on" }, leaky);
  assertEquals(
    traceOf(on).removed.map((r) => [r.slot, r.reason]),
    [[2, "prompt_leak"]],
  );
  const off = await run({}, leaky);
  assertEquals(traceOf(off).removed, []);
  // 不是 B47（原本的情境）：開著也不比這一句。
  const other = await run({ ANALYZE_GUIDE_V3_WRITER_TRIM: "on" }, leaky, false);
  assertEquals(traceOf(other).removed, []);
  // 正常的收尾、改約別的地方照送。
  const natural = (card: number) =>
    card === 2
      ? "這次先不約了 等你哪天想換個地方再說"
      : "改約燒肉吧 週六晚上七點";
  const kept = await run({ ANALYZE_GUIDE_V3_WRITER_TRIM: "on" }, natural);
  assertEquals(traceOf(kept).removed, []);
});
