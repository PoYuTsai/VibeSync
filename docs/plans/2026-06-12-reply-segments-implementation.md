# #12 一球一回 replySegments 實作計畫

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> 設計依據：`docs/plans/2026-06-11-reply-segments-one-ball-one-reply-design.md`（Codex 設計把關 r2 APPROVED @ `435e6a1`，cap 3 Eric 拍板）。
> 實作後走高風險雙審（queue 另開 item），APPROVED 前不得說 dogfood safe。

**Goal:** 對方連發多顆球時，full mode（含 streaming）穩定輸出每球一段的 `replySegments`（cap 3、各段綁定 sourceMessage/sourceIndex、絕不空 source 流出 server）。

**Architecture:** 三戰場——(1) `post_process.ts` sanitizer 升級三層缺 source 規則 + 球清單抽取；(2) `index.ts` SYSTEM_PROMPT §1.2/1.3/1.5 條件式改強制式 + vision reminder 鏡射；(3) `stream_prompt.ts` 補 contract 行（偵察發現：「compact finalResult」是 streaming 掉段的反向拉力，segments 唯一通道是 `analysis.done.finalResult`）。Client 完全不動（cap 3 對齊 `.take(3)`）。

**Tech Stack:** Deno (Edge Function TS)、Flutter 測試僅跑 style-pair 鎖回歸。

## 偵察結論（2026-06-12，影響實作的事實）

- `content` 換行 join **已存在**（`post_process.ts:461/:568` 皆 `join("\n")`）→ 規格 #4 只需測試上鎖，無 code 變更。
- Mid-stream `analysis.recommendation` 事件只帶單句 preview（`reframer.ts:440-446` 組出的 finalRecommendation 無 replySegments）；segments 唯一來源 = `analysis.done.finalResult`（`reframer.ts:506-508` merge）→ sanitizer 在 markDone（`index.ts:6677`）統一把關，無繞過路徑。
- `postProcessAnalysisResult` 共 3 個 prod 呼叫點：`index.ts:6395`（full JSON）、`:6677`（stream markDone）、`:7159`（legacy/vision）。三處都在主 handler 內，`messages`（request 訊息）在 scope。
- Vision 路徑的球清單來自 OCR 結果 `result.recognizedConversation.messages`，優先於 request messages。
- Quick mode 用獨立 `QUICK_SYSTEM_PROMPT`（`quick_prompt.ts:27`），不 import SYSTEM_PROMPT → 規格 #3（quick 不動）天然成立，驗收跑既有 quick 測試即可。
- Style-pair byte-for-byte 鎖鎖在 **client Dart builder**（`effective_style_prompt_builder_test.dart:124`，鎖 `buildForAnalysis` 輸出）。本案只動 server prompt，builder 一字不碰 → 鎖測試應**原樣通過**（不需重立基準）。這比設計文件保守假設「知情破鎖重立」更強；驗收改為「跑該測試、證明 byte-for-byte 仍成立」，並在 queue item 如實記載。
- `sourceIndex` 語意目前 prompt 未定義（client 顯示「回第 N 句」，display 主鍵其實是 `sourceMessage`，`analysis_screen.dart:4372`）。本案定義：**她這一輪連發（trailing partner run）中的第幾句，1-based**；server 端球清單同此語意。

---

### Task 1: sanitizer 三層 source contract + 球清單抽取（post_process.ts）

**Files:**
- Modify: `supabase/functions/analyze-chat/post_process.ts`
- Test: `supabase/functions/analyze-chat/post_process_test.ts`

**Step 1: 寫失敗測試**（post_process_test.ts 末尾新增 group）

