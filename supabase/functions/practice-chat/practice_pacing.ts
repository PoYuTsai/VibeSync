/**
 * 標準／新手的回合下限（Eric 2026-08-12「推進慢，稍微跟 game mode 學一下」）。
 *
 * 兩個模式的推進全靠分數，但分數在一場練習裡根本到不了門檻：熟悉度 <40 永遠是
 * 「建立熟悉中」、邀約成熟度要 50（一般難度全對也只有 32-36），所以聊十個來回
 * hint 還在寫「先接住她的情緒、不要直接曖昧」。Game 已經用
 * turnPressurePhaseFloor（每顆球推一階）解掉同一個病，這裡照抄想法但慢一拍：
 * 教學模式要留練習空間，不是把她推到 P4。
 *
 * 安全網照 game：她 guarded／annoyed 時整組下限不套，退場路線優先。
 */
import type { InviteStage } from "./invite_maturity.ts";
import type { PracticeDifficulty } from "./practice_persona.ts";
import type {
  PartnerMood,
  RelationshipStage,
  RelationshipStageInfo,
} from "./temperature.ts";
import type { PracticeTurn } from "./validate.ts";

/**
 * 難度別回合下限政策表（PR 4）。守門與 prompt 都吃這一份；challenge 的
 * 模糊邀約沒有純回合數下限（invite: null），要真的把分數聊上去。
 */
const PACING_FLOORS: Record<
  PracticeDifficulty,
  { personal: number; flirt: number; invite: number | null }
> = {
  easy: { personal: 3, flirt: 6, invite: 8 },
  normal: { personal: 3, flirt: 6, invite: 8 },
  challenge: { personal: 5, flirt: 9, invite: null },
};

/** 使用者出手幾次＝這場走到第幾顆球。 */
export function practiceUserTurnCount(turns: readonly PracticeTurn[]): number {
  return turns.filter((turn) => turn.role === "user").length;
}

function floorsSuspended(mood?: PartnerMood | null): boolean {
  return mood === "guarded" || mood === "annoyed";
}

/** 關係階段下限：easy／normal 第 3 顆球聊個人、第 6 顆輕推曖昧；challenge 5／9。 */
export function practiceStageFloorFor(
  userTurnCount: number,
  mood?: PartnerMood | null,
  difficulty: PracticeDifficulty = "normal",
): RelationshipStage | null {
  if (floorsSuspended(mood)) return null;
  const floors = PACING_FLOORS[difficulty];
  if (userTurnCount >= floors.flirt) return "flirt_allowed";
  if (userTurnCount >= floors.personal) return "personal_allowed";
  return null;
}

/**
 * 邀約成熟度下限：第 8 顆球開放模糊邀約。
 * 只開到模糊（「改天一起…」）——明確邀約仍然要真的把分數聊上去。
 */
export function practiceInviteFloorFor(
  userTurnCount: number,
  mood?: PartnerMood | null,
  difficulty: PracticeDifficulty = "normal",
): InviteStage | null {
  if (floorsSuspended(mood)) return null;
  const floors = PACING_FLOORS[difficulty];
  return floors.invite !== null && userTurnCount >= floors.invite
    ? "soft_invite_ready"
    : null;
}

const STAGE_ORDER: readonly RelationshipStage[] = [
  "building_familiarity",
  "personal_allowed",
  "flirt_allowed",
];

const STAGE_LABEL: Record<RelationshipStage, RelationshipStageInfo["label"]> = {
  building_familiarity: "建立熟悉中",
  personal_allowed: "可以聊個人",
  flirt_allowed: "可以輕推曖昧",
};

export function applyStageFloor(
  info: RelationshipStageInfo,
  floor: RelationshipStage | null,
): RelationshipStageInfo {
  if (!floor) return info;
  if (STAGE_ORDER.indexOf(info.stage) >= STAGE_ORDER.indexOf(floor)) {
    return info;
  }
  return { stage: floor, label: STAGE_LABEL[floor] };
}

/**
 * 標準模式沒有任何分數，下限只能用白話講給她聽。回合數是 server 算的，
 * 不讓模型自己數。
 */
/** standard 模式的邀約回合下限是否已到（challenge 沒有下限，永遠 false）。 */
export function standardInviteFloorReached(
  userTurnCount: number,
  difficulty: PracticeDifficulty = "normal",
): boolean {
  const floor = PACING_FLOORS[difficulty].invite;
  return floor !== null && userTurnCount >= floor;
}

export function standardPacingLine(
  userTurnCount: number,
  mood?: PartnerMood | null,
  difficulty: PracticeDifficulty = "normal",
): string {
  if (floorsSuspended(mood)) return "";
  const floors = PACING_FLOORS[difficulty];
  if (floors.invite !== null && userTurnCount >= floors.invite) {
    return `\npacing: 你們已經來回 ${userTurnCount} 次了。只要對方沒有讓你不舒服，這時候你會比開場放鬆——可以主動提一點自己的事、接輕鬆的玩笑，也可以順著話題丟出你有空的時段或想去的地方。對方提「改天一起…」這種模糊邀約是自然的，不用當成太快。`;
  }
  // challenge 專用輕曖昧行（flirt: 9）：easy／normal 的第 8 回合行已涵蓋曖昧＋
  // 模糊邀約，這條只在沒有邀約回合下限（invite: null）時出現，避免改動
  // easy／normal 第 6-7 回合的既有行為。
  if (floors.invite === null && userTurnCount >= floors.flirt) {
    return `\npacing: 你們已經來回 ${userTurnCount} 次了。聊得順的話可以接一點輕鬆的玩笑、帶一點曖昧的張力，但先不急著提「改天一起…」這種邀約——她的興趣要真的被你聊起來才算數。`;
  }
  // 中段行門檻沿用原本的 personal+1（3→4），challenge 順移成 6。
  if (userTurnCount >= floors.personal + 1) {
    return `\npacing: 你們已經來回 ${userTurnCount} 次了。聊得順的話就從生活資訊往感受、偏好、小故事走一點，不要每一輪都停在客套的問答。`;
  }
  return "";
}
