// practice-chat 請求驗證測試。
// 跑法：deno test supabase/functions/practice-chat/validate_test.ts

import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  countAiTurns,
  validateDrawRequest,
  validateRequest,
} from "./validate.ts";

function chatReq(turns: Array<{ role: string; text: string }>) {
  return { mode: "chat", sessionId: "s1", turns };
}

function hintReq(turns: Array<{ role: string; text: string }>) {
  return { mode: "hint", sessionId: "s1", turns };
}

// ── happy path ───────────────────────────────────────────────────────

Deno.test("chat：合法第一則請求通過", () => {
  const r = validateRequest(chatReq([{ role: "user", text: "嗨" }]));
  assertEquals(r.mode, "chat");
  assertEquals(r.turns.length, 1);
});

Deno.test("chat：多輪一來一回、最後一則是 user → 通過", () => {
  const r = validateRequest(
    chatReq([
      { role: "user", text: "嗨" },
      { role: "ai", text: "嗯？" },
      { role: "user", text: "在幹嘛" },
    ]),
  );
  assertEquals(countAiTurns(r.turns), 1);
});

Deno.test("debrief：有一來一回 → 通過", () => {
  const r = validateRequest({
    mode: "debrief",
    sessionId: "s1",
    turns: [
      { role: "user", text: "嗨" },
      { role: "ai", text: "嗯？" },
    ],
  });
  assertEquals(r.mode, "debrief");
});

Deno.test("chat without practiceMode defaults to standard", () => {
  const r = validateRequest(chatReq([{ role: "user", text: "hi" }]));
  assertEquals(r.practiceMode, "standard");
});

Deno.test("chat without practiceMode defaults temperatureScore to 30", () => {
  const r = validateRequest(chatReq([{ role: "user", text: "hi" }]));
  assertEquals(r.practiceMode, "standard");
  assertEquals(r.temperatureScore, 30);
});

Deno.test("practiceMode standard is accepted", () => {
  const r = validateRequest({
    ...chatReq([{ role: "user", text: "hi" }]),
    practiceMode: "standard",
  });
  assertEquals(r.practiceMode, "standard");
});

Deno.test("practiceMode beginner is accepted", () => {
  const r = validateRequest({
    ...chatReq([{ role: "user", text: "hi" }]),
    practiceMode: "beginner",
  });
  assertEquals(r.practiceMode, "beginner");
});

Deno.test("invalid practiceMode throws invalid_practiceMode", () => {
  assertThrows(
    () =>
      validateRequest({
        ...chatReq([{ role: "user", text: "hi" }]),
        practiceMode: "expert",
      }),
    Error,
    "invalid_practiceMode",
  );
});

Deno.test("temperatureScore accepts integers from 0 to 100", () => {
  for (const temperatureScore of [0, 1, 30, 100]) {
    const r = validateRequest({
      ...chatReq([{ role: "user", text: "hi" }]),
      practiceMode: "beginner",
      temperatureScore,
    });
    assertEquals(r.temperatureScore, temperatureScore);
  }
});

Deno.test("missing beginner temperatureScore defaults to 30", () => {
  const r = validateRequest({
    ...chatReq([{ role: "user", text: "hi" }]),
    practiceMode: "beginner",
  });
  assertEquals(r.temperatureScore, 30);
});

Deno.test("invalid temperatureScore throws invalid_temperatureScore", () => {
  for (const temperatureScore of [-1, 101, 1.5, "30", null]) {
    assertThrows(
      () =>
        validateRequest({
          ...chatReq([{ role: "user", text: "hi" }]),
          practiceMode: "beginner",
          temperatureScore,
        }),
      Error,
      "invalid_temperatureScore",
    );
  }
});

Deno.test("familiarityScore accepts integers from 0 to 100 and defaults to 0", () => {
  const missing = validateRequest({
    ...chatReq([{ role: "user", text: "hi" }]),
    practiceMode: "beginner",
  });
  assertEquals((missing as { familiarityScore?: unknown }).familiarityScore, 0);

  for (const familiarityScore of [0, 1, 40, 100]) {
    const r = validateRequest({
      ...chatReq([{ role: "user", text: "hi" }]),
      practiceMode: "beginner",
      familiarityScore,
    });
    assertEquals(
      (r as { familiarityScore?: unknown }).familiarityScore,
      familiarityScore,
    );
  }
});

