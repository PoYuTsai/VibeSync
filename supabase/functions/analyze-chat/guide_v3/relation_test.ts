// 關係訊號（開關 ANALYZE_GUIDE_V3_RELATION，Bruce 2026-10-19 路線二）：開關怎麼讀、入口怎麼接，
// 讀局面多要的三欄（schema、提示詞、逐欄檢查），以及那一段的外洩哨兵。不呼叫模型、不連網。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "../../_shared/prompt_leak_guard.ts";
import {
  leakVariants,
  SENTINEL_LISTS,
} from "../../_shared/prompt_leak_harness.ts";
import fixtures from "../testdata/guide_v3_replay_fixtures.json" with {
  type: "json",
};
import { vetPlanText } from "./finalize.ts";
import { type GuideV3Plan, HOLD_WAIT_FALLBACK } from "./plan.ts";
import { readSystemPrompt } from "./prompts.ts";
import { HER_MOVES, READ_TAGS_SCHEMA } from "./read_tags.ts";
import {
  GAME_STAGES,
  parseRelation,
  READ_TAGS_SCHEMA_WITH_RELATION,
  readSystemPromptWithRelation,
  RELATION_DIMENSIONS,
  RELATION_FIELD_NOTES,
  RELATION_LEAK_SENTINELS,
  RELATION_SCORE_MAX,
  RELATION_SCORE_MIN,
  RELATION_SENTINELS,
  RELATION_SENTINELS_NORMALIZED,
  type RelationField,
  withRelationFields,
} from "./relation.ts";
import { guideV3Mode, shouldReadGuideV3Relation } from "./routing.ts";
import { HER_MOVE_CODE, readView, relationView } from "./wire.ts";

Deno.test("關係訊號開關：沒設或打錯都不開；test 只給測試帳號；on 誰都開", () => {
  for (const raw of [undefined, "", "true", "1", "offf"]) {
    for (const accountIsTest of [true, false]) {
      assertEquals(
        shouldReadGuideV3Relation({ mode: guideV3Mode(raw), accountIsTest }),
        false,
        `${raw}/${accountIsTest}`,
      );
    }
  }
  assertEquals(
    shouldReadGuideV3Relation({ mode: "test", accountIsTest: true }),
    true,
  );
  assertEquals(
    shouldReadGuideV3Relation({ mode: "test", accountIsTest: false }),
    false,
  );
  for (const accountIsTest of [true, false]) {
    assertEquals(
      shouldReadGuideV3Relation({ mode: guideV3Mode(" On "), accountIsTest }),
      true,
    );
  }
});

const handlerSource = await Deno.readTextFile(
  new URL("../analyze_chat_handler.ts", import.meta.url),
);

function at(needle: string): number {
  const index = handlerSource.indexOf(needle);
  assert(index >= 0, `找不到：${needle}`);
  return index;
}

Deno.test("關係訊號開關只在 v3 入口讀一次，交給流程（每次請求讀，跟對象記憶一樣）", () => {
  const v3Call = at("return await handleGuideV3Stream({");
  const v2Dispatch = at(
    'if (responseMode === "stream") {\n      return await handleAnalyzeStream({',
  );
  const wiring = at(
    'relation: shouldReadGuideV3Relation({\n          mode: guideV3Mode(Deno.env.get("ANALYZE_GUIDE_V3_RELATION")),\n          accountIsTest,\n        }),',
  );
  assert(v3Call < wiring && wiring < v2Dispatch);
  assertEquals(
    handlerSource.split('Deno.env.get("ANALYZE_GUIDE_V3_RELATION")').length -
      1,
    1,
  );
});

type Schema = {
  type: string;
  additionalProperties: boolean;
  required: string[];
  properties: Record<string, unknown>;
};

const RELATION_KEYS: readonly RelationField[] = [
  "gameStage",
  "heatScore",
  "dimensions",
];

