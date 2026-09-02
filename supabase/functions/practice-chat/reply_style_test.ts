// reply-style-v1 資料層自測（規格 §8.1）：mapping 明確、無複製人、renderer 乾淨。
import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  renderReplyStyleGuidance,
  replyStyleFor,
  STYLE_BY_PROFILE_ID,
  styleFingerprint,
} from "./reply_style.ts";
import { GIRL_PROFILES } from "./practice_persona.ts";
import { hasVisibleInternalLabelLeak } from "./visible_text_guard.ts";

Deno.test("mapping 只指向真實存在的 profile，且沒有 mapping 的角色回 null", () => {
  const known = new Set(GIRL_PROFILES.map((g) => g.profileId));
  for (const id of Object.keys(STYLE_BY_PROFILE_ID)) assert(known.has(id), id);
  assertEquals(replyStyleFor("practice_girl_999"), null);
  assertNotEquals(replyStyleFor("practice_girl_001"), null);
});

Deno.test("沒有兩人 fingerprint 相同；同一 preset 也要有個人覆寫", () => {
  const prints = Object.values(STYLE_BY_PROFILE_ID).map(styleFingerprint);
  assertEquals(new Set(prints).size, prints.length);
  for (const s of Object.values(STYLE_BY_PROFILE_ID)) {
    assert(s.habits.length >= 2 && s.habits.length <= 3, s.presetId);
    assert(s.turnTaking.bubbleRange[0] <= s.turnTaking.bubbleRange[1]);
    assert(s.turnTaking.charRange[0] < s.turnTaking.charRange[1]);
    assert(s.responseBiases.boundary?.length, "boundary bias required");
  }
});

Deno.test("renderer 不含例句、不含可見內部標籤、長度有上限", () => {
  for (const [id, s] of Object.entries(STYLE_BY_PROFILE_ID)) {
    const text = renderReplyStyleGuidance(s);
    assert(text.length <= 320, `${id} ${text.length}`);
    assert(
      !/「[^」]{6,}」/u.test(text.replace(/「(哈哈|你呢)」/g, "")),
      `${id} 疑似例句`,
    );
    assert(
      !hasVisibleInternalLabelLeak(text.replace(/hidden guidance/g, "")),
      id,
    );
    assert(!text.includes(s.presetId), "preset 名稱不可進 prompt");
  }
});

Deno.test("mapping 不依賴年齡／城市／職業：同職業或同城市的人不共用同一份 style", () => {
  const byProfile = GIRL_PROFILES.filter((g) =>
    STYLE_BY_PROFILE_ID[g.profileId]
  );
  for (const a of byProfile) {
    for (const b of byProfile) {
      if (a === b) continue;
      if (a.city === b.city || a.professionId === b.professionId) {
        assertNotEquals(
          styleFingerprint(STYLE_BY_PROFILE_ID[a.profileId]),
          styleFingerprint(STYLE_BY_PROFILE_ID[b.profileId]),
        );
      }
    }
  }
});
