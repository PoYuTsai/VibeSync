// 新話題共用部分（2026-10-01 規格 §3／§4／§6）：指紋、「這次的局面」規則、
// 紅燈收尾、稽核、telemetry。提示詞本身走結構刀（ADR #53），這裡用它組出的
// 使用者提示詞驗證局面那段；任務與資料的結構測試在 new_topic_slots_test.ts。
import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { hasCustomerExplanationLeak } from "./customer_explanation.ts";
import { computeNewTopicInputHash } from "./new_topic_billing.ts";
import {
  allowsNewTopicSharedFrame,
  NEW_TOPIC_FIELD_CAPS,
  type NewTopicModelTopic,
  type NewTopicSituation,
} from "./new_topic_payload.ts";
import {
  buildNewTopicSlotsUserPrompt,
  parseNewTopicInterests,
  planNewTopicSlots,
} from "./new_topic_slots.ts";
import {
  auditNewTopicTwoStageTopics,
  enforceNewTopicRedClose,
  isNewTopicRedClose,
  NEW_TOPIC_COLD_DURATIONS,
  NEW_TOPIC_COLD_STOPS,
  NEW_TOPIC_ENGAGEMENTS,
  NEW_TOPIC_MATERIAL_KINDS,
  NEW_TOPIC_RED_CLOSE_REASON,
  newTopicGapMentionAllowed,
  newTopicTodayLabel,
  type NewTopicTopicContext,
  newTopicTwoStageTelemetry,
  sanitizeNewTopicTopicContext,
} from "./new_topic_two_stage.ts";

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";
const USER_ID = "11111111-2222-4333-8444-555555555555";
const STRONG_KEY = btoa(String.fromCharCode(...new Uint8Array(32).fill(7)));

function context(
  raw: Record<string, unknown>,
  situation: NewTopicSituation | null,
): NewTopicTopicContext {
  const result = sanitizeNewTopicTopicContext(raw, situation);
  if (!result.ok || result.topicContext === null) {
    throw new Error(`fixture invalid: ${JSON.stringify(raw)}`);
  }
  return result.topicContext;
}

/** 結構刀的使用者提示詞（任務由 planNewTopicSlots 依同一份輸入排）。 */
function slotsPrompt(input: {
  partnerSummary: string | null;
  effectiveStyleContext: string | null;
  situation: NewTopicSituation | null;
  topicContext: NewTopicTopicContext | null;
  requestId: string;
  today?: string | null;
}): string {
  return buildNewTopicSlotsUserPrompt({
    partnerSummary: input.partnerSummary,
    effectiveStyleContext: input.effectiveStyleContext,
    situation: input.situation,
    topicContext: input.topicContext,
    slots: planNewTopicSlots({
      situation: input.situation,
      topicContext: input.topicContext,
      interests: parseNewTopicInterests(input.partnerSummary),
      requestId: input.requestId,
    }),
    today: input.today ?? null,
  });
}

function promptFor(
  situation: NewTopicSituation | null,
  raw: Record<string, unknown>,
): string {
  return slotsPrompt({
    partnerSummary: null,
    effectiveStyleContext: null,
    situation,
    topicContext: context(raw, situation),
    requestId: REQUEST_ID,
  });
}

/** 「這次的局面」段落裡的做法行（不含「- 」）。 */
function situationRules(prompt: string): string[] {
  const section = prompt.split("## 這次的局面")[1].split("\n\n")[0];
  return section.split("做法：\n")[1].split("\n").map((line) => line.slice(2));
}

function hasRule(rules: string[], prefix: string): boolean {
  return rules.some((rule) => rule.startsWith(prefix));
}

/**
 * 提示詞本來就得點名的 JSON 欄位名與「不得出現」的內部代碼；扣掉這些之後，
 * 提示詞不得再含任何解釋欄守門會擋的詞（模型照抄進解釋欄就會被判外洩）。
 */
const PROMPT_CONTRACT_TERMS =
  "direction openingLine whyItWorks nextMove recommendation.reason " +
  "went_cold after_date stuck warm_up new_topic";

const SHARED_FRAME_ALLOWED_LINE =
  "「我們」：可以寫你們一起的事或一起做某件事的小想像，但不越級。";
const SHARED_FRAME_DENIED_LINE =
  "「我們」：不寫「我們」接動作或「我們兩個」「我們家」「我們以後」這類句子，也不寫一起養、一起住；提到過去的事用「上次」「那次」「妳那句」。";

// ---------------------------------------------------------------------------
// §3 重放指紋
// ---------------------------------------------------------------------------

