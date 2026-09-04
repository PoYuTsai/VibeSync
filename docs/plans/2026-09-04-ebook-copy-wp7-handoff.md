# 工作包 7 交接：入口、章名與完整視覺驗收（2026-09-04）

給下一個 Claude Code session 的開工包。先讀這份，再讀規格 §8「工作包 7」、§3.3 已拍板字串、§13 視覺與真機驗收、§17 完成定義；不要整份規格重讀。

## 0. 一句話

工作包 0–4 已 Squash Merge 進 main（#61–#65）；#66（工作包 5，第 1–4 冊口語化）與 #67（工作包 6，第 5–7 冊口吻）都 open、base 都是 main、標籤 `next:eric-ai`，等 Eric 決定。工作包 7 是最後一包：書架說明句、8 個過長章名、繼續閱讀卡改兩行、widget test 與 visual proof 更新，然後用 §17 逐項關閉，交 Eric 真機驗收。付費說明與「已開始 n／m 本」已經是規格要的樣子，只需確認。

## 1. 現況

| 項目 | 狀態 |
|---|---|
| main | `a20e14f`（#65 合併後）。 |
| #66 | open，head `721c749`（Eric 已把 main 併進去並補審查修正），第 1–4 冊 JSON、`audit_baseline.json` 12→2、Dart 契約一條、報告。 |
| #67 | open，head `53bd993`，第 5–7 冊 JSON（105 區塊、9 條目標題、4 章欄位）、報告；建 PR 時 CI 排隊中。 |
| 分支 | `claude/ebook-copy-wp7-entry`，從 #67 的 head `53bd993` 切出（章名要縮的 8 個全在第 5–7 冊，跟 #67 同檔）。開工時先 `git fetch origin main`：若 #67 已合併，`git rebase --onto origin/main 53bd993 claude/ebook-copy-wp7-entry`，PR base main；沒合併就 PR base `claude/ebook-copy-wp6-voice`（沒有 CI），合併後再 rebase。#66 合併與否不影響（工作包 7 不碰第 1–4 冊）。 |
| 稽核 | main 的 baseline 12 筆（R09 8 → #66 歸零；R06 4：第 1–4 冊 2 筆 → #66 歸零；5.6、7.4 章名 2 筆 → 這一包歸零）。三個 PR 都進 main 之後 `--write-baseline` 應該是 0 筆。 |
| Reviewer（§15） | Eric 真機。交棒標籤 `next:eric-ai`。 |
| 環境 | 容器沒有 Flutter：Dart／widget／visual proof 由 PR CI（base=main）跑；本機門檻是工具單元測試、`normalize --check`、`audit --baseline`、`compare`。 |

## 2. 範圍（§8 工作包 7）

### 2.1 書架說明句（`lib/features/learning/presentation/widgets/ebook_shelf_section.dart` 第 375–376 行）

現況：「從配對到把她約出來。先診斷你卡在哪一階，只練那一階——這是報酬率最高的事。」
定稿（§8）：「先看你卡在配對、聊天，還是邀約。找到卡點後，只練現在最需要的那一步。」
大標「高階互動指南」、副標「系統化實戰教材」不動（§3.3；`ebook_shelf_section_test.dart:126` 有斷言）。目前沒有測試斷言說明句，改完可以加一條 `find.text`。

### 2.2 已經是規格要的樣子，只確認

- 單元進度「已開始 n／m 本」（工作包 1 做完，`ebook_shelf_section_test`、`learning_screen_ebook_hierarchy_test` 七處斷言）。
- 付費說明（`ebook_detail_screen.dart` `_LockedNoticeCard` 與免費試讀卡）已是短版：「這本要訂閱才能讀。免費能讀完第 1 冊和第 2 冊第一章；訂閱後第 2–4 冊全開，Essential 再多開《成為獎賞》三冊。」不碰購買、權限與訂閱判斷。

### 2.3 章名縮短（目前超過 14 字的 8 個；R06 上限 22 字，5.6 與 7.4 超標）