Deno.test("讀局面 schema（開關開）：原本的欄位與順序不動，三欄排在最後、都必填", () => {
  const base = READ_TAGS_SCHEMA as Schema;
  const on = READ_TAGS_SCHEMA_WITH_RELATION as Schema;
  assertEquals(Object.keys(on), Object.keys(base));
  assertEquals(on.type, base.type);
  assertEquals(on.additionalProperties, false);
  assertEquals(on.required, [...base.required, ...RELATION_KEYS]);
  assertEquals(Object.keys(on.properties), [
    ...Object.keys(base.properties),
    ...RELATION_KEYS,
  ]);
  for (const key of Object.keys(base.properties)) {
    assertEquals(on.properties[key], base.properties[key], key);
  }
  assertEquals(GAME_STAGES, [
    "opening",
    "premise",
    "qualification",
    "narrative",
    "close",
  ]);
  assertEquals(on.properties.gameStage, {
    type: "string",
    enum: [...GAME_STAGES],
  });
  assertEquals(on.properties.heatScore, { type: "integer" });
  assertEquals(on.properties.dimensions, {
    type: "object",
    additionalProperties: false,
    required: [
      "engagement",
      "topicDepth",
      "replyWillingness",
      "emotionalConnection",
    ],
    properties: {
      engagement: { type: "integer" },
      topicDepth: { type: "integer" },
      replyWillingness: { type: "integer" },
      emotionalConnection: { type: "integer" },
    },
  });
  // 結構化輸出不支援數值範圍：0–100 在程式裡檢查，schema 裡不能出現。
  const text = JSON.stringify(on);
  for (const unsupported of ["minimum", "maximum", "multipleOf"]) {
    assert(
      !text.toLowerCase().includes(unsupported.toLowerCase()),
      unsupported,
    );
  }
});

Deno.test("三欄接在任何一份讀局面 schema 的最後，原本那份不改（之後跟別的實驗的 schema 合併也一樣）", () => {
  const other: Schema = {
    type: "object",
    additionalProperties: false,
    required: ["light", "extra"],
    properties: { light: { type: "string" }, extra: { type: "boolean" } },
  };
  const on = withRelationFields(other) as Schema;
  assertEquals(on.required, ["light", "extra", ...RELATION_KEYS]);
  assertEquals(Object.keys(on.properties), [
    "light",
    "extra",
    ...RELATION_KEYS,
  ]);
  assertEquals(other.required, ["light", "extra"]);
  assertEquals(Object.keys(other.properties), ["light", "extra"]);
});

Deno.test("讀局面提示詞（開關開）：欄位說明之後多一段關係狀態，其他一字不變，保密指示照舊在最後", () => {
  const base = readSystemPrompt();
  const on = readSystemPromptWithRelation();
  const triggers = "\n\n## 情境條目的觸發";
  assertEquals(base.split(triggers).length, 2);
  assertEquals(
    on,
    base.replace(triggers, `\n\n${RELATION_FIELD_NOTES}${triggers}`),
  );
  assert(on.endsWith(PROMPT_LEAK_DEFENSE_DIRECTIVE.trim()));
  // 提示詞跟 schema 用同一組欄位名與代碼：改了一邊忘了另一邊就會失敗。
  for (
    const word of [...RELATION_KEYS, ...GAME_STAGES, ...RELATION_DIMENSIONS]
  ) {
    assert(RELATION_FIELD_NOTES.includes(word), word);
  }
  assert(
    RELATION_FIELD_NOTES.includes(
      `${RELATION_SCORE_MIN}–${RELATION_SCORE_MAX} 的整數`,
    ),
  );
});

const DIMENSIONS = {
  engagement: 70,
  topicDepth: 55,
  replyWillingness: 65,
  emotionalConnection: 50,
};
const GOOD = {
  gameStage: "qualification",
  heatScore: 62,
  dimensions: DIMENSIONS,
};