```ts
// ---------------------------------------------------------------------------
// #12 一球一回 — extractPartnerBallList + enforceReplySegmentSourceContract
// ---------------------------------------------------------------------------

import {
  enforceReplySegmentSourceContract,
  extractPartnerBallList,
} from "./post_process.ts";

Deno.test("extractPartnerBallList takes trailing partner run from request messages", () => {
  const balls = extractPartnerBallList({
    requestMessages: [
      { isFromMe: true, content: "我先說一句" },
      { isFromMe: false, content: "紅牛跟賓士差點打起來XD" },
      { isFromMe: false, content: "剛來吃晚餐" },
      { isFromMe: false, content: "等等要去樂華夜市" },
    ],
  });
  assertEquals(balls, ["紅牛跟賓士差點打起來XD", "剛來吃晚餐", "等等要去樂華夜市"]);
});

Deno.test("extractPartnerBallList prefers recognizedConversation over request messages", () => {
  const balls = extractPartnerBallList({
    result: {
      recognizedConversation: {
        messages: [
          { isFromMe: false, content: "OCR 球一" },
          { isFromMe: false, content: "OCR 球二" },
        ],
      },
    },
    requestMessages: [{ isFromMe: false, content: "request 球" }],
  });
  assertEquals(balls, ["OCR 球一", "OCR 球二"]);
});

Deno.test("extractPartnerBallList falls back to last partner messages when trailing run is mine", () => {
  const balls = extractPartnerBallList({
    requestMessages: [
      { isFromMe: false, content: "她的舊球" },
      { isFromMe: true, content: "我剛回了一句" },
    ],
  });
  assertEquals(balls, ["她的舊球"]);
});

Deno.test("source contract layer 1: invalid sourceIndex repaired by text lookup", () => {
  const repaired = enforceReplySegmentSourceContract(
    [{ sourceIndex: 99, label: "", sourceMessage: "剛來吃晚餐", reply: "回吃飯球", reason: "" }],
    ["紅牛跟賓士差點打起來XD", "剛來吃晚餐"],
  );
  assertEquals(repaired.length, 1);
  assertEquals(repaired[0].sourceIndex, 2);
});

Deno.test("source contract layer 1b: valid sourceIndex backfills empty sourceMessage", () => {
  const repaired = enforceReplySegmentSourceContract(
    [{ sourceIndex: 1, label: "", sourceMessage: "", reply: "回 F1 球", reason: "" }],
    ["紅牛跟賓士差點打起來XD"],
  );
  assertEquals(repaired[0].sourceMessage, "紅牛跟賓士差點打起來XD");
});

Deno.test("source contract layer 2: unrepairable segment is dropped", () => {
  const repaired = enforceReplySegmentSourceContract(
    [
      { label: "", sourceMessage: "", reply: "沒 source 的段", reason: "" },
      { sourceIndex: 1, label: "", sourceMessage: "球一", reply: "好段", reason: "" },
    ],
    ["球一"],
  );
  assertEquals(repaired.length, 1);
  assertEquals(repaired[0].reply, "好段");
});

Deno.test("source contract: empty ball list keeps well-formed segments, drops empty-source ones", () => {
  const repaired = enforceReplySegmentSourceContract(
    [
      { sourceIndex: 2, label: "", sourceMessage: "她的原句", reply: "保留", reason: "" },
      { label: "", sourceMessage: "", reply: "丟棄", reason: "" },
    ],
    [],
  );
  assertEquals(repaired.length, 1);
  assertEquals(repaired[0].reply, "保留");
});
```

**Step 2: 跑測試確認失敗**

Run: `deno test --allow-read supabase/functions/analyze-chat/post_process_test.ts`
Expected: FAIL（export 不存在）

**Step 3: 實作**（post_process.ts，`sanitizeReplySegments` 之後）

