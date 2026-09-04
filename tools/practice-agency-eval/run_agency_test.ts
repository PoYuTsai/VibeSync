// run_agency.ts CLI 自測（零網路）：parseArgs 的新旗標（--mode=game、--state）＋
// Phase 3.3 修正後 A27 的迴圈行為（用假 callChat，不打 DeepSeek）。
import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  parseArgs,
  runAgencyScenario,
  saltedThreadId,
  threadSaltOfArtifactMeta,
} from "./run_agency.ts";
import { AGENCY_SCENARIOS } from "./scenarios.ts";
import { buildChatPromptBundle } from "../../supabase/functions/practice-chat/prompt.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
import {
  BAKEOFF_THREAD_ID,
  buildBakeoffContextFixture,
} from "../practice-difficulty-bakeoff/bakeoff.ts";

Deno.test("parseArgs：--mode 接受 standard／beginner／game，其餘拒絕", () => {
  assertEquals(parseArgs([]).mode, "standard");
  assertEquals(parseArgs(["--mode=beginner"]).mode, "beginner");
  assertEquals(parseArgs(["--mode=game"]).mode, "game");
  assertThrows(
    () => parseArgs(["--mode=challenge"]),
    Error,
    "agency_invalid_mode",
  );
});

Deno.test("parseArgs：--state 省略或非 1/true 一律 false，1/true 才開", () => {
  assertEquals(parseArgs([]).stateSimulation, false);
  assertEquals(parseArgs(["--state=0"]).stateSimulation, false);
  assertEquals(
    parseArgs(["--mode=beginner", "--state=1"]).stateSimulation,
    true,
  );
  assertEquals(
    parseArgs(["--mode=game", "--state=true"]).stateSimulation,
    true,
  );
});

Deno.test("parseArgs：--state=1 搭 standard 直接報錯（Codex round-2 P2-d）", () => {
  // standard 不持久化跨回合狀態，靜默忽略會讓 artifact meta 的
  // stateSimulation:true 說謊。
  for (const args of [["--state=1"], ["--mode=standard", "--state=true"]]) {
    assertThrows(
      () => parseArgs(args),
      Error,
      "agency_state_requires_assisted_mode",
    );
  }
});

Deno.test("parseArgs：未知旗標仍拒絕（新旗標沒有意外放寬白名單）", () => {
  assertThrows(
    () => parseArgs(["--bogus=1"]),
    Error,
    "agency_unknown_cli_flag",
  );
});

Deno.test("parseArgs：--mode=game 可以搭配 --state=1 與 --agency=on 一起解析", () => {
  const opts = parseArgs(["--mode=game", "--state=1", "--agency=on"]);
  assert(opts.mode === "game" && opts.stateSimulation && opts.agency === "on");
});

Deno.test("parseArgs：--shape 省略＝off，只認 truncate，亂填（含已刪的 prompt 臂）直接報錯", () => {
  // 靜默當 off 會讓 artifact meta 的 shapeExperiment 說謊（跟 --state 同理）。
  assertEquals(parseArgs([]).shape, "off");
  assertEquals(parseArgs(["--shape=off"]).shape, "off");
  assertEquals(
    parseArgs(["--agency=on", "--shape=truncate"]).shape,
    "truncate",
  );
  for (const bad of ["--shape=1", "--shape=prompt"]) {
    assertThrows(
      () => parseArgs([bad]),
      Error,
      "agency_invalid_shape_experiment",
    );
  }
});

Deno.test("runAgencyScenario：A27.p2／p4 的 previousAiAskedQuestion 吃到腳本非問句，不是 p1 真實生成的問句（Phase 3.3 修正）", async () => {
  const scenario = AGENCY_SCENARIOS.find((s) => s.id === "A27")!;
  let calls = 0;
  // p1 模擬 README 記過的真實觀察：對裸帳號幾乎必問「你是？」。修正前這句會
  // 直接變成 p2 的 previousAiAskedQuestion=true；修正後 p1／p2 之間夾了腳本
  // 化非問句，p2 不該再吃到這一句。
  const replies = ["你是？我不認識你欸", "喔 好啊 那你最近好嗎", "嗯嗯 好喔"];
  const result = await runAgencyScenario({
    callChat: () => Promise.resolve(replies[calls++]),
    profileId: "practice_girl_001",
    scenario,
    repeat: 1,
    difficulty: "normal",
    mode: "standard",
    style: false,
    agency: "off",
  });
  assertEquals(result.error, undefined);
  assertEquals(calls, 3, "只有 p1／p2／p4 三個真探針該打模型，填充行要走腳本");

  const byProbe = (id: string) => result.turns.find((t) => t.probe?.id === id)!;
  assertEquals(byProbe("A27.p1").previousAiAskedQuestion, false);
  assertEquals(byProbe("A27.p1").reply, replies[0]);
  // 核心斷言：p2 前面最後一則不是 p1 那句真實生成的問句，是腳本化非問句。
  assertEquals(byProbe("A27.p2").previousAiAskedQuestion, false);
  assertEquals(byProbe("A27.p2").reply, replies[1]);
  assertEquals(byProbe("A27.p4").previousAiAskedQuestion, false);
  assertEquals(byProbe("A27.p4").reply, replies[2]);

  // 兩則填充行本身要是腳本（不打模型、不進 judge），內容釘死成 scenarios.ts
  // 裡寫的那兩句非問句閒聊。
  const scripted = result.turns.filter((t) => t.scripted && t.probe === null);
  assertEquals(scripted.map((t) => t.reply), [
    "我也在耍廢 等等要洗澡了",
    "對啊 我也是 電費要爆了",
  ]);
});

