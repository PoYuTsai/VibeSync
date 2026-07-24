import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildNewTopicLedgerResult,
  hasNewTopicMaterial,
  isValidNewTopicLedgerResult,
  NEW_TOPIC_FIELD_CAPS,
  NEW_TOPIC_PARTNER_SUMMARY_MAX,
  NEW_TOPIC_SITUATIONS,
  NEW_TOPIC_STYLE_CONTEXT_MAX,
  type NewTopicModelTopic,
  normalizeNewTopicModelPayload,
  sanitizeNewTopicRequest,
} from "./new_topic_payload.ts";

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";

function validBody(): Record<string, unknown> {
  return {
    mode: "new_topic",
    requestId: REQUEST_ID,
    partnerSummary: "對象：小雅。熱度 72。興趣：爬山、手沖咖啡。",
    effectiveStyleContext: "- 偏好語氣：輕鬆幽默",
    situation: "went_cold",
    expectedTier: "free",
    revenueCatAppUserId: "$RCAnonymousID:abc",
  };
}

function modelTopics(): NewTopicModelTopic[] {
  return [1, 2, 3, 4, 5].map((n) => ({
    direction: `方向${n}`,
    openingLine: `開場句${n}`,
    whyItWorks: `因為${n}`,
    nextMove: `下一步${n}`,
  }));
}

// ---------------------------------------------------------------------------
// sanitizeNewTopicRequest
// ---------------------------------------------------------------------------

Deno.test("sanitize：合法 request 全欄位正規化", () => {
  const result = sanitizeNewTopicRequest(validBody());
  assert(result.ok);
  assertEquals(result.request.requestId, REQUEST_ID);
  assertEquals(result.request.situation, "went_cold");
  assertEquals(result.request.expectedTier, "free");
});

Deno.test("sanitize：requestId 必須是 canonical UUID", () => {
  for (const bad of [undefined, null, "", "not-a-uuid", 123]) {
    const body = validBody();
    body.requestId = bad;
    const result = sanitizeNewTopicRequest(body);
    assertFalse(result.ok, `requestId=${bad} 應拒絕`);
  }
});

Deno.test("sanitize：大小寫混寫 UUID 正規化成小寫", () => {
  const body = validBody();
  body.requestId = REQUEST_ID.toUpperCase();
  const result = sanitizeNewTopicRequest(body);
  assert(result.ok);
  assertEquals(result.request.requestId, REQUEST_ID);
});

Deno.test("sanitize：禁用欄位一律拒絕、不靜默忽略", () => {
  const forbidden: Array<[string, unknown]> = [
    ["images", [{ data: "x" }]],
    ["messages", [{ content: "hi" }]],
    ["profileInfo", { name: "x" }],
    ["userDraft", "草稿"],
    ["recognizeOnly", true],
    ["sessionContext", { turns: [] }],
    ["conversationSummary", "摘要"],
  ];
  for (const [key, value] of forbidden) {
    const body = validBody();
    body[key] = value;
    const result = sanitizeNewTopicRequest(body);
    assertFalse(result.ok, `${key} 應拒絕`);
  }
});

Deno.test("sanitize：空 messages 陣列可容忍、recognizeOnly true 拒絕 false 為未知鍵拒絕", () => {
  const bodyEmpty = validBody();
  bodyEmpty.messages = [];
  // 空 messages 不觸發 messages_forbidden，但 messages 不在 allowlist →
  // unknown_field 拒絕（allowlist 之外一律不靜默忽略）。
  assertFalse(sanitizeNewTopicRequest(bodyEmpty).ok);

  const bodyFalse = validBody();
  bodyFalse.recognizeOnly = false;
  assertFalse(sanitizeNewTopicRequest(bodyFalse).ok);
});

Deno.test("sanitize：未列入 allowlist 的業務欄位拒絕", () => {
  const body = validBody();
  body.analyzeMode = "full";
  assertFalse(sanitizeNewTopicRequest(body).ok);
});

