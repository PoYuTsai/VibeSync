// supabase/functions/_shared/age_gate_test.ts
//
// 18+ 年齡閘門（AGE-01）：紀錄讀取、開關、檢查矩陣、寫入規則與 record_age_gate。

import {
  assertEquals,
  assertStrictEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  AGE_GATE_BLOCKED_MESSAGE,
  AGE_GATE_POLICY_VERSION,
  AGE_GATE_REQUIRED_MESSAGE,
  type AgeGateRecord,
  checkAgeGate,
  decideAgeGateWrite,
  handleRecordAgeGate,
  parseAgeGateEnforcement,
  readAgeGateRecord,
} from "./age_gate.ts";
import { TEST_EMAILS } from "./quota.ts";

const AT = "2026-10-30T08:00:00.000Z";
const adult: AgeGateRecord = { result: "adult", policy: 1, at: AT };
const minor: AgeGateRecord = { result: "minor", policy: 1, at: AT };

Deno.test("readAgeGateRecord：只認形狀正確的紀錄", () => {
  assertEquals(readAgeGateRecord({ age_gate: adult }), adult);
  assertEquals(
    readAgeGateRecord({ age_gate: minor, provider: "apple" }),
    minor,
  );
  for (
    const bad of [
      undefined,
      null,
      "adult",
      {},
      { age_gate: null },
      { age_gate: { result: "teen", policy: 1, at: AT } },
      { age_gate: { result: "adult", policy: 0, at: AT } },
      { age_gate: { result: "adult", policy: 1.5, at: AT } },
      { age_gate: { result: "adult", policy: 1, at: "not a date" } },
      { age_gate: { result: "adult", policy: 1 } },
    ]
  ) {
    assertStrictEquals(readAgeGateRecord(bad), null, JSON.stringify(bad));
  }
});

Deno.test("parseAgeGateEnforcement：沒設或其他值都是關", () => {
  assertEquals(parseAgeGateEnforcement(undefined), "off");
  assertEquals(parseAgeGateEnforcement(null), "off");
  assertEquals(parseAgeGateEnforcement(""), "off");
  assertEquals(parseAgeGateEnforcement("false"), "off");
  assertEquals(parseAgeGateEnforcement("yes"), "off");
  assertEquals(parseAgeGateEnforcement("test"), "test");
  assertEquals(parseAgeGateEnforcement(" Test "), "test");
  assertEquals(parseAgeGateEnforcement("on"), "on");
  assertEquals(parseAgeGateEnforcement("true"), "on");
});

Deno.test("checkAgeGate：開關 × 紀錄 × 測試帳號", () => {
  const testEmail = TEST_EMAILS[0];
  const required = {
    status: 403,
    body: { error: "AGE_GATE_REQUIRED", message: AGE_GATE_REQUIRED_MESSAGE },
  };
  const blocked = {
    status: 403,
    body: { error: "AGE_GATE_BLOCKED", message: AGE_GATE_BLOCKED_MESSAGE },
  };
  const user = (email: string, record?: AgeGateRecord) => ({
    email,
    app_metadata: record ? { age_gate: record } : { provider: "email" },
  });

  // 關：誰都放行（App Store 上的舊版不受影響）。
  for (const record of [undefined, adult, minor]) {
    assertEquals(
      checkAgeGate({ user: user("a@b.c", record), enforcement: undefined }),
      null,
    );
  }
  // 成年：任何開關都放行。
  for (const enforcement of ["off", "test", "on"]) {
    assertEquals(
      checkAgeGate({ user: user(testEmail, adult), enforcement }),
      null,
    );
  }
  // test：只擋測試帳號。
  assertEquals(
    checkAgeGate({ user: user("a@b.c"), enforcement: "test" }),
    null,
  );
  assertEquals(
    checkAgeGate({ user: user(testEmail), enforcement: "test" }),
    required,
  );
  assertEquals(
    checkAgeGate({ user: user(testEmail, minor), enforcement: "test" }),
    blocked,
  );
  // on：沒有紀錄要先確認，未成年擋下；email 沒有也照擋。
  assertEquals(
    checkAgeGate({ user: user("a@b.c"), enforcement: "on" }),
    required,
  );
  assertEquals(
    checkAgeGate({ user: user("a@b.c", minor), enforcement: "on" }),
    blocked,
  );
  assertEquals(
    checkAgeGate({ user: { app_metadata: {} }, enforcement: "on" }),
    required,
  );
});