Deno.test("invalid familiarityScore throws invalid_familiarityScore", () => {
  for (const familiarityScore of [-1, 101, 1.5, "30", null]) {
    assertThrows(
      () =>
        validateRequest({
          ...chatReq([{ role: "user", text: "hi" }]),
          practiceMode: "beginner",
          familiarityScore,
        }),
      Error,
      "invalid_familiarityScore",
    );
  }
});

Deno.test("chat accepts appliedHintType for exact applied beginner hints", () => {
  for (const appliedHintType of ["warm_up", "steady"]) {
    const r = validateRequest({
      ...chatReq([{ role: "user", text: "hint reply" }]),
      practiceMode: "beginner",
      appliedHintType,
    });
    assertEquals(
      (r as { appliedHintType?: unknown }).appliedHintType,
      appliedHintType,
    );
  }
});

Deno.test("chat accepts appliedHintText when a hint draft was edited", () => {
  const r = validateRequest({
    ...chatReq([{ role: "user", text: "edited hint reply" }]),
    practiceMode: "beginner",
    appliedHintType: "steady",
    appliedHintText: "original hint reply",
  });

  assertEquals(
    (r as { appliedHintText?: unknown }).appliedHintText,
    "original hint reply",
  );
});

Deno.test("appliedHintText without appliedHintType throws invalid_appliedHintText", () => {
  assertThrows(
    () =>
      validateRequest({
        ...chatReq([{ role: "user", text: "edited hint reply" }]),
        practiceMode: "beginner",
        appliedHintText: "original hint reply",
      }),
    Error,
    "invalid_appliedHintText",
  );
});

Deno.test("invalid appliedHintType throws invalid_appliedHintType", () => {
  for (const appliedHintType of ["warmUp", "hot", "", null, 1]) {
    assertThrows(
      () =>
        validateRequest({
          ...chatReq([{ role: "user", text: "hint reply" }]),
          practiceMode: "beginner",
          appliedHintType,
        }),
      Error,
      "invalid_appliedHintType",
    );
  }
});

Deno.test("invalid appliedHintText throws invalid_appliedHintText", () => {
  for (
    const appliedHintText of [
      "",
      "   ",
      "x".repeat(501),
      "S__42795075.jpg",
      null,
      1,
    ]
  ) {
    assertThrows(
      () =>
        validateRequest({
          ...chatReq([{ role: "user", text: "hint reply" }]),
          practiceMode: "beginner",
          appliedHintType: "warm_up",
          appliedHintText,
        }),
      Error,
      "invalid_appliedHintText",
    );
  }
});

Deno.test("mode hint is accepted when latest turn is AI", () => {
  const r = validateRequest(
    hintReq([
      { role: "user", text: "hi" },
      { role: "ai", text: "hello" },
    ]),
  );
  assertEquals(r.mode, "hint");
});

Deno.test("hint with no AI turns throws invalid_hint_no_ai_turns", () => {
  assertThrows(
    () => validateRequest(hintReq([{ role: "user", text: "hi" }])),
    Error,
    "invalid_hint_no_ai_turns",
  );
});

Deno.test("hint whose latest turn is not AI throws invalid_hint_last_turn_must_be_ai", () => {
  assertThrows(
    () =>
      validateRequest(
        hintReq([
          { role: "user", text: "hi" },
          { role: "ai", text: "hello" },
          { role: "user", text: "one more" },
        ]),
      ),
    Error,
    "invalid_hint_last_turn_must_be_ai",
  );
});

// ── hint requestId（冪等 key，選填）──────────────────────────────────

function validHintTurns(): Array<{ role: string; text: string }> {
  return [
    { role: "user", text: "hi" },
    { role: "ai", text: "hello" },
  ];
}

Deno.test("hint：缺 requestId → 通過（向後相容，requestId undefined）", () => {
  const r = validateRequest(hintReq(validHintTurns()));
  assertEquals(r.requestId, undefined);
});

Deno.test("hint：合法 requestId（uuid）被解析", () => {
  const r = validateRequest({
    ...hintReq(validHintTurns()),
    requestId: "11111111-2222-3333-4444-555555555555",
  });
  assertEquals(r.requestId, "11111111-2222-3333-4444-555555555555");
});

Deno.test("hint：requestId 非字串 → invalid_requestId", () => {
  assertThrows(
    () =>
      validateRequest({
        ...hintReq(validHintTurns()),
        requestId: 123,
      }),
    Error,
    "invalid_requestId",
  );
});

Deno.test("hint：requestId 空字串 → invalid_requestId", () => {
  assertThrows(
    () =>
      validateRequest({
        ...hintReq(validHintTurns()),
        requestId: "",
      }),
    Error,
    "invalid_requestId",
  );
});