```ts
// ---------------------------------------------------------------------------
// #12 一球一回 — 球清單抽取 + 三層缺 source 規則
//
// 球清單 = 對方這一輪連發（trailing partner run）的訊息內容，1-based。
// vision 路徑優先用 OCR 結果 recognizedConversation.messages。
// trailing run 為空（最後一則是我）時回退最近 10 則對方訊息，
// 讓「我已回一半再分析」的真實案例不至於全段被丟。
// ---------------------------------------------------------------------------

const BALL_LIST_FALLBACK_LIMIT = 10;

export function extractPartnerBallList({ result, requestMessages }: {
  result?: Record<string, unknown>;
  requestMessages?: Array<Record<string, unknown>>;
}): string[] {
  const recognized = (result?.recognizedConversation as
    | Record<string, unknown>
    | undefined)?.messages;
  const source = Array.isArray(recognized) && recognized.length > 0
    ? recognized
    : (requestMessages ?? []);

  const trailingRun: string[] = [];
  for (let i = source.length - 1; i >= 0; i--) {
    const item = source[i];
    if (!item || typeof item !== "object") break;
    const record = item as Record<string, unknown>;
    if (record.isFromMe === true) break;
    const content = normalizeAiText(record.content);
    if (content.length > 0) trailingRun.unshift(content);
  }
  if (trailingRun.length > 0) return trailingRun;

  const fallback: string[] = [];
  for (let i = source.length - 1; i >= 0; i--) {
    const item = source[i];
    if (!item || typeof item !== "object") continue;
    const record = item as Record<string, unknown>;
    if (record.isFromMe === true) continue;
    const content = normalizeAiText(record.content);
    if (content.length > 0) fallback.unshift(content);
    if (fallback.length >= BALL_LIST_FALLBACK_LIMIT) break;
  }
  return fallback;
}

function normalizeForBallMatch(value: string): string {
  return value.replace(/\s+/g, "").toLowerCase();
}

export function enforceReplySegmentSourceContract(
  segments: ReturnType<typeof sanitizeReplySegments>,
  ballList: string[],
): ReturnType<typeof sanitizeReplySegments> {
  const repaired: ReturnType<typeof sanitizeReplySegments> = [];
  for (const segment of segments) {
    let sourceIndex = segment.sourceIndex;
    let sourceMessage = segment.sourceMessage;

    if (ballList.length === 0) {
      // 球清單不可得（防衛路徑）：只驗形狀，不驗範圍。
      if (sourceIndex != null && sourceIndex >= 1 && sourceMessage.length > 0) {
        repaired.push(segment);
      }
      continue;
    }

    const indexValid = sourceIndex != null && sourceIndex >= 1 &&
      sourceIndex <= ballList.length;

    if (!indexValid) {
      sourceIndex = undefined;
      if (sourceMessage.length > 0) {
        // 第一層：以 sourceMessage 文字回查球清單修復 sourceIndex。
        const target = normalizeForBallMatch(sourceMessage);
        const matched = ballList.findIndex((ball) => {
          const normalizedBall = normalizeForBallMatch(ball);
          return normalizedBall === target ||
            (target.length >= 4 && normalizedBall.includes(target)) ||
            (normalizedBall.length >= 4 && target.includes(normalizedBall));
        });
        if (matched >= 0) sourceIndex = matched + 1;
      }
    }

    if (sourceIndex != null && sourceMessage.length === 0) {
      sourceMessage = ballList[sourceIndex - 1].slice(0, 120);
    }

    if (sourceIndex == null || sourceMessage.length === 0) {
      // 第二層：兩者都缺 / 修不回 → drop 該段，絕不讓空 source 流出。
      continue;
    }

    repaired.push({ ...segment, sourceIndex, sourceMessage });
  }
  return repaired;
}
```

**Step 4: 跑測試確認通過**

Run: `deno test --allow-read supabase/functions/analyze-chat/post_process_test.ts`
Expected: PASS（新增 7 案 + 既有全綠）

**Step 5: Commit**

```bash
git add supabase/functions/analyze-chat/post_process.ts supabase/functions/analyze-chat/post_process_test.ts
git commit -m "feat: #12 一球一回 — sanitizer 球清單抽取 + 三層缺 source 規則（純函式層）"
```

---

### Task 2: 接線 — finalRecommendation.replySegments 過 contract（三層回退語意）

**Files:**
- Modify: `supabase/functions/analyze-chat/post_process.ts`（`ensureNonEmptyAnalysisOutput` + `postProcessAnalysisResult` Step 3）
- Modify: `supabase/functions/analyze-chat/index.ts:6395 / :6677 / :7159`（傳 `requestMessages`）
- Test: `supabase/functions/analyze-chat/post_process_test.ts`

**Step 1: 寫失敗測試**

