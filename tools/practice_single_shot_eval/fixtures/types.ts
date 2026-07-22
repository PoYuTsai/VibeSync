// 四路黑箱 eval fixture 型別（Batch H1）。
// 只 import practice-chat 的型別，不碰任何 handler / DB / ledger 邏輯。
import type {
  AppliedHintTurn,
  PracticeTurn,
} from "../../../supabase/functions/practice-chat/validate.ts";
import type { PracticeLearningMode } from "../../../supabase/functions/practice-chat/quota_decision.ts";
import type { PartnerMood } from "../../../supabase/functions/practice-chat/temperature.ts";
import type { PersistedGameState } from "../../../supabase/functions/practice-chat/game_state.ts";
import type {
  PersonaId,
  PracticeDifficulty,
} from "../../../supabase/functions/practice-chat/practice_persona.ts";

export type EvalRoute =
  | "beginner_hint"
  | "game_hint"
  | "beginner_debrief"
  | "game_debrief";

export interface EvalFixture {
  id: string;
  route: EvalRoute;
  /** 對應 request.practiceMode（beginner｜game）。 */
  practiceMode: PracticeLearningMode;
  /** 交給 resolvePracticeProfile 的 allowlist 參數。 */
  profileArgs: {
    personaId: PersonaId;
    difficulty: PracticeDifficulty;
  };
  /** 對應 ledger.temperatureScore。 */
  temperatureScore: number;
  /** 對應 ledger.familiarityScore。 */
  familiarityScore: number;
  /** 對應 partnerStateFromLedger(ledger)?.mood。 */
  partnerMood: PartnerMood | null;
  /** 逐字稿：user=使用者、ai=練習對象。 */
  turns: PracticeTurn[];
  /** Game 路徑必填（FSM 持久化狀態）；新手路徑 null。 */
  gameState: PersistedGameState | null;
  /** 對應 ledgerAppliedHintTurns；本 eval 一律走「本場沒套用提示」。 */
  appliedHintTurns: AppliedHintTurn[];
  /** 對應 promptMemorySummary；null＝無長期記憶。 */
  memorySummary: string | null;
}