Deno.test("關係訊號檢查：三欄都對就照收（每個階段、邊界 0 與 100 都收），其他標記不看", () => {
  assertEquals(parseRelation({ light: "green", ...GOOD }), {
    stage: "qualification",
    heat: 62,
    dimensions: DIMENSIONS,
    dropped: [],
  });
  for (const stage of GAME_STAGES) {
    assertEquals(parseRelation({ ...GOOD, gameStage: stage }).stage, stage);
  }
  const edge = parseRelation({
    gameStage: "close",
    heatScore: RELATION_SCORE_MIN,
    dimensions: {
      engagement: RELATION_SCORE_MAX,
      topicDepth: RELATION_SCORE_MIN,
      replyWillingness: RELATION_SCORE_MAX,
      emotionalConnection: RELATION_SCORE_MIN,
    },
  });
  assertEquals(edge.dropped, []);
  assertEquals(edge.heat, RELATION_SCORE_MIN);
  assertEquals(edge.dimensions?.engagement, RELATION_SCORE_MAX);
});

Deno.test("關係訊號檢查：沒給的那一欄記 missing，其他照收；整個不是物件就三欄都 missing", () => {
  for (const field of RELATION_KEYS) {
    const rest = Object.fromEntries(
      Object.entries(GOOD).filter(([k]) => k !== field),
    );
    const out = parseRelation(rest);
    assertEquals(out.dropped, [{ field, reason: "missing" }], field);
    assertEquals(
      Object.keys(out).filter((k) => k !== "dropped").length,
      2,
      field,
    );
  }
  for (const value of [null, undefined, "text", 3, []]) {
    assertEquals(parseRelation(value), {
      dropped: RELATION_KEYS.map((field) => ({
        field,
        reason: "missing" as const,
      })),
    });
  }
});

Deno.test("關係訊號檢查：熱度不是 0–100 的整數、階段不在選項裡，就拿掉那一欄（不夾到範圍內）", () => {
  for (const heatScore of [-1, 101, 62.5, "62", null, true, {}]) {
    const out = parseRelation({ ...GOOD, heatScore });
    assertEquals(out.dropped, [{ field: "heatScore", reason: "invalid" }]);
    assertEquals("heat" in out, false, JSON.stringify(heatScore));
    assertEquals(out.stage, "qualification");
    assertEquals(out.dimensions, DIMENSIONS);
  }
  for (const gameStage of ["dating", "Opening", " close", "", null, 3]) {
    const out = parseRelation({ ...GOOD, gameStage });
    assertEquals(out.dropped, [{ field: "gameStage", reason: "invalid" }]);
    assertEquals("stage" in out, false, JSON.stringify(gameStage));
    assertEquals(out.heat, 62);
  }
});

Deno.test("關係訊號檢查：四個維度要全部是 0–100 的整數，缺一個或壞一個就整組拿掉；多給的欄位不收", () => {
  const broken = [
    { engagement: 70, topicDepth: 55, replyWillingness: 65 },
    { ...DIMENSIONS, topicDepth: 101 },
    { ...DIMENSIONS, emotionalConnection: -5 },
    { ...DIMENSIONS, engagement: 70.5 },
    { ...DIMENSIONS, replyWillingness: "65" },
    [70, 55, 65, 50],
    "70",
    null,
  ];
  for (const dimensions of broken) {
    const out = parseRelation({ ...GOOD, dimensions });
    assertEquals(out.dropped, [{ field: "dimensions", reason: "invalid" }]);
    assertEquals("dimensions" in out, false, JSON.stringify(dimensions));
    assertEquals(out.heat, 62);
  }
  const extra = parseRelation({
    ...GOOD,
    dimensions: { ...DIMENSIONS, heat: 99, mood: 3 },
  });
  assertEquals(extra.dimensions, DIMENSIONS);
  assertEquals(extra.dropped, []);
});

Deno.test("她這一輪在做什麼的代碼：十一類都有，不重複，都是小寫英文與底線", () => {
  assertEquals(Object.keys(HER_MOVE_CODE), [...HER_MOVES]);
  const codes = Object.values(HER_MOVE_CODE);
  assertEquals(new Set(codes).size, HER_MOVES.length);
  for (const code of codes) assert(/^[a-z]+(_[a-z]+)*$/.test(code), code);
});

