// Phase 4.4 越界輪黑箱新增 A31：鎖住「情境檔宣稱的強度」跟「production 實際判斷」
// 一致，不是只鎖字面常數。detectTurnSignals 是 chatModelFor 的 situation===
// "boundary" 入口實際吃的地面真相（見 conversation_agency.ts chatModelFor 註解）。
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { detectTurnSignals } from "../../supabase/functions/practice-chat/turn_response_plan.ts";
import {
  evaluateGameFsm,
  looksOverEscalated,
} from "../../supabase/functions/practice-chat/game_fsm.ts";
import { looksLikeGameSoftInvite } from "../../supabase/functions/practice-chat/game_invite_classifier.ts";
import { inviteMaturityFromLearningScores } from "../../supabase/functions/practice-chat/invite_maturity.ts";
import { buildChatPromptBundle } from "../../supabase/functions/practice-chat/prompt.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
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

// ── Phase 4.5h：A32／A33 也照 A31 的作法，鎖「情境檔宣稱的結構事實」＝
// 「production 判斷的結果」，不是只鎖字面常數。這兩個情境存在的唯一理由就是
// 走進 4.4／4.5c 量到 0 覆蓋的那兩條 FSM 分支，走不進去就沒有意義。

const scenario = (id: string) => {
  const s = AGENCY_SCENARIOS.find((x) => x.id === id);
  if (!s) throw new Error(`${id} 不存在`);
  return s;
};
const userTexts = (id: string) =>
  scenario(id).turns.filter((t) => t.role === "user").map((t) => t.text);
const textOf = (id: string, probeId: string) => {
  const turn = scenario(id).turns.find((t) => t.probe?.id === probeId);
  if (!turn) throw new Error(`${probeId} 不存在`);
  return turn.text;
};
/**
 * 只用玩家那幾句重建 FSM 輸入（她的回覆是生成的，離線拿不到，也不影響這幾個分支）。
 *
 * **刻意不傳 `inviteStage`**：`prompt.ts` 的聊天路徑就是這樣呼叫
 * `evaluateGameFsm` 的（只給 turns／分數／partnerMood）。傳了 `inviteStage`
 * 會多開兩條這支 runner 實際上走不到的路（見 README「Phase 4.5h」節記的
 * production 缺口），測試就會鎖住一個假的事實。
 */
const snapshotAt = (id: string, upto: number, T: number, F: number) => {
  const turns: PracticeTurn[] = userTexts(id).slice(0, upto).map((text) => ({
    role: "user",
    text,
  }));
  return evaluateGameFsm({
    turns,
    temperatureScore: T,
    familiarityScore: F,
    partnerMood: null,
  });
};

Deno.test("Phase 4.5h 分數→邀約成熟度對照表（README 那張表的機器可讀版）", () => {
  const stage = (T: number, F: number) =>
    inviteMaturityFromLearningScores({
      temperatureScore: T,
      familiarityScore: F,
      partnerMood: null,
      stageFloor: null,
    })!;
  // 預設（handler 的 beginner 起始值）：成熟度 28，永遠到不了任何邀約階。
  assertEquals(stage(40, 10).score, 28);
  assertEquals(stage(40, 10).stage, "not_ready");
  assertEquals(stage(60, 40).stage, "soft_invite_ready"); // 52
  assertEquals(stage(80, 70).stage, "direct_invite_ready"); // 76
  assertEquals(stage(85, 75).stage, "partner_window"); // 81
  assertEquals(stage(90, 80).stage, "high_intimacy"); // 86
});

Deno.test("A32 的邀約句命中 production 的 looksLikeGameSoftInvite（FSM 這一輪一定看得到邀約訊號）", () => {
  assertEquals(looksLikeGameSoftInvite(textOf("A32", "A32.p4")), true);
  // 前三句是普通閒聊，不該提早觸發邀約訊號。
  for (const text of userTexts("A32").slice(0, 3)) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }
});

Deno.test("A32：高分開場改變 FSM 的階段與 spicy 上限；邀約那一輪兩臂都走 direct_invite_low_pressure", () => {
  // 預設 40／10：閒聊三句還停在建立投資，spicy 鎖 L1。
  const low = snapshotAt("A32", 3, 40, 10);
  assertEquals(low.speedInviteDirection, "no_invite_build_investment");
  assertEquals(low.spicyLevel, "L1");
  // 高分開場 80／70：relationshipStage 直接把 basePhase 抬到張力階，spicy 開到 L3。
  const high = snapshotAt("A32", 3, 80, 70);
  assertEquals(high.phase, "P4_TENSION");
  assertEquals(high.speedInviteDirection, "soft_invite_probe");
  assertEquals(high.spicyLevel, "L3");
  // 邀約那一輪（p4）：`softInvite` 自己就會把方向推到 direct_invite_low_pressure，
  // 兩臂都一樣——**分數在聊天 prompt 這條路上推不動 speedInviteDirection**
  // （`prompt.ts` 呼叫 `evaluateGameFsm` 時沒有傳 `inviteStage`，見 README），
  // 分數是靠 inviteMaturity／spicyLevel／phase 三個區塊進 prompt 的。
  for (const [T, F] of [[40, 10], [85, 75]]) {
    assertEquals(
      snapshotAt("A32", 4, T, F).speedInviteDirection,
      "direct_invite_low_pressure",
      `T=${T}`,
    );
  }
  // 記錄用（不是期望行為）：聊天路徑沒傳 inviteStage，所以 partner_window_close
  // 這條路在這支 runner 走不到；哪天 production 補上了，這一行會變紅提醒更新。
  assertEquals(
    snapshotAt("A32", 3, 85, 75).speedInviteDirection,
    "soft_invite_probe",
  );
});

