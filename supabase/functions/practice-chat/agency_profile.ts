// conversation-agency-v1 Phase 4.0：分人強弱（`ConversationAgencyProfile`，報告 §7.3）。
//
// 四個 0–4 的欄位，每一個都有 planner／threshold consumer 與單元測試；難度表是
// base，profile 只做位移（報告 §7.4「難度只調門檻與口氣，不關掉 agency」）。
//
// **`strangerCuriosity` 刻意不新增欄位**：報告 §7.3 列的第五個欄位（值域
// rare／selective／reciprocal／curious）跟既有的 `ReplyStyleProfile.turnTaking.
// questionHabit` 值域一模一樣，而且 Phase 3.8 已經在消費它（`questionBudget`
// 的 habit 分支、`ASK_USER_EXCLUDED_HABITS`）。再開一個同義欄位只會製造兩份
// 可能漂掉的真相，所以「陌生人好奇度」＝`questionHabit`，不在本檔重複。
// 同理 `preferredCuriosityTargets` 也不做：Phase 3.7 的認識管道好奇點
// （`acquaintanceOrigin.curiosityFocus`）已經供應 `askUserFocus`。
//
// 依賴方向：本檔可以讀 `reply_style.ts`（拿 presetId），`conversation_agency.ts`
// 只收 `ConversationAgencyProfile` 這個純資料型別，仍然不 import reply_style。

import type { ConversationAgencyProfile } from "./conversation_agency.ts";
import {
  PRESET_IDS,
  type PresetId,
  STYLE_BY_PROFILE_ID,
} from "./reply_style.ts";

/** 沒有 mapping 時的中性值（四個欄位都不位移難度表）。 */
export const NEUTRAL_AGENCY_PROFILE: ConversationAgencyProfile = {
  initiative: 2,
  topicPersistence: 2,
  ambiguityTolerance: 2,
  skepticism: 2,
};

/**
 * preset 級預設。人工依 preset 名與其 `questionHabit`／`directness`／
 * `disclosure` 配；四個欄位在 14 筆裡各自都涵蓋 0–1／2／3–4 三個區段
 * （`agency_profile_test.ts` 釘住），不全部擠在中性值。
 */
export const AGENCY_BY_PRESET: Readonly<
  Record<PresetId, ConversationAgencyProfile>