Deno.test("sanitize：situation 只吃四個 enum、自由輸入拒絕", () => {
  assertEquals(NEW_TOPIC_SITUATIONS, [
    "went_cold",
    "after_date",
    "stuck",
    "warm_up",
  ]);
  const body = validBody();
  body.situation = "她生日快到了";
  assertFalse(sanitizeNewTopicRequest(body).ok);

  const bodyOk = validBody();
  delete bodyOk.situation;
  const result = sanitizeNewTopicRequest(bodyOk);
  assert(result.ok);
  assertEquals(result.request.situation, null);
});

Deno.test("sanitize：長度上限（partnerSummary 2000 / styleContext 1200）", () => {
  const body = validBody();
  body.partnerSummary = "甲".repeat(NEW_TOPIC_PARTNER_SUMMARY_MAX + 1);
  assertFalse(sanitizeNewTopicRequest(body).ok);

  const body2 = validBody();
  body2.effectiveStyleContext = "乙".repeat(NEW_TOPIC_STYLE_CONTEXT_MAX + 1);
  assertFalse(sanitizeNewTopicRequest(body2).ok);
});

Deno.test("sanitize：空白字串正規化為 null", () => {
  const body = validBody();
  body.partnerSummary = "   ";
  body.effectiveStyleContext = "";
  delete body.situation;
  const result = sanitizeNewTopicRequest(body);
  assert(result.ok);
  assertEquals(result.request.partnerSummary, null);
  assertEquals(result.request.effectiveStyleContext, null);
});

// ---------------------------------------------------------------------------
// hasNewTopicMaterial
// ---------------------------------------------------------------------------

Deno.test("material：三類至少一類有實質內容才可生成", () => {
  const base = {
    requestId: REQUEST_ID,
    partnerSummary: null,
    effectiveStyleContext: null,
    situation: null,
    expectedTier: null,
    revenueCatAppUserId: null,
  } as const;
  assertFalse(hasNewTopicMaterial({ ...base }));
  assert(hasNewTopicMaterial({ ...base, partnerSummary: "對象摘要" }));
  assert(hasNewTopicMaterial({ ...base, effectiveStyleContext: "風格" }));
  assert(hasNewTopicMaterial({ ...base, situation: "stuck" }));
});

// ---------------------------------------------------------------------------
// normalizeNewTopicModelPayload
// ---------------------------------------------------------------------------

Deno.test("normalize：合法五題通過", () => {
  const result = normalizeNewTopicModelPayload({
    topics: modelTopics(),
    recommendation: { index: 2, reason: "最貼近她的近況" },
  });
  assert(result.ok);
  assertEquals(result.topics.length, 5);
  assertEquals(result.recommendationIndex, 2);
  assertEquals(result.recommendationReason, "最貼近她的近況");
});

Deno.test("normalize：項數不是五整份失敗（不可丟壞題續走）", () => {
  assertFalse(
    normalizeNewTopicModelPayload({
      topics: modelTopics().slice(0, 4),
      recommendation: { index: 0 },
    }).ok,
    "topics=4 應整份失敗",
  );
  assertFalse(
    normalizeNewTopicModelPayload({
      topics: [...modelTopics(), {
        direction: "方向6",
        openingLine: "開場句6",
        whyItWorks: "因為6",
        nextMove: "下一步6",
      }],
      recommendation: { index: 0 },
    }).ok,
    "topics=6 應整份失敗",
  );
});

Deno.test("normalize：缺欄／空白／超長整份失敗", () => {
  const missing = modelTopics();
  // deno-lint-ignore no-explicit-any
  delete (missing[3] as any).nextMove;
  assertFalse(
    normalizeNewTopicModelPayload({
      topics: missing,
      recommendation: { index: 0 },
    }).ok,
  );

  const blank = modelTopics();
  blank[1].whyItWorks = "   ";
  assertFalse(
    normalizeNewTopicModelPayload({
      topics: blank,
      recommendation: { index: 0 },
    }).ok,
  );

  const tooLong = modelTopics();
  tooLong[0].openingLine = "丙".repeat(NEW_TOPIC_FIELD_CAPS.openingLine + 1);
  assertFalse(
    normalizeNewTopicModelPayload({
      topics: tooLong,
      recommendation: { index: 0 },
    }).ok,
  );
});

