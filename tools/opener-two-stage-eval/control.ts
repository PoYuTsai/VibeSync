// 舊單段控制組的 user content（R6a）：只吃對方資料、走正式 mode: opener 的
// buildLegacyOpenerUserContent；不經第一段 user content、不看初稿、不看 A／B 補充。
// 「舊單段＋A 補充」附加實驗另外接在這個字串後面（run.ts --legacy-plus-a）。
import { buildLegacyOpenerUserContent } from "../../supabase/functions/analyze-chat/opener_prompt.ts";
import { normalizeOpenerProfileInfo } from "../../supabase/functions/analyze-chat/opener_profile.ts";
import type { EvalScenario } from "./fixtures.ts";

export function legacyControlUserContent(scenario: EvalScenario): string {
  const profile = normalizeOpenerProfileInfo(scenario.profileInfo);
  return buildLegacyOpenerUserContent({ normalizedProfile: profile, imageCount: 0, openerStyleContext: null }).join("\n");
}