> = {
  // 話少、直接、不解釋：不主動開題，但自己起的頭會咬住，模糊直接問。
  concise_observer: {
    initiative: 1,
    topicPersistence: 3,
    ambiguityTolerance: 1,
    skepticism: 3,
  },
  // 對等回問、務實：什麼都中間值，容忍度略高（先接住再說）。
  reciprocal_practical: {
    initiative: 2,
    topicPersistence: 2,
    ambiguityTolerance: 3,
    skepticism: 2,
  },
  // 乾式觀察：話不多但邏輯緊，最會指出前提不成立。
  dry_observational: {
    initiative: 2,
    topicPersistence: 3,
    ambiguityTolerance: 1,
    skepticism: 4,
  },
  // 溫和、沒電：不追、不質疑，模糊也先接住。
  warm_low_energy: {
    initiative: 1,
    topicPersistence: 1,
    ambiguityTolerance: 3,
    skepticism: 1,
  },
  // 愛鬧、好奇：很會開自己的題，但話題跳，愛戳前提。
  playful_challenger: {
    initiative: 4,
    topicPersistence: 2,
    ambiguityTolerance: 2,
    skepticism: 3,
  },
  // 直爽（directness 4/4）：想到就講，模糊當場問，話咬得住。
  candid_direct: {
    initiative: 3,
    topicPersistence: 3,
    ambiguityTolerance: 1,
    skepticism: 4,
  },
  // 什麼都想問、熱起來一直接：最高主動、最高容忍、最低懷疑。
  curious_explorer: {
    initiative: 4,
    topicPersistence: 1,
    ambiguityTolerance: 4,
    skepticism: 0,
  },
  // 聊到有興趣的題會一路講下去：主動高、最會把話拉回未聊完的那件事。
  topic_enthusiast: {
    initiative: 3,
    topicPersistence: 4,
    ambiguityTolerance: 2,
    skepticism: 2,
  },
  // 有界線（directness 3/4、questionHabit rare）：不主動開題，但前提不成立會講。
  soft_boundary: {
    initiative: 1,
    topicPersistence: 2,
    ambiguityTolerance: 2,
    skepticism: 4,
  },
  // 平常短、有感才講一段：主動中高，容忍度高（先聽完再說）。
  story_when_engaged: {
    initiative: 3,
    topicPersistence: 2,
    ambiguityTolerance: 3,
    skepticism: 1,
  },
  // 回得小心、會把話接圓：最不主動開題，最容忍模糊，但會記得回頭。
  reserved_repairer: {
    initiative: 1,
    topicPersistence: 3,
    ambiguityTolerance: 4,
    skepticism: 1,
  },
  // 接對方的話、不太主動：主動與懷疑都最低，容忍度最高。
  warm_listener: {
    initiative: 0,
    topicPersistence: 1,
    ambiguityTolerance: 4,
    skepticism: 0,
  },
  // 低能量、常收尾：既不開題也不追，其餘中性。
  low_energy_consistent: {
    initiative: 0,
    topicPersistence: 0,
    ambiguityTolerance: 2,
    skepticism: 2,
  },
  // 一針見血、很短：最不容忍模糊（一句話就問清楚），懷疑度高。
  quick_witted_brief: {
    initiative: 2,
    topicPersistence: 2,
    ambiguityTolerance: 0,
    skepticism: 3,
  },
};

/**
 * 前 20 位代表角色（`STYLE_BY_PROFILE_ID` 的 PR-1 區塊）逐位人工定值，
 * 依人設註解微調，不是 preset 的 spread。其餘 80 位走 preset 預設。
 */
export const AGENCY_BY_PROFILE_ID: Readonly<
  Record<string, ConversationAgencyProfile>
