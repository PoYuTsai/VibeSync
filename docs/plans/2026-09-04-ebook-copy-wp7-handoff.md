# 工作包 7 交接：入口、章名與完整視覺驗收（2026-09-04）

給下一個 Claude Code session 的開工包。先讀這份，再讀規格 §8「工作包 7」、§3.3（已拍板字串）、§13（視覺與真機驗收）、§17（完成定義）；研究報告 §5「區塊 UI 文案」。不要整份規格重讀。

## 0. 一句話

工作包 0–4 已合併進 main（`a20e14f`）；#66（工作包 5，第 1–4 冊口語化）與 #67（工作包 6，第 5–7 冊口吻）等 Eric 合併。工作包 7 是最後一包：書架說明句、付費說明拆短、繼續閱讀卡改兩行、8 個過長章名縮短、widget test 與 visual proof 更新（390／320 pt，文字縮放 1.0／1.3／2.0），然後用 §17 逐項關閉，交 Eric 真機驗收。不碰購買、權限與訂閱判斷；大標「高階互動指南」與副標「系統化實戰教材」不動。

## 1. 現況

| 項目 | 狀態 |
|---|---|
| #66 工作包 5 | open，base main，head `721c749`（Eric 已補審查修正、併入 main），標籤 `next:eric-ai` |
| #67 工作包 6 | open，base main，head `53bd993`，標籤 `next:eric-ai`，CI 已在跑 |
| 分支 | `claude/ebook-copy-wp7-entry` 從 #67 的 head `53bd993` 切出（章名改的都在第 5–7 冊，跟 #67 同檔）。開工時先 `git fetch origin`：#67 已合併就 `git rebase --onto origin/main 53bd993 claude/ebook-copy-wp7-entry`、PR base main；還沒合併就 PR base `claude/ebook-copy-wp6-voice`（沒有 CI，合併後再 rebase）。#66 只動第 1–4 冊與 Dart 契約測試，跟這包不衝突 |
| 稽核 | main 的 baseline 12 筆（R09 8 在 #66 歸零；R06 4：第 3 冊 3.2 e4 摘要、第 4 冊 4.3 cmp6 caption 在 #66 修掉；章名 5.6、7.4 是這包） |
| Reviewer（§15） | Eric 真機：書架、章名、字級與閱讀節奏。交棒標籤 `next:eric-ai` |
| 環境 | 容器沒有 Flutter：Dart／widget／visual proof 由 PR CI 跑（base=main 才跑）；本機只能跑工具單元測試、`normalize --check`、`audit --baseline`、`compare` |

## 2. 範圍（§8 工作包 7）

### 2.1 UI 文案（Dart）

| 位置 | 現況 | 改成 |
|---|---|---|
| `lib/features/learning/presentation/widgets/ebook_shelf_section.dart:375-376` 標題卡說明 | 從配對到把她約出來。先診斷你卡在哪一階，只練那一階——這是報酬率最高的事。 | 規格 §8 定稿：「先看你卡在配對、聊天，還是邀約。找到卡點後，只練現在最需要的那一步。」 |
| 同檔 `:350`／`:361` 大標、副標 | 高階互動指南／系統化實戰教材 | 不動（§3.3，2026-08-09 拍板）；`ebook_shelf_section_test.dart:126` 有斷言 |
| 同檔 `:216-220` 繼續閱讀卡「上次讀到 3.4 …」 | `maxLines: 1` | 改 `maxLines: 2`（§8：不靠極端縮名解決截斷）；書名那行維持 1 行 |
| 同檔 `:295` 群組卡 | 已開始 n／m 本 | 工作包 1 已改，不動 |
| `lib/features/learning/presentation/screens/ebook_detail_screen.dart` `_LockedNoticeCard`（`:418-455`）付費說明 | 四句塞三個方案名（先讀現況全文） | 研究報告 §5 建議：「這本要訂閱才能讀。免費能讀完第 1 冊和第 2 冊第一章；訂閱後第 2–4 冊全開，Essential 再多開《成為獎賞》三冊。」Essential 專屬那個分支也拆短。只改字，不改 `isEssentialOnly` 判斷與任何權限邏輯 |

### 2.2 章名（第 5–7 冊 JSON 的 `chapters[].title`；章 id 不動）

規格說 13 個，工作包 4／6 已改掉 5 個；現在超過 14 字的剩 8 個（R06 章名上限 22 字，5.6 與 7.4 超標）。建議（保留原意、≤14 字，Eric 拍板）：

