// reply-style-v1 資料層自測（規格 §8.1）：mapping 明確、無結構複製人、renderer 乾淨。
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

Deno.test("mapping 只指向真實存在的 profile；五個 persona 各 4 位；沒有 mapping 的角色回 null", () => {
  const byId = new Map(GIRL_PROFILES.map((g) => [g.profileId, g]));
  const perPersona = new Map<string, number>();
  for (const id of Object.keys(STYLE_BY_PROFILE_ID)) {
    const girl = byId.get(id);
    assert(girl, id);
    perPersona.set(girl.personaId, (perPersona.get(girl.personaId) ?? 0) + 1);
  }
  assertEquals([...perPersona.values()], [4, 4, 4, 4, 4]);
  assertEquals(replyStyleFor("practice_girl_999"), null);
});

Deno.test("結構 fingerprint（不含 preset 名與 habits 文字）兩兩不同；每個 persona 覆蓋多個 preset", () => {
  const prints = Object.values(STYLE_BY_PROFILE_ID).map(styleFingerprint);
  assertEquals(new Set(prints).size, prints.length);
  const byId = new Map(GIRL_PROFILES.map((g) => [g.profileId, g]));
  const presetsPerPersona = new Map<string, Set<string>>();
  for (const [id, s] of Object.entries(STYLE_BY_PROFILE_ID)) {
    assert(s.habits.length <= 3, id);
    assert(s.turnTaking.bubbleRange[0] <= s.turnTaking.bubbleRange[1]);
    assert(s.turnTaking.charRange[0] < s.turnTaking.charRange[1]);
    assert(s.responseBiases.boundary?.length, "boundary bias required");
    const persona = byId.get(id)!.personaId;
    presetsPerPersona.set(
      persona,
      (presetsPerPersona.get(persona) ?? new Set()).add(s.presetId),
    );
  }
  for (const [persona, presets] of presetsPerPersona) {
    assert(presets.size >= 3, persona);
  }
});

Deno.test("renderer 不含例句、不含可見內部標籤、長度有上限；笑法四種 mode 各有正確措辭", () => {
  for (const [id, s] of Object.entries(STYLE_BY_PROFILE_ID)) {
    const text = renderReplyStyleGuidance(s);
    assert(text.length <= 360, `${id} ${text.length}`);
    assert(
      !/「[^」]{6,}」/u.test(text.replace(/「(哈哈|你呢|笑死)」/g, "")),
      `${id} 疑似例句`,
    );
    assert(
      !hasVisibleInternalLabelLeak(
        text.replace(
          /你平常的說話習慣（hidden guidance，這是你本人的樣子，不要向對方描述它）：/g,
          "",
        ),
      ),
      id,
    );
    assert(!text.includes(s.presetId), "preset 名稱不可進 prompt");
    assert(
      text.includes(
        `${s.turnTaking.charRange[0]}～${s.turnTaking.charRange[1]} 字`,
      ),
    );
    const mode = s.surface.laughter.mode;
    if (mode === "word") {
      assert(text.includes("笑死") && !text.includes("短短的哈哈"), id);
    }
    if (mode === "long") assert(text.includes("長串哈哈"), id);
    if (mode === "rare") assert(text.includes("幾乎不打哈哈"), id);
    if (mode === "short") assert(text.includes("短短的哈哈"), id);
  }
});

Deno.test("mapping 不依賴年齡／城市／職業：同職業或同城市的人結構 fingerprint 不同", () => {
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
