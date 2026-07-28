# 回覆風格微調 — 設計審查結果（雙審合併）

日期：2026-07-28
審查標的：`../plans/2026-07-28-reply-refinement-design.md` v1（分支 `claude/reply-style-refinement-j6br3y`）
審查包：`2026-07-28-reply-refinement-design-review-packet.md`
基準 SHA：`c7cefb4405bcacd1bb127e56e6e5e8b46fd145af`

審查者：

- **Codex（GPT-5.6）** — 讀碼審查，另讓 Claude Fable 與 GLM-5.2 各做一次唯讀 falsification。
- **Claude Opus 5** — 獨立讀碼審查，未看 Codex 結果前先出裁決，之後回原始碼核對 Codex 的每一條主張。

兩份審查皆為唯讀，工作樹未被修改。

---

## 總裁決

**v1 未通過 gate。** 兩份審查獨立指出同一個結構性 blocker（付費邊界不可強制），Codex 另外抓到第二個 blocker（安全條款無執行機制），Claude 回原始碼確認屬實。

**方向本身兩邊都同意值得做。** v2 已依 Eric 拍板重寫，見設計文件。

---

## 兩個 Blocker

### B-1 Free／Essential 邊界可被繞過（兩邊獨立抓到）

`deriveRequestType`（`quota_usage.ts:3-27`）由請求形狀推導 requestType，server **沒有任何證據**能證明 `userDraft` 是 AI 產出的建議。Free 使用者把自己的草稿加一句 `.` 或「自然一點」，即可使用原本 Essential-only 的草稿潤飾。

不可靠的收斂方式（兩邊一致）：顯式旗標、最短字數、關鍵詞、語意分類——都不是 entitlement seam。

**Codex 提出的唯一技術解**：server 產生 AI 回覆時一併回傳簽名的 `refineCapability`（綁 user、原文 hash、來源、效期），每輪微調再簽發下一張；沒有合法 capability 就不能走 Free refine，自己的草稿仍走 Essential polish。可用 stateless HMAC 完成，不需 migration，但**會改 wire 契約**。

**Claude 補充的成本**：分析回覆是串流產出，capability 必須隨串流輸出帶下每張卡的簽章，Phase 1 規模約翻倍；且 `_copyAllText` 合併後的整組文字對不上任何單張簽章，簽章粒度必須是單句。

**Eric 拍板：拆牆**（見設計文件 §2.1）。

> Claude 的 v1 裁決曾主張「無 server 解、只能二選一（開放或放棄迭代）」，**此裁決被 Codex 推翻**：capability 是成立的第三條路。記錄於此以免日後重覆討論。

### B-2「安全鐵律」目前只是 prompt 願望（Codex 抓到，Claude 驗證屬實）

`guardrails.ts:92` 的 `checkAiOutput` 開頭：

```ts
if (!result?.replies) { return result; }
```

`optimizedMessage` 的回應沒有 `replies` 欄位，因此 **`optimizedMessage.optimized` 完全不經過輸出守門**。`OPTIMIZE_MESSAGE_PROMPT`（`index.ts:2165`）也沒有形成可驗證的「不改變對話動作」保證。

**Claude 補充**：這是既有漏洞，草稿潤飾器自 `4b624617`（2026-07-16）上線至今從未被守門掃過，不是本設計造成的；但微調把使用者可控指令接上這條無守門路徑，把靜態破口變成可被引導的破口。**建議獨立於本功能先修。**

最低要求（Codex，v2 全數採納）：不可覆蓋規則放 system prompt、指令用 JSON 編碼、輸出守門實掃 `optimizedMessage.optimized`、建立 coercion／捏造／越界／改變邀約或拒絕方向的 adversarial fixtures。若仍要自稱「鐵律」，還需 generation 後的語意 verifier；否則文件改稱 best-effort policy。**v2 選擇後者。**

---

## Q-1 ～ Q-9 合併裁決