| 章 | 現況（字數） | 建議 |
|---|---|---|
| 5.1 | 你不是不會聊，是大腦一直在替你找台階（18） | 大腦一直在替你找台階 |
| 5.6 | 她到底在要什麼——六種感覺，還有撩跟對的那條線（23） | 她要的六種感覺，還有怎麼給 |
| 6.1 | 對話有兩層：上面聊內容，下面分主導（17） | 對話有兩層：內容和主導 |
| 6.3 | 對她好沒錯，別把自己整個交出去（15） | 對她好，但別把自己交出去 |
| 6.4 | 吵完還能笑著約出來，才算真的過了這關（18） | 吵完還能笑著約出來 |
| 6.6 | 她一開始回得冷，先別急著對號入座（16） | 她回得冷，先別對號入座 |
| 7.4 | 聊了三個月還是「網友」？因為你的訊息少了這兩樣東西（25） | 訊息裡少了前提和樣本 |
| 7.5 | 三個訊號，看穿她對你到底有沒有興趣（17） | 三個訊號，看她有沒有興趣 |

- 第 1–4 冊章名都在 14 字內，不動。書名、副標、goal 不動。
- 章名改了不升 `contentVersion`（§14：續讀存 chapter id）。第 7 冊漏斗的 `targetLabel`（「第 3.2 章：回得冷時先止損」等）與第 5 冊 `c6-cal2`「下一章」這類提到章名的地方要對一遍。
- 改完 `audit --baseline` 應解決 2 筆（R06 章名），`--write-baseline` 後 baseline 12 → 10（#66 合併後 → 0）。

### 2.3 測試與 visual proof

- `test/widget/features/learning/ebook_shelf_section_test.dart`、`learning_screen_ebook_hierarchy_test.dart`：說明句與繼續閱讀卡兩行的斷言；付費說明的 widget test（grep `訂閱` 找）。
- visual proof 現有：`test/visual_proof/ebook_shelf_proof_test.dart`（書架）、`ebook_reading_layout_proof_test.dart`（5.1 全章、6.3 全章，framed／spine；ADR 提到 spine 下 320 px＋2.0 字級不 overflow 的測試在學習模組單元測試裡）、`ebook_library_proof_test.dart`（2.5、3.4 條目庫）、`ebook_funnel_proof_test.dart`（1.1 漏斗）。共用 `proof_support.dart`／`proof_themes.dart`（`kPhone` 390 寬）。輸出 `build/visual_proof/*.png`。
- 這包要補：§13.2 的矩陣——390 pt 與 320 pt、文字縮放 1.0／1.3／2.0（`MediaQuery` `textScaler`），至少覆蓋書架入口、繼續閱讀卡（25 字章名的前後對照）、最密的 callout／comparison 章（6.3、6.5 或 7.6）。用正式 JSON，不用手工假資料（§18 第 9 條）。
- §12.3 第 14 條契約：書架大標、副標與單元 layout 不得被順手改掉——widget test 已有副標斷言，可補大標。

### 2.4 收尾（§17 完成定義）

- 對照 §17 逐項寫「達成／未達成／不在本次」：例如「7 冊 39 章、558 block」的數字已因結構修復變成 610 block、112 entry、21 crossRef，要在報告寫明是設計變更不是遺失；「5 位未參與編寫者試讀」「Eric 完成實機閱讀驗收」是人做的，報告只能標待辦。
- 報告 `docs/reviews/2026-09-04-ebook-copy-wp7-entry-report.md`＋規格 §19.12；`docs/snapshot.md` 若有電子書文案優化的階段描述，更新一句。

## 3. 做法

1. UI 文案與章名各一個 commit（Dart／JSON 分開），測試與 proof 一個 commit，文件一個 commit；繁中訊息。
2. 章名用腳本依 chapter id 改，先斷言原文；再 `normalize --check`、`audit --baseline`、`--write-baseline`、工具單元測試、`compare_ebook_import.py --official <#67 的七冊> --candidate assets/learning/ebooks`（只應有 8 個章名變動）。
3. Dart 改完自己讀一遍 diff（沒有 Flutter 可跑）：`maxLines`、字串常數、測試斷言要對得上；push 後由 PR CI 驗。
4. PR 說明列出：8 個章名前後對照、說明句、付費說明前後、proof 圖檔清單；標籤 `next:eric-ai`；請 Eric 真機看 §13.1 那張表。

## 4. 坑

- `ebook_shelf_section.dart` 的說明句是兩個相鄰字串常數拼接，改的時候整段換。
- 付費說明有兩個分支（Essential 專屬／一般訂閱），兩邊都要拆短，且不能對 Starter 說「訂閱就全開」（檔內註解有寫）。
- 章名出現在漏斗 `targetLabel`、「下一章」callout、前往按鈕 label 裡的都是自由文字，改章名後 grep 舊章名確認沒有殘留。
- 第 7 冊 7.1 漏斗第 2 層 `targetLabel`「第 3.3 章：接住試探」之類是章「編號＋短語」不是章名，不用同步。
- `tools/content/__pycache__` 不要 commit；Stop hook 會催 commit／push，在這條分支照做。

## 5. 留給 Eric 的決定

- 8 個章名的建議寫法（上表）。
- 付費說明兩個分支的最終字。
- 繼續閱讀卡改兩行後，書架高度會多一行；如果不接受，改成章名縮到 14 字內就夠。