```ts
Deno.test("postProcess repairs finalRecommendation segment sources against ball list", () => {
  const result = postProcessAnalysisResult({
    result: {
      replies: { extend: "合併版" },
      finalRecommendation: {
        pick: "extend",
        content: "合併版",
        reason: "r",
        psychology: "p",
        replySegments: [
          { sourceMessage: "剛來吃晚餐", reply: "回吃飯球", reason: "" },
          { sourceIndex: 3, sourceMessage: "等等要去樂華夜市", reply: "回夜市球", reason: "" },
        ],
      },
    },
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ["extend"],
    requestMessages: [
      { isFromMe: false, content: "紅牛跟賓士差點打起來XD" },
      { isFromMe: false, content: "剛來吃晚餐" },
      { isFromMe: false, content: "等等要去樂華夜市" },
    ],
  });
  const rec = result.finalRecommendation as Record<string, unknown>;
  const segments = rec.replySegments as Array<Record<string, unknown>>;
  assertEquals(segments.length, 2);
  assertEquals(segments[0].sourceIndex, 2); // 文字回查修復
  assertEquals(segments[1].sourceIndex, 3); // 原本就合法
});

Deno.test("postProcess layer 3: all segments dropped falls back to merged content, never empty-source segments", () => {
  const result = postProcessAnalysisResult({
    result: {
      replies: {},
      finalRecommendation: {
        pick: "extend",
        content: "",
        reason: "r",
        psychology: "p",
        replySegments: [
          { sourceMessage: "", reply: "第一段", reason: "" },
          { sourceMessage: "", reply: "第二段", reason: "" },
        ],
      },
    },
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ["extend"],
    requestMessages: [{ isFromMe: false, content: "她的球" }],
  });
  const rec = result.finalRecommendation as Record<string, unknown>;
  assertEquals((rec.replySegments as unknown[]).length, 0);
  // 現狀單段行為：content 保留換行合併版
  assertEquals(rec.content, "第一段\n第二段");
});
```

**Step 2: 確認失敗** — `requestMessages` 參數不存在 → type error / 測試失敗。

**Step 3: 實作接線**

`postProcessAnalysisResult` / `ensureNonEmptyAnalysisOutput` 簽名加 `requestMessages?: Array<Record<string, unknown>>`，內部：

```ts
const ballList = extractPartnerBallList({ result, requestMessages });
```

`ensureNonEmptyAnalysisOutput`（:456-461 / :483 改）：

```ts
const effectiveSegments = preferredSegments.length > 0
  ? preferredSegments
  : fallbackOptionSegments;
const contractSegments = enforceReplySegmentSourceContract(
  effectiveSegments,
  ballList,
);
// 第三層：全段被 drop → content 回退「現狀單段行為」用 drop 前合併版。
const segmentMappedContent =
  (contractSegments.length > 0 ? contractSegments : effectiveSegments)
    .map((segment) => segment.reply)
    .join("\n");
// ...
  replySegments: contractSegments,
```

Step 3（:561-589）同型改法：`safeRecommendationSegments` 過 contract 得 `contractRecommendationSegments`；`segmentRecommendationContent` 用「contract 後非空則 contract 後、否則 drop 前」的清單；輸出 `replySegments: contractRecommendationSegments`。

注意 gating：contract 只在 `!recognizeOnly && !isMyMessageMode` 時 enforce（與 ensureNonEmpty 既有 gate 一致；my-message/recognizeOnly 路徑不產 segments，不可誤傷）。

`index.ts` 三呼叫點各加一行 `requestMessages: messages,`（:7159 vision 路徑同樣傳——OCR 球清單由 `extractPartnerBallList` 內部優先取 `result.recognizedConversation`）。

**Step 4: 跑測試**

Run: `deno test --allow-read supabase/functions/analyze-chat/post_process_test.ts supabase/functions/analyze-chat/index_test.ts`
Expected: PASS（含既有案；若既有案因 contract 落空段而紅，逐案補 `requestMessages` 或斷言更新——不得放寬 contract 本身）

**Step 5: Commit**

```bash
git add supabase/functions/analyze-chat/post_process.ts supabase/functions/analyze-chat/index.ts supabase/functions/analyze-chat/post_process_test.ts
git commit -m "feat: #12 一球一回 — finalRecommendation segments 過 source contract（三呼叫點接線 + 三層回退）"
```

---