| # | 裁決 | 兩邊是否一致 |
|---|---|---|
| **Q-1 Hash 相容** | **成立**。條件式 append 不改變舊陣列 bytes（server `JSON.stringify` 8 元素；client `jsonEncode` 7 元素＋collection-if）。鎖法＝**兩側各一條舊版 canonical string＋固定 SHA 常數**，不能互比。另測「舊 client pending 可被新版恢復」。 | 一致 |
| **Q-2 13 個使用點** | 除 Essential gate 外全部加寬。`4711` request shape 與 `5106`/`5144` quota early gate 一併涵蓋（Claude 補：後兩者用的就是 4711 的變數，加寬 4711 即自動涵蓋）。漏改分級見設計文件 §2.9。 | 一致 |
| **Q-3 付費牆** | **有洞、blocking**。空字串／全空白在明確 refine 操作下應 **400、0 扣費**，不得默默降級為 polish。標點／emoji 可視為合法指令。 | Codex 的處理較佳，Claude 原主張「降級回 polish」已撤回 |
| **Q-4 1500 字** | **會撞上**。不截斷；server 限制 refine **輸出**上限，client 對過長來源禁用送出。**Claude 主張更根本的解＝只微調單句**，v2 採用（同時解掉簽章粒度問題）。 | 互補 |
| **Q-5 Rate limit** | Phase 1 共用 `analyze` scope（6/分）。依 requestType 監控命中率。**拆獨立 scope 不需要 migration**（`20260703170000_model_call_rate_limit.sql:26-27` 的 scope 是自由 text，只有長度 CHECK，上限權威在 Edge）。 | Codex 對；Claude 原主張「拆 scope 會破 P1」已撤回 |
| **Q-6 Injection** | **不足**。不用關鍵詞 blocklist（易繞過＋誤傷繁中）。需 system hierarchy、JSON encoding、output guard、adversarial eval。硬性語意 invariant 需 verifier。 | 一致（Claude 的「剝除換行與控制字元」是 JSON encoding 的子集） |
| **Q-7 Telemetry** | **(c) 獨立事件**，key＝`refine:<originAdviceId>:<requestId>`，另帶 `originCardKey`。原卡 KPI 連續、微調採用率獨立、避開 first-write-wins。 | 一致 |
| **Q-8 Regenerate** | **v1 前提錯誤**。Replay key 是 `(user_id, request_id)`，hash 只是 mismatch guard；`markSuccess`（`optimize_message_request_session.dart:262`）成功後清 pending，再按同指令會產生新 UUID、重新生成、再扣 1。**「再換一版」可以安全提供。** | Codex 抓到機制；Claude 獨立抓到「連點必扣」的產品後果，兩者互補 |
| **Q-9 錯誤文案** | 保留穩定 server code，由 client 依 polish／refine 入口顯示文案；server fallback 可改中性「回覆處理」，不改 code 字串。 | 一致 |

---

## P1 ～ P3

| 命題 | 裁決 |
|---|---|
| **P1 不需要任何 migration** | **SUPPORTED（有條件）**。既有 ledger、JSON shape、`request_type TEXT`（`00003_ai_logs.sql:10`，**無值白名單 CHECK**）、rate-limit scope 都能承接；採 stateless capability 也不需 migration。**但若改採 provenance table，或 v2 的免費額度改用獨立表，即不成立。** |
| **P2 不改變既有付費邊界** | **REFUTED**。沒有任何 server 證據能證明 `userDraft` 是 AI 產出。v2 已把「拆除潤飾器 Essential 閘門」寫成明示的商業決定，不再宣稱邊界未變。 |
| **P3 對 7 天窗內 pending 零影響** | **SUPPORTED（有條件）**。前提是指令缺席時兩側各自 byte-identical，且**必須用舊版固定 golden 常數鎖住**。 |

---

## v1 文件的事實錯誤（已於 v2 修正）

| # | v1 說法 | 實際 | 抓到者 |
|---|---|---|---|
| E-1 | 審查包 F3「client fingerprint 元素與順序與 server 對應」 | **server 8 元素（含 `forceModel`）、client 7 元素（不含）**。照「對齊兩側」去改 client 才會炸掉 pending。 | 兩邊獨立抓到 |
| E-2 | 審查包 F13「mismatch 都是 400」 | preflight mismatch **400**（`index.ts:6942`）；settlement race mismatch **409**（`index.ts:9276`）。 | Codex |
| E-3 | 白話版「扣費與防重複機制穩定跑兩個月」 | `optimize_message_billing.ts` 與整套 fixed-charge exactly-once 出自 `4b624617`（**2026-07-16**），到今天 **12 天**。 | Codex |
| E-4 | 白話版「相同輸入＋相同要求一定 replay 且不扣費」 | 錯，見 Q-8。 | Codex |

---

## Phase 2 裁決：整段延後

Codex 指出「用三次就記住」定義不足，Claude 同意。重寫時必須處理：只計成功且被採用的版本、固定 chip 用穩定 category ID、自由文字第一版不做語意歸類、最好跨至少兩個不同來源才觸發、定義時間窗／cooldown／重複提示／刪除行為。

**不要把學到的偏好塞進 100 字的 `UserProfile.notes`**；改用獨立、結構化、可刪除的加密本機 preference，由 `EffectiveStylePromptBuilder` 這個 seam 合併輸出。

---

## 其他採納的建議

- 微調結果離開畫面全失去**不建議直接上線**：用加密本機暫存保留最後成功版本 24 小時，不污染不可變的 `AnalysisRecord`。（Codex）
- 快捷 chip 的「更直接一點」改為「白話一點」——「更直接」容易被讀成改變承諾／邀約／界線方向，與安全條款衝突。（Codex）
- client 端加按鈕 in-flight 鎖與 debounce，把連點源頭掐掉，不靠 server 節流兜底。（Claude）
- Q-7 的 (c) 有現成先例：`cardKey == 'polish'` 已有自己的 `_polishRunKey` 命名空間（`analysis_screen.dart:5532`），照抄即可，成本遠低於文件估計。（Claude）

---

## 未完成事項

- 兩份審查皆未執行任何測試（設計審查、無 code）。
- Claude 未逐一核對 Dart 端閘門的所有呼叫點，未驗證 `findClientShapeViolations` 對 refine 輸出的實際行為。
- 實作階段會另出 review packet，屆時附 Deno／Flutter 測試輸出與 live smoke。