Deno.test("decideAgeGateWrite：未成年鎖住、同結果不重寫、成年可改成未成年", () => {
  const now = new Date("2026-10-31T00:00:00.000Z");
  const fresh = (result: "adult" | "minor") => ({
    result,
    policy: AGE_GATE_POLICY_VERSION,
    at: now.toISOString(),
  });
  assertEquals(decideAgeGateWrite(null, "adult", now), {
    kind: "write",
    record: fresh("adult"),
  });
  assertEquals(decideAgeGateWrite(null, "minor", now), {
    kind: "write",
    record: fresh("minor"),
  });
  assertEquals(decideAgeGateWrite(adult, "adult", now), {
    kind: "unchanged",
    record: adult,
  });
  assertEquals(decideAgeGateWrite(adult, "minor", now), {
    kind: "write",
    record: fresh("minor"),
  });
  assertEquals(decideAgeGateWrite(minor, "minor", now), {
    kind: "unchanged",
    record: minor,
  });
  assertEquals(decideAgeGateWrite(minor, "adult", now), {
    kind: "locked",
    record: minor,
  });
});

Deno.test("handleRecordAgeGate：驗輸入、寫 app_metadata、未成年鎖住回 409", async () => {
  const writes: Array<{ userId: string; appMetadata: unknown }> = [];
  const now = new Date("2026-10-31T00:00:00.000Z");
  const deps = (error: { message: string } | null = null) => ({
    updateAppMetadata: (userId: string, appMetadata: unknown) => {
      writes.push({ userId, appMetadata });
      return Promise.resolve({ error });
    },
    now: () => now,
  });
  const newUser = { id: "u1", app_metadata: { provider: "apple" } };

  assertEquals(
    await handleRecordAgeGate(
      { user: newUser, body: { result: "teen", policy: 1 } },
      deps(),
    ),
    { status: 400, body: { error: "invalid_age_gate_result" } },
  );
  assertEquals(
    await handleRecordAgeGate(
      { user: newUser, body: { result: "adult", policy: 2 } },
      deps(),
    ),
    { status: 400, body: { error: "invalid_age_gate_policy" } },
  );
  assertEquals(writes.length, 0, "輸入不對不寫");

  const recorded = {
    result: "adult",
    policy: AGE_GATE_POLICY_VERSION,
    at: now.toISOString(),
  };
  assertEquals(
    await handleRecordAgeGate(
      { user: newUser, body: { result: "adult", policy: 1 } },
      deps(),
    ),
    { status: 200, body: { ageGate: recorded } },
  );
  assertEquals(writes, [{ userId: "u1", appMetadata: { age_gate: recorded } }]);

  // 已經成年：不重寫，回原紀錄。
  writes.length = 0;
  assertEquals(
    await handleRecordAgeGate(
      {
        user: { id: "u1", app_metadata: { age_gate: adult } },
        body: { result: "adult", policy: 1 },
      },
      deps(),
    ),
    { status: 200, body: { ageGate: adult } },
  );
  assertEquals(writes.length, 0);

  // 未成年鎖住：換成「成年」也不寫，回 409＋目前紀錄。
  assertEquals(
    await handleRecordAgeGate(
      {
        user: { id: "u1", app_metadata: { age_gate: minor } },
        body: { result: "adult", policy: 1 },
      },
      deps(),
    ),
    { status: 409, body: { error: "AGE_GATE_LOCKED", ageGate: minor } },
  );
  assertEquals(writes.length, 0);

  // 寫入失敗：回 500，不假裝成功。
  assertEquals(
    await handleRecordAgeGate(
      { user: newUser, body: { result: "minor", policy: 1 } },
      deps({ message: "boom" }),
    ),
    { status: 500, body: { error: "age_gate_record_failed" } },
  );
});