Deno.test("hint：requestId 含非法字元 → invalid_requestId", () => {
  assertThrows(
    () =>
      validateRequest({
        ...hintReq(validHintTurns()),
        requestId: "bad id with space",
      }),
    Error,
    "invalid_requestId",
  );
});

Deno.test("hint：requestId 過長（>64）→ invalid_requestId", () => {
  assertThrows(
    () =>
      validateRequest({
        ...hintReq(validHintTurns()),
        requestId: "a".repeat(65),
      }),
    Error,
    "invalid_requestId",
  );
});

Deno.test("chat：requestId 只屬於 hint，chat 模式一律忽略", () => {
  const r = validateRequest({
    ...chatReq([{ role: "user", text: "hi" }]),
    requestId: "bad id with space",
  });
  assertEquals(r.requestId, undefined);
});

Deno.test("chat still requires latest turn to be user", () => {
  assertThrows(
    () =>
      validateRequest(
        chatReq([
          { role: "user", text: "hi" },
          { role: "ai", text: "hello" },
        ]),
      ),
    Error,
    "invalid_chat_last_turn_must_be_user",
  );
});

// ── mode / sessionId ─────────────────────────────────────────────────

Deno.test("非物件 body → invalid_request_body", () => {
  assertThrows(() => validateRequest(null), Error, "invalid_request_body");
  assertThrows(() => validateRequest("x"), Error, "invalid_request_body");
});

Deno.test("未知 mode → invalid_mode", () => {
  assertThrows(
    () => validateRequest({ mode: "coach", sessionId: "s", turns: [] }),
    Error,
    "invalid_mode",
  );
});

Deno.test("缺 / 空 sessionId → invalid_sessionId", () => {
  assertThrows(
    () => validateRequest({ mode: "chat", sessionId: "", turns: [] }),
    Error,
    "invalid_sessionId",
  );
});

// ── turns 形狀 ───────────────────────────────────────────────────────

Deno.test("turns 非陣列 → invalid_turns", () => {
  assertThrows(
    () => validateRequest({ mode: "chat", sessionId: "s", turns: {} }),
    Error,
    "invalid_turns",
  );
});

Deno.test("turns 空陣列 → invalid_turns_empty", () => {
  assertThrows(
    () => validateRequest(chatReq([])),
    Error,
    "invalid_turns_empty",
  );
});

Deno.test("turns 過多 → invalid_turns_too_many", () => {
  // MAX_TURNS=130（涵蓋 3 輪 visible thread）；131 才超量。
  const many = Array.from({ length: 131 }, () => ({ role: "user", text: "x" }));
  assertThrows(
    () => validateRequest(chatReq(many)),
    Error,
    "invalid_turns_too_many",
  );
});

Deno.test("turns 120（3 輪 visible thread）→ 通過", () => {
  const turns: Array<{ role: string; text: string }> = [];
  for (let i = 0; i < 60; i++) {
    turns.push({ role: "user", text: `u${i}` });
    turns.push({ role: "ai", text: `a${i}` });
  }
  turns.push({ role: "user", text: "再一句" });
  const r = validateRequest(chatReq(turns.slice(0, 119)));
  assertEquals(r.mode, "chat");
});

Deno.test("turn role 非法 → invalid_turn_role", () => {
  assertThrows(
    () => validateRequest(chatReq([{ role: "system", text: "x" }])),
    Error,
    "invalid_turn_role_0",
  );
});

Deno.test("turn text 空白 → invalid_turn_text", () => {
  assertThrows(
    () => validateRequest(chatReq([{ role: "user", text: "   " }])),
    Error,
    "invalid_turn_text_0",
  );
});

Deno.test("turn text 過長 → invalid_turn_text_len", () => {
  const long = "x".repeat(501);
  assertThrows(
    () => validateRequest(chatReq([{ role: "user", text: long }])),
    Error,
    "invalid_turn_text_len_0",
  );
});

// ── chat 專屬規則 ────────────────────────────────────────────────────

Deno.test("chat 最後一則是 ai → invalid_chat_last_turn_must_be_user", () => {
  assertThrows(
    () =>
      validateRequest(
        chatReq([
          { role: "user", text: "嗨" },
          { role: "ai", text: "嗯" },
        ]),
      ),
    Error,
    "invalid_chat_last_turn_must_be_user",
  );
});

