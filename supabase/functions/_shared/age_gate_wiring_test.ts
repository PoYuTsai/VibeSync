// supabase/functions/_shared/age_gate_wiring_test.ts
//
// 18+ 年齡閘門（AGE-01）的接線守衛：核心 AI 功能都要在驗完使用者之後、讀請求內容
// 與扣額度之前呼叫 checkAgeGate（開關 AGE_GATE_ENFORCE）；年齡紀錄的寫入要在
// sync-subscription 碰 RevenueCat 之前分流。鍵盤兩個功能（keyboard-reply、
// keyboard-assist）有自己的錯誤碼合約與手動部署，跟全開一起接，不在這份清單。

import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const root = new URL("../", import.meta.url);
const read = (path: string) => Deno.readTextFileSync(new URL(path, root));

const CORE_FUNCTIONS: Array<{ file: string; bodyRead: RegExp }> = [
  {
    file: "analyze-chat/analyze_chat_handler.ts",
    bodyRead: /await req\.json\(\)/,
  },
  { file: "coach-chat/index.ts", bodyRead: /await req\.json\(\)/ },
  { file: "coach-follow-up/index.ts", bodyRead: /await req\.json\(\)/ },
  { file: "practice-chat/handler.ts", bodyRead: /await req\.text\(\)/ },
];

for (const { file, bodyRead } of CORE_FUNCTIONS) {
  Deno.test(`${file}：驗完使用者就檢查年齡，才讀請求內容`, () => {
    const source = read(file);
    const auth = source.indexOf("auth.getUser(");
    const gate = source.indexOf("checkAgeGate({");
    const body = source.search(bodyRead);
    assert(auth >= 0, "找不到 auth.getUser(");
    assert(gate > auth, "checkAgeGate 要在 auth.getUser 之後");
    assert(body > gate, "checkAgeGate 要在讀請求內容之前");
    assert(
      source.includes('enforcement: Deno.env.get("AGE_GATE_ENFORCE")'),
      "開關要讀 AGE_GATE_ENFORCE",
    );
    assert(
      /if \(ageGateBlock\) \{\s*return jsonResponse\(ageGateBlock\.body, ageGateBlock\.status\);/
        .test(source),
      "擋下時照 checkAgeGate 的 status／body 回應",
    );
  });
}

Deno.test("sync-subscription：record_age_gate 在碰 RevenueCat 之前分流", () => {
  const source = read("sync-subscription/index.ts");
  const branch = source.indexOf('requestBody.mode === "record_age_gate"');
  const revenueCatCheck = source.indexOf("if (!REVENUECAT_IOS_API_KEY)");
  const revenueCatFetch = source.indexOf("https://api.revenuecat.com");
  assert(branch >= 0, "找不到 record_age_gate 分流");
  assert(branch < revenueCatCheck, "要在 RevenueCat 設定檢查之前");
  assert(branch < revenueCatFetch, "要在呼叫 RevenueCat 之前");
  assert(
    source.includes("handleRecordAgeGate("),
    "寫入走 _shared/age_gate.ts 的 handleRecordAgeGate",
  );
});