Deno.test("normalize：direction/openingLine 重複（含空白差異）整份失敗", () => {
  const dupDirection = modelTopics();
  dupDirection[4].direction = ` ${dupDirection[0].direction} `;
  assertFalse(
    normalizeNewTopicModelPayload({
      topics: dupDirection,
      recommendation: { index: 0 },
    }).ok,
  );

  const dupOpening = modelTopics();
  dupOpening[3].openingLine = dupOpening[1].openingLine.toUpperCase();
  assertFalse(
    normalizeNewTopicModelPayload({
      topics: dupOpening,
      recommendation: { index: 0 },
    }).ok,
  );
});

Deno.test("normalize：code fence／raw JSON 洩漏判缺", () => {
  const fenced = modelTopics();
  fenced[2].openingLine = '```json {"openingLine":"hi"} ```';
  assertFalse(
    normalizeNewTopicModelPayload({
      topics: fenced,
      recommendation: { index: 0 },
    }).ok,
  );

  const jsonLeak = modelTopics();
  jsonLeak[0].whyItWorks = '{"topics": []}';
  assertFalse(
    normalizeNewTopicModelPayload({
      topics: jsonLeak,
      recommendation: { index: 0 },
    }).ok,
  );
});

Deno.test("normalize：recommendation index 非 0-4 整數拒絕；reason 選填", () => {
  for (const bad of [-1, 5, 1.5, "2", null, undefined]) {
    assertFalse(
      normalizeNewTopicModelPayload({
        topics: modelTopics(),
        recommendation: { index: bad },
      }).ok,
      `index=${bad} 應拒絕`,
    );
  }

  const noReason = normalizeNewTopicModelPayload({
    topics: modelTopics(),
    recommendation: { index: 0 },
  });
  assert(noReason.ok);
  assertEquals(noReason.recommendationReason, null);

  assertFalse(
    normalizeNewTopicModelPayload({
      topics: modelTopics(),
      recommendation: {
        index: 0,
        reason: "丁".repeat(NEW_TOPIC_FIELD_CAPS.recommendationReason + 1),
      },
    }).ok,
  );
});

// ---------------------------------------------------------------------------
// buildNewTopicLedgerResult＋isValidNewTopicLedgerResult
// ---------------------------------------------------------------------------

Deno.test("build：paid 五題全存、推薦排第一、topicId 不因排序重算", () => {
  const result = buildNewTopicLedgerResult({
    topics: modelTopics(),
    recommendationIndex: 2,
    recommendationReason: "理由",
    servedTier: "essential",
    formulaTopics: [],
  });
  assertEquals(result.topics.length, 5);
  assertEquals(result.topics[0].id, "nt_3");
  assertEquals(result.topics[0].direction, "方向3");
  assertEquals(
    result.topics.map((t) => t.id),
    ["nt_3", "nt_1", "nt_2", "nt_4", "nt_5"],
  );
  assertEquals(result.recommendation, { topicId: "nt_3", reason: "理由" });
  assertEquals(result.access, {
    servedTier: "essential",
    limited: false,
    totalCount: 5,
    unlockedCount: 5,
    lockedCount: 0,
  });
  assert(isValidNewTopicLedgerResult(result));
});

Deno.test("build：free 只存推薦一題，另外四題文字不落 ledger", () => {
  const result = buildNewTopicLedgerResult({
    topics: modelTopics(),
    recommendationIndex: 4,
    recommendationReason: null,
    servedTier: "free",
    formulaTopics: [],
  });
  assertEquals(result.topics.length, 1);
  assertEquals(result.topics[0].id, "nt_5");
  assertEquals(result.recommendation, { topicId: "nt_5" });
  assertEquals(result.access, {
    servedTier: "free",
    limited: true,
    totalCount: 5,
    unlockedCount: 1,
    lockedCount: 4,
  });
  const serialized = JSON.stringify(result);
  for (const hidden of ["開場句1", "開場句2", "開場句3", "開場句4"]) {
    assertFalse(serialized.includes(hidden), `${hidden} 不得落 ledger`);
  }
  assert(isValidNewTopicLedgerResult(result));
});

