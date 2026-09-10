// 練習室動態配圖：每位角色固定的「拍照習慣」一句（2026-09-10）。
//
// 背景：舊版全站共用一段風格前綴（手機隨手拍、台北、柔暖光、抬高暗部、顆粒、
// 中央 4:3），100 位角色的圖像同一個攝影師拍的。tools/moments-visual-probe 的
// 24 張同 seed 對照證明：同模型、同場景，只把前綴換成「這個人怎麼拍」一句，
// 就看得出不同的人在拍，且同一人跨貼文仍像同一人（results.md）。
//
// 設計刻意最小：一個取景習慣 ＋ 一個處理習慣，由 profileId 的 hash 固定，
// 不隨日期／使用者／attempt 變；十位角色人工指定（報告 §4.4）。不做主／次
// 配方權重、整潔度、處理強度——探針顯示一句就夠，加維度只會讓驗收變數翻倍。
// 拍法不描述主體與地點（那是場景句的事），也不能覆蓋貼文事實。
import { fnv1a } from "./moments_schedule.ts";

/** 取景習慣：四種都不指定主體是什麼；第 0 種偏物件，海景會少一點貼切。 */
const SHOTS = [
  // 0 斜側近拍：主體狀態與質地
  "An oblique close view with the subject slightly off-center, showing its used state and texture.",
  // 1 偏位中景：拿場景裡的一條邊當線條，留白
  "A medium view with the subject toward one side, using an edge or line in the scene as a simple graphic element, with some empty space.",
  // 2 平視帶環境
  "An eye-level view keeping a bit of the surrounding environment, casually framed a little off-center.",
  // 3 稍微俯視
  "A view from slightly above, looking down at the subject where that suits it, with the surface or ground around it.",
] as const;

/** 處理習慣：全部寫實；不含 flash（日間／隔玻璃不相容，第一輪不收）。 */
const STYLES = [
  // 0 neutral_snapshot
  "Neutral color, ordinary exposure, nothing stylized.",
  // 1 warm_soft
  "Warm but true-to-object color, moderately soft contrast.",
  // 2 clean_graphic
  "Clean and uncluttered, restrained color, natural contrast.",
  // 3 daylight_color
  "Daylight-like color with clear, slightly saturated hues.",
  // 4 quiet_muted
  "Slightly desaturated, natural tonal range, observational.",
  // 5 crisp_contrast
  "Clear local contrast and neutral color under ordinary available light.",
  // 6 soft_grain
  "Slightly soft detail with fine grain and natural color.",
] as const;

/** 人工指定：[取景, 處理]；其餘角色由 hash 決定。 */
const OVERRIDES: Readonly<Record<string, readonly [number, number]>> = {
  practice_girl_002: [2, 3], // Ivy：平視帶環境、日光色
  practice_girl_003: [1, 0], // Zoe：偏位中景、原色
  practice_girl_004: [0, 5], // Mia：近拍主體狀態、高反差
  practice_girl_005: [1, 2], // Chloe：線條、偏位、留白
  practice_girl_068: [3, 3], // Flora：稍微俯視、日光色
  practice_girl_071: [2, 4], // Luna：平視帶環境、低飽和
  practice_girl_073: [0, 1], // Noelle：斜側近拍質地、暖
  practice_girl_074: [2, 0], // Sasha：平視帶環境、原色
  practice_girl_081: [0, 2], // Aileen：斜側近拍、乾淨
  practice_girl_097: [2, 5], // Hana：平視帶環境、亮暗分明
};

/** 這位角色拍照的一句話；同 profileId 永遠同一句。 */
export function momentVisualRecipe(profileId: string): string {
  const [shot, style] = OVERRIDES[profileId] ?? [
    fnv1a(`${profileId}|moment_visual_shot`) % SHOTS.length,
    fnv1a(`${profileId}|moment_visual_style`) % STYLES.length,
  ];
  return `${SHOTS[shot]} ${STYLES[style]}`;
}

/** 測試對帳用。 */
export const MOMENT_VISUAL_OVERRIDE_IDS: readonly string[] = Object.keys(
  OVERRIDES,
);