// ── Phase 4.2 `--thread-salt`（見 `saltedThreadId` 的註解）────────────────────

Deno.test("parseArgs：--thread-salt 省略＝空字串（thread id 逐字沿用舊行為）", () => {
  assertEquals(parseArgs([]).threadSalt, "");
  assertEquals(saltedThreadId("", 3), BAKEOFF_THREAD_ID);
  assertEquals(parseArgs(["--thread-salt=r1"]).threadSalt, "r1");
  assertEquals(saltedThreadId("r1", 2), `${BAKEOFF_THREAD_ID}|r1|2`);
  // 同一個 salt 的不同 repeat 要拿到不同 thread id，否則骰子還是同一面。
  assert(saltedThreadId("r1", 1) !== saltedThreadId("r1", 2));
});

Deno.test("thread-salt 讓 initiative 分支量得到：5 個**不同**的 salt 打同一位角色，已知有 salt 命中 self_disclose、有 salt 不命中", () => {
  // 兩輪黑箱（Phase 4.0／Phase 4 完整矩陣）在 A29 都是 0/40——固定 thread id 讓
  // `fnv1a(seedKey|回合|initiative) % 5` 在這個探針位置恆為同一個值。這支測試
  // 不打模型，也**不宣稱機率**：下面是這一版 FNV-1a、這位角色、這段逐字稿的
  // deterministic fixture，鎖的是「換 salt 會換骰面」這件事本身（Codex R1 P3）。
  const profile = resolvePracticeProfile({
    profileId: "practice_girl_007", // Ava：initiative 4（agency_profile.ts）
    difficulty: "normal",
  });
  const fx = buildBakeoffContextFixture(profile);
  // A29 的形狀：她先講自己的事，玩家連兩則純反應詞（第 2 個 user 回合才是量測點）。
  const turns: PracticeTurn[] = [
    { role: "ai", text: "我今天差點睡過頭 昨晚追劇追到三點才睡" },
    { role: "user", text: "哈哈" },
    { role: "ai", text: "對啊 現在整個很累" },
    { role: "user", text: "嗯嗯" },
  ];
  const disclosesFor = (threadId: string) =>
    buildChatPromptBundle(turns, profile, {
      replyStyle: true,
      agencyMode: "on",
      visiblePracticeThreadId: threadId,
      partnerState: null,
      styleState: null,
      agencyState: null,
      practiceMode: "beginner",
      temperatureScore: 40,
      familiarityScore: 10,
      sceneContext: fx.sceneContext,
      acquaintanceOrigin: fx.acquaintanceOrigin,
      memorySummary: fx.memorySummary,
      timeContext: fx.timeContext,
      herRecentMomentsBlock: fx.herRecentMomentsBlock,
    }).responsePlan!.optionalAct === "self_disclose";

  const salts = ["s1", "s2", "s3", "s4", "s5"];
  const hits = salts.map((salt) => disclosesFor(saltedThreadId(salt, 1)));
  // 沒有鹽的那一面（兩輪黑箱實際打到的那一格）是 false——這就是 0/40 的來源。
  assertEquals(disclosesFor(saltedThreadId("", 1)), false);
  // 5 個不同的鹽裡，已知至少一個命中、至少一個不命中：證明 salt 真的換骰面，
  // 而不是把整組推成同一個結果。
  assert(hits.some(Boolean), `五個 salt 應有命中：${JSON.stringify(hits)}`);
  assert(hits.some((h) => !h), `五個 salt 應有不命中：${JSON.stringify(hits)}`);
});

Deno.test("Phase 4.2（Codex R1 P3）：Phase 4.2 之前的舊 artifact 沒有 meta.fixture.threadSalt，回放要退回 BAKEOFF_THREAD_ID", async () => {
  const oldArtifact = JSON.parse(
    await Deno.readTextFile(
      new URL("./out/2026-09-04-p36-mini-artifact.json", import.meta.url),
    ),
  );
  // 真的是舊格式：fixture 只有 now／threadId。
  assertEquals(oldArtifact.meta.fixture.threadSalt, undefined);
  const salt = threadSaltOfArtifactMeta(oldArtifact.meta);
  assertEquals(salt, "");
  assertEquals(
    saltedThreadId(salt, oldArtifact.results[0].repeat),
    BAKEOFF_THREAD_ID,
  );
  // 壞形狀（meta 缺 fixture、threadSalt 不是字串）也一律退回空字串。
  assertEquals(threadSaltOfArtifactMeta(undefined), "");
  assertEquals(threadSaltOfArtifactMeta({}), "");
  assertEquals(threadSaltOfArtifactMeta({ fixture: { threadSalt: 7 } }), "");
  assertEquals(
    threadSaltOfArtifactMeta({ fixture: { threadSalt: "r1" } }),
    "r1",
  );
});
