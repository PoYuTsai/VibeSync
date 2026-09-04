// run_agency.ts CLI 自測（零網路）：parseArgs 的新旗標（--mode=game、--state）。
import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { parseArgs } from "./run_agency.ts";

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
