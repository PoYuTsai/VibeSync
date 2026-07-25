# 互動電子書 — 跨模型雙審 reconciliation

- 日期：2026-07-25 ~ 07-26
- Primary implementer／integrator：Claude Code（Opus 5）
- Opposite-frontier review：Codex CLI（gpt-5.6-sol），read-only／ephemeral／tools-reduced
- Falsification pass：GLM 5.2，read-only
- Review range：`1f89b00f..HEAD`（branch `claude/interactive-learning-ebooks`）
- Packet：最小自含 packet（需求＋不變量＋13 個新增/修改 Dart 檔全文＋learning/settings/routes diff
  ＋Book 3 §3.5 與 Book 4 §4.4 安全 callout 樣本）。未送 secrets、`.env`、
  客戶資料或真實聊天。
- Reviewer 均為唯讀，未修改 worktree、未部署、未 push。

## 判定摘要

| # | Review focus | Codex | GLM | Primary 裁決 |
|---|---|---|---|---|
| 1 | Free 是否可能看到 Books 2–4 | ISSUE P1 | 沒找到反例 | 部分成立 → 見 F1；stale-premium 部分為刻意決策 D1 |
| 2 | loading／error 是否閃出內容或假裝 upsell | ISSUE P1 | 找到反例 P2 | **成立 → 已修（F1）** |
| 3 | 是否誤扣文章額度 | PASS | 沒找到反例 | PASS |
| 4 | 帳號 A／B 是否串進度 | ISSUE P1 | 輕微 P3 | **成立 → 已修（F2、F3）** |
| 5 | content／quiz revision 舊答案 | ISSUE P2 | 沒找到反例 | quiz 正確；contentVersion 為既定策略 → D2 |
| 6 | parser 是否 fail closed | ISSUE P2（少 20 章檢查） | 沒找到反例 | 型別安全 PASS；章數為測試期不變量 → D3 |
| 7 | 三燈／Quiz 是否只靠顏色 | PASS | 大部分 PASS，兩檔未見 | PASS（未見部分由既有測試覆蓋） |
| 8 | 反操弄內容是否被重新包裝 | UNCERTAIN（僅樣本） | 沒找到反例（僅樣本） | 機械掃描 PASS；**人工通讀仍待 Eric／夥伴** |
| 9 | 既有 24 篇與 Coach 深連 | UNCERTAIN（缺證據） | 沒找到反例（Coach 證據不足） | 已補測試 → PASS |

兩位 reviewer 獨立指向同一個最重要的問題（focus 2 的書架卡），這一致性提高了它的可信度。

## 已修的問題

### F1 — 書架把「訂閱狀態未確認」包裝成 Free upsell（Codex P1／GLM P2）

`ebookLockedFor` 把 `resolving` 與 `unavailable` 都折成 `locked=true`，於是書架對
Books 2–4 顯示「訂閱解鎖」pill，點一下直接 `push('/paywall')`。這與「無法確認時不
把技術錯誤包裝成 Free upsell」直接矛盾。暴露條件是 `!isPremium && (isLoading || error)`，
例如重裝後首次載入、或訂閱查詢失敗。

修法：書架改用三態 `EbookAccessDecision` 而不是 bool。
- `locked`（已確認免費）→「訂閱解鎖」＋導 paywall。
- `resolving`／`unavailable` →「確認訂閱中」中性標籤，點擊進書籍目錄，
  由 `EbookAccessGate` 顯示 loading 或可重試錯誤。

測試：`ebook_shelf_section_test.dart` 新增 resolving／unavailable 兩案，
斷言不出現「訂閱解鎖」、不進 paywall、而是進入目錄。

### F2 — 帳號切換競態下 A 的 snapshot 可能發布到 B 的畫面（Codex P1）

`_publish` 只檢查 `_disposed`，snapshot 不帶 owner。A 啟動的 Hive 寫入若在 auth
切到 B 之後才 resolve，就會把 A 的進度寫進已經屬於 B 的 state。

修法：controller 記住 `_currentOwner`，`_publish(writeOwner, snapshot)` 在 owner
不符時丟棄結果（寫入本身照舊完成，不取消）。