Deno.test("chat 10 則上限不再由 client count 把關（改 server ledger 權威）", () => {
  // client 可少報 ai turns 繞過上限，故 validate 不得再用 client count 當閘。
  // 形狀合法即通過；真正的 10 則上限由 server preflight（ledger.ai_count）強制。
  const turns: Array<{ role: string; text: string }> = [];
  for (let i = 0; i < 10; i++) {
    turns.push({ role: "user", text: `u${i}` });
    turns.push({ role: "ai", text: `a${i}` });
  }
  turns.push({ role: "user", text: "再一句" });
  const r = validateRequest(chatReq(turns));
  assertEquals(r.mode, "chat");
  assertEquals(countAiTurns(r.turns), 10);
});

// ── debrief 專屬規則 ─────────────────────────────────────────────────

Deno.test("debrief 沒有任何 AI 回覆 → invalid_debrief_no_ai_turns", () => {
  assertThrows(
    () =>
      validateRequest({
        mode: "debrief",
        sessionId: "s",
        turns: [{ role: "user", text: "嗨" }],
      }),
    Error,
    "invalid_debrief_no_ai_turns",
  );
});

// ── persona / difficulty profile ─────────────────────────────────────

Deno.test("profile：缺 persona/difficulty → fallback slow_worker + normal", () => {
  const r = validateRequest(chatReq([{ role: "user", text: "嗨" }]));
  assertEquals(r.profile.personaId, "slow_worker");
  assertEquals(r.profile.personaLabel, "慢熱上班族");
  assertEquals(r.profile.difficulty, "normal");
  assertEquals(r.profile.difficultyLabel, "一般");
});

Deno.test("profile：合法 persona/difficulty 通過並解析 label", () => {
  const r = validateRequest({
    mode: "chat",
    sessionId: "s1",
    personaId: "teasing_humor",
    difficulty: "challenge",
    turns: [{ role: "user", text: "今天好無聊" }],
  });

  assertEquals(r.profile.personaId, "teasing_humor");
  assertEquals(r.profile.personaLabel, "幽默吐槽型");
  assertEquals(r.profile.difficulty, "challenge");
  assertEquals(r.profile.difficultyLabel, "挑戰");
});

Deno.test("profile：非法 personaId → invalid_personaId", () => {
  assertThrows(
    () =>
      validateRequest({
        mode: "chat",
        sessionId: "s1",
        personaId: "write_your_own_prompt",
        difficulty: "normal",
        turns: [{ role: "user", text: "嗨" }],
      }),
    Error,
    "invalid_personaId",
  );
});

Deno.test("profile：非法 difficulty → invalid_difficulty", () => {
  assertThrows(
    () =>
      validateRequest({
        mode: "chat",
        sessionId: "s1",
        personaId: "slow_worker",
        difficulty: "nightmare",
        turns: [{ role: "user", text: "嗨" }],
      }),
    Error,
    "invalid_difficulty",
  );
});

// ── 陪練女孩 profile / profession / photo / name metadata ──────────────

Deno.test("profile：缺 profileId → fallback 預設陪練女孩 practice_girl_001", () => {
  const r = validateRequest(chatReq([{ role: "user", text: "嗨" }]));
  assertEquals(r.profile.girl.profileId, "practice_girl_001");
  assertEquals(r.profile.girl.displayName, "Alice");
  assertEquals(r.profile.girl.professionId, "flight_attendant");
  // 帶 profileId 時 persona 綁定該 profile（alice = slow_worker）。
  assertEquals(r.profile.personaId, "slow_worker");
});

Deno.test("profile：合法 profileId → 解析出對應 girl，persona 綁定 profile", () => {
  const r = validateRequest({
    mode: "chat",
    sessionId: "s1",
    profileId: "practice_girl_004",
    turns: [{ role: "user", text: "嗨" }],
  });
  assertEquals(r.profile.girl.profileId, "practice_girl_004");
  assertEquals(r.profile.girl.displayName, "Mia");
  assertEquals(r.profile.girl.professionId, "barista");
  assertEquals(r.profile.personaId, "teasing_humor");
  // reaction model 與 signal style 有被組出來。
  assertEquals(r.profile.girl.reactionModel.likes.length > 0, true);
  assertEquals(r.profile.girl.signalStyle.length > 0, true);
});

Deno.test("profile：非法 profileId → invalid_profileId", () => {
  assertThrows(
    () =>
      validateRequest({
        mode: "chat",
        sessionId: "s1",
        profileId: "practice_girl_999",
        turns: [{ role: "user", text: "嗨" }],
      }),
    Error,
    "invalid_profileId",
  );
});

