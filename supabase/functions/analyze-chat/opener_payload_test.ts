// supabase/functions/analyze-chat/opener_payload_test.ts

import {
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildOpenerAccess,
  buildWrongSurfaceErrorBody,
  detectOpenerWrongSurface,
  filterOpenerPayloadForAllowedFeatures,
  missingOpenerTypes,
  normalizeOpenerPayload,
  normalizeStretchLevels,
  OPENER_FREE_V1_TYPES,
  OPENER_FREE_V2_LOCKED_TYPES,
  OPENER_FREE_V2_TYPES,
  parseOpenerContractVersion,
  sanitizeOpenerText,
} from "./opener_payload.ts";

const ALL_FEATURES = [
  "extend",
  "resonate",
  "tease",
  "humor",
  "coldRead",
] as const;

// 2026-08-19 真機實錄：聊天截圖誤餵 opener，模型把拒答說明寫進五張卡照常
// 渲染＋扣費。拒答句保底清空（第一層是 wrongSurface 旗標，見 index.ts）。
Deno.test("sanitizeOpenerText 擋拒答說明句", () => {
  assertEquals(
    sanitizeOpenerText("目前截圖資訊不足，無法生成開場白，請提供對方的交友軟體或社群截圖。"),
    null,
  );
  assertEquals(sanitizeOpenerText("無法產生開場白，請提供更多資訊"), null);
  assertEquals(sanitizeOpenerText("請提供對方的個人頁截圖"), null);
  assertEquals(sanitizeOpenerText("截圖資訊不足，無法判讀對方背景"), null);
  // 正常開場白不可誤殺——R1 主審 P1 構造的邊界句全部要活著。
  for (
    const legit of [
      "妳那張登山截圖也太猛，這是哪條路線",
      "請提供那張登山截圖的路線",
      "下次請提供更多截圖給我看",
      "妳的截圖資訊不足啊，多放幾張生活照",
    ]
  ) {
    assertEquals(sanitizeOpenerText(legit), legit);
  }
});

// R1 主審 P1：422 不扣費路徑的判定與回應體要有可執行測試（source-scan
// 測不到邏輯被刪）。
Deno.test("detectOpenerWrongSurface 只認白名單值且要有圖", () => {
  assertEquals(
    detectOpenerWrongSurface({ wrongSurface: "chat_conversation" }, 1),
    "chat_conversation",
  );
  assertEquals(
    detectOpenerWrongSurface({ wrongSurface: "unrelated" }, 3),
    "unrelated",
  );
  // 無圖＝純手填請求，不得走免費 422（fail-open 進正常計費路）。
  assertEquals(
    detectOpenerWrongSurface({ wrongSurface: "chat_conversation" }, 0),
    null,
  );
  // 未知值／注入形狀一律 fail-open。
  assertEquals(detectOpenerWrongSurface({ wrongSurface: "CHAT_CONVERSATION" }, 1), null);
  assertEquals(detectOpenerWrongSurface({ wrongSurface: true }, 1), null);
  assertEquals(detectOpenerWrongSurface({ wrongSurface: null }, 1), null);
  assertEquals(detectOpenerWrongSurface({}, 1), null);
  assertEquals(detectOpenerWrongSurface(null, 1), null);
});

Deno.test("buildWrongSurfaceErrorBody 固定鍵零模型內容且不扣費", () => {
  for (const surface of ["chat_conversation", "unrelated"] as const) {
    const body = buildWrongSurfaceErrorBody(surface);
    assertEquals(
      Object.keys(body).sort(),
      ["error", "message", "shouldChargeQuota", "surface"],
    );
    assertEquals(body.error, "OPENER_WRONG_SURFACE");
    assertEquals(body.surface, surface);
    assertEquals(body.shouldChargeQuota, false);
    assertEquals(body.message.includes("本次不會扣額度"), true);
  }
});

// R1 主審 P2：wrongSurface 是 parse 層消費完的旗標，healthy 200 不得殘留。
Deno.test("normalize/filter 剝除 wrongSurface 鍵", () => {
  const parsed = {
    wrongSurface: null,
    openers: { extend: "妳那隻柴犬的表情也太欠揍" },
  };
  const normalized = normalizeOpenerPayload(parsed);
  assertEquals(normalized !== null && "wrongSurface" in normalized, false);
  const filtered = filterOpenerPayloadForAllowedFeatures(
    parsed,
    ALL_FEATURES,
  );
  assertEquals(filtered !== null && "wrongSurface" in filtered, false);
});

// 分則（2026-08-19）：模型常吐字面 \n；真換行要留著讓 client 分行渲染。
Deno.test("sanitizeOpenerText 正規化換行：字面 \\n 轉真換行、壓多餘空行、逐行 trim", () => {
  assertEquals(
    sanitizeOpenerText("大夜班還在學新東西\\n有點狠欸"),
    "大夜班還在學新東西\n有點狠欸",
  );
  assertEquals(
    sanitizeOpenerText("第一則  \n\n\n  第二則"),
    "第一則\n第二則",
  );
  // 單則不受影響。
  assertEquals(sanitizeOpenerText("大夜班還在學新東西 有點狠欸"), "大夜班還在學新東西 有點狠欸");
});