| 章 | 現況（字數） | 建議 | 備註 |
|---|---|---|---|
| 5.1 | 你不是不會聊，是大腦一直在替你找台階（18） | 大腦一直在替你找台階（10） | 研究報告建議 |
| 5.6 | 她到底在要什麼——六種感覺，還有撩跟對的那條線（23） | 她要的六種感覺，還有怎麼給（13） | 工作包 6 已把「撩／對」改成「輕鬆試探／逼對方表態」，章名不要再用「撩」 |
| 6.1 | 對話有兩層：上面聊內容，下面分主導（17） | 對話有兩層：內容和主導（12） | |
| 6.3 | 對她好沒錯，別把自己整個交出去（15） | 不動 | §9.6 定稿字串，15 字可接受 |
| 6.4 | 吵完還能笑著約出來，才算真的過了這關（18） | 吵完還能笑著約出來（10） | |
| 6.6 | 她一開始回得冷，先別急著對號入座（16） | 不動，或「她回得冷，先別對號入座」（12） | §9.6 P0 定稿字串，改短要 Eric 點頭 |
| 7.4 | 聊了三個月還是「網友」？因為你的訊息少了這兩樣東西（25） | 訊息裡少了前提和樣本（11） | 研究報告建議；工作包 6 已用「兩個問題」定義前提／樣本 |
| 7.5 | 三個訊號，看穿她對你到底有沒有興趣（17） | 三個訊號，看她有沒有興趣（12） | |

章 id 不動（續讀存 chapter id；教練深連結只指章 id）；測試沒有硬寫章名字串（grep 過）。第 1–4 冊章名最長 14 字（2.1、4.2），不動。

### 2.4 繼續閱讀卡改最多 2 行

`ebook_shelf_section.dart` 第 216–220 行「上次讀到 ${chapter.number} ${chapter.title}」是 `maxLines: 1` + ellipsis；改 `maxLines: 2`（書名那行維持 1 行）。看 `ebook_shelf_proof_test.dart`（390pt，量內容高度後截圖）與 `ebook_shelf_section_test.dart`（含 320pt／文字縮放）有沒有因為高度變化要調；新增一條 widget test：25 字章名在 320pt、文字縮放 2.0 下不 overflow、看得到章名前半。

### 2.5 視覺驗收（§13）

- 既有 visual proof：`ebook_shelf_proof_test`（書架）、`ebook_library_proof_test`（條目庫、前往按鈕）、`ebook_reading_layout_proof_test`（5.1 全章、6.3 全章 framed／spine）、`ebook_funnel_proof_test`；都是 390pt、正式 JSON，輸出 `build/visual_proof/*.png`。既有 widget test 已覆蓋 320pt 與文字縮放 2.0（`ebook_block_renderer_test`、`ebook_entry_list_test`、`ebook_shelf_section_test`、`ebook_reader_screen_test` 等）。
- 這一包要做的：跑全部 learning 測試確認章名與說明句改完仍綠；§13.1 那張「必看畫面」表逐項在報告裡寫「哪個 proof／哪個 test 覆蓋」，沒覆蓋的列給 Eric 真機看。
- 不用手工假資料做 proof（§18 第 9 條）。

### 2.6 用 §17 逐項關閉

報告末段放一張 §17 的表：每一條寫「哪個 PR／哪條規則／哪個測試」證明，未達成的寫清楚（例如「5 位未參與編寫者試讀」「Eric 實機驗收」是這包之後的人工步驟）。

## 3. 做法

1. UI：改 `ebook_shelf_section.dart` 兩處（說明句、`maxLines`），補 widget test。
2. 章名：直接改第 5–7 冊 JSON 的 chapter `title`（8 個，或依 Eric 拍板的子集）；`normalize --check`；`audit --baseline` 新發現 0 → `--write-baseline`（5.6、7.4 兩筆消失）；`--parent-baseline` 對 main 只縮小。
3. 工具測試、`compare_ebook_import.py --official <基底七冊> --candidate assets/learning/ebooks`（只有章名變動）。
4. 報告 `docs/reviews/2026-09-04-ebook-copy-wp7-entry-report.md`（改了什麼、§13.1 覆蓋表、§17 關閉表）＋規格 §19.12；commit 拆成 UI／章名＋baseline／文件；push；PR；標籤 `next:eric-ai`；PR 說明列出 Eric 要真機看的畫面。
5. `contentVersion` 不升（只改章名與 UI，§14）。

## 4. 坑

- `flutter-ci.yml` 只在 base 為 main 的 PR 上跑；堆疊在 #67 上就沒有 CI，合併後要 rebase。
- 章名進 R06 用「不含空白的字元數」計，上限 22；目標 14 以內。
- `tools/content/__pycache__` 不要 commit；Stop hook 會催 commit／push，在這條分支照做。
- 說明句改完，書架 hero 卡高度會變，`ebook_shelf_proof_test` 是量內容高度再截圖，不會 overflow，但 PNG 會變。

## 5. 留給 Eric 的決定

- 章名建議表（2.3），尤其 5.6 與 6.6 是他拍過的字串。
- 繼續閱讀卡 2 行 vs 維持 1 行靠縮章名。
- 320pt 壓力測試要拍哪幾章（建議 6.3 最密 callout、2.5 案例長修正框）。