### Task 3: SYSTEM_PROMPT 條件式 → 強制式（§1.2 範例 / §1.3 註記 / §1.5 重寫 / vision reminder / schema 範例）

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts`（:1135、:1400-1408、:1418-1426、:1458-1477、:1899-1913）
- Test: `supabase/functions/analyze-chat/index_test.ts`（:240-264 字串鎖更新）

**Step 1: 更新 index_test.ts 字串鎖（先紅）**

`SYSTEM_PROMPT supports structured split replies` 測試改鎖新不變量：

```ts
assert(source.includes("一球一回"));
assert(source.includes("必須分開回"));
assert(source.includes("每顆值得接的球各出一段"));
assert(source.includes("replySegments 最多 3 段"));
assert(source.includes("必填 sourceIndex"));
assert(source.includes("缺 sourceMessage 或 sourceIndex 的段會被系統丟棄"));
assert(source.includes("各段獨立成立"));
assert(source.includes("讓 App 顯示引用原句與分段複製"));
assert(source.includes("可直接複製送出"));
// emoji 鎖保留不動
```

（移除「一句總回」「分開回」舊條件式字串鎖；`:201` 的「通常只選 1-2 顆球，最多 3 顆」選球鎖保留。）

**Step 2: 確認失敗** — `deno test --allow-read supabase/functions/analyze-chat/index_test.ts`

**Step 3: 改 prompt**

§1.5（:1458-1477）重寫為「一球一回」強制式：

```
### 1.5 一球一回：分段引用與 emoji 畫龍點睛
先依 1.3 選球，再依「值得接的球數」決定回覆結構。同一個情緒/同一個生活片段的連續幾句算同一顆球，在同一段接住即可。

- 值得接的球只有 1 顆：維持單段——replySegments 填 1 段引用該球。
- 值得接的球有 2 顆以上：**必須分開回**——finalRecommendation.replySegments 每顆值得接的球各出一段，絕不把兩顆球的答案用逗點或頓號串成同一句。
- replySegments 最多 3 段；球超過 3 顆時挑互動價值最高的 3 顆出段，其餘不出段也不用提示。
- 每段必填 sourceIndex（這顆球是她這輪連發中的第幾句，從 1 開始數）與 sourceMessage（引用她的原句或片段），加上 reply（可直接複製送出的那句）、reason（為什麼這顆球值得單獨接）。缺 sourceMessage 或 sourceIndex 的段會被系統丟棄，等於白寫。
- 各段獨立成立：每段 reply 單獨送出也通順，不依賴其他段的上下文，讓 App 顯示引用原句與分段複製。
- finalRecommendation.content 仍要填：各段 reply 用換行串起來的合併版（舊版 App 備援），不能用 ①②、箭頭或「回某句」報告格式。
- replyOptions.*.messages 也要套用同樣規則：每種風格給 1-3 則短訊息，不要硬做成一大段代聊文；messages 可被 App 單獨複製。
- 不要把每個流水帳都拆成一段；只有「值得接」的球才出段，拆太多會像客服逐條回覆。
```

範例（:1472-1477）升級為三球三段（golden case 同構）：

```
範例（三顆球都值得接 → 三段，不准串成一句）：
- 她：「紅牛跟賓士差點打起來XD」「剛來吃晚餐」「等等要去樂華夜市」
- replySegments:
  - sourceIndex: 1 / sourceMessage:「紅牛跟賓士差點打起來XD」 / reply:「紅牛跟賓士沒打起來，但妳這行程已經先熱血起來了XD」
  - sourceIndex: 2 / sourceMessage:「剛來吃晚餐」 / reply:「先報告晚餐吃了什麼，我要評估妳今天的認真程度。」
  - sourceIndex: 3 / sourceMessage:「等等要去樂華夜市」 / reply:「樂華夜市我只問一件事：妳等等會不會被罪惡美食收買？」