Deno.test("profile：非法 professionId → invalid_professionId", () => {
  assertThrows(
    () =>
      validateRequest({
        mode: "chat",
        sessionId: "s1",
        professionId: "ceo_billionaire",
        turns: [{ role: "user", text: "嗨" }],
      }),
    Error,
    "invalid_professionId",
  );
});

Deno.test("profile：非法 photoId → invalid_photoId", () => {
  assertThrows(
    () =>
      validateRequest({
        mode: "chat",
        sessionId: "s1",
        photoId: "totally_made_up_photo",
        turns: [{ role: "user", text: "嗨" }],
      }),
    Error,
    "invalid_photoId",
  );
});

Deno.test("profile：非法 nameId → invalid_nameId", () => {
  assertThrows(
    () =>
      validateRequest({
        mode: "chat",
        sessionId: "s1",
        nameId: "definitely_not_a_name",
        turns: [{ role: "user", text: "嗨" }],
      }),
    Error,
    "invalid_nameId",
  );
});

Deno.test("profile：profileId 與 professionId 不符 → invalid_profile_metadata", () => {
  assertThrows(
    () =>
      validateRequest({
        mode: "chat",
        sessionId: "s1",
        profileId: "practice_girl_004", // barista
        professionId: "flight_attendant",
        turns: [{ role: "user", text: "嗨" }],
      }),
    Error,
    "invalid_profile_metadata",
  );
});

Deno.test("profile：profileId 與 photoId 不符 → invalid_profile_metadata", () => {
  assertThrows(
    () =>
      validateRequest({
        mode: "chat",
        sessionId: "s1",
        profileId: "practice_girl_004",
        photoId: "practice_girl_001",
        turns: [{ role: "user", text: "嗨" }],
      }),
    Error,
    "invalid_profile_metadata",
  );
});

Deno.test("profile：profileId 與 nameId 不符 → invalid_profile_metadata", () => {
  assertThrows(
    () =>
      validateRequest({
        mode: "chat",
        sessionId: "s1",
        profileId: "practice_girl_004", // mia
        nameId: "alice",
        turns: [{ role: "user", text: "嗨" }],
      }),
    Error,
    "invalid_profile_metadata",
  );
});

Deno.test("profile：profileId + 相符的 profession/photo/name → 通過", () => {
  const r = validateRequest({
    mode: "chat",
    sessionId: "s1",
    profileId: "practice_girl_001",
    professionId: "flight_attendant",
    photoId: "practice_girl_001",
    nameId: "alice",
    turns: [{ role: "user", text: "嗨" }],
  });
  assertEquals(r.profile.girl.profileId, "practice_girl_001");
});

// ── roundIndex / visiblePracticeThreadId ──────────────────────────────

Deno.test("roundIndex：缺值 → fallback 1", () => {
  const r = validateRequest(chatReq([{ role: "user", text: "嗨" }]));
  assertEquals(r.roundIndex, 1);
});

Deno.test("roundIndex：合法 1..3 → 通過", () => {
  for (const idx of [1, 2, 3]) {
    const r = validateRequest({
      mode: "chat",
      sessionId: "s1",
      roundIndex: idx,
      turns: [{ role: "user", text: "嗨" }],
    });
    assertEquals(r.roundIndex, idx);
  }
});

Deno.test("roundIndex：4（超過 3 輪上限）→ invalid_roundIndex", () => {
  assertThrows(
    () =>
      validateRequest({
        mode: "chat",
        sessionId: "s1",
        roundIndex: 4,
        turns: [{ role: "user", text: "嗨" }],
      }),
    Error,
    "invalid_roundIndex",
  );
});

Deno.test("roundIndex：非整數 → invalid_roundIndex", () => {
  assertThrows(
    () =>
      validateRequest({
        mode: "chat",
        sessionId: "s1",
        roundIndex: 1.5,
        turns: [{ role: "user", text: "嗨" }],
      }),
    Error,
    "invalid_roundIndex",
  );
});

Deno.test("visiblePracticeThreadId：合法字串 → 通過並保留", () => {
  const r = validateRequest({
    mode: "chat",
    sessionId: "s1",
    visiblePracticeThreadId: "local-thread-abc",
    turns: [{ role: "user", text: "嗨" }],
  });
  assertEquals(r.visiblePracticeThreadId, "local-thread-abc");
});