Deno.test("validate：頂層夾帶其他鍵、tier 投影不一致、推薦不存在都拒絕", () => {
  const paid = buildNewTopicLedgerResult({
    topics: modelTopics(),
    recommendationIndex: 0,
    recommendationReason: null,
    servedTier: "starter",
    formulaTopics: [],
  });

  assertFalse(
    isValidNewTopicLedgerResult({ ...paid, usage: { cost: 3 } }),
    "頂層多 usage 鍵應拒絕",
  );

  const wrongCounts = structuredClone(paid) as Record<string, unknown>;
  // deno-lint-ignore no-explicit-any
  (wrongCounts.access as any).lockedCount = 4;
  assertFalse(isValidNewTopicLedgerResult(wrongCounts));

  const freeWithFive = structuredClone(paid) as Record<string, unknown>;
  // deno-lint-ignore no-explicit-any
  (freeWithFive.access as any).servedTier = "free";
  assertFalse(
    isValidNewTopicLedgerResult(freeWithFive),
    "free 存五題應拒絕（鎖定內容不得落地）",
  );

  const danglingRec = structuredClone(paid) as Record<string, unknown>;
  // deno-lint-ignore no-explicit-any
  (danglingRec.recommendation as any).topicId = "nt_9";
  assertFalse(isValidNewTopicLedgerResult(danglingRec));

  const extraTopicKey = structuredClone(paid) as Record<string, unknown>;
  // deno-lint-ignore no-explicit-any
  ((extraTopicKey.topics as any)[0] as any).prompt = "leak";
  assertFalse(
    isValidNewTopicLedgerResult(extraTopicKey),
    "topic 多任何一鍵應拒絕（防 prompt 滲入帳本）",
  );
});

// ---------------------------------------------------------------------------
// formulaTopics ledger 相容（2026-07-24 公式回覆計畫 §7.2/§7.3）
// ---------------------------------------------------------------------------

function formulaItem(n: number): Record<string, unknown> {
  return {
    openingLine: `公式開場句${n}，抓一個具體線索加一點我的反應。`,
    whyItWorks: `因為她可以順手補一個細節，不用想太久（${n}）。`,
  };
}

function ledgerWithFormula(
  servedTier: "free" | "essential",
  formulaTopics: unknown,
): Record<string, unknown> {
  const base = buildNewTopicLedgerResult({
    topics: modelTopics(),
    recommendationIndex: 0,
    recommendationReason: null,
    servedTier,
    formulaTopics: [],
  }) as unknown as Record<string, unknown>;
  return { ...base, formulaTopics };
}

Deno.test("validate formula：legacy 三-key 仍合法；四-key 0/1/2 則皆合法（Free/Paid）", () => {
  for (const tier of ["free", "essential"] as const) {
    // Legacy row（migration 前寫入）＝根本沒有 formulaTopics 鍵。
    const legacy = buildNewTopicLedgerResult({
      topics: modelTopics(),
      recommendationIndex: 0,
      recommendationReason: null,
      servedTier: tier,
      formulaTopics: [],
    }) as unknown as Record<string, unknown>;
    delete legacy.formulaTopics;
    assert(isValidNewTopicLedgerResult(legacy), `${tier} legacy 三-key 合法`);
    for (const count of [0, 1, 2]) {
      const stored = ledgerWithFormula(
        tier,
        [1, 2].slice(0, count).map(formulaItem),
      );
      assert(
        isValidNewTopicLedgerResult(stored),
        `${tier}＋formula ${count} 則應合法`,
      );
    }
  }
});