Deno.test("A33 踩線句命中 looksOverEscalated 但不是 A31 的 BOUNDARY_RE 入口", () => {
  const cross = textOf("A33", "A33.p3");
  assertEquals(looksOverEscalated(cross), true);
  assertEquals(
    detectTurnSignals([{ role: "user", text: cross }]).boundaryLike,
    false,
  );
});

Deno.test("A33 踩線輪與道歉輪都讓 FSM 進修復優先，且踩線輪蓋掉高分臂的邀約方向", () => {
  for (const [T, F] of [[40, 10], [80, 70]]) {
    const cross = snapshotAt("A33", 3, T, F);
    assertEquals(cross.repairPriority, true, `T=${T}`);
    assertEquals(cross.speedInviteDirection, "repair_before_invite", `T=${T}`);
    assertEquals(cross.failureStates.includes("GREASY"), true, `T=${T}`);
    assertEquals(cross.spicyLevel, "L0", `T=${T}`);
    // 道歉輪：GREASY 只跟最新一句走，接住修復優先的是 FRAME_COLLAPSE
    // （「我不是那個意思」）——這句話留在情境檔裡就是為了這件事。
    const repair = snapshotAt("A33", 4, T, F);
    assertEquals(repair.repairPriority, true, `T=${T}`);
    assertEquals(
      repair.failureStates.includes("FRAME_COLLAPSE"),
      true,
      `T=${T}`,
    );
  }
});

Deno.test("A32／A33 的探針分母就是新增的兩個 kind（指標分母不被別的家族稀釋）", () => {
  const kinds = (id: string) =>
    scenario(id).turns.filter((t) => t.probe).map((t) => t.probe!.kinds);
  assertEquals(kinds("A32"), [["invite_probe"], ["invite_probe"]]);
  assertEquals(kinds("A33"), [["boundary_probe"], ["repair_priority"], [
    "repair_accept",
  ]]);
});

Deno.test("A32／A33 在真正的 prompt bundle 上走到對的分支（situation 與 gameFsmPriority）", () => {
  // SR 角色：production 的 game 模式只開給 rarity==="sr"。
  const profile = resolvePracticeProfile({
    difficulty: "normal",
    profileId: "practice_girl_004",
  });
  const bundleAt = (id: string, upto: number) => {
    const texts = userTexts(id);
    const turns: PracticeTurn[] = [];
    for (let k = 0; k < upto; k++) {
      turns.push({ role: "user", text: texts[k] });
      if (k < upto - 1) turns.push({ role: "ai", text: "嗯嗯" });
    }
    return buildChatPromptBundle(turns, profile, {
      replyStyle: true,
      agencyMode: "on",
      visiblePracticeThreadId: "t",
      partnerState: null,
      styleState: null,
      agencyState: null,
      practiceMode: "game",
      temperatureScore: 80,
      familiarityScore: 70,
    });
  };
  // A32：邀約那一輪走 mature_invite（高分開場），確認那一輪走 early_invite
  // ——兩個都是 `chatModelFor` 的既有 situation 入口，之前沒有情境碰得到。
  assertEquals(bundleAt("A32", 4).situation, "mature_invite");
  assertEquals(bundleAt("A32", 5).situation, "early_invite");
  // A33：踩線輪 boundary、道歉輪 neutral，兩輪都是 Game 修復優先。
  const cross = bundleAt("A33", 3);
  assertEquals(cross.situation, "boundary");
  assertEquals(cross.gameFsmPriority, true);
  const repair = bundleAt("A33", 4);
  assertEquals(repair.situation, "neutral");
  assertEquals(repair.gameFsmPriority, true);
  // 記錄用：這兩輪 `agencyDecision.applied` 是 false，所以 `--shape=truncate`
  // 在它們身上本來就是空操作——4.5h 把 runner 的截斷條件補齊成 handler 的
  // `&& !gameFsmPriority` 只是對齊，對現有情境沒有行為差異。哪天 planner 改成
  // 在修復優先輪也介入，這一行會變紅，那時候截斷條件才真的開始有作用。
  assertEquals(cross.agencyDecision?.applied, false);
  assertEquals(repair.agencyDecision?.applied, false);
});
