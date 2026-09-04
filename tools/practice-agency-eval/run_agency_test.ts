// run_agency.ts CLI 自測（零網路）：parseArgs 的新旗標（--mode=game、--state）＋
// Phase 3.3 修正後 A27 的迴圈行為（用假 callChat，不打 DeepSeek）。
import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { parseArgs, runAgencyScenario } from "./run_agency.ts";
import { AGENCY_SCENARIOS } from "./scenarios.ts";

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

Deno.test("parseArgs：--shape 省略＝off，只認 prompt／truncate，亂填直接報錯", () => {
  // 靜默當 off 會讓 artifact meta 的 shapeExperiment 說謊（跟 --state 同理）。
  assertEquals(parseArgs([]).shape, "off");
  assertEquals(parseArgs(["--shape=off"]).shape, "off");
  assertEquals(parseArgs(["--shape=prompt"]).shape, "prompt");
  assertEquals(
    parseArgs(["--agency=on", "--shape=truncate"]).shape,
    "truncate",
  );
  assertThrows(
    () => parseArgs(["--shape=1"]),
    Error,
    "agency_invalid_shape_experiment",
  );
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

  const byProbe = (id: string) =>
    result.turns.find((t) => t.probe?.id === id)!;
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
  assertEquals(scripted.map((t) => t.reply), ["哈哈哈 傳來看", "喔 辛苦你了"]);
});
