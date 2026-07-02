// supabase/functions/analyze-chat/opener_payload_test.ts

import {
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  filterOpenerPayloadForAllowedFeatures,
  normalizeOpenerPayload,
  sanitizeOpenerText,
} from "./opener_payload.ts";

const ALL_FEATURES = [
  "extend",
  "resonate",
  "tease",
  "humor",
  "coldRead",
] as const;

Deno.test("sanitizeOpenerText 擋 JSON/code fence/超長，收合法短句", () => {
  assertEquals(sanitizeOpenerText("你好，看到你養柴犬"), "你好，看到你養柴犬");
  assertEquals(sanitizeOpenerText("  留白修剪  "), "留白修剪");
  assertEquals(sanitizeOpenerText({ text: "巢狀欄位也收" }), "巢狀欄位也收");
  assertEquals(sanitizeOpenerText('{"openers": {}}'), null);
  assertEquals(sanitizeOpenerText("```json\n{}\n```"), null);
  assertEquals(sanitizeOpenerText("a".repeat(181)), null);
  assertEquals(sanitizeOpenerText(""), null);
  assertEquals(sanitizeOpenerText(42), null);
});

Deno.test("normalizeOpenerPayload 全空 openers 回 null，合法句保留", () => {
  assertEquals(normalizeOpenerPayload(null), null);
  assertEquals(
    normalizeOpenerPayload({ openers: { extend: "{raw json}" } }),
    null,
  );

  const normalized = normalizeOpenerPayload({
    openers: { extend: "延展句", tease: { text: "調情句" }, humor: 42 },
    other: "keep",
  });
  assertEquals(normalized?.openers, { extend: "延展句", tease: "調情句" });
  assertEquals(normalized?.other, "keep");
});

Deno.test("filterOpener 只留 allowed 風格，全被過濾時回 null", () => {
  const filtered = filterOpenerPayloadForAllowedFeatures(
    { openers: { extend: "延展句", tease: "調情句" } },
    ["extend"],
  );
  assertEquals(filtered?.openers, { extend: "延展句" });

  assertEquals(
    filterOpenerPayloadForAllowedFeatures(
      { openers: { tease: "調情句" } },
      ["extend"],
    ),
    null,
  );
});

Deno.test("filterOpener 頂層 recommendedPick 合法且有句時沿用，並保留 reason", () => {
  const filtered = filterOpenerPayloadForAllowedFeatures(
    {
      openers: { extend: "延展句", humor: "幽默句" },
      recommendedPick: "humor",
      recommendedReason: "幽默對上她的動態",
    },
    ALL_FEATURES,
  );
  assertEquals(filtered?.recommendedPick, "humor");
  assertEquals(filtered?.recommendedReason, "幽默對上她的動態");
});

// 2026-07-02 Eric 拍板：模型 schema 只吐 recommendation.pick（client 也只讀
// 這欄），頂層 recommendedPick 是本函式 fallback 注入的，恆為 extend＝同一
// response 兩欄矛盾。頂層必須優先對齊 recommendation.pick（合法＋tier
// allowed＋openers 有句），fallback 只在 recommendation.pick 不可用時兜底。
Deno.test("filterOpener 頂層缺 recommendedPick 時對齊 recommendation.pick", () => {
  const filtered = filterOpenerPayloadForAllowedFeatures(
    {
      openers: { extend: "延展句", tease: "調情句" },
      recommendation: { pick: "tease", reason: "她的動態在丟球" },
    },
    ALL_FEATURES,
  );
  assertEquals(filtered?.recommendedPick, "tease");
});

Deno.test("filterOpener 兩欄矛盾時 recommendation.pick 勝（兩欄一致）", () => {
  const filtered = filterOpenerPayloadForAllowedFeatures(
    {
      openers: { extend: "延展句", tease: "調情句", humor: "幽默句" },
      recommendedPick: "humor",
      recommendation: { pick: "tease", reason: "她的動態在丟球" },
    },
    ALL_FEATURES,
  );
  assertEquals(filtered?.recommendedPick, "tease");
});

Deno.test("filterOpener recommendation.pick 不在 tier allowed 時 fallback 兜底", () => {
  const filtered = filterOpenerPayloadForAllowedFeatures(
    {
      openers: { extend: "延展句", tease: "調情句" },
      recommendation: { pick: "tease", reason: "調情最對味" },
    },
    ["extend"],
  );
  assertEquals(filtered?.recommendedPick, "extend");
  // recommendation 本體不改寫：client 端 bestOpenerType 對缺句 pick 自帶 fallback
  assertEquals(
    (filtered?.recommendation as Record<string, unknown>).pick,
    "tease",
  );
});

Deno.test("filterOpener recommendation.pick 非法或缺句時 fallback 兜底", () => {
  const illegal = filterOpenerPayloadForAllowedFeatures(
    {
      openers: { resonate: "共鳴句" },
      recommendation: { pick: "banana", reason: "非法值" },
    },
    ALL_FEATURES,
  );
  assertEquals(illegal?.recommendedPick, "resonate");

  const missingLine = filterOpenerPayloadForAllowedFeatures(
    {
      openers: { extend: "延展句" },
      recommendation: { pick: "coldRead", reason: "冷讀但沒句子" },
    },
    ALL_FEATURES,
  );
  assertEquals(missingLine?.recommendedPick, "extend");
});

Deno.test("filterOpener 頂層 recommendedPick 無效時 fallback 首個有句風格並刪 reason", () => {
  const filtered = filterOpenerPayloadForAllowedFeatures(
    {
      openers: { resonate: "共鳴句", humor: "幽默句" },
      recommendedPick: "banana",
      recommendedReason: "不該留下來的理由",
    },
    ALL_FEATURES,
  );
  assertEquals(filtered?.recommendedPick, "resonate");
  assertEquals("recommendedReason" in (filtered ?? {}), false);
});