Deno.test("validate formula：三則、缺欄、多鍵、空白、非 array、非 object 全拒絕", () => {
  const cases: Array<[string, unknown]> = [
    ["三則", [formulaItem(1), formulaItem(2), formulaItem(3)]],
    ["缺 whyItWorks", [{ openingLine: "只有一欄" }]],
    ["多餘鍵", [{ ...formulaItem(1), nextMove: "leak" }]],
    ["openingLine 空白", [{ openingLine: "   ", whyItWorks: "理由" }]],
    ["whyItWorks 非 string", [{ openingLine: "句子", whyItWorks: 42 }]],
    ["非 array", { openingLine: "句子", whyItWorks: "理由" }],
    ["item 非 object", ["句子"]],
    ["null item", [null]],
  ];
  for (const [label, formula] of cases) {
    assertFalse(
      isValidNewTopicLedgerResult(ledgerWithFormula("essential", formula)),
      `${label} 應拒絕`,
    );
  }
});

Deno.test("validate formula：cap 以 Unicode code points 計（astral emoji 邊界）", () => {
  // 180 個 code points 的 openingLine（含 astral emoji）合法；181 拒絕。
  const emoji = "🀄"; // astral plane，UTF-16 length 2、code point 1
  const at180 = emoji.repeat(180);
  const at181 = emoji.repeat(181);
  assert(
    isValidNewTopicLedgerResult(ledgerWithFormula("essential", [
      { openingLine: at180, whyItWorks: "理由" },
    ])),
    "openingLine 180 code points 應合法",
  );
  assertFalse(
    isValidNewTopicLedgerResult(ledgerWithFormula("essential", [
      { openingLine: at181, whyItWorks: "理由" },
    ])),
    "openingLine 181 code points 應拒絕",
  );
  assertFalse(
    isValidNewTopicLedgerResult(ledgerWithFormula("essential", [
      { openingLine: "句子", whyItWorks: "多".repeat(301) },
    ])),
    "whyItWorks 301 code points 應拒絕",
  );
});

Deno.test("build：新 row 一律帶 formulaTopics（即使空）、0–2 則原封存入、>2 throw", () => {
  const empty = buildNewTopicLedgerResult({
    topics: modelTopics(),
    recommendationIndex: 0,
    recommendationReason: null,
    servedTier: "free",
    formulaTopics: [],
  });
  assert("formulaTopics" in empty, "新 row 必帶 formulaTopics 鍵");
  assertEquals(empty.formulaTopics, []);
  assert(isValidNewTopicLedgerResult(empty));

  const canonical = [
    { openingLine: "公式一", whyItWorks: "理由一" },
    { openingLine: "公式二", whyItWorks: "理由二" },
  ];
  const twoFree = buildNewTopicLedgerResult({
    topics: modelTopics(),
    recommendationIndex: 0,
    recommendationReason: null,
    servedTier: "free",
    formulaTopics: canonical,
  });
  // Free 只存推薦一題，但 formula 原封兩則（不投影）。
  assertEquals(twoFree.topics.length, 1);
  assertEquals(twoFree.formulaTopics, canonical);
  assert(isValidNewTopicLedgerResult(twoFree));

  let threw = false;
  try {
    buildNewTopicLedgerResult({
      topics: modelTopics(),
      recommendationIndex: 0,
      recommendationReason: null,
      servedTier: "free",
      formulaTopics: [
        ...canonical,
        { openingLine: "公式三", whyItWorks: "理由三" },
      ],
    });
  } catch {
    threw = true;
  }
  assert(threw, "formulaTopics >2 應 throw（上游 normalizer 出錯要炸出來）");
});

Deno.test("validate formula：code fence／raw JSON／schema 洩漏拒絕；formula 不改 tier 投影規則", () => {
  for (
    const leaked of [
      "```json",
      '{"formulaTopics":[]}',
      '看看 "openingline" 這個鍵',
    ]
  ) {
    assertFalse(
      isValidNewTopicLedgerResult(ledgerWithFormula("essential", [
        { openingLine: leaked, whyItWorks: "理由" },
      ])),
      `${leaked} 應拒絕`,
    );
  }
  // formula 合法也救不了 tier 投影錯誤（free 存五題仍拒絕）。
  const freeWithFive = ledgerWithFormula("essential", [formulaItem(1)]);
  // deno-lint-ignore no-explicit-any
  (freeWithFive.access as any).servedTier = "free";
  assertFalse(isValidNewTopicLedgerResult(freeWithFive));
});
