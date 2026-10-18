// 上一輪脈絡（previousRound，Eric 2026-10-18）：欄位驗證與上限、開關、兩段提示詞的
// 段落位置與內容；沒帶時兩段使用者提示詞跟改版前（20ca3aa1）逐字相同（sha256 鎖）。
import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  acceptedPreviousRound,
  type GuideV3PreviousRound,
  parsePreviousRound,
  PREVIOUS_ROUND_MAX_CHARS,
  PREVIOUS_ROUND_MAX_MESSAGES,
  PREVIOUS_ROUND_MAX_TEXT_CHARS,
  type PreviousRoundIgnoredReason,
  previousRoundReadSection,
  previousRoundTrace,
  previousRoundWriteSection,
  traceWithoutText,
} from "./previous_round.ts";
import { readUserPrompt, writeUserPrompt } from "./prompts.ts";
import type { ReadTags } from "./read_tags.ts";
import { guideV3Mode, shouldUseGuideV3PreviousRound } from "./routing.ts";
import type { CardSpec } from "./rules.ts";
import { toTurns } from "./turns.ts";
import type { GuideV3Trace } from "./wire.ts";

const FULL = {
  decision: "hold",
  light: "yellow",
  judgment: "  她只回了貼圖，先等她多說一點。 ",
  messages: [
    { isFromMe: true, content: "週末有空嗎" },
    { isFromMe: false, content: " 應該在家耍廢 " },
  ],
  extra: "不認得的欄位直接丟掉",
};

function ok(raw: unknown): GuideV3PreviousRound {
  const parsed = parsePreviousRound(raw);
  if (parsed.kind !== "ok") throw new Error(`沒過：${JSON.stringify(parsed)}`);
  return parsed.round;
}

function reason(raw: unknown): PreviousRoundIgnoredReason | null {
  const parsed = parsePreviousRound(raw);
  return parsed.kind === "ignored" ? parsed.reason : null;
}

const text = (n: number) => "字".repeat(n);

Deno.test("上一輪：沒帶是 absent；帶了就 trim、丟掉不認得的欄位", () => {
  assertEquals(parsePreviousRound(undefined), { kind: "absent" });
  assertEquals(parsePreviousRound(null), { kind: "absent" });
  assertEquals(ok(FULL), {
    decision: "hold",
    light: "yellow",
    judgment: "她只回了貼圖，先等她多說一點。",
    messages: [
      { isFromMe: true, content: "週末有空嗎" },
      { isFromMe: false, content: "應該在家耍廢" },
    ],
  });
  // 燈號、判讀都可以沒有；空白當沒有。
  assertEquals(
    ok({
      decision: "send",
      light: null,
      judgment: "   ",
      messages: [{ isFromMe: false, content: "好啊" }],
    }),
    { decision: "send", messages: [{ isFromMe: false, content: "好啊" }] },
  );
  assertEquals(ok({ decision: "stop", judgment: "她說了不要" }), {
    decision: "stop",
    judgment: "她說了不要",
    messages: [],
  });
});

Deno.test("上一輪：格式不對就整份不用，原因代碼對得上", () => {
  assertEquals(reason("一段字"), "not_object");
  assertEquals(reason([FULL]), "not_object");
  assertEquals(reason({ ...FULL, decision: undefined }), "decision");
  // 自傷關心不帶（那一輪只有固定文案）。
  assertEquals(reason({ ...FULL, decision: "care" }), "decision");
  assertEquals(reason({ ...FULL, light: "blue" }), "light");
  assertEquals(reason({ ...FULL, judgment: 3 }), "judgment");
  assertEquals(reason({ ...FULL, messages: "她：好" }), "messages");
  assertEquals(
    reason({ ...FULL, messages: [{ isFromMe: "yes", content: "好" }] }),
    "message",
  );
  assertEquals(
    reason({ ...FULL, messages: [{ isFromMe: false, content: "  " }] }),
    "message",
  );
  assertEquals(reason({ decision: "send", judgment: "" }), "empty");
});

Deno.test("上一輪：上限是每段 120、最多 4 則、全部 600，剛好到上限可以", () => {
  assertEquals(PREVIOUS_ROUND_MAX_TEXT_CHARS, 120);
  assertEquals(PREVIOUS_ROUND_MAX_MESSAGES, 4);
  assertEquals(PREVIOUS_ROUND_MAX_CHARS, 600);
  const at = PREVIOUS_ROUND_MAX_TEXT_CHARS;
  // 每段剛好 120：判讀＋4 則＝600，也就是合計上限；合計那條只是之後改上限時的保險。
  assertEquals(
    PREVIOUS_ROUND_MAX_TEXT_CHARS * (PREVIOUS_ROUND_MAX_MESSAGES + 1),
    PREVIOUS_ROUND_MAX_CHARS,
  );
  const atLimit = {
    decision: "send",
    judgment: text(at),
    messages: [0, 1, 2, 3].map((i) => ({
      isFromMe: i % 2 === 0,
      content: text(at),
    })),
  };
  assertEquals(previousRoundTrace(ok(atLimit)).chars, 600);
  assertEquals(reason({ ...atLimit, judgment: text(at + 1) }), "judgment");
  assertEquals(
    reason({
      decision: "send",
      messages: [{ isFromMe: false, content: text(at + 1) }],
    }),
    "message",
  );
  assertEquals(
    reason({
      decision: "send",
      messages: [0, 1, 2, 3, 4].map(() => ({ isFromMe: false, content: "好" })),
    }),
    "messages",
  );
  // 長度照 trim 之後算。
  ok({
    decision: "send",
    messages: [{ isFromMe: false, content: ` ${text(at)} ` }],
  });
});

