import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { LINE_INVITE_RE, shouldSuppressInviteLine } from "./invite_policy.ts";

const invite = (outcome: string, summary = "週六要不要一起吃飯？") => ({
  summary,
  outcome,
});
const nonInvite = (outcome: string) => ({
  summary: "先輕接她的話題，不要急著解釋",
  outcome,
});

Deno.test("B3: LINE_INVITE_RE 分類邀約句（含無「約」字句型）", () => {
  assertEquals(LINE_INVITE_RE.test("週六要不要吃飯？"), true);
  assertEquals(LINE_INVITE_RE.test("想不想去喝咖啡"), true);
  assertEquals(LINE_INVITE_RE.test("下次一起去看展"), true);
  assertEquals(LINE_INVITE_RE.test("先穩住節奏，輕鬆接話就好"), false);
});

Deno.test("B3: 兩次未承接才禁再邀；pending/unknown 誠實不判", () => {
  // 最近兩筆邀約都未承接 → 禁。
  assertEquals(
    shouldSuppressInviteLine([invite("noReply"), invite("cold")]),
    true,
  );
  assertEquals(
    shouldSuppressInviteLine([invite("negative"), invite("noReply")]),
    true,
  );
  // 只有一筆邀約 → 不禁。
  assertEquals(shouldSuppressInviteLine([invite("noReply")]), false);
  // 最近一筆是 engaged → 不禁（由舊到新，最近的算數）。
  assertEquals(
    shouldSuppressInviteLine([
      invite("noReply"),
      invite("cold"),
      invite("engaged"),
    ]),
    false,
  );
  // pending/unknown 不算未承接。
  assertEquals(
    shouldSuppressInviteLine([invite("noReply"), invite("pending")]),
    false,
  );
  // 非邀約事件不參與計數（夾在中間也不影響最近兩筆邀約）。
  assertEquals(
    shouldSuppressInviteLine([
      invite("noReply"),
      nonInvite("engaged"),
      invite("cold"),
    ]),
    true,
  );
  // 缺席/空陣列 → 不禁（現行為）。
  assertEquals(shouldSuppressInviteLine(undefined), false);
  assertEquals(shouldSuppressInviteLine([]), false);
});