- content: 三段 reply 用換行串起來的合併版
```

§1.2 範例（:1406-1408）改成換行兩段版（消滅「逗點串兩球」示範）；§1.3（:1420-1426 尾）加一行「選完球後若 ≥2 顆值得接，回覆結構走 1.5 一球一回分開回」。

Vision reminder（:1135）「如果判斷應該分開回，請填 finalRecommendation.replySegments」改為「對方連發 2 顆以上值得接的球時，必須填 finalRecommendation.replySegments 一球一段（最多 3 段，每段必填 sourceIndex 與 sourceMessage）」。

Schema 範例（:1904-1912）replySegments 擴成 2 段示範。

**Step 4: 跑測試** — `deno test --allow-read supabase/functions/analyze-chat/index_test.ts` Expected: PASS

**Step 5: Commit**

```bash
git add supabase/functions/analyze-chat/index.ts supabase/functions/analyze-chat/index_test.ts
git commit -m "feat: #12 一球一回 — SYSTEM_PROMPT 條件式改強制式（≥2 球必分段、source 必填、cap 3）"
```

---

### Task 4: stream contract 補 replySegments 必含規則（streaming 掉段根因）

**Files:**
- Modify: `supabase/functions/analyze-chat/stream_prompt.ts`（done 事件條目後）
- Test: `supabase/functions/analyze-chat/stream_prompt_test.ts`

**Step 1: 失敗測試**

```ts
Deno.test("stream contract requires replySegments in finalResult for multi-ball replies", () => {
  const prompt = buildStreamSystemPrompt("BASE");
  assert(prompt.includes("finalResult.finalRecommendation.replySegments"));
  assert(prompt.includes("Never omit `replySegments` to save tokens"));
});
```

**Step 2: 確認失敗。**

**Step 3: 實作** — `stream_prompt.ts` 在 "7. `analysis.done` ..." 行後插入：

```ts
"When the base rules require split replies (the other person threw 2+ catchable balls), `finalResult.finalRecommendation.replySegments` is REQUIRED: one segment per caught ball (max 3), each with non-empty `sourceIndex`, `sourceMessage`, `reply`, and `reason`. Never omit `replySegments` to save tokens; shorten optional report sections instead.",
```

**Step 4: 跑測試** — `deno test --allow-read supabase/functions/analyze-chat/stream_prompt_test.ts` Expected: PASS

**Step 5: Commit**

```bash
git add supabase/functions/analyze-chat/stream_prompt.ts supabase/functions/analyze-chat/stream_prompt_test.ts
git commit -m "feat: #12 一球一回 — stream contract 明定 finalResult 必含 replySegments（堵 compact 掉段）"
```

---

### Task 5: 全量驗證 + queue item + push（送 Codex 實作雙審）

**Step 1: 全套 Deno 測試**

Run: `deno test --allow-read --allow-env supabase/functions/analyze-chat/`
Expected: 全綠（基準 323+，新增約 10 案）

**Step 2: Style-pair 鎖回歸（驗收規格 #7）**

Run: `flutter test test/unit/features/user_profile/domain/effective_style_prompt_builder_test.dart`
Expected: PASS 原樣——client builder 未動，byte-for-byte 鎖不破（如實記入 queue：本案實際未破鎖，比設計假設的「重立基準」更強）。

**Step 3: Quick mode 不變驗證**

Run: `deno test --allow-read supabase/functions/analyze-chat/quick_prompt_test.ts supabase/functions/analyze-chat/quick_response_test.ts`
Expected: PASS 原樣（quick 用獨立 QUICK_SYSTEM_PROMPT，零變更）。

**Step 4: queue item 開「#12 實作雙審」**（`docs/reviews/ai-arbitration-queue.md` 置頂）——列 commits、測試證據、審查重點（球清單語意/trailing run 回退、contract 誤殺風險、stream contract 措辭、§1.2/1.3/1.5 一致性、golden case 為 TF 行為驗收非單元測試可證）。同 commit push（push 即自動部署 analyze-chat ~30s——舊 prompt 行為屬可回退範圍，但 APPROVED 前不得對 Bruce 說 safe）。

**Step 5: Commit + push**

```bash
git add docs/reviews/ai-arbitration-queue.md
git commit -m "docs: #12 一球一回實作 land — 開 queue item 送 Codex 實作雙審"
git push
```

**驗收對照（設計規格 #7）：**

| 驗收項 | 本計畫對應 |
|---|---|
| Golden case 三球三段 | prompt 強制式 + 範例同構（單元測試鎖字串；行為驗收 = 新 TF build Bruce 實測） |
| N=1 回歸 | §1.5 單球維持單段 + sanitizer N=1 不受影響（Task 2 gating） |
| Cap overflow | cap 3 全鏈未動（slice/take/prompt 一致），prompt 明寫挑互動價值最高 3 顆 |
| Schema validation | Task 1/2 三層規則 + 測試 |
| Quick 不變 | Task 5 Step 3 |
| Style-pair 重驗 | Task 5 Step 2（實測不破鎖，原樣通過） |