測試：`ebook_progress_controller_test.dart`「帳號切換期間完成的舊寫入不會發布到
新帳號的 state」——同時斷言 B 看不到 A 的章節、且 A 的寫入仍落地。

### F3 — 重建期間 AsyncLoading 的 previousValue 洩漏上一個帳號的完成度（GLM P3／Codex P1 同源）

`ebookBookProgressProvider` 用 `snapshot.value`，而 Riverpod 重建時會把上一次的值
掛在 `AsyncLoading.previousValue`，於是換帳號的空窗期會短暫顯示 A 的完成度。

修法：改成只讀 `AsyncData`，其餘一律回 `EbookBookProgress.empty`。
代價是任何 refresh 都會短暫顯示 0%，這比顯示別人的進度好。

測試：同檔「重建期間不沿用上一個帳號的進度」。

### F4 — 完成章節寫入失敗會永久卡在 loading（Codex P2）

`_completeChapter` 沒有 try/finally，Hive 寫入拋錯時 `_saving` 永遠是 true，
按鈕從此不能按。

修法：try/catch，失敗時解除 loading 並顯示「進度沒有存起來，請再按一次。」，
不翻頁、不假裝完成。

測試：`ebook_reader_screen_test.dart`「寫入失敗不會卡在 loading」，用
`FailingHiveBox`（`put` 必拋）驗證按鈕回到可按狀態且沒有翻頁。

### F5 — Quiz／checklist 保存失敗時畫面仍宣稱已保存（Codex P2）

閱讀器的 `onQuizSubmitted`／`onChecklistItemChanged` 是 fire-and-forget，失敗會
變成 unhandled error，而畫面仍顯示「答對了／已理解」。

修法：兩個 callback 都接上 `catchError`，失敗時 SnackBar 告知「這一題的作答沒有
存起來」。樂觀 UI 保留（本機進度是 best-effort，不阻擋閱讀），但不再無聲失敗。

### F6 — 從 paywall 返回後卡在無盡 loading（GLM P3）

`locked` 分支用 `_redirected` 防重複導航，但畫面是 spinner。使用者從 paywall
返回後不會再自動導航，於是看到一個永遠不會結束的 loading，只能按返回。

修法：`locked` 改為可操作畫面（標題＋「看訂閱方案」＋「回學習頁」），
仍然完全不建立 premium child。

測試：`ebook_access_gate_test.dart`「從 paywall 返回後不是無盡 loading」。

### F7 — 同一題的 savedState 換人時沒有重置（Codex P1 附帶）

`didUpdateWidget` 只在 quiz id／revision 改變時 restore，帳號切換導致同一題的
savedState 變成 null 時不會清空，A 的作答會留在 B 的畫面上。

修法：`savedState` reference 改變時也重跑 restore。
測試：`ebook_quiz_card_test.dart`「savedState 換人時清掉畫面上的作答」。

## 不修，但已記錄為刻意決策

### D1 — `isPremium` 優先於 `isResolving`／`hasError`（Codex P1）

Codex 正確指出：本機仍快取 premium 但 entitlement 已失效者，在刷新完成前可以
開啟付費書，因此「Free 絕對看不到 Books 2–4」不是無條件成立。

不改的理由：
1. `SubscriptionState` 啟動時就是「先用本機快取 tier ＋ `isLoading: true`」
   （`buildInitialSubscriptionStateFromUsage`）。把 resolving 排在 isPremium 前面，
   等於每個付費使用者冷啟動都先看到 loading 或降級，這與 App 既有的 entitlement
   姿態相反。
2. 這不是本功能新增的破洞，而是全 App 共用的快取信任模型。
3. 會自我修正：tier 一旦解析成 free，閘門重算即轉 locked 並導 paywall。

已在 `ebookAccessFor` 的 doc comment 寫明取捨，並加測試把
`premium+resolving`／`premium+error` → `allowed` 釘成明確決策而不是意外。
**若 Eric 認為應改成「未確認即不放行」，那是產品決策，我不自行更動。**

### D2 — `contentVersionSeen` 只記錄、不失效進度（Codex P2）

拍板策略是「純文案修改保留進度；真正改寫一章時改 chapter id 或升 quiz revision」。
所以 contentVersion 變動不清除完成狀態是規格行為，不是漏洞。已在
`EbookBookProgress.contentVersionSeen` 的 doc comment 寫明，並保留欄位給未來
需要明確 migration 時當起點。

