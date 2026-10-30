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

// 整段呼叫＋擋下就回應要一字不差地出現一次；只寫在註解裡或少了 return 都不算。
const GATE_STATEMENT =
  /const ageGateBlock = checkAgeGate\(\{\s*user,\s*enforcement: Deno\.env\.get\("AGE_GATE_ENFORCE"\),\s*\}\);\s*if \(ageGateBlock\) \{\s*return jsonResponse\(ageGateBlock\.body, ageGateBlock\.status\);\s*\}/g;

for (const { file, bodyRead } of CORE_FUNCTIONS) {
  Deno.test(`${file}：驗完使用者就檢查年齡，才讀請求內容`, () => {
    const source = read(file);
    const auth = source.indexOf("auth.getUser(");
    const statements = [...source.matchAll(GATE_STATEMENT)];
    const body = source.search(bodyRead);
    assert(auth >= 0, "找不到 auth.getUser(");
    assert(
      source.indexOf("auth.getUser(", auth + 1) < 0,
      "只能有一個驗使用者的地方",
    );
    assert(statements.length === 1, "年齡檢查整段要剛好出現一次");
    const gate = statements[0].index!;
    assert(gate > auth, "checkAgeGate 要在 auth.getUser 之後");
    assert(body > gate, "checkAgeGate 要在讀請求內容之前");
    assert(
      source.split("checkAgeGate(").length === 2,
      "checkAgeGate 只呼叫一次",
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
