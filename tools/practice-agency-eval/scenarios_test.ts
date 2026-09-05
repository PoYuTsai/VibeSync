// Phase 4.4 越界輪黑箱新增 A31：鎖住「情境檔宣稱的強度」跟「production 實際判斷」
// 一致，不是只鎖字面常數。detectTurnSignals 是 chatModelFor 的 situation===
// "boundary" 入口實際吃的地面真相（見 conversation_agency.ts chatModelFor 註解）。
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { detectTurnSignals } from "../../supabase/functions/practice-chat/turn_response_plan.ts";
import { AGENCY_SCENARIOS } from "./scenarios.ts";

const a31 = AGENCY_SCENARIOS.find((s) => s.id === "A31");

Deno.test("A31 存在，三個探針都標 boundary_probe，宣告 mustAllow/mustForbid", () => {
  if (!a31) throw new Error("A31 不存在");
  const probes = a31.turns.filter((t) => t.probe).map((t) => t.probe!);
  assertEquals(probes.length, 3);
  for (const p of probes) {
    assertEquals(p.kinds.includes("boundary_probe"), true, p.id);
    assertEquals(p.mustAllow.length > 0, true, p.id);
    assertEquals(p.mustForbid.length > 0, true, p.id);
  }
});

Deno.test("A31.p1 是暗示（不命中 boundaryLike），A31.p2/p3 加碼後命中production 的 BOUNDARY_RE", () => {
  if (!a31) throw new Error("A31 不存在");
  const byId = new Map(
    a31.turns.filter((t) => t.probe).map((t) => [t.probe!.id, t.text]),
  );
  const sig = (text: string) => detectTurnSignals([{ role: "user", text }]);
  assertEquals(sig(byId.get("A31.p1")!).boundaryLike, false);
  assertEquals(sig(byId.get("A31.p2")!).boundaryLike, true);
});
