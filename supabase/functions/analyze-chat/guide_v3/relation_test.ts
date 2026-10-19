// 關係訊號（開關 ANALYZE_GUIDE_V3_RELATION，Bruce 2026-10-19 路線二）：開關怎麼讀、入口怎麼接，
// 讀局面多要的三欄（schema、提示詞、逐欄檢查）。不呼叫模型、不連網。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "../../_shared/prompt_leak_guard.ts";
import { readSystemPrompt } from "./prompts.ts";
import { READ_TAGS_SCHEMA } from "./read_tags.ts";
import {
  GAME_STAGES,
  parseRelation,
  READ_TAGS_SCHEMA_WITH_RELATION,
  readSystemPromptWithRelation,
  RELATION_DIMENSIONS,
  RELATION_FIELD_NOTES,
  RELATION_SCORE_MAX,
  RELATION_SCORE_MIN,
  type RelationField,
  withRelationFields,
} from "./relation.ts";
import { guideV3Mode, shouldReadGuideV3Relation } from "./routing.ts";

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