### D3 — 四本二十章不在 runtime 強制（Codex P2）

Runtime 已強制：書號與資產順序一致、Book 1 免費其餘訂閱、id 全域唯一、
型別與必填欄位、單選恰一正解、複選至少一正解且非全對。

章數刻意留在測試期（`ebook_content_invariants_test.dart`：四本、每本五章、
共 20 章）。若寫進 runtime，未來合法新增一章就會讓整個學習頁書架掛掉，
代價遠大於效益。

### D4 — 「再試一次」不清除已保存的作答（Codex P3）

按重試但沒重新提交就離開，回來仍會看到上一次的作答。這是刻意的：那筆紀錄是
事實（確實答錯過一次），清掉反而是抹除資料。已在 `ebook_quiz_card.dart` 註明
「retry 只是暫時 UI 狀態」，並加測試釘住（按重試不產生任何保存呼叫）。

## Reviewer 的 uncertain 項，由 primary 補證

| Reviewer 疑慮 | 補證 |
|---|---|
| settings box 是否真的加密 | `storage_service.dart:121-124` 以 `HiveAesCipher(encryptionKey)` 開啟 `AppConstants.settingsBox`，key 存在 `FlutterSecureStorage`。 |
| 24 篇文章／article id 回歸 | `learning_screen_ebook_hierarchy_test.dart` 斷言 `articles` 仍為 24 且電子書 id 不在 article id space；`ebook_routes_test.dart` 斷言 `/article/:id` 未改。 |
| Coach「看教學」深連 | `ebook_routes_test.dart` 對每個 `CoachActionType` 檢查 `LearningLinkResolver.resolve` 仍指向存在的 article id；既有 `learning_link_resolver_test.dart` 22 項全綠。 |
| `isSolvedBy` 未在 packet 中 | `ebook_catalog_test.dart`「isSolvedBy needs the exact correct set」驗證完全匹配（子集、超集、空集皆為 false）。 |
| flip card／checklist 灰階可判讀 | `ebook_flip_card_test.dart`（正反面用不同標題與 hint 文字＋semantics label）、`ebook_block_renderer_test.dart`（checklist 用 check_box 圖示＋「N / M」計數）。 |

## 事實勘誤（不影響結論）

兩位 reviewer 都把既有文章路由寫成 `/learning/articles/:id`；實際是 `/article/:id`
（`lib/app/routes.dart:224`）。packet 內含該段 diff，屬 reviewer 讀取疏漏，
不改變「既有路由未被修改」的結論。

## 仍然開著的 gate

1. **人工通讀二十章文案**：兩位 reviewer 都只拿到 2 章樣本，且明確指出機械掃描
   無法取代人工調性審查。本輪的自動化只做到：禁語掃描（14 條）、反效果技巧必須
   落在 warning／safety 框架、涉及邀約／拒絕／升級的章節必須有安全 callout。
   → 需要 Eric／夥伴驗收，這是 DoD 的「文案驗收」項。
2. **真機 dogfood**：Free／付費、deep link、續讀、帳號切換、2.0 字級與 reduced
   motion 的實機確認。
3. 未 push、未 deploy、未送 TestFlight。

## 證據檔

已入 repo（完整 stdout，未經截斷）：

- `docs/reviews/2026-07-25-interactive-ebooks-codex-review.stdout.md`
- `docs/reviews/2026-07-25-interactive-ebooks-glm-falsification.stdout.md`

只留在 session scratchpad（packet 含大量程式碼全文，不入 repo）：

- `review_packet.md`（157KB）／`falsify_packet.md`（158KB）
- 兩支 wrapper 的 stderr（含 CLI 版本、模型名、isolation 標記與 token 用量）
- 位置：`/tmp/claude-1000/-mnt-c-Users-eric1-OneDrive-Desktop-VibeSync/060f5b64-af5c-44cd-af31-fa8f5df47a8b/scratchpad/`

Wrapper 與模型：

- `invoke-codex.sh --mode review` → `gpt-5.6-sol`，isolation `read-only/ephemeral/tools-reduced`，exit 0，62,492 tokens
- `invoke-glm.sh review` → `glm-5.2`，read-only，exit 0