Deno.test("上一輪：handler 的包裝只在格式不對時回報原因，沒帶不回報", () => {
  const seen: string[] = [];
  const onIgnored = (r: PreviousRoundIgnoredReason) => seen.push(r);
  assertEquals(acceptedPreviousRound(undefined, onIgnored), undefined);
  assertEquals(acceptedPreviousRound({ decision: "x" }, onIgnored), undefined);
  assertEquals(acceptedPreviousRound(FULL, onIgnored)?.decision, "hold");
  assertEquals(seen, ["decision"]);
});

Deno.test("上一輪：trace 只有數量，不放任何字", () => {
  const trace = previousRoundTrace(ok(FULL));
  assertEquals(trace, {
    messages: 2,
    chars: "她只回了貼圖，先等她多說一點。".length + "週末有空嗎".length +
      "應該在家耍廢".length,
    judgment: true,
  });
});

Deno.test("上一輪開關：off／test／on，test 只給測試帳號，沒設、打錯都是 off", () => {
  for (const raw of [undefined, "", "off", "ON?", "yes"]) {
    assertEquals(
      shouldUseGuideV3PreviousRound({
        mode: guideV3Mode(raw),
        accountIsTest: true,
      }),
      false,
      String(raw),
    );
  }
  assert(
    shouldUseGuideV3PreviousRound({
      mode: guideV3Mode(" On "),
      accountIsTest: false,
    }),
  );
  assert(
    shouldUseGuideV3PreviousRound({
      mode: guideV3Mode("test"),
      accountIsTest: true,
    }),
  );
  assertEquals(
    shouldUseGuideV3PreviousRound({
      mode: guideV3Mode("test"),
      accountIsTest: false,
    }),
    false,
  );
});

// ── 提示詞 ──

const MESSAGES = [
  { isFromMe: true, content: "週末去哪玩" },
  { isFromMe: false, content: "去爬山，腿快斷了" },
  { isFromMe: false, content: "你呢" },
];
const BACKGROUND = {
  meetingContext: "交友軟體",
  duration: "一週內",
  goal: "約出來",
  partnerSummary: "[對象背景：小雲]\n- 興趣：爬山",
};
const TAGS: ReadTags = {
  light: "green",
  herMove: "問他的事",
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
  needsHisFacts: true,
  identityQuestion: false,
  hisStatedFacts: ["週末去哪玩"],
  hasHisVoiceSample: true,
  replyWillingness: "high",
  worthyBallCount: 2,
  herTurnsPerfunctory: [],
  matchedEntries: [],
  readForUser: "她在反問你，球在你這邊。",
  waitFor: "",
};
const CARDS: CardSpec[] = [
  {
    task: "接住",
    method: "用他說過的",
    voice: "照他",
    questionBudget: 1,
    push: null,
    angle: 0,
  },
  {
    task: "帶張力",
    method: "留空格",
    voice: "預設",
    questionBudget: 0,
    push: null,
    angle: 0,
  },
];

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function prompts(previousRound?: GuideV3PreviousRound) {
  const turns = toTurns(MESSAGES);
  return {
    read: readUserPrompt(turns, BACKGROUND, previousRound),
    write: writeUserPrompt({
      turns,
      tags: TAGS,
      entries: [],
      cards: CARDS,
      background: BACKGROUND,
      previousRound,
    }),
  };
}

Deno.test("沒帶上一輪：兩段使用者提示詞跟改版前（20ca3aa1）逐字相同", async () => {
  // 雜湊在改版前的程式上算出來（同一組樣本），改提示詞的人要連這裡一起看。
  const { read, write } = prompts();
  assertEquals(
    await sha256(read),
    "bccc90aa3c21d9ffb0c012e04ac6f6d6139b424befb04305761b36b64d816aa0",
  );
  assertEquals(
    await sha256(write),
    "eed2b268348441502a64b1ff4f2667d7231d969dba9b029c1f6773b82bde7b12",
  );
  assertEquals(previousRoundReadSection(undefined), []);
  assertEquals(previousRoundWriteSection(undefined), []);
});

