import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  allowsNewTopicSharedFrame,
  buildNewTopicLedgerResult,
  hasNewTopicMaterial,
  isValidNewTopicLedgerResult,
  mergeNewTopicRepairWithPrimaryOpeningLines,
  NEW_TOPIC_FIELD_CAPS,
  NEW_TOPIC_PARTNER_SUMMARY_MAX,
  NEW_TOPIC_SITUATIONS,
  NEW_TOPIC_STYLE_CONTEXT_MAX,
  type NewTopicModelTopic,
  normalizeNewTopicModelPayload,
  sanitizeNewTopicRequest,
} from "./new_topic_payload.ts";
import {
  NEW_TOPIC_MATERIAL_TEXT_MAX_CODE_UNITS,
  NEW_TOPIC_MATERIAL_TEXT_MAX_GRAPHEMES,
} from "./new_topic_two_stage.ts";

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

Deno.test("sanitize：App 的串流 envelope 不改變業務內容與 requestId", () => {
  const legacy = sanitizeNewTopicRequest(validBody());
  for (const responseMode of ["stream", "legacy"]) {
    const result = sanitizeNewTopicRequest({ ...validBody(), responseMode });
    assertEquals(result, legacy);
  }
});

Deno.test("sanitize：傳輸欄位仍嚴格驗證，不能放行任意模式或業務欄位", () => {
  for (const responseMode of [null, "", "quick", "full", "batch", 1, {}]) {
    assertFalse(sanitizeNewTopicRequest({ ...validBody(), responseMode }).ok);
  }
  assertFalse(
    sanitizeNewTopicRequest({
      ...validBody(),
      responseMode: "stream",
      userDraft: "不能繞過的欄位",
    }).ok,
  );
  assertFalse(
    sanitizeNewTopicRequest({
      ...validBody(),
      responseMode: "stream",
      unexpected: true,
    }).ok,
  );
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
// topicContext（2026-10-01 規格 §1）
// ---------------------------------------------------------------------------

function sanitizeContext(
  topicContext: unknown,
  situation: unknown = "went_cold",
) {
  return sanitizeNewTopicRequest({ ...validBody(), situation, topicContext });
}

function contextReason(topicContext: unknown, situation?: unknown): string {
  const result = sanitizeContext(topicContext, situation);
  assertFalse(result.ok, JSON.stringify(topicContext));
  return result.reason;
}

Deno.test("topicContext：缺席或 null＝沒有；其他非物件拒絕", () => {
  const absent = sanitizeNewTopicRequest(validBody());
  assert(absent.ok);
  assertEquals(absent.request.topicContext, null);
  const explicitNull = sanitizeContext(null);
  assert(explicitNull.ok);
  assertEquals(explicitNull.request.topicContext, null);
  for (const bad of ["x", 1, true, [], [{ materialKind: "none" }]]) {
    assertEquals(contextReason(bad), "topic_context_invalid");
  }
});

Deno.test("topicContext：只收五個鍵；空物件與全 null 拒絕", () => {
  assertEquals(
    contextReason({ materialKind: "none", mood: "happy" }),
    "topic_context_unknown_field:mood",
  );
  assertEquals(contextReason({}), "topic_context_empty");
  assertEquals(
    contextReason({ coldDuration: null, materialText: null }),
    "topic_context_empty",
  );
  const result = sanitizeContext({ materialKind: "none", coldStop: null });
  assert(result.ok);
  assertEquals(result.request.topicContext, {
    coldDuration: null,
    coldStop: null,
    engagement: null,
    materialKind: "none",
    materialText: null,
  });
});

Deno.test("topicContext：enum 值不在清單各自拒絕", () => {
  assertEquals(
    contextReason({ coldDuration: "year" }),
    "topic_context_cold_duration_invalid",
  );
  assertEquals(
    contextReason({ coldStop: "blocked" }),
    "topic_context_cold_stop_invalid",
  );
  assertEquals(
    contextReason({ engagement: "blue" }, "stuck"),
    "topic_context_engagement_invalid",
  );
  assertEquals(
    contextReason({ materialKind: "photo" }),
    "topic_context_material_kind_invalid",
  );
  assertEquals(
    contextReason({ materialKind: 1 }),
    "topic_context_material_kind_invalid",
  );
  const ok = sanitizeContext({ coldDuration: "weeks", coldStop: "she_cold" });
  assert(ok.ok);
  assertEquals(ok.request.topicContext?.coldDuration, "weeks");
  assertEquals(ok.request.topicContext?.coldStop, "she_cold");
});

Deno.test("topicContext：冷掉追問只能搭 went_cold", () => {
  for (const situation of ["stuck", "after_date", "warm_up", null]) {
    assertEquals(
      contextReason({ coldDuration: "days" }, situation),
      "topic_context_cold_fields_without_went_cold",
    );
    assertEquals(
      contextReason({ coldStop: "faded" }, situation),
      "topic_context_cold_fields_without_went_cold",
    );
  }
  assert(sanitizeContext({ coldDuration: "days" }, "went_cold").ok);
});

Deno.test("topicContext：投入程度只能搭 stuck／after_date／warm_up", () => {
  for (const situation of ["went_cold", null]) {
    assertEquals(
      contextReason({ engagement: "green" }, situation),
      "topic_context_engagement_situation_mismatch",
    );
  }
  for (const situation of ["stuck", "after_date", "warm_up"]) {
    const result = sanitizeContext({ engagement: "red" }, situation);
    assert(result.ok, situation);
    assertEquals(result.request.topicContext?.engagement, "red");
  }
});

Deno.test("topicContext：素材類型可以單獨出現（不選第一問）", () => {
  const result = sanitizeContext(
    { materialKind: "trigger", materialText: "路過浮誇甜點店" },
    null,
  );
  assert(result.ok);
  assertEquals(result.request.situation, null);
  assertEquals(result.request.topicContext?.materialKind, "trigger");
});

Deno.test("topicContext：前四種素材必填原文；none／缺席不得帶原文", () => {
  for (const kind of ["past_topic", "trigger", "my_story", "inside_joke"]) {
    assertEquals(
      contextReason({ materialKind: kind }),
      "topic_context_material_text_required",
    );
    assertEquals(
      contextReason({ materialKind: kind, materialText: " \n　 " }),
      "topic_context_material_text_required",
    );
    assertEquals(
      contextReason({ materialKind: kind, materialText: 123 }),
      "topic_context_material_text_invalid",
    );
    assert(sanitizeContext({ materialKind: kind, materialText: "有內容" }).ok);
  }
  assertEquals(
    contextReason({ materialKind: "none", materialText: "多的" }),
    "topic_context_material_text_unexpected",
  );
  assertEquals(
    contextReason({ coldDuration: "days", materialText: "多的" }),
    "topic_context_material_text_unexpected",
  );
  assert(sanitizeContext({ materialKind: "none", materialText: null }).ok);
});

Deno.test("topicContext：原文 trim＋連續空白（含換行）收成一個半形空白", () => {
  const result = sanitizeContext({
    materialKind: "past_topic",
    materialText: "  她說\n\n在準備　潛水  證照\t ",
  });
  assert(result.ok);
  assertEquals(
    result.request.topicContext?.materialText,
    "她說 在準備 潛水 證照",
  );
});

Deno.test("topicContext：原文上限 150 grapheme（emoji 算一個），超長不截斷", () => {
  const family = "👨‍👩‍👧";
  const at150 = "字".repeat(149) + family;
  assert(at150.length > 150, "UTF-16 長度超過 150，只有 grapheme 計數會放行");
  const ok = sanitizeContext({ materialKind: "my_story", materialText: at150 });
  assert(ok.ok);
  assertEquals(ok.request.topicContext?.materialText, at150);
  assertEquals(
    contextReason({ materialKind: "my_story", materialText: at150 + "字" }),
    "topic_context_material_text_too_long",
  );
});

Deno.test("topicContext：原文先拿掉零寬／雙向控制／軟連字號，emoji 組合的 ZWJ 保留", () => {
  const cases: Array<[string, string]> = [
    ["她說\u200B想打\u200C炮", "她說想打炮"],
    ["打\u200D炮", "打炮"],
    ["\u202E反過來\u202C的字", "反過來的字"],
    ["潛\u00AD水\u2060證照\uFEFF", "潛水證照"],
    ["\u200B \u200B她說 \u2066在準備\u2069", "她說 在準備"],
    ["全家出動👨‍👩‍👧 彩虹🏳️‍🌈", "全家出動👨‍👩‍👧 彩虹🏳️‍🌈"],
  ];
  for (const [raw, expected] of cases) {
    const result = sanitizeContext({
      materialKind: "my_story",
      materialText: raw,
    });
    assert(result.ok, raw);
    assertEquals(result.request.topicContext?.materialText, expected, raw);
  }
  assertEquals(
    contextReason({ materialKind: "my_story", materialText: "\u200B\u200E" }),
    "topic_context_material_text_required",
  );
});

Deno.test("topicContext：原文另以 UTF-16 長度 1500 封頂（組合符號／ZWJ 疊字）", () => {
  assertEquals(NEW_TOPIC_MATERIAL_TEXT_MAX_CODE_UNITS, 1500);
  const zalgo =
    ("字" + "\u0301\u0302\u0303\u0304\u0306\u0307\u0308\u030A\u030B\u030C")
      .repeat(NEW_TOPIC_MATERIAL_TEXT_MAX_GRAPHEMES);
  const zwjChain = "👨‍👩‍👧‍👦".repeat(NEW_TOPIC_MATERIAL_TEXT_MAX_GRAPHEMES);
  for (const [name, text] of [["zalgo", zalgo], ["zwj", zwjChain]]) {
    const graphemes = [
      ...new Intl.Segmenter("zh-Hant", { granularity: "grapheme" }).segment(
        text,
      ),
    ].length;
    assertEquals(graphemes, NEW_TOPIC_MATERIAL_TEXT_MAX_GRAPHEMES, name);
    assert(text.length > NEW_TOPIC_MATERIAL_TEXT_MAX_CODE_UNITS, name);
    assertEquals(
      contextReason({ materialKind: "my_story", materialText: text }),
      "topic_context_material_text_too_long",
      name,
    );
  }
  const normal = "字".repeat(145) + "😂👨‍👩‍👧🇹🇼🏳️‍🌈❤️‍🔥";
  const ok = sanitizeContext({
    materialKind: "my_story",
    materialText: normal,
  });
  assert(ok.ok);
  assertEquals(ok.request.topicContext?.materialText, normal);
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
    topicContext: null,
  } as const;
  const noContext = {
    coldDuration: null,
    coldStop: null,
    engagement: null,
    materialKind: null,
    materialText: null,
  } as const;
  assertFalse(hasNewTopicMaterial({ ...base }));
  assert(hasNewTopicMaterial({ ...base, partnerSummary: "對象摘要" }));
  assert(hasNewTopicMaterial({ ...base, effectiveStyleContext: "風格" }));
  assert(hasNewTopicMaterial({ ...base, situation: "stuck" }));
  // 用戶寫的素材原文也算素材；「沒有，幫我想」單獨不算。
  assert(hasNewTopicMaterial({
    ...base,
    topicContext: {
      ...noContext,
      materialKind: "my_story",
      materialText: "走錯分店",
    },
  }));
  assertFalse(hasNewTopicMaterial({
    ...base,
    topicContext: { ...noContext, materialKind: "none" },
  }));
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

Deno.test("normalize：openingLine 的「你」轉「妳」，教練欄位不動", () => {
  const topics = modelTopics();
  topics[0] = {
    direction: "方向1",
    openingLine: "如果拉你去爬山，妳大概走十分鐘就想放棄",
    whyItWorks: "因為你已經跟她熟到可以開玩笑",
    nextMove: "她反駁的話你就順著演",
  };
  topics[1] = { ...topics[1], openingLine: "鄰居，你們那棟最近吵嗎" };
  const result = normalizeNewTopicModelPayload({
    topics,
    recommendation: { index: 0, reason: "最貼近她的近況" },
  });
  assert(result.ok);
  assertEquals(
    result.topics[0].openingLine,
    "如果拉妳去爬山，妳大概走十分鐘就想放棄",
  );
  // 「你們」可能是混合群體，刻意不動。
  assertEquals(result.topics[1].openingLine, "鄰居，你們那棟最近吵嗎");
  // 教練欄位是對使用者講話，「你」＝他本人，不得被改。
  assertEquals(result.topics[0].whyItWorks, "因為你已經跟她熟到可以開玩笑");
  assertEquals(result.topics[0].nextMove, "她反駁的話你就順著演");
});

Deno.test("normalize：openingLine 丟掉混入外語 token 的整個子句", () => {
  const topics = modelTopics();
  topics[0] = {
    ...topics[0],
    openingLine: "妳學新東西的時間都long在白天，感覺很自律",
  };
  topics[1] = {
    ...topics[1],
    openingLine: "大夜班還在學新東西，怎麼約простее。妳平常都幾點睡",
  };
  const result = normalizeNewTopicModelPayload({
    topics,
    recommendation: { index: 0 },
  });

  assert(result.ok);
  assertEquals(result.topics[0].openingLine, "感覺很自律");
  assertEquals(
    result.topics[1].openingLine,
    "大夜班還在學新東西，妳平常都幾點睡",
  );
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

Deno.test("normalize：內部 situation token 不得出現在任何可見欄位", () => {
  const leaked = modelTopics();
  leaked[0].whyItWorks = "warm_up 階段適合增加互動深度";
  assertFalse(
    normalizeNewTopicModelPayload({
      topics: leaked,
      recommendation: { index: 0, reason: "符合 warm_up 目標" },
    }).ok,
  );
});

Deno.test("normalize：客戶解釋欄擋內部術語，不誤殺自然教練句", () => {
  const leaks: Array<[keyof NewTopicModelTopic, string]> = [
    ["direction", "怪選項切角"],
    ["whyItWorks", "這題用旁路冷讀做好奇心鉤子"],
    ["nextMove", "她回了就用雙球繼續推進"],
  ];
  for (const [field, leakedText] of leaks) {
    const topics = modelTopics();
    topics[0] = { ...topics[0], [field]: leakedText };
    assertFalse(
      normalizeNewTopicModelPayload({
        topics,
        recommendation: { index: 0, reason: "最貼近她的近況" },
      }).ok,
      `${field} 的內部術語應拒絕`,
    );
  }

  assertFalse(
    normalizeNewTopicModelPayload({
      topics: modelTopics(),
      recommendation: { index: 0, reason: "這張符合 warm_up 目標" },
    }).ok,
    "recommendation.reason 的內部代碼應拒絕",
  );

  const natural = modelTopics();
  natural[0] = {
    direction: "休假突然多一天",
    openingLine: "突然多一天假，你會先跑去哪",
    whyItWorks: "這句給她一個具體情境，不用想很久就能回",
    nextMove: "她如果反駁，就順著她補充的細節聊",
  };
  const result = normalizeNewTopicModelPayload({
    topics: natural,
    recommendation: { index: 0, reason: "這題最容易讓她從自己的日常接話" },
  });
  assert(result.ok);
  assertEquals(result.topics[0].openingLine, "突然多一天假，妳會先跑去哪");
});

Deno.test("repair merge：只修解釋時保留 primary 可直接傳句子", () => {
  const primaryTopics = modelTopics();
  primaryTopics[0].openingLine = "你這張照片有點像電影劇照";
  primaryTopics[0].whyItWorks = "旁路冷讀：她容易反駁";
  const repairedTopics = modelTopics();
  repairedTopics[0].openingLine = "修復器不得改成這句";
  repairedTopics[0].whyItWorks = "照片本身有具體畫面，她容易補充當時在做什麼";

  const merged = mergeNewTopicRepairWithPrimaryOpeningLines(
    { topics: primaryTopics, recommendation: { index: 0 } },
    { topics: repairedTopics, recommendation: { index: 0 } },
  );
  const result = normalizeNewTopicModelPayload(merged);
  assert(result.ok);
  assertEquals(result.topics[0].openingLine, "妳這張照片有點像電影劇照");
  assertEquals(
    result.topics[0].whyItWorks,
    "照片本身有具體畫面，她容易補充當時在做什麼",
  );
});

Deno.test("normalize：用戶素材原文裡本來就有的詞撞到內部術語不算外洩", () => {
  const cases: Array<{
    material: string;
    topic: Partial<NewTopicModelTopic>;
    reason?: string;
  }> = [
    {
      material: "她說最近在重看人間失格",
      topic: {
        direction: "她在重看的人間失格",
        whyItWorks: "她正在重看人間失格，接後續她最好回",
      },
      reason: "直接接她在看的人間失格",
    },
    {
      material: "路過一家雙球冰淇淋只要五十元的店",
      topic: {
        openingLine: "剛路過一家雙球冰淇淋只要五十",
        nextMove: "她回了就問她雙球會怎麼配口味",
      },
    },
    {
      material: "她說高中超迷 One Direction",
      topic: {
        direction: "她高中迷 One Direction 的那段",
        openingLine: "剛聽到 One Direction 的歌就想到妳",
      },
    },
    {
      material: "這週寫報告一直 stuck 在第一段",
      topic: {
        openingLine: "報告卡在第一段，整個 stuck 住",
        whyItWorks: "用你自己 stuck 的小事開場，她不用回答問題也能接",
      },
      reason: "Stuck 在第一段的小事最好接",
    },
  ];
  for (const { material, topic, reason } of cases) {
    const topics = modelTopics();
    topics[0] = { ...topics[0], ...topic };
    const payload = {
      topics,
      recommendation: { index: 0, reason: reason ?? "最貼近她的近況" },
    };
    const result = normalizeNewTopicModelPayload(payload, {
      allowSharedFrame: false,
      userMaterialText: material,
    });
    assert(result.ok, material);
    for (const [field, value] of Object.entries(topic)) {
      assertEquals(
        result.topics[0][field as keyof NewTopicModelTopic],
        value,
        material,
      );
    }
    // 沒給素材（legacy 路徑）照舊擋。
    assertFalse(
      normalizeNewTopicModelPayload(payload, { allowSharedFrame: false }).ok,
      material,
    );
    assertFalse(normalizeNewTopicModelPayload(payload).ok, material);
  }
});

Deno.test("normalize：素材原文只放行它自己有的詞，其他內部術語照擋", () => {
  const material = "她說最近在重看人間失格";
  const leaks: Array<Partial<NewTopicModelTopic>> = [
    { whyItWorks: "人間失格這題用旁路冷讀，她容易反駁" },
    { nextMove: "她回了就用雙球繼續推進" },
    { openingLine: "人間失格看到 warm_up 的段落了嗎" },
    { direction: "stuck 的時候聊人間失格" },
  ];
  for (const leak of leaks) {
    const topics = modelTopics();
    topics[0] = { ...topics[0], ...leak };
    assertFalse(
      normalizeNewTopicModelPayload(
        { topics, recommendation: { index: 0 } },
        { allowSharedFrame: true, userMaterialText: material },
      ).ok,
      JSON.stringify(leak),
    );
  }
});

Deno.test("repair merge：素材裡的 stuck 不會讓 primary 可直接傳句子被換掉", () => {
  const primaryTopics = modelTopics();
  primaryTopics[0].openingLine = "報告卡在第一段，整個 stuck 住";
  primaryTopics[0].whyItWorks = "旁路冷讀：她容易反駁";
  const repairedTopics = modelTopics();
  repairedTopics[0].openingLine = "修復器不得改成這句";
  const material = "這週寫報告一直 stuck 在第一段";
  const merged = mergeNewTopicRepairWithPrimaryOpeningLines(
    { topics: primaryTopics, recommendation: { index: 0 } },
    { topics: repairedTopics, recommendation: { index: 0 } },
    material,
  );
  const result = normalizeNewTopicModelPayload(merged, {
    allowSharedFrame: true,
    userMaterialText: material,
  });
  assert(result.ok);
  assertEquals(result.topics[0].openingLine, "報告卡在第一段，整個 stuck 住");
  // 沒給素材時 primary 那句算外洩，照舊用修復版。
  const legacy = mergeNewTopicRepairWithPrimaryOpeningLines(
    { topics: primaryTopics, recommendation: { index: 0 } },
    { topics: repairedTopics, recommendation: { index: 0 } },
  ) as { topics: NewTopicModelTopic[] };
  assertEquals(legacy.topics[0].openingLine, "修復器不得改成這句");
});

Deno.test("normalize：未知關係階段不得用共同生活的『我們』框架", () => {
  const overstepped = modelTopics();
  overstepped[0].openingLine = "如果我們一起養狗妳一定搶著取名";
  assertFalse(
    normalizeNewTopicModelPayload(
      {
        topics: overstepped,
        recommendation: { index: 0 },
      },
      { allowSharedFrame: false },
    ).ok,
  );
  assert(
    normalizeNewTopicModelPayload(
      {
        topics: overstepped,
        recommendation: { index: 0 },
      },
      { allowSharedFrame: true },
    ).ok,
  );
});

Deno.test("shared frame 權限只來自明確熟悉階段，不把 warm_up 當階段", () => {
  assertFalse(
    allowsNewTopicSharedFrame({ partnerSummary: null, situation: "warm_up" }),
  );
  assertFalse(
    allowsNewTopicSharedFrame({
      partnerSummary: "[對象作戰板：Miya]\n- 興趣：咖啡",
      situation: "warm_up",
    }),
  );
  assert(
    allowsNewTopicSharedFrame({
      partnerSummary: "[對象作戰板：Miya]\n- 你的備註：聊得來但還沒約",
      situation: "warm_up",
    }),
  );
});

Deno.test("shared frame：進階路徑只有想更靠近＋她很投入才放行", () => {
  const context = (engagement: "green" | "yellow" | null) => ({
    coldDuration: null,
    coldStop: null,
    engagement,
    materialKind: null,
    materialText: null,
  });
  assert(
    allowsNewTopicSharedFrame({
      partnerSummary: null,
      situation: "warm_up",
      topicContext: context("green"),
    }),
  );
  assertFalse(
    allowsNewTopicSharedFrame({
      partnerSummary: null,
      situation: "warm_up",
      topicContext: context("yellow"),
    }),
  );
  assertFalse(
    allowsNewTopicSharedFrame({
      partnerSummary: null,
      situation: "stuck",
      topicContext: context("green"),
    }),
  );
  assert(
    allowsNewTopicSharedFrame({
      partnerSummary: null,
      situation: "after_date",
      topicContext: context(null),
    }),
  );
});

Deno.test("shared frame：用戶寫了你們之間的梗＝他確認有共同經歷，放行", () => {
  const joke = {
    coldDuration: null,
    coldStop: null,
    engagement: null,
    materialKind: "inside_joke" as const,
    materialText: "她說我的五分鐘都是半小時",
  };
  for (const situation of [null, "went_cold", "stuck"] as const) {
    assert(
      allowsNewTopicSharedFrame({
        partnerSummary: null,
        situation,
        topicContext: joke,
      }),
      String(situation),
    );
  }
  assertFalse(
    allowsNewTopicSharedFrame({
      partnerSummary: null,
      situation: "stuck",
      topicContext: { ...joke, materialText: null },
    }),
  );
  assertFalse(
    allowsNewTopicSharedFrame({
      partnerSummary: null,
      situation: "stuck",
      topicContext: { ...joke, materialKind: "past_topic" },
    }),
  );
  // legacy 呼叫（沒有 topicContext）不變。
  assertFalse(
    allowsNewTopicSharedFrame({ partnerSummary: null, situation: "stuck" }),
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
  });

  assertFalse(
    isValidNewTopicLedgerResult({ ...paid, usage: { cost: 3 } }),
    "頂層多 usage 鍵應拒絕",
  );
  assertFalse(
    isValidNewTopicLedgerResult({ ...paid, formulaTopics: [] }),
    "已下架的公式欄 formulaTopics 也算多鍵，應拒絕",
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