const SIGNALS_PLAN: GuideV3Plan = {
  decision: "send",
  judgment: "她在分享日常，氣氛輕鬆。",
  reason: "照常回",
  waitFor: "",
  push: null,
  specs: [],
  entries: [],
  signals: {
    inviteReadiness: "沒機會",
    cold: { c1: false, herPerfunctoryStreak: 0 },
  },
};

const MOVE = { herMove: "調侃", replyWillingness: "high" } as const;

Deno.test("判讀的 relation：照合約的欄位與順序，雷達的 heat 用熱度補上", () => {
  const view = relationView({
    stage: "qualification",
    heat: 62,
    dimensions: DIMENSIONS,
  }, MOVE);
  // 用 JSON 字串比，連欄位順序一起鎖住。
  assertEquals(
    JSON.stringify(view),
    JSON.stringify({
      stage: "qualification",
      heat: 62,
      dimensions: {
        heat: 62,
        engagement: 70,
        topicDepth: 55,
        replyWillingness: 65,
        emotionalConnection: 50,
      },
      herMove: "teasing",
      willingness: "high",
    }),
  );
});

Deno.test("判讀的 relation：沒通過檢查的不放；熱度沒過時雷達整組不放；三欄都沒有就沒有 relation", () => {
  assertEquals(relationView({ stage: "close" }, MOVE), {
    stage: "close",
    herMove: "teasing",
    willingness: "high",
  });
  assertEquals(relationView({ heat: 30 }, MOVE), {
    heat: 30,
    herMove: "teasing",
    willingness: "high",
  });
  assertEquals(
    relationView({ stage: "premise", dimensions: DIMENSIONS }, MOVE),
    { stage: "premise", herMove: "teasing", willingness: "high" },
  );
  assertEquals(relationView({ dimensions: DIMENSIONS }, MOVE), undefined);
  assertEquals(relationView({}, MOVE), undefined);
  assertEquals(
    relationView({ heat: 0 }, { herMove: "煞車", replyWillingness: "low" }),
    { heat: 0, herMove: "braking", willingness: "low" },
  );
});

Deno.test("判讀：relation 排在最後；沒給就跟今天一樣；自傷關心、未成年一律不帶", () => {
  const relation = relationView({ stage: "premise", heat: 70 }, MOVE)!;
  const without = readView(SIGNALS_PLAN, "green");
  const withRelation = readView(SIGNALS_PLAN, "green", relation);
  assertEquals(Object.keys(withRelation), [
    ...Object.keys(without),
    "relation",
  ]);
  assertEquals(withRelation.relation, relation);
  assertEquals("relation" in without, false);
  for (const careKind of ["self_harm", "minor"] as const) {
    const care: GuideV3Plan = {
      decision: "care",
      judgment: "",
      reason: "",
      waitFor: "",
      push: null,
      specs: [],
      entries: [],
      careKind,
      careTrigger: "model",
    };
    assertEquals(readView(care, "green", relation), readView(care, "green"));
    assertEquals("relation" in readView(care, "green", relation), false);
  }
});

// ---- 關係狀態那一段的外洩哨兵（主審第 1 輪 P2） ----

Deno.test("關係狀態那一段的外洩哨兵：每句都照抄自那一段，每一行都有，整理過的那份一起比，也登記在共用清單", () => {
  for (const sentinel of RELATION_SENTINELS) {
    assert(RELATION_FIELD_NOTES.includes(sentinel), sentinel);
  }
  // 標題、階段、熱度、四個維度每一行都至少有一句。
  const lines = RELATION_FIELD_NOTES.split("\n").filter((l) => l.trim());
  assertEquals(lines.length, 4);
  for (const line of lines) {
    assert(RELATION_SENTINELS.some((s) => line.includes(s)), line);
  }
  assertEquals(RELATION_LEAK_SENTINELS, [
    ...new Set([...RELATION_SENTINELS, ...RELATION_SENTINELS_NORMALIZED]),
  ]);
  // 共用的哨兵測試（各種照抄寫法都抓得到、至少 8 字、一般聊天與錄下的輸出都不中）照這份清單跑。
  assertEquals(SENTINEL_LISTS.RELATION_SENTINELS, RELATION_SENTINELS);
  assertEquals(
    SENTINEL_LISTS.RELATION_SENTINELS_NORMALIZED,
    RELATION_SENTINELS_NORMALIZED,
  );
});