Deno.test("sanitizeOpenerText 擋 JSON/code fence/超長，收合法短句", () => {
  // 傳給對方的訊息一律「妳」（見 outgoing_message_text.ts）。
  assertEquals(sanitizeOpenerText("你好，看到你養柴犬"), "妳好，看到妳養柴犬");
  assertEquals(sanitizeOpenerText("  留白修剪  "), "留白修剪");
  assertEquals(sanitizeOpenerText({ text: "巢狀欄位也收" }), "巢狀欄位也收");
  assertEquals(sanitizeOpenerText('{"openers": {}}'), null);
  assertEquals(sanitizeOpenerText("```json\n{}\n```"), null);
  // 哨兵子字串不在句首也要擋（模型把整包 JSON 塞進說明文字的洩漏形態）
  assertEquals(sanitizeOpenerText('開場白如下 "profileAnalysis" 洩漏'), null);
  assertEquals(sanitizeOpenerText('先看 "openers" 欄位再說'), null);
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

Deno.test("normalizeOpenerPayload 附帶 stretchLevels（缺欄 fallback within）", () => {
  const normalized = normalizeOpenerPayload({
    openers: { extend: "延展句" },
    stretchLevels: { extend: "stretch" },
  });
  assertEquals(normalized?.stretchLevels, {
    extend: "stretch",
    resonate: "within",
    tease: "within",
    humor: "within",
    coldRead: "within",
  });
});

Deno.test("normalizeStretchLevels：五個 key 都合法值時原樣保留", () => {
  const levels = normalizeStretchLevels({
    stretchLevels: {
      extend: "within",
      resonate: "stretch",
      tease: "far",
      humor: "stretch",
      coldRead: "within",
    },
  });
  assertEquals(levels, {
    extend: "within",
    resonate: "stretch",
    tease: "far",
    humor: "stretch",
    coldRead: "within",
  });
});

Deno.test("normalizeStretchLevels：缺一個 key → fallback 該 key 為 within，不整包拒絕", () => {
  const levels = normalizeStretchLevels({
    stretchLevels: {
      extend: "stretch",
      resonate: "far",
      tease: "stretch",
      humor: "far",
      // coldRead 缺席
    },
  });
  assertEquals(levels.coldRead, "within");
  assertEquals(levels.extend, "stretch");
});

Deno.test("normalizeStretchLevels：值不合法字串 → fallback within；整包缺席 → 全部 within", () => {
  const levels = normalizeStretchLevels({
    stretchLevels: {
      extend: "way-too-far",
      resonate: 42,
      tease: null,
    },
  });
  assertEquals(levels, {
    extend: "within",
    resonate: "within",
    tease: "within",
    humor: "within",
    coldRead: "within",
  });

  assertEquals(normalizeStretchLevels({}), {
    extend: "within",
    resonate: "within",
    tease: "within",
    humor: "within",
    coldRead: "within",
  });
});

Deno.test("filterOpener stretchLevels 只留 allowed 風格對應的 key", () => {
  const filtered = filterOpenerPayloadForAllowedFeatures(
    {
      openers: { extend: "延展句", tease: "調情句" },
      stretchLevels: { extend: "stretch", tease: "far", humor: "within" },
    },
    ["extend"],
  );
  assertEquals(filtered?.stretchLevels, { extend: "stretch" });
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

Deno.test("filterOpener recommendation.pick 不在 tier allowed 時 fallback 兜底並改寫 nested", () => {
  const filtered = filterOpenerPayloadForAllowedFeatures(
    {
      openers: { extend: "延展句", tease: "調情句" },
      recommendation: { pick: "tease", reason: "調情最對味" },
    },
    ["extend"],
  );
  assertEquals(filtered?.recommendedPick, "extend");
  // contract v2：nested recommendation 一起 canonicalize——live client 讀
  // recommendation.pick，不能讓它指向鎖卡；被鎖 pick 的 reason 不硬套 fallback。
  assertEquals(
    filtered?.recommendation,
    { pick: "extend" },
  );
});

Deno.test("filterOpener 推薦被鎖時依 fallbackOrder 取首個完整卡（Free v2）", () => {
  const filtered = filterOpenerPayloadForAllowedFeatures(
    {
      openers: {
        extend: "延展句",
        humor: "幽默句",
        tease: "調情句",
        resonate: "共鳴句",
        coldRead: "冷讀句",
      },
      recommendation: { pick: "coldRead", reason: "只適用冷讀的理由" },
    },
    OPENER_FREE_V2_TYPES,
    { fallbackOrder: OPENER_FREE_V2_TYPES },
  );
  assertEquals(filtered?.openers, {
    extend: "延展句",
    tease: "調情句",
    humor: "幽默句",
  });
  assertEquals(filtered?.recommendation, { pick: "extend" });
  assertEquals(filtered?.recommendedPick, "extend");
});

Deno.test("filterOpener 推薦落在 Free v2 可見集合時 pick/reason 原樣保留", () => {
  const filtered = filterOpenerPayloadForAllowedFeatures(
    {
      openers: {
        extend: "延展句",
        humor: "幽默句",
        tease: "調情句",
        resonate: "共鳴句",
        coldRead: "冷讀句",
      },
      recommendation: { pick: "humor", reason: "幽默對上她的動態" },
    },
    OPENER_FREE_V2_TYPES,
    { fallbackOrder: OPENER_FREE_V2_TYPES },
  );
  assertEquals(filtered?.recommendation, {
    pick: "humor",
    reason: "幽默對上她的動態",
  });
  // 鎖定內容絕不留在 Free response
  const openers = filtered?.openers as Record<string, string>;
  assertEquals("resonate" in openers, false);
  assertEquals("coldRead" in openers, false);
});

Deno.test("parseOpenerContractVersion：缺席/1→v1、>=2→v2、非法型別拒絕", () => {
  assertEquals(parseOpenerContractVersion(undefined), { ok: true, version: 1 });
  assertEquals(parseOpenerContractVersion(null), { ok: true, version: 1 });
  assertEquals(parseOpenerContractVersion(1), { ok: true, version: 1 });
  assertEquals(parseOpenerContractVersion(2), { ok: true, version: 2 });
  assertEquals(parseOpenerContractVersion(3), { ok: true, version: 2 });
  assertEquals(parseOpenerContractVersion("2"), { ok: false });
  assertEquals(parseOpenerContractVersion(1.5), { ok: false });
  assertEquals(parseOpenerContractVersion(0), { ok: false });
  assertEquals(parseOpenerContractVersion(-1), { ok: false });
});

Deno.test("missingOpenerTypes：缺句/髒句列出、五種俱全回空", () => {
  assertEquals(
    missingOpenerTypes({
      openers: {
        extend: "延展句",
        resonate: "共鳴句",
        tease: "調情句",
        humor: "幽默句",
        coldRead: "冷讀句",
      },
    }),
    [],
  );
  assertEquals(
    missingOpenerTypes({
      openers: {
        extend: "延展句",
        resonate: "共鳴句",
        tease: "```json 洩漏```",
        coldRead: "冷讀句",
      },
    }),
    ["tease", "humor"],
  );
});

Deno.test("buildOpenerAccess：visible/locked 互補且順序照 tier 展示序", () => {
  assertEquals(
    buildOpenerAccess({
      contractVersion: 2,
      servedTier: "free",
      visibleTypes: OPENER_FREE_V2_TYPES,
    }),
    {
      contractVersion: 2,
      servedTier: "free",
      visibleTypes: ["extend", "humor", "tease"],
      lockedTypes: [...OPENER_FREE_V2_LOCKED_TYPES],
    },
  );
  assertEquals(
    buildOpenerAccess({
      contractVersion: 1,
      servedTier: "free",
      visibleTypes: OPENER_FREE_V1_TYPES,
    }).lockedTypes,
    ["resonate", "tease", "humor", "coldRead"],
  );
  assertEquals(
    buildOpenerAccess({
      contractVersion: 2,
      servedTier: "essential",
      visibleTypes: ALL_FEATURES,
    }).lockedTypes,
    [],
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


Deno.test("sanitizeOpenerText 把傳給對方的「你」正規化成「妳」", () => {
  // 2026-08-19 真機：同一輪五張卡整輪飄成「你」（25 句量到 3 句）。
  assertEquals(
    sanitizeOpenerText("大夜班還有力氣學新東西，你這時間管理是點在哪"),
    "大夜班還有力氣學新東西，妳這時間管理是點在哪",
  );
  // 「你們」可能指混合群體，留著不動。
  assertEquals(
    sanitizeOpenerText("你們那棟最近吵嗎"),
    "你們那棟最近吵嗎",
  );
  // 分則（真換行）兩則都要轉。
  assertEquals(
    sanitizeOpenerText("你這自介有點狠\n但我還敢傳給你"),
    "妳這自介有點狠\n但我還敢傳給妳",
  );
});

Deno.test("sanitizeOpenerText 修中文之間的半形逗號與全形標點前的空白", () => {
  assertEquals(
    sanitizeOpenerText("自介寫到最後我有點想鞠躬,講話直接我喜歡"),
    "自介寫到最後我有點想鞠躬，講話直接我喜歡",
  );
  assertEquals(
    sanitizeOpenerText("講話直接我喜歡 ，浪費時間我也怕"),
    "講話直接我喜歡，浪費時間我也怕",
  );
  // 數字千分位前後不是中文，不動。
  assertEquals(sanitizeOpenerText("一個月 1,000 塊而已"), "一個月 1,000 塊而已");
});
