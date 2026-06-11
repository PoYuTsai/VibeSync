import { bandForBillableChars, computeBillingPayloadHash, countPayloadChars } from "../../supabase/functions/analyze-chat/billing.ts";

type Spec = { name: string; contents: Array<string | { repeat: string; times: number }> };
const specs: Spec[] = [
  { name: "simple_chinese", contents: ["你好"] },
  { name: "known_sha256_abc", contents: ["abc"] },
  { name: "trim_whitespace", contents: [" ab ", "c"] },
  { name: "emoji_two_units_each", contents: ["😀😀😀"] },
  { name: "zero_width_counted", contents: ["a​b"] },
  { name: "two_units_41", contents: [{ repeat: "a", times: 41 }] },
  { name: "soft_cap_edge_400", contents: [{ repeat: "好", times: 400 }] },
  { name: "buffer_band_401", contents: [{ repeat: "a", times: 401 }] },
  { name: "buffer_band_2000", contents: [{ repeat: "安", times: 2000 }] },
  { name: "overcharge_2001", contents: [{ repeat: "a", times: 2001 }] },
  { name: "overcharge_4000", contents: [{ repeat: "安", times: 4000 }] },
  { name: "reject_4001", contents: [{ repeat: "a", times: 4001 }] },
  { name: "multi_message_mixed", contents: ["哈囉😀", "今天 要去夜市嗎？"] },
  { name: "boundary_no_collision_a_b", contents: ["a b"] },
  { name: "boundary_no_collision_a__b", contents: ["a", "b"] },
];

function expand(c: string | { repeat: string; times: number }): string {
  return typeof c === "string" ? c : c.repeat.repeat(c.times);
}

const vectors = [];
for (const spec of specs) {
  const contents = spec.contents.map(expand);
  const messages = contents.map((content) => ({ content }));
  const charCount = countPayloadChars(messages);
  const band = bandForBillableChars(charCount);
  vectors.push({
    name: spec.name,
    contents: spec.contents,
    charCount,
    band: band.band,
    units: band.band === "reject" ? null : (band as { units: number }).units,
    sha256: await computeBillingPayloadHash(messages),
  });
}
console.log(JSON.stringify({
  _comment: "ADR #19 JS/Dart 計費鏡像共用樣本（規格 #4 mirror tests）。由 tools 腳本以 server billing.ts 生成；known_sha256_abc 的 hash 是外部已知常數，釘死 SHA-256 演算法本身。兩端測試（billing_test.ts / message_calculator_test.dart）必須同時讀本檔。",
  vectors,
}, null, 2));