> = {
  // Alice：慢熱、獨立、有點防備 → 比 preset 更懷疑。
  practice_girl_001: {
    initiative: 1,
    topicPersistence: 3,
    ambiguityTolerance: 1,
    skepticism: 4,
  },
  // Nina：務實、穩、習慣讓對話對等 → 會記得回頭把話補完。
  practice_girl_008: {
    initiative: 2,
    topicPersistence: 3,
    ambiguityTolerance: 3,
    skepticism: 2,
  },
  // Lumi：安靜、細膩、被戳到才多說 → 不主動開題，容忍度比 preset 高一階。
  practice_girl_064: {
    initiative: 1,
    topicPersistence: 3,
    ambiguityTolerance: 2,
    skepticism: 3,
  },
  // Bonnie：安定、溫和、沒電會直說 → 不追、不質疑。
  practice_girl_077: {
    initiative: 1,
    topicPersistence: 1,
    ambiguityTolerance: 3,
    skepticism: 1,
  },
  // Ava：活潑、點子多、什麼都想問 → 最高主動與容忍。
  practice_girl_007: {
    initiative: 4,
    topicPersistence: 1,
    ambiguityTolerance: 4,
    skepticism: 0,
  },
  // Ella：陽光、直爽、話直接 → 模糊當場問，但沒有 Mia 那麼刺。
  practice_girl_011: {
    initiative: 3,
    topicPersistence: 3,
    ambiguityTolerance: 1,
    skepticism: 3,
  },
  // Ivy：愛玩、話多的大學生 → 主動高、話題跳，模糊先笑著接。
  practice_girl_002: {
    initiative: 4,
    topicPersistence: 1,
    ambiguityTolerance: 3,
    skepticism: 2,
  },
  // Tara：外向、有感的事會講一段故事 → 主動中高、容忍高。
  practice_girl_083: {
    initiative: 3,
    topicPersistence: 2,
    ambiguityTolerance: 3,
    skepticism: 1,
  },
  // Bella：得體、理性、有距離感 → 話少、不解釋，前提不成立會直接說。
  practice_girl_009: {
    initiative: 1,
    topicPersistence: 3,
    ambiguityTolerance: 1,
    skepticism: 4,
  },
  // Yuna：理性、獨立的研究生 → 最會咬住一個題目，最不容忍跳題。
  practice_girl_012: {
    initiative: 2,
    topicPersistence: 4,
    ambiguityTolerance: 1,
    skepticism: 4,
  },
  // Olivia：有想法、不愛寒暄 → 聊到想法會一路講，話題被打斷會拉回來。
  practice_girl_020: {
    initiative: 3,
    topicPersistence: 4,
    ambiguityTolerance: 1,
    skepticism: 3,
  },
  // Lina：細節控、回得小心、會把話接圓 → 容忍度最高，但記得回頭。
  practice_girl_084: {
    initiative: 1,
    topicPersistence: 3,
    ambiguityTolerance: 4,
    skepticism: 2,
  },
  // Mia：反應快、愛吐槽、一針見血 → 最不容忍模糊。
  practice_girl_004: {
    initiative: 2,
    topicPersistence: 2,
    ambiguityTolerance: 0,
    skepticism: 4,
  },
  // Rina：俏皮、愛鬧、有主見 → 主動最高，愛戳前提。
  practice_girl_013: {
    initiative: 4,
    topicPersistence: 2,
    ambiguityTolerance: 2,
    skepticism: 3,
  },
  // Hazel：機智、嘴甜帶刺、觀察力強 → 刺在句尾，模糊會挑出來。
  practice_girl_061: {
    initiative: 2,
    topicPersistence: 3,
    ambiguityTolerance: 1,
    skepticism: 4,
  },
  // Cora：嘴硬、話少、不解釋 → 最不容忍模糊，也不主動開題。
  practice_girl_089: {
    initiative: 2,
    topicPersistence: 2,
    ambiguityTolerance: 0,
    skepticism: 4,
  },
  // Emma：自律、有界線的瑜珈老師 → 界線清楚，不主動開自己的題。
  practice_girl_006: {
    initiative: 1,
    topicPersistence: 2,
    ambiguityTolerance: 2,
    skepticism: 4,
  },
  // Claire：細膩、有原則、偶爾回問 → 比 preset 更會指出對不上。
  practice_girl_018: {
    initiative: 1,
    topicPersistence: 3,
    ambiguityTolerance: 3,
    skepticism: 3,
  },
  // Zoe：溫和、重視安全感的護理師 → 先接住，不質疑。
  practice_girl_003: {
    initiative: 1,
    topicPersistence: 1,
    ambiguityTolerance: 4,
    skepticism: 1,
  },
  // Erin：成熟、會觀察人、重分寸 → 對等回問、會講原因，懷疑度偏高。
  practice_girl_091: {
    initiative: 2,
    topicPersistence: 3,
    ambiguityTolerance: 2,
    skepticism: 3,
  },
};

/**
 * profileId 覆寫 → preset 預設 → 中性值。
 *
 * preset 從 `STYLE_BY_PROFILE_ID` 查（那是一張純資料表，跟
 * `PRACTICE_REPLY_STYLE_ENABLED` 旗標無關）——agency 與 reply-style 解耦的
 * 同一條線：style 旗標關掉時 agency 仍然拿得到分人強弱。
 */
export function agencyProfileFor(
  profileId: string,
): ConversationAgencyProfile {
  const byId = AGENCY_BY_PROFILE_ID[profileId];
  if (byId) return byId;
  const presetId = STYLE_BY_PROFILE_ID[profileId]?.presetId as
    | PresetId
    | undefined;
  if (presetId && PRESET_IDS.includes(presetId)) {
    return AGENCY_BY_PRESET[presetId];
  }
  return NEUTRAL_AGENCY_PROFILE;
}