/** 獨立重算 38ebd30d 的 HMAC 演算法（不呼叫被測函式）。 */
async function legacyHmac(canonical: unknown[]): Promise<string> {
  const encoder = new TextEncoder();
  const derivedKey = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(`vibesync-new-topic-replay-v1\u0000${STRONG_KEY}`),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    derivedKey,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(JSON.stringify(canonical)),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.test("hash：沒有 topicContext 時與舊 canonical 逐位元相同（golden）", async () => {
  const base = {
    userId: USER_ID,
    partnerSummary: "對象：小雅。興趣：爬山。",
    effectiveStyleContext: null,
    situation: "went_cold" as const,
    secret: STRONG_KEY,
  };
  const expected = await legacyHmac([
    "vibesync-new-topic-replay-v1",
    base.userId,
    base.partnerSummary,
    base.effectiveStyleContext,
    base.situation,
  ]);
  // 38ebd30d 實際輸出，鎖住演算法本身也沒被動到。
  assertEquals(
    expected,
    "34148aa03a19df9f9ee213056861fab55c746e4e25c36f0f83be5c2fb1eec4e7",
  );
  assertEquals(await computeNewTopicInputHash(base), expected);
  assertEquals(
    await computeNewTopicInputHash({ ...base, topicContext: null }),
    expected,
  );
});

Deno.test("hash：有 topicContext 時尾端多固定順序陣列，不同答案不同指紋", async () => {
  const base = {
    userId: USER_ID,
    partnerSummary: null,
    effectiveStyleContext: null,
    situation: "went_cold" as const,
    secret: STRONG_KEY,
  };
  const story = context(
    {
      coldDuration: "weeks",
      materialKind: "my_story",
      materialText: "走錯分店",
    },
    "went_cold",
  );
  const withStory = await computeNewTopicInputHash({
    ...base,
    topicContext: story,
  });
  assertEquals(
    withStory,
    await legacyHmac([
      "vibesync-new-topic-replay-v1",
      USER_ID,
      null,
      null,
      "went_cold",
      ["weeks", null, null, "my_story", "走錯分店"],
    ]),
  );
  const variants: NewTopicTopicContext[] = [
    { ...story, materialText: "走錯分店了" },
    { ...story, coldDuration: "days" },
    { ...story, coldStop: "faded" },
    { ...story, materialKind: "trigger" },
    context({ materialKind: "none" }, "went_cold"),
  ];
  const hashes = new Set([
    withStory,
    await computeNewTopicInputHash(base),
  ]);
  for (const topicContext of variants) {
    hashes.add(await computeNewTopicInputHash({ ...base, topicContext }));
  }
  assertEquals(hashes.size, variants.length + 2);
});

// ---------------------------------------------------------------------------
// §4.1 系統提示詞
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// §4.2–§4.4 使用者提示詞
// ---------------------------------------------------------------------------

Deno.test("user prompt：狀況基本行（有選送一條、沒選送日常重啟）", () => {
  const cases: Array<[NewTopicSituation | null, string]> = [
    ["went_cold", "冷掉了：低壓重啟。"],
    ["stuck", "還在聊但接不下去："],
    // 沒有寫約會裡的事的素材：只知道剛約完（nt3 盲測 B6）。
    [
      "after_date",
      "剛約完會：你只知道剛約完，不知道去了哪、做了什麼、聊了什麼",
    ],
    ["warm_up", "聊得不錯想更靠近："],
    [null, "沒選狀況：當作日常重啟"],
  ];
  for (const [situation, prefix] of cases) {
    const rules = situationRules(
      promptFor(situation, { materialKind: "none" }),
    );
    assert(rules[0].startsWith(prefix), `${situation}: ${rules[0]}`);
  }
});

Deno.test("user prompt：冷掉了的多久／怎麼停各條件", () => {
  const rulesFor = (raw: Record<string, unknown>) =>
    situationRules(promptFor("went_cold", raw));
  assert(hasRule(rulesFor({ coldDuration: "days" }), "幾天到一週沒聊："));
  assert(hasRule(rulesFor({ coldDuration: "weeks" }), "一到四週沒聊："));
  assert(
    hasRule(
      rulesFor({ coldDuration: "month_plus" }),
      "一個月以上沒聊：可以用一句輕鬆承認有陣子沒聊",
    ),
  );
  assert(
    hasRule(
      rulesFor({ coldDuration: "month_plus", coldStop: "she_cold" }),
      "一個月以上沒聊：帶著一個具體的新東西出現，不提很久沒聊",
    ),
  );
  assert(hasRule(rulesFor({ coldStop: "faded" }), "沒說多久："));
  // 她沒回上一則：「直接接上次聊到的事」會變成追上一則，多久那行讓給怎麼停。
  const daysNoReply = rulesFor({
    coldDuration: "days",
    coldStop: "she_no_reply",
  });
  assert(hasRule(daysNoReply, "她沒回上一則："));
  assertFalse(hasRule(daysNoReply, "幾天到一週沒聊："));
  assert(hasRule(daysNoReply, "見面："));
  assert(hasRule(daysNoReply, "nextMove 多寫一句："));
  assert(
    hasRule(
      rulesFor({ coldDuration: "days", coldStop: "she_cold" }),
      "幾天到一週沒聊：",
    ),
  );

  const stops: Array<[string, string]> = [
    ["she_no_reply", "她沒回上一則："],
    ["i_no_reply", "上次是用戶沒回她："],
    ["she_cold", "她最近都回很冷："],
  ];
  for (const [coldStop, prefix] of stops) {
    const rules = rulesFor({ coldDuration: "weeks", coldStop });
    assert(hasRule(rules, prefix), coldStop);
    // 「怎麼停」比「多久」優先，排在多久那行前面。
    assert(
      rules.findIndex((rule) => rule.startsWith(prefix)) <
        rules.findIndex((rule) => rule.startsWith("一到四週沒聊：")),
    );
  }
  // faded 不加行：基本行＋多久＋見面＋偏冷補一行＋「我們」。
  assertEquals(
    rulesFor({ coldDuration: "weeks", coldStop: "faded" }).length,
    5,
  );
  // 一個月以上＋我沒回她：不解釋、不道歉，也不提很久沒聊（ADR #51 產品裁決 5）。
  const monthIDidNotReply = rulesFor({
    coldDuration: "month_plus",
    coldStop: "i_no_reply",
  });
  assert(monthIDidNotReply.includes(
    "上次是用戶沒回她：直接傳一個新內容，像平常聊天；不解釋為什麼沒回、不道歉、不替自己辯解，也不提很久沒聊。",
  ));
  assert(monthIDidNotReply.includes(
    "一個月以上沒聊：帶著一個具體的新東西出現，不提很久沒聊；不一上來就曖昧。",
  ));
  assertFalse(
    hasRule(monthIDidNotReply, "一個月以上沒聊：可以用一句輕鬆承認有陣子沒聊"),
  );
  assertFalse(monthIDidNotReply.some((rule) => rule.includes("帶過")));
  assertFalse(
    hasRule(
      situationRules(promptFor("stuck", { materialKind: "none" })),
      "沒說多久：",
    ),
    "不是冷掉了就沒有多久那行",
  );
});

Deno.test("user prompt：gapMentionAllowed 真值表", () => {
  const expected: Record<string, boolean> = {
    null: true,
    faded: true,
    she_no_reply: false,
    i_no_reply: false,
    she_cold: false,
  };
  for (const coldStop of [null, ...NEW_TOPIC_COLD_STOPS]) {
    const topicContext = context(
      { coldDuration: "month_plus", coldStop },
      "went_cold",
    );
    const allowed = newTopicGapMentionAllowed("went_cold", topicContext);
    assertEquals(allowed, expected[String(coldStop)], String(coldStop));
    const rules = situationRules(
      promptFor("went_cold", { coldDuration: "month_plus", coldStop }),
    );
    // 我沒回她也不提空窗（ADR #51 產品裁決 5）。
    assertEquals(
      hasRule(rules, "一個月以上沒聊：可以用一句輕鬆承認有陣子沒聊"),
      allowed,
    );
    assertEquals(
      hasRule(rules, "一個月以上沒聊：帶著一個具體的新東西出現，不提很久沒聊"),
      !allowed,
    );
  }
  for (const coldDuration of [null, "days", "weeks"]) {
    for (const coldStop of [null, ...NEW_TOPIC_COLD_STOPS]) {
      assertFalse(
        newTopicGapMentionAllowed(
          "went_cold",
          context(
            { coldDuration, coldStop, materialKind: "none" },
            "went_cold",
          ),
        ),
      );
    }
  }
  assertFalse(newTopicGapMentionAllowed("went_cold", null));
});

Deno.test("user prompt：投入程度 3×3 規則行＋標題，沒選不加行", () => {
  const expected: Record<string, Record<string, [string, string]>> = {
    stuck: {
      green: ["會反問、聊很多", "她有在投入："],
      yellow: ["有回，但很短", "她有回但很短："],
      red: [
        "常只回哈哈、嗯",
        "她常只回哈哈、嗯：其他題也都很輕",
      ],
    },
    after_date: {
      green: ["主動傳訊息或說開心", "約完她主動傳訊息或說開心："],
      yellow: ["有回，但普通", "約完她反應普通："],
      red: ["還沒回或很冷淡", "約完她還沒回或很冷淡："],
    },
    warm_up: {
      green: ["會反問、聊很多", "她很投入：可以加個人感"],
      yellow: ["有回，但很短", "她有回但普通："],
      red: [
        "常只回哈哈、嗯",
        "她常只回哈哈、嗯：現在不升溫",
      ],
    },
  };
  for (const [situation, byEngagement] of Object.entries(expected)) {
    const title = situation === "after_date"
      ? "約完之後她的反應"
      : "她最近回你的樣子";
    for (const engagement of NEW_TOPIC_ENGAGEMENTS) {
      const [label, prefix] = byEngagement[engagement];
      const prompt = promptFor(situation as NewTopicSituation, { engagement });
      assert(
        prompt.includes(`- ${title}：${label}`),
        `${situation}/${engagement}`,
      );
      assert(
        hasRule(situationRules(prompt), prefix),
        `${situation}/${engagement}`,
      );
    }
    const none = situationRules(
      promptFor(situation as NewTopicSituation, { materialKind: "none" }),
    );
    // 沒選投入程度：只有基本行＋見面行＋「我們」。
    assertEquals(none.length, 3, situation);
  }
});

Deno.test("user prompt：沒有共同經歷的素材時不叫模型接上次／用約會裡的事", () => {
  const shared = [
    { materialKind: "past_topic", materialText: "她說在準備潛水證照" },
    { materialKind: "inside_joke", materialText: "她說我的五分鐘都是半小時" },
  ];
  const notShared = [
    {},
    { materialKind: "none" },
    { materialKind: "trigger", materialText: "路過浮誇甜點店" },
    { materialKind: "my_story", materialText: "走錯分店" },
  ];
  const daysShared =
    "幾天到一週沒聊：直接接素材裡那件事，像昨天才聊過；不說好久沒聊。";
  const daysFresh =
    "幾天到一週沒聊：像昨天才聊過一樣自然，直接帶一個新東西；不說好久沒聊，也不假裝接上次的話題。";
  const afterDate = {
    green: [
      "約完她主動傳訊息或說開心：用約會裡的事或梗延續，可以輕提「下次」，但不約時間。",
      "約完她主動傳訊息或說開心：延續約會的好心情，可以輕提「下次」，但不約時間；你不知道約會細節，不編約會裡發生的事。",
    ],
    yellow: [
      "約完她反應普通：用約會裡一件小事輕輕接，不問她覺得你怎樣，先不約下次。",
      "約完她反應普通：輕輕帶一個新東西，不問她覺得你怎樣，先不約下次；不編約會裡發生的事。",
    ],
  } as const;
  for (
    const [material, sharedHistory] of [
      ...shared.map((raw) => [raw, true] as const),
      ...notShared.map((raw) => [raw, false] as const),
    ]
  ) {
    const label = JSON.stringify(material);
    const days = situationRules(
      promptFor("went_cold", { coldDuration: "days", ...material }),
    );
    assert(days.includes(sharedHistory ? daysShared : daysFresh), label);
    // 剛約完會的基本行也一樣：素材沒寫約會裡的事，就只知道剛約完（nt3 盲測 B6）。
    const afterDateBase = situationRules(
      promptFor("after_date", { materialKind: "none", ...material }),
    )[0];
    assert(
      afterDateBase.startsWith(
        sharedHistory ? "剛約完會：承接約會的餘溫" : "剛約完會：你只知道剛約完",
      ),
      `${label}/after_date`,
    );
    for (const engagement of ["green", "yellow"] as const) {
      const rules = situationRules(
        promptFor("after_date", { engagement, ...material }),
      );
      assert(
        rules.includes(afterDate[engagement][sharedHistory ? 0 : 1]),
        `${label}/${engagement}`,
      );
    }
  }
  // red 不分有沒有共同經歷。
  assert(
    hasRule(
      situationRules(promptFor("after_date", { engagement: "red" })),
      "約完她還沒回或很冷淡：",
    ),
  );
});

Deno.test("user prompt：想更靠近＋她很投入，只有寫了你們的梗才回勾曖昧梗", () => {
  const joke = situationRules(
    promptFor("warm_up", {
      engagement: "green",
      materialKind: "inside_joke",
      materialText: "她說我的五分鐘都是半小時",
    }),
  );
  assert(joke.includes(
    "她很投入：可以加個人感——具體稱讚、「我們」一起做某件事的小想像、輕輕回勾你們的曖昧梗；不突然告白、不越界。",
  ));
  for (
    const material of [
      {},
      { materialKind: "past_topic", materialText: "她說在準備潛水證照" },
      { materialKind: "none" },
    ]
  ) {
    const rules = situationRules(
      promptFor("warm_up", { engagement: "green", ...material }),
    );
    assert(
      rules.includes(
        "她很投入：可以加個人感——具體稱讚、「我們」一起做某件事的小想像；不突然告白、不越界。",
      ),
      JSON.stringify(material),
    );
    assertFalse(rules.some((rule) => rule.includes("曖昧梗")));
  }
});

Deno.test("user prompt：原文裡的「」換成『』，指紋仍用原值", async () => {
  const raw = {
    materialKind: "inside_joke",
    materialText: "她說「五分鐘」都是半小時",
  };
  const prompt = promptFor("stuck", raw);
  assert(prompt.includes("- 原文：「她說『五分鐘』都是半小時」\n"));
  assertEquals(context(raw, "stuck").materialText, "她說「五分鐘」都是半小時");
  const hashOf = (materialText: string) =>
    computeNewTopicInputHash({
      userId: USER_ID,
      partnerSummary: null,
      effectiveStyleContext: null,
      situation: "stuck",
      secret: STRONG_KEY,
      topicContext: { ...context(raw, "stuck"), materialText },
    });
  assertFalse(
    await hashOf("她說「五分鐘」都是半小時") ===
      await hashOf("她說『五分鐘』都是半小時"),
  );
});

Deno.test("user prompt：「我們」那一行永遠在局面最後，跟輸出守門同一個判準", () => {
  const cases: Array<
    [string | null, NewTopicSituation | null, Record<string, unknown>, boolean]
  > = [
    [null, "warm_up", { engagement: "green" }, true],
    [null, "warm_up", { engagement: "yellow" }, false],
    [null, "after_date", { materialKind: "none" }, true],
    [null, "stuck", {
      engagement: "yellow",
      materialKind: "my_story",
      materialText: "走錯分店",
    }, false],
    [null, "stuck", {
      materialKind: "inside_joke",
      materialText: "她說我的五分鐘都是半小時",
    }, true],
    [null, "went_cold", { coldDuration: "weeks" }, false],
    ["[對象作戰板：Miya]\n- 你的備註：聊得來但還沒約", "stuck", {
      engagement: "green",
    }, true],
  ];
  for (const [partnerSummary, situation, raw, expected] of cases) {
    const topicContext = context(raw, situation);
    assertEquals(
      allowsNewTopicSharedFrame({ partnerSummary, situation, topicContext }),
      expected,
    );
    const rules = situationRules(
      slotsPrompt({
        partnerSummary,
        effectiveStyleContext: null,
        situation,
        topicContext,
        requestId: REQUEST_ID,
      }),
    );
    assertEquals(
      rules.at(-1),
      expected ? SHARED_FRAME_ALLOWED_LINE : SHARED_FRAME_DENIED_LINE,
      `${situation} ${JSON.stringify(raw)}`,
    );
  }
});

Deno.test("user prompt：見面行（只有約完／想靠近＋她很投入才可提）", () => {
  const allowed = "見面：nextMove 可以提「聊熱了再從話題帶出見面";
  const denied = "見面：五題的第一則都不約，nextMove 也不建議約她。";
  for (const situation of ["after_date", "warm_up"] as const) {
    assert(
      hasRule(
        situationRules(promptFor(situation, { engagement: "green" })),
        allowed,
      ),
    );
    assert(
      hasRule(
        situationRules(promptFor(situation, { engagement: "yellow" })),
        denied,
      ),
    );
  }
  assert(
    hasRule(
      situationRules(promptFor("stuck", { engagement: "green" })),
      denied,
    ),
  );
  assert(
    hasRule(
      situationRules(promptFor("went_cold", { coldDuration: "days" })),
      denied,
    ),
  );
  assert(
    hasRule(situationRules(promptFor(null, { materialKind: "none" })), denied),
  );
});

Deno.test("user prompt：偏冷補一行（冷掉了或投入 yellow／red）", () => {
  const line = "nextMove 多寫一句：她沒回就別追，只回很短就自然收掉。";
  const has = (
    situation: NewTopicSituation | null,
    raw: Record<string, unknown>,
  ) => situationRules(promptFor(situation, raw)).includes(line);
  assert(has("went_cold", { coldDuration: "days" }));
  assert(has("stuck", { engagement: "yellow" }));
  assert(has("after_date", { engagement: "red" }));
  assertFalse(has("warm_up", { engagement: "green" }));
  assertFalse(has("stuck", { materialKind: "none" }));
  assertFalse(has(null, { materialKind: "none" }));
});

Deno.test("user prompt（基本模式）：沒帶 topicContext → 局面只有狀況那幾行、素材段明說沒有、沒有換個方向段", () => {
  const meet = "見面：五題的第一則都不約，nextMove 也不建議約她。";
  const expected: Array<[NewTopicSituation | null, string, string[]]> = [
    [null, "沒有選", [
      "沒選狀況：當作日常重啟，自然、低壓、好接。",
      meet,
      SHARED_FRAME_DENIED_LINE,
    ]],
    ["went_cold", "冷掉了，想重新聊", [
      "冷掉了：低壓重啟。不責問對方消失、不陰陽怪氣、不討拍；openingLine 收在 30 字內，像順手丟的。",
      "沒說多久：有內容、低壓力、不追討；不提很久沒聊。",
      meet,
      "nextMove 多寫一句：她沒回就別追，只回很短就自然收掉。",
      SHARED_FRAME_DENIED_LINE,
    ]],
    ["stuck", "還在聊，但接不下去", [
      "還在聊但接不下去：換一個角度或場景，一次只開一條線，不像面試連環問，不重複舊話題。",
      meet,
      SHARED_FRAME_DENIED_LINE,
    ]],
    ["after_date", "剛約完會", [
      "剛約完會：你只知道剛約完，不知道去了哪、做了什麼、聊了什麼——不寫地點、店家、當時的互動或她的反應；餘溫只用一句不帶細節的話，或直接帶一個新東西。不急著約第二次，不索取評價（不問她覺得你怎樣）。",
      meet,
      SHARED_FRAME_ALLOWED_LINE,
    ]],
    ["warm_up", "聊得不錯，想更靠近", [
      "聊得不錯想更靠近：可以多一點個人感，但不突然告白、不越界。",
      meet,
      SHARED_FRAME_DENIED_LINE,
    ]],
  ];
  for (const [situation, label, rules] of expected) {
    const prompt = slotsPrompt({
      partnerSummary: "[對象作戰板：Miya]\n- 興趣：咖啡、爬山",
      effectiveStyleContext: null,
      situation,
      topicContext: null,
      requestId: REQUEST_ID,
    });
    assert(
      prompt.includes(
        `## 這次的局面（用戶自己說的現況，照這裡的做法寫）\n- 狀況：${label}\n做法：\n`,
      ),
    );
    assertEquals(situationRules(prompt), rules, String(situation));
    assert(
      prompt.includes("（沒有：這次不寫用戶做過、看過或遇過的事）"),
      String(situation),
    );
    assertFalse(prompt.includes("- 多久沒聊："), String(situation));
    assertFalse(prompt.includes("本輪換個方向"), String(situation));
    assert(prompt.endsWith("請依系統規則產出恰好五個新話題的 JSON。"));
    // 全 null 的答案與沒帶 topicContext 產出相同的提示詞。
    assertEquals(
      prompt,
      slotsPrompt({
        partnerSummary: "[對象作戰板：Miya]\n- 興趣：咖啡、爬山",
        effectiveStyleContext: null,
        situation,
        topicContext: {
          coldDuration: null,
          coldStop: null,
          engagement: null,
          materialKind: null,
          materialText: null,
        },
        requestId: REQUEST_ID,
      }),
    );
  }
});

Deno.test("今天：台灣時間的日期與星期（跨午夜照台灣算）", () => {
  // 2026-10-04 15:59 UTC＝台灣 10/4（週日）23:59；16:30 UTC＝台灣 10/5（週一）00:30。
  assertEquals(
    newTopicTodayLabel(Date.UTC(2026, 9, 4, 15, 59)),
    "2026 年 10 月 4 日（週日）",
  );
  assertEquals(
    newTopicTodayLabel(Date.UTC(2026, 9, 4, 16, 30)),
    "2026 年 10 月 5 日（週一）",
  );
  assertEquals(
    newTopicTodayLabel(Date.UTC(2027, 0, 1, 3, 0)),
    "2027 年 1 月 1 日（週五）",
  );
});

Deno.test("user prompt：所有合法組合都不出現任何 enum 代碼", () => {
  const codes = new RegExp(
    `\\b(?:${
      [
        "went_cold",
        "after_date",
        "stuck",
        "warm_up",
        ...NEW_TOPIC_COLD_DURATIONS,
        ...NEW_TOPIC_COLD_STOPS,
        ...NEW_TOPIC_ENGAGEMENTS,
        ...NEW_TOPIC_MATERIAL_KINDS,
      ].join("|")
    })\\b`,
  );
  let checked = 0;
  for (
    const situation of [
      null,
      "went_cold",
      "stuck",
      "after_date",
      "warm_up",
    ] as const
  ) {
    for (const coldDuration of [null, ...NEW_TOPIC_COLD_DURATIONS]) {
      for (const coldStop of [null, ...NEW_TOPIC_COLD_STOPS]) {
        for (const engagement of [null, ...NEW_TOPIC_ENGAGEMENTS]) {
          for (const materialKind of [null, ...NEW_TOPIC_MATERIAL_KINDS]) {
            const raw: Record<string, unknown> = {
              coldDuration,
              coldStop,
              engagement,
              materialKind,
            };
            if (materialKind !== null && materialKind !== "none") {
              raw.materialText = "一句筆記";
            }
            const result = sanitizeNewTopicTopicContext(raw, situation);
            if (!result.ok || result.topicContext === null) continue;
            const prompt = slotsPrompt({
              partnerSummary: null,
              effectiveStyleContext: null,
              situation,
              topicContext: result.topicContext,
              requestId: REQUEST_ID,
            });
            assertFalse(codes.test(prompt), prompt);
            // 收尾句的任務只出現在還在聊／想更靠近＋紅燈，而且是第一題。
            assertEquals(
              prompt.includes("\n1. 這一題不是開場，是收尾句"),
              isNewTopicRedClose(situation, result.topicContext),
              prompt,
            );
            assertEquals(
              prompt.includes("這一題不是開場，是收尾句"),
              isNewTopicRedClose(situation, result.topicContext),
              prompt,
            );
            // 規則行不含解釋欄守門會擋的詞；「我們」行與守門同一判準。
            assertFalse(
              hasCustomerExplanationLeak(prompt, PROMPT_CONTRACT_TERMS),
              prompt,
            );
            assertFalse(prompt.includes("球"), prompt);
            assertEquals(
              situationRules(prompt).at(-1),
              allowsNewTopicSharedFrame({
                  partnerSummary: null,
                  situation,
                  topicContext: result.topicContext,
                })
                ? SHARED_FRAME_ALLOWED_LINE
                : SHARED_FRAME_DENIED_LINE,
            );
            checked++;
          }
        }
      }
    }
  }
  // 基本模式（沒帶 topicContext）五種狀況走同一組檢查。
  for (
    const situation of [
      null,
      "went_cold",
      "stuck",
      "after_date",
      "warm_up",
    ] as const
  ) {
    const prompt = slotsPrompt({
      partnerSummary: null,
      effectiveStyleContext: null,
      situation,
      topicContext: null,
      requestId: REQUEST_ID,
    });
    assertFalse(codes.test(prompt), prompt);
    assertFalse(
      prompt.includes("推薦固定是第一題（recommendation.index 填 0）"),
      prompt,
    );
    assertFalse(
      hasCustomerExplanationLeak(prompt, PROMPT_CONTRACT_TERMS),
      prompt,
    );
    assertFalse(prompt.includes("球"), prompt);
    assertEquals(
      situationRules(prompt).at(-1),
      allowsNewTopicSharedFrame({
          partnerSummary: null,
          situation,
          topicContext: null,
        })
        ? SHARED_FRAME_ALLOWED_LINE
        : SHARED_FRAME_DENIED_LINE,
    );
    checked++;
  }
  assertEquals(checked, 198);
});

// ---------------------------------------------------------------------------
// §4.6 稽核（只記錄、不擋）
// ---------------------------------------------------------------------------

function topics(openingLines: string[]): NewTopicModelTopic[] {
  return openingLines.map((openingLine, index) => ({
    direction: `方向${index + 1}`,
    openingLine,
    whyItWorks: "好接",
    nextMove: "接著聊",
  }));
}

const PLAIN_LINES = [
  "今天吃到超酸的檸檬",
  "我剛學會煮咖啡",
  "路上看到一隻胖貓",
  "辦公室冷氣太強",
  "週末想去看海",
];

function audit(
  openingLines: string[],
  raw: Record<string, unknown> = { materialKind: "none" },
  situation: NewTopicSituation | null = "went_cold",
  recommendationIndex = 0,
) {
  return auditNewTopicTwoStageTopics({
    topics: topics(openingLines),
    recommendationIndex,
    topicContext: context(raw, situation),
    situation,
  });
}

Deno.test("audit：素材使用（≥2 個中文二字詞或 ≥1 個英文字），沒有原文為 null", () => {
  const raw = {
    materialKind: "past_topic",
    materialText: "她說在準備潛水證照",
  };
  const lines = [
    "潛水證照考到哪了",
    "準備潛水好累吧",
    "我也想學潛水",
    ...PLAIN_LINES.slice(0, 2),
  ];
  const used = audit(lines, raw);
  assertEquals(used.materialUsedInRecommended, true);
  // 「我也想學潛水」只共享一個二字詞（潛水）不算。
  assertEquals(used.topicsUsingMaterial, 2);
  assertEquals(
    audit(lines, raw, "went_cold", 2).materialUsedInRecommended,
    false,
  );

  const english = audit(
    ["Netflix 那部看完了嗎", ...PLAIN_LINES.slice(0, 4)],
    { materialKind: "trigger", materialText: "她發限動在追 netflix 新劇" },
  );
  assertEquals(english.materialUsedInRecommended, true);
  assertEquals(english.topicsUsingMaterial, 1);

  const noText = audit(PLAIN_LINES);
  assertEquals(noText.materialUsedInRecommended, null);
  assertEquals(noText.topicsUsingMaterial, null);
});

Deno.test("audit：空窗、禁用開場、邀約、道歉、多 emoji 各自計數", () => {
  const clean = audit(PLAIN_LINES);
  assertEquals(clean.gapMentionLines, 0);
  assertEquals(clean.bannedOpenerLines, 0);
  assertEquals(clean.inviteLines, 0);
  assertEquals(clean.apologyLines, 0);
  assertEquals(clean.multiEmojiLines, 0);

  const dirty = audit([
    "好久沒聊了欸",
    "在嗎 有件事想跟妳說",
    "下週約妳去看展",
    "Sorry 上次沒回",
    "今天超開心😂🎉",
  ]);
  assertEquals(dirty.gapMentionLines, 1);
  assertEquals(dirty.bannedOpenerLines, 1);
  assertEquals(dirty.inviteLines, 1);
  assertEquals(dirty.apologyLines, 1);
  assertEquals(dirty.multiEmojiLines, 1);
  // 單一 emoji 不算；ZWJ 家庭、國旗以 grapheme 計各算一個。
  for (const single of ["只有一個😂", "全家出動👨‍👩‍👧", "台灣隊加油🇹🇼"]) {
    assertEquals(
      audit([single, ...PLAIN_LINES.slice(1)]).multiEmojiLines,
      0,
      single,
    );
  }
  assertEquals(
    audit(["兩面國旗🇹🇼🇯🇵", ...PLAIN_LINES.slice(1)]).multiEmojiLines,
    1,
  );
});

Deno.test("audit：gapMentionAllowed 跟提示詞同一套判準", () => {
  assert(audit(PLAIN_LINES, { coldDuration: "month_plus" }).gapMentionAllowed);
  assertFalse(
    audit(PLAIN_LINES, { coldDuration: "month_plus", coldStop: "she_no_reply" })
      .gapMentionAllowed,
  );
  assertFalse(
    audit(PLAIN_LINES, { engagement: "green" }, "stuck").gapMentionAllowed,
  );
});

Deno.test("audit：基本模式（沒帶 topicContext）也能記，素材相關欄位為 null、不是紅燈收尾", () => {
  const result = auditNewTopicTwoStageTopics({
    topics: topics(["好久沒聊了吧", ...PLAIN_LINES.slice(1)]),
    recommendationIndex: 0,
    topicContext: null,
    situation: "went_cold",
  });
  assertEquals(result.materialUsedInRecommended, null);
  assertEquals(result.topicsUsingMaterial, null);
  assertEquals(result.gapMentionLines, 1);
  assertFalse(result.gapMentionAllowed);
  assertFalse(result.redCloseApplied);
  assertEquals(result.redCloseCueInFirst, null);
  assertEquals(
    auditNewTopicTwoStageTopics({
      topics: topics(PLAIN_LINES),
      recommendationIndex: 0,
      topicContext: null,
      situation: "stuck",
    }).redCloseApplied,
    false,
  );
});

Deno.test("audit：回傳只有數字／布林／null，不含原文", () => {
  const result = audit(PLAIN_LINES, {
    materialKind: "my_story",
    materialText: "走錯分店",
  });
  for (const value of Object.values(result)) {
    assert(
      value === null || typeof value === "number" || typeof value === "boolean",
    );
  }
});

// ---------------------------------------------------------------------------
// §4.7 telemetry
// ---------------------------------------------------------------------------

Deno.test("telemetry：基本與進階欄位，只記代碼與字數不記原文", () => {
  assertEquals(newTopicTwoStageTelemetry(null), {
    promptVariant: "basic",
    promptVersion: "new-topic-slots-v1",
    coldDuration: null,
    coldStop: null,
    engagement: null,
    materialKind: null,
    materialTextLength: 0,
  });
  const fields = newTopicTwoStageTelemetry(
    context(
      {
        coldDuration: "weeks",
        coldStop: "faded",
        materialKind: "my_story",
        materialText: "走錯分店👨‍👩‍👧",
      },
      "went_cold",
    ),
  );
  assertEquals(fields, {
    promptVariant: "advanced",
    promptVersion: "new-topic-slots-v1",
    coldDuration: "weeks",
    coldStop: "faded",
    engagement: null,
    materialKind: "my_story",
    materialTextLength: 5,
  });
  assertFalse(JSON.stringify(fields).includes("走錯分店"));
});

Deno.test("sanitize：看起來空白的填充字（U+3164／U+2800 等）也拿掉，擋字不會被拆開躲過", () => {
  for (const filler of ["ㅤ", "⠀", "ᅟ", "ᅠ", "ﾠ"]) {
    const result = sanitizeNewTopicTopicContext(
      { materialKind: "my_story", materialText: `打${filler}炮` },
      null,
    );
    assert(result.ok);
    assertEquals(result.topicContext?.materialText, "打炮");
  }
});

const RED_CLOSE_RULES = {
  stuck: "她常只回哈哈、嗯：其他題也都很輕、很短，不連問、不加曖昧。",
  warm_up: "她常只回哈哈、嗯：現在不升溫，其他題也只給輕的；不加曖昧、不約。",
} as const;

Deno.test("user prompt：她常只回哈哈、嗯（stuck／warm_up 紅燈）第一題寫成收尾、推薦固定第一題（規格 §9.4）", () => {
  for (const situation of ["stuck", "warm_up"] as const) {
    const rules = situationRules(
      promptFor(situation, { engagement: "red", materialKind: "none" }),
    );
    assert(rules.includes(RED_CLOSE_RULES[situation]), situation);
    assert(
      promptFor(situation, { engagement: "red", materialKind: "none" })
        .includes("\n1. 這一題不是開場，是收尾句"),
      situation,
    );
  }
  // 其他燈號與約完會的紅燈不變。
  assertEquals(
    situationRules(promptFor("stuck", { engagement: "yellow" }))[1],
    "她有回但很短：不加長、不連問，給好回的小題目（選邊、當裁判）。",
  );
  assertEquals(
    situationRules(promptFor("warm_up", { engagement: "yellow" }))[1],
    "她有回但普通：先讓聊天重新好玩，不加曖昧。",
  );
  assertEquals(
    situationRules(promptFor("after_date", { engagement: "red" }))[1],
    "約完她還沒回或很冷淡：最多一則輕鬆的內容，她沒接就先停；不追問感受、不約下次。",
  );
});

Deno.test("enforceNewTopicRedClose：紅燈收尾推薦固定第一題、理由換固定句；其他不動", () => {
  const red = (situation: NewTopicSituation | null) => ({
    situation,
    topicContext: context({ engagement: "red" }, situation),
  });
  type Recommendation = {
    recommendationIndex: number;
    recommendationReason: string | null;
  };
  const picked2: Recommendation = {
    recommendationIndex: 2,
    recommendationReason: "寫給第三題的理由",
  };
  for (const situation of ["stuck", "warm_up"] as const) {
    const fixed = {
      recommendationIndex: 0,
      recommendationReason: NEW_TOPIC_RED_CLOSE_REASON,
    };
    assertEquals(enforceNewTopicRedClose(picked2, red(situation)), {
      normalized: fixed,
      applied: true,
      overridden: true,
    });
    // 模型自己推第一題：理由也換（模型寫的理由會漏指示措辭，nt2-red-r2）。
    const picked0: Recommendation = {
      recommendationIndex: 0,
      recommendationReason: "照局面規定第一題要是收尾句",
    };
    assertEquals(enforceNewTopicRedClose(picked0, red(situation)), {
      normalized: fixed,
      applied: true,
      overridden: false,
    });
  }
  // 約完會紅燈、黃燈、沒有 topicContext（legacy）都不動。
  for (
    const input of [
      red("after_date"),
      {
        situation: "stuck" as const,
        topicContext: context({ engagement: "yellow" }, "stuck"),
      },
      { situation: "stuck" as const, topicContext: null },
    ]
  ) {
    assertEquals(enforceNewTopicRedClose(picked2, input), {
      normalized: picked2,
      applied: false,
      overridden: false,
    });
  }
  // 固定句本身要過客戶可見理由的 cap 與外洩檢查。
  assert(
    NEW_TOPIC_RED_CLOSE_REASON.length <=
      NEW_TOPIC_FIELD_CAPS.recommendationReason,
  );
  assertFalse(hasCustomerExplanationLeak(NEW_TOPIC_RED_CLOSE_REASON));
  // 其他欄位原樣帶過。
  const withTopics = { ...picked2, topics: topics(PLAIN_LINES) };
  assertEquals(
    enforceNewTopicRedClose(withTopics, red("stuck")).normalized.topics,
    withTopics.topics,
  );
});

Deno.test("audit：紅燈收尾標記與第一題收尾字眼（只記 0／1，不是紅燈收尾為 null）", () => {
  const closing = ["我先去忙，晚點再跟妳說", ...PLAIN_LINES.slice(1)];
  const redStuck = audit(closing, { engagement: "red" }, "stuck");
  assertEquals(redStuck.redCloseApplied, true);
  assertEquals(redStuck.redCloseCueInFirst, 1);
  const noCue = audit(PLAIN_LINES, { engagement: "red" }, "warm_up");
  assertEquals(noCue.redCloseApplied, true);
  assertEquals(noCue.redCloseCueInFirst, 0);
  // 收尾字眼只看第一題。
  assertEquals(
    audit(
      [...PLAIN_LINES.slice(0, 4), "改天再聊"],
      { engagement: "red" },
      "stuck",
    )
      .redCloseCueInFirst,
    0,
  );
  for (
    const [raw, situation] of [
      [{ engagement: "red" }, "after_date"],
      [{ engagement: "yellow" }, "stuck"],
      [{ materialKind: "none" }, "went_cold"],
    ] as const
  ) {
    const result = audit(closing, raw, situation);
    assertEquals(result.redCloseApplied, false, situation);
    assertEquals(result.redCloseCueInFirst, null, situation);
  }
});