Deno.test("visiblePracticeThreadId：過長 → invalid_visiblePracticeThreadId", () => {
  assertThrows(
    () =>
      validateRequest({
        mode: "chat",
        sessionId: "s1",
        visiblePracticeThreadId: "x".repeat(129),
        turns: [{ role: "user", text: "嗨" }],
      }),
    Error,
    "invalid_visiblePracticeThreadId",
  );
});

// ── draw_profile 驗證 ──────────────────────────────────────────────────

Deno.test("draw：合法請求（只有 requestId）→ 通過，不需要 turns", () => {
  const r = validateDrawRequest({
    mode: "draw_profile",
    requestId: "11111111-2222-3333-4444-555555555555",
  });
  assertEquals(r.mode, "draw_profile");
  assertEquals(r.requestId, "11111111-2222-3333-4444-555555555555");
  assertEquals(r.currentProfileId, undefined);
});

Deno.test("draw：帶合法 currentProfileId / visiblePracticeThreadId → 保留", () => {
  const r = validateDrawRequest({
    mode: "draw_profile",
    requestId: "req_abc-123",
    currentProfileId: "practice_girl_001",
    visiblePracticeThreadId: "local-thread-9",
  });
  assertEquals(r.currentProfileId, "practice_girl_001");
  assertEquals(r.visiblePracticeThreadId, "local-thread-9");
});

Deno.test("draw：缺 requestId → invalid_requestId", () => {
  assertThrows(
    () => validateDrawRequest({ mode: "draw_profile" }),
    Error,
    "invalid_requestId",
  );
});

Deno.test("draw：requestId 含非法字元 → invalid_requestId", () => {
  assertThrows(
    () =>
      validateDrawRequest({
        mode: "draw_profile",
        requestId: "bad id with space",
      }),
    Error,
    "invalid_requestId",
  );
});

Deno.test("draw：requestId 過長（>64）→ invalid_requestId", () => {
  assertThrows(
    () =>
      validateDrawRequest({
        mode: "draw_profile",
        requestId: "a".repeat(65),
      }),
    Error,
    "invalid_requestId",
  );
});

Deno.test("draw：currentProfileId 非 allowlist → invalid_currentProfileId", () => {
  assertThrows(
    () =>
      validateDrawRequest({
        mode: "draw_profile",
        requestId: "req-1",
        currentProfileId: "practice_girl_999",
      }),
    Error,
    "invalid_currentProfileId",
  );
});

Deno.test("draw：currentProfileId 自由文字 → invalid_currentProfileId（堵拼裝人設）", () => {
  assertThrows(
    () =>
      validateDrawRequest({
        mode: "draw_profile",
        requestId: "req-1",
        currentProfileId: "; drop table",
      }),
    Error,
    "invalid_currentProfileId",
  );
});

Deno.test("draw：錯 mode → invalid_mode", () => {
  assertThrows(
    () => validateDrawRequest({ mode: "chat", requestId: "req-1" }),
    Error,
    "invalid_mode",
  );
});

Deno.test("draw：catalogSize 缺席 → undefined（legacy client，由切池層降級 60）", () => {
  const r = validateDrawRequest({
    mode: "draw_profile",
    requestId: "req-1",
  });
  assertEquals(r.catalogSize, undefined);
});

Deno.test("draw：catalogSize 合法正整數 → 原值保留", () => {
  const r = validateDrawRequest({
    mode: "draw_profile",
    requestId: "req-1",
    catalogSize: 100,
  });
  assertEquals(r.catalogSize, 100);
});

Deno.test("draw：catalogSize 非法（型別/小數/非正）→ 靜默降級 undefined，絕不 400", () => {
  // 400 會鎖死已裝機的舊 client（Edge 收緊必配 client clamp；這裡直接不收緊）。
  const bads: unknown[] = ["abc", "100", 1.5, 0, -1, Number.NaN, true, {}, []];
  for (const bad of bads) {
    const r = validateDrawRequest({
      mode: "draw_profile",
      requestId: "req-1",
      catalogSize: bad,
    });
    assertEquals(r.catalogSize, undefined, `catalogSize=${String(bad)} 應降級`);
  }
});

Deno.test("draw：visiblePracticeThreadId 過長 → invalid_visiblePracticeThreadId", () => {
  assertThrows(
    () =>
      validateDrawRequest({
        mode: "draw_profile",
        requestId: "req-1",
        visiblePracticeThreadId: "x".repeat(129),
      }),
    Error,
    "invalid_visiblePracticeThreadId",
  );
});