function planWith(judgment: string, waitFor = ""): GuideV3Plan {
  return { ...SIGNALS_PLAN, judgment, waitFor };
}

function vetted(plan: GuideV3Plan, extra?: readonly string[]) {
  const removed: string[] = [];
  const out = vetPlanText(plan, (field) => removed.push(field), extra);
  return { judgment: out.judgment, waitFor: out.waitFor, removed };
}

/// 主審舉的例子：判讀把那一段的標題與熱度的說明照抄出來。
const COPIED_HEADING_AND_HEAT =
  "她在分享日常。最後三個欄位：關係狀態（另外記錄，不影響上面的標記）\n- heatScore：她對這段互動的熱度，0–100 的整數，只看她的訊息";

Deno.test("開關開時的判讀檢查：判讀照抄關係狀態那一段（標題、熱度的說明、每一句的各種照抄寫法）就不給；要等她做什麼換成預設那句", () => {
  assertEquals(
    vetted(planWith(COPIED_HEADING_AND_HEAT), RELATION_LEAK_SENTINELS),
    { judgment: "", waitFor: "", removed: ["judgment"] },
  );
  let checks = 0;
  const missed: string[] = [];
  for (const sentinel of RELATION_SENTINELS) {
    for (const variant of leakVariants(sentinel)) {
      checks++;
      const out = vetted(
        planWith(`她回得很長，${variant}，可以接著聊。`, `等她${variant}再回`),
        RELATION_LEAK_SENTINELS,
      );
      if (
        out.judgment !== "" || out.waitFor !== HOLD_WAIT_FALLBACK ||
        out.removed.join() !== "judgment,waitFor"
      ) missed.push(JSON.stringify(variant));
    }
  }
  assertEquals(missed, []);
  // 每一句至少有原樣與插空白兩種寫法：確認真的每句都跑過，不是空迴圈。
  assert(checks >= RELATION_SENTINELS.length * 2, String(checks));
});

Deno.test("開關開時的判讀檢查：一般判讀照給——錄下的判讀與要等她做什麼、講到熱度或步調的一般說法，結果跟不多比一樣", () => {
  const natural = [
    "她對這段互動的熱度不低，回得長還反問你，可以接著聊。",
    "她回得短、話題也轉走了，先別急著追。",
    "你們生活步調合不合還看不出來，先接她的話就好。",
    "她把週五的票留給你，等於主動約你，直接答應就好。",
  ];
  const recorded = fixtures.cases.flatMap((c) => {
    const tags = JSON.parse(c.readText) as Record<string, unknown>;
    return [tags.readForUser, tags.waitFor].filter((t): t is string =>
      typeof t === "string" && t.trim() !== ""
    );
  });
  assertEquals(recorded.length, 28);
  for (const text of [...natural, ...recorded]) {
    const plan = planWith(text, text);
    const on = vetted(plan, RELATION_LEAK_SENTINELS);
    assertEquals(on, vetted(plan), text);
    assertEquals(on.removed, [], text);
    assert(on.judgment !== "", text);
  }
});

Deno.test("開關沒開時不多比（跟 afa50d6f 一樣）：模型看不到那一段，同一句照舊通過", () => {
  const plan = planWith(COPIED_HEADING_AND_HEAT);
  assertEquals(vetted(plan), vetted(plan, []));
  assertEquals(vetted(plan).removed, []);
  assert(vetted(plan).judgment.includes("最後三個欄位"));
});
