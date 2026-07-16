import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

import { normalizeGoogleMapsShares } from "./map_share_normalizer.ts";

interface TestMessage {
  side: "left" | "right" | "unknown";
  isFromMe: boolean;
  content: string;
}

function message(content: string, isFromMe = true): TestMessage {
  return {
    side: isFromMe ? "right" : "left",
    isFromMe,
    content,
  };
}

Deno.test("Google Maps URL and adjacent preview collapse to one semantic message", () => {
  const result = normalizeGoogleMapsShares([
    message("https://maps.app.goo.gl/uc5fDzbtP61xw2kz7?g_st=il"),
    message(
      "[地圖預覽] Chun Shui Tang Huashan Shop · Meihua Village, Zhongzheng... Find local businesses, view maps and get driving directions in Goo...",
    ),
  ]);

  assertEquals(result.messages, [
    message("[分享地點：Chun Shui Tang Huashan Shop]"),
  ]);
  assertEquals(result.collapsedCount, 1);
});

Deno.test("standalone Google Maps URL becomes a generic location share", () => {
  const result = normalizeGoogleMapsShares([
    message("https://maps.app.goo.gl/uc5fDzbtP61xw2kz7?g_st=il"),
  ]);

  assertEquals(result.messages, [message("[分享了 Google Maps 地點]")]);
  assertEquals(result.collapsedCount, 0);
});

Deno.test("explicit Google Maps preview keeps the place name without boilerplate", () => {
  const result = normalizeGoogleMapsShares([
    message(
      "[地圖預覽] 春水堂華山店 · 台北市中正區 Find local businesses, view maps and get driving directions in Google Maps.",
    ),
  ]);

  assertEquals(result.messages, [message("[分享地點：春水堂華山店]")]);
});

Deno.test("normal URLs and English chat remain unchanged", () => {
  const original = [
    message("https://example.com/menu"),
    message("Find local businesses near the station"),
    message("Google Maps says it closes at 9"),
  ];

  const result = normalizeGoogleMapsShares(original);

  assertEquals(result.messages, original);
  assertEquals(result.collapsedCount, 0);
});

Deno.test("different speakers never merge into one map share", () => {
  const result = normalizeGoogleMapsShares([
    message("https://maps.app.goo.gl/place", true),
    message(
      "[地圖預覽] Chun Shui Tang Huashan Shop · Taipei Find local businesses, view maps and get driving directions in Google Maps.",
      false,
    ),
  ]);

  assertEquals(result.messages, [
    message("[分享了 Google Maps 地點]", true),
    message("[分享地點：Chun Shui Tang Huashan Shop]", false),
  ]);
  assertEquals(result.collapsedCount, 0);
});

Deno.test({
  name: "OCR pipeline normalizes map shares before overlap deduplication",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );
    const normalizeIndex = source.indexOf("normalizeGoogleMapsShares(");
    const deduplicateIndex = source.indexOf(
      "deduplicateSequentialMessages(\n    mapShareAdjustment.messages",
    );

    assertEquals(normalizeIndex >= 0, true);
    assertEquals(deduplicateIndex > normalizeIndex, true);
  },
});