Deno.test("帶上一輪：讀局面在對話前多一段，標明比較早、只當背景、燈號照這次重判", () => {
  const round = ok(FULL);
  const without = prompts();
  const withRound = prompts(round);
  const [section] = previousRoundReadSection(round);
  assertEquals(
    withRound.read,
    without.read.replace("## 對話\n", `${section}\n\n## 對話\n`),
  );
  assertEquals(
    section,
    [
      "## 上一輪（比下面的對話早）",
      "上一段分析留下的紀錄，只當背景：不是她這次說的話，跟這次的對話對不上時以這次為準，燈號也照這次的對話重新判斷。",
      "- 上次的判讀：黃燈，先別回。她只回了貼圖，先等她多說一點。",
      "- 上一段最後幾則：",
      "  - 他：週末有空嗎",
      "  - 她：應該在家耍廢",
    ].join("\n"),
  );
  // 上一輪不編輪次：「第 N 輪」只屬於這次的對話。
  assert(!section.includes("輪・"));
  assert(withRound.read.indexOf(section) < withRound.read.indexOf("## 對話"));
});

Deno.test("帶上一輪：寫卡只放最後幾則，不放燈號與判讀", () => {
  const round = ok(FULL);
  const without = prompts();
  const withRound = prompts(round);
  const [section] = previousRoundWriteSection(round);
  assertEquals(
    withRound.write,
    without.write.replace("## 對話\n", `${section}\n\n## 對話\n`),
  );
  assertStringIncludes(section, "  - 她：應該在家耍廢");
  for (const hidden of ["黃燈", "先別回", "她只回了貼圖"]) {
    assert(!section.includes(hidden), hidden);
  }
  // 只有判讀可以給讀局面，寫卡就整段不放。
  assertEquals(
    previousRoundWriteSection(ok({ decision: "send", judgment: "她很熱" })),
    [],
  );
  // 沒有燈號就只寫決定；沒有判讀就停在決定。
  assertEquals(
    previousRoundReadSection(
      ok({
        decision: "stop",
        messages: [{ isFromMe: false, content: "不要再傳了" }],
      }),
    )[0].split("\n")[2],
    "- 上次的判讀：停，不再主動傳。",
  );
});

Deno.test("帶上一輪：多餘的換行與空白壓成一行，不會打亂段落", () => {
  const [section] = previousRoundReadSection(
    ok({
      decision: "send",
      light: "green",
      judgment: "她在\n\n反問你",
      messages: [{ isFromMe: false, content: "好啊\n  那就週六" }],
    }),
  );
  assertStringIncludes(section, "- 上次的判讀：綠燈，回她。她在 反問你");
  assertStringIncludes(section, "  - 她：好啊 那就週六");
});

Deno.test("上一輪不帶他複製的那張：舊版 App 送來也不收、不進提示詞、不記數量（主審第 1 輪 P2）", () => {
  const round = ok({ ...FULL, sentCard: "那週六去吃早午餐？" });
  assertEquals(Object.keys(round).sort(), [
    "decision",
    "judgment",
    "light",
    "messages",
  ]);
  for (
    const section of [
      ...previousRoundReadSection(round),
      ...previousRoundWriteSection(round),
    ]
  ) {
    assert(!section.includes("早午餐"), section);
    assert(!section.includes("複製"), section);
  }
  assertEquals(Object.keys(previousRoundTrace(round)).sort(), [
    "chars",
    "judgment",
    "messages",
  ]);
});

Deno.test("帶上一輪那次的 trace：標記用白名單，自由文字只留數量，卡片原文只留則數（主審第 1 輪 P1）", () => {
  const tags = {
    ...TAGS,
    hisStatedFacts: ["上一輪的原句", "第二句"],
    matchedEntries: ["B05", "上一輪的原句"],
    readForUser: "判讀裡抄了上一輪的原句",
    waitFor: "",
    herTurnsPerfunctory: [{ turn: 2, perfunctory: true }],
    // 之後才加的欄位：旗標照留，字串一律不留。
    minorSignal: true,
    note: "上一輪的原句",
  } as unknown as ReadTags;
  const trace = {
    tags,
    push: null,
    specs: CARDS,
    entries: ["B05"],
    removed: [{ slot: 2, reason: "unsafe" }],
    invalidLines: 0,
    scoringWords: [],
    rawMessages: [{ slot: 1, messages: ["上一輪的原句", "妳好"] }],
    models: { read: "m", write: "m" },
    firstCardMs: 10,
  } satisfies GuideV3Trace;
  const out = traceWithoutText(trace, tags);
  assertEquals(JSON.stringify(out).includes("上一輪的原句"), false);
  const kept = out.tags as Record<string, unknown>;
  assertEquals(kept.minorSignal, true);
  assertEquals("note" in kept, false);
  assertEquals(kept.light, "green");
  assertEquals(kept.herMove, "問他的事");
  assertEquals(kept.matchedEntries, ["B05"]);
  assertEquals(kept.herTurnsPerfunctory, [{ turn: 2, perfunctory: true }]);
  assertEquals(kept.hisStatedFactsCount, 2);
  assertEquals(kept.readForUserChars, "判讀裡抄了上一輪的原句".length);
  assertEquals(kept.waitForChars, 0);
  assertEquals(out.rawMessages, [{ slot: 1, messageCount: 2 }]);
  // 其他欄位原樣。
  assertEquals(out.removed, trace.removed);
  assertEquals(out.specs, CARDS);
});
