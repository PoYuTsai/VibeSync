# 工作包 7：入口、章名與完整視覺驗收 報告

日期：2026-09-04　基底：#67 head `53bd993`（工作包 6，尚未合併；main 仍是 `a20e14f`）　分支：`claude/ebook-copy-wp7-entry`
規格：§8「工作包 7」、§3.3 已拍板字串、§12.3 第 14 條、§13 視覺與真機驗收、§17 完成定義；研究報告 §5 區塊 UI 文案；交接 `docs/plans/2026-09-04-ebook-copy-wp7-handoff.md`。

## 一句話

書架說明句改成 §8 定稿句、繼續閱讀卡的章名改成最多兩行、付費說明（鎖卡兩個分支＋試讀卡）拆短、第 5–7 冊 8 個超過 14 字的章名縮短（章 id 不動、不升 `contentVersion`）；補書架大標／說明句／繼續閱讀卡的 widget test，新增 §13.2 的 visual proof 矩陣（390／320 pt × 文字縮放 1.0／1.3／2.0：書架入口、25 字章名前後對照、6.3 最密章）。不碰購買、權限與訂閱判斷；大標「高階互動指南」與副標「系統化實戰教材」不動。稽核 12 → 10（R06 章名 2 筆歸零；其餘 10 筆在 #66 歸零）。這是文案優化八個工作包的最後一包。

## 怎麼做的

- Dart、JSON、測試、文件各一個 commit。章名用腳本依 chapter id 只改 `title` 那一行：先斷言原文，改完斷言其餘欄位一字不動；`compare_ebook_import.py --official <53bd993 的七冊> --candidate assets/learning/ebooks` 只列出這 8 個 `title`。
- 舊章名在漏斗 `targetLabel`、「下一章」callout、前往按鈕 label 都沒有引用（grep 0 筆）。7.1 漏斗的「第 3.2 章：回得冷時先止損」是章號＋短語，不是章名，不同步。
- 容器沒有 Flutter：Dart／widget／visual proof 由 PR CI 跑（`flutter-ci.yml` 只在 base 為 main 的 PR 上跑，所以要等 #67 合併、這裡 rebase 到 main 之後）。本機跑了工具單元測試、`normalize --check`、`audit --baseline`／`--write-baseline`／`--parent-baseline`、`compare`。

## UI 文案（Dart）

| 位置 | 之前 | 之後 |
|---|---|---|
| 書架標題卡說明（`ebook_shelf_section.dart`） | 從配對到把她約出來。先診斷你卡在哪一階，只練那一階——這是報酬率最高的事。 | 先看你卡在配對、聊天，還是邀約。找到卡點後，只練現在最需要的那一步。（§8 定稿） |
| 繼續閱讀卡「上次讀到 3.4 …」 | `maxLines: 1` | `maxLines: 2`（§8：不靠極端縮名解決截斷）；書名那行維持一行 |
| 鎖卡一般分支（`ebook_detail_screen.dart` `_LockedNoticeCard`） | 這本的每一章都要訂閱才能讀。免費可以讀完第 1 冊，以及第 2 冊的第一章。訂閱後第 2–4 冊一次全開；升級 Essential 再加開《成為獎賞》三冊。 | 這本要訂閱才能讀。免費能讀完第 1 冊和第 2 冊第一章；訂閱後第 2–4 冊全開，Essential 再多開《成為獎賞》三冊。（研究報告 §5 建議句） |
| 鎖卡 Essential 專屬分支 | 《成為獎賞》三冊是 Essential 方案專屬，訂閱 Essential 一次全開；Starter 可讀第 2–4 冊。 | 《成為獎賞》三冊是 Essential 專屬：訂閱 Essential 三冊全開，Starter 可以讀第 2–4 冊。 |
| 試讀卡（`_PreviewNoticeCard`） | 第一章可以直接讀完，其餘 N 章訂閱後開放。訂閱後第 2–4 冊一次全開，升級 Essential 再加開《成為獎賞》三冊；不需要照順序讀。 | 第一章可以直接讀完，其餘 N 章要訂閱；不用照順序讀。訂閱後第 2–4 冊全開，Essential 再多開《成為獎賞》三冊。 |

- 試讀卡在研究報告 §5 同一列（`:499-501`），交接表沒列；三張卡同一套說法才不會一長一短，所以一起拆短。Eric 不要可以只退回這一處。
- 大標與副標一個字不動（§3.3）；`isEssentialOnly` 與所有權限判斷不動；仍不對 Starter 說「訂閱就全開」。

## 章名（第 5–7 冊 `chapters[].title`）

| 章 | 之前（字數） | 之後（字數） |
|---|---|---|
| 5.1 | 你不是不會聊，是大腦一直在替你找台階（18） | 大腦一直在替你找台階（10） |
| 5.6 | 她到底在要什麼——六種感覺，還有撩跟對的那條線（23） | 她要的六種感覺，還有怎麼給（13） |
| 6.1 | 對話有兩層：上面聊內容，下面分主導（17） | 對話有兩層：內容和主導（11） |
| 6.3 | 對她好沒錯，別把自己整個交出去（15） | 對她好，但別把自己交出去（12） |
| 6.4 | 吵完還能笑著約出來，才算真的過了這關（18） | 吵完還能笑著約出來（9） |
| 6.6 | 她一開始回得冷，先別急著對號入座（16） | 她回得冷，先別對號入座（11） |
| 7.4 | 聊了三個月還是「網友」？因為你的訊息少了這兩樣東西（25） | 訊息裡少了前提和樣本（10） |
| 7.5 | 三個訊號，看穿她對你到底有沒有興趣（17） | 三個訊號，看她有沒有興趣（12） |

- 規格 §8 說 13 個；前幾包已改過 5 個（工作包 4：6.6、7.3；5：2.3；6：6.3、7.1），這包縮短仍超過 14 字的 8 個。第 1–4 冊不動（最長是 2.1「變數標記法 V／F／E／I／R」15 字，含分隔符）。
- 書名、副標、goal 不動；章 id 不動，`contentVersion` 不升（§14：續讀存 chapter id）。

## 測試與 visual proof

| 檔案 | 改了什麼 |
|---|---|
| `test/widget/features/learning/ebook_shelf_section_test.dart` | 斷言大標「高階互動指南」（§12.3 第 14 條，原本只有副標）與 §8 說明句、不再有「報酬率」；新測試用全套最長章名壓繼續閱讀卡：390／320 pt × 1.0 與 390 × 1.3 斷言兩行內完整（用同一份 TextSpan 與字級重排、`didExceedMaxLines` 為 false）、`maxLines` 為 2；320 × 1.3 與兩個 2.0 格子只斷言不 overflow |
| `test/widget/features/learning/ebook_detail_screen_test.dart` | 鎖卡兩分支與試讀卡改成拆短後的字；Essential 分支仍斷言不出現「再多開」（不對 Starter 謊稱全開） |
| `test/widget/features/learning/learning_screen_ebook_hierarchy_test.dart` | 學習頁上大標與說明句各出現一次 |
| `test/visual_proof/ebook_copy_matrix_proof_test.dart`（新增） | §13.2 矩陣，每格先 layout 整段內容並斷言 `takeException()` 為 null（RenderFlex overflow 會從這裡冒出來），再截圖 |

visual proof 輸出（`flutter test test/visual_proof/ebook_copy_matrix_proof_test.dart`，圖在 `build/visual_proof/`；CI 不上傳圖檔，要看圖請在 WSL 跑這條）：

| 圖檔 | 內容 |
|---|---|
| `ebook_wp7_shelf_{390,320}_{100,130,200}.png`（6 張） | 書架入口：標題卡（大標、副標、說明句）＋繼續閱讀卡停在 7.4「訊息裡少了前提和樣本」＋兩張收合的單元卡「已開始 n／m 本」 |
| `ebook_wp7_shelf_before_{390,320}_{100,130,200}.png`（6 張） | 同一張書架，7.4 換回工作包 7 之前的 25 字舊章名（§13.1「25 字章名不再被截成無法理解的半句」的前後對照）。「前」用的是 `53bd993` 正式 JSON 的舊章名配現在的兩行卡片，不是手工假資料 |
| `ebook_wp7_dense_{390,320}_{100,130,200}_p{n}.png`（6 格，每 2400 pt 一頁） | 6.3 整章 spine 排版：第 5–7 冊頂層 callout＋comparison 最多的那型（2＋2，另有條目庫與前往按鈕），與既有 `ebook_reading_layout_proof_test.dart` 的密度章同一章 |

- 為什麼 widget test 不在每一格都斷言「兩行內完整」：測試字型每個字形（含數字與空白）都是 1em，比真字型寬得多，320 pt × 1.3 與 2.0 在測試字型下會多一行；真字型（Noto Sans CJK TC）的版面由 proof 出圖給 Eric 看。
- 320 pt × 2.0 是極端組合：最長章名那一行在真字型下也可能以省略號收尾（兩行放不下 19 個全形字），但不 overflow、書名與章號仍完整；§8「不靠極端縮名解決截斷」接受這個取捨。

## 稽核與契約

- `audit --baseline`：新發現 0、已解決 2（`ebook-5-chapter-6.title`、`ebook-7-chapter-4.title`）；`--write-baseline` 12 → 10；`--parent-baseline`（main 的 12 筆）通過；`normalize --check` 0 diff；工具測試 46 條通過；`compare` 對 `53bd993` 只有 8 個 `title` 變動。
- 內容規模不變：書 7｜章 39｜區塊 610｜條目 112｜前往按鈕 21；可見字串 ≥80 字元 127、≥100 49、≥120 2。
- 棘輪注意：#66 合併後 main 的 baseline 會變成 2 筆（5.6、7.4 章名），這包 rebase 到 main 後要重跑 `--write-baseline`，預期 0 筆；不重跑會被「baseline 只准縮小」擋下。
- 2026-09-04 同步：#67 head 更新為 `28b0077`（Eric 審查補修「妳」＋main 的 #66）後併進本分支（`d218946`）。`audit_baseline.json` 是唯一衝突：先取 #67 那版（2 筆），再用 `--write-baseline` 重新生成，得 0 筆，沒有手動改項目；`--parent-baseline`（#67 的 2 筆）通過；`compare` 對 `28b0077` 仍只有 8 個 `title`；`normalize --check` 0 diff；工具測試 46 條通過。#67 合併後只需把 base 改成 main、再併一次 main（不 rebase），重跑 `audit --baseline` 與 `compare`，預期 baseline 仍 0 筆；之後 PR CI 才會跑 Flutter。
- 沒有新增 Dart 內容契約：章名長度已由 R06（22 字）守；書架大標／副標由 widget test 守（§12.3 第 14 條補上大標）。

## §17 完成定義逐項

| 項目 | 狀態 | 依據 |
|---|---|---|
| 7 冊 39 章、558 block、130 entry、17 crossRef 全部仍可解析 | 達成（數字已變） | 現在是 610 區塊、112 條目、21 前往按鈕：工作包 2／3 的結構修復（表格改清單／對照／自評、長段拆段、條目庫重整、5.6 兩個 heading）與工作包 6 刪 3 加 1，是設計變更不是遺失。解析由 Dart catalog 測試與 R14 結構契約守 |
| builder 預設不能覆寫正式 assets | 達成 | 工作包 0：輸出路徑落在正式目錄即失敗，工具測試涵蓋 |
| 正式內容只有一個真源 | 達成 | ADR #45；`tools/content/README.md` |
| 前四冊 1,169 個核心半形標點清零；其餘例外有規則 | 達成 | R01 0（例外「數字:數字」「數字,數字」寫在規則） |
| 70 個「｜」表格殘留清零 | 達成 | R05 0 |
| paragraph／caption／annotation 內雙換行清零 | 達成 | R04 0 |
| 4 處 summary／body 完全重複清零 | 達成 | R07 0 |
| 65 個 ≥120 字元可見字串清零或逐 ID 核准 | 部分達成 | 剩 2 筆，都是條目內段落：第 2 冊 2.5 案例（`ebook-2-c5` 條目庫第 3 條，144 字）、第 3 冊 3.2 第 1 條內文（122 字）。R06 的 paragraph 門檻只套頂層 paragraph 區塊，條目內段落不在門檻裡，所以稽核不列。要再拆或逐 ID 核准，留給 Eric |
| 168 個 ≥80 字元可見字串全部人工檢查 | 依前包報告達成 | 現在 ≥80 為 127 筆；工作包 3 拆段、5／6 逐段改寫時讀過。這包沒有再逐條複查 |
| 第 1 冊不再提前丟未定義代碼 | 在 #66 達成，待合併 | R09 8 筆由 #66 歸零；main 與本分支 baseline 仍列這 8 筆 |
| 五變數 glossary 名稱與定義一致 | 達成 | R10 0；Dart 契約直接讀 `audit_rules.json` |
| 第 3 冊診斷樹、第 4 冊 12 週計畫與自評結構可掃讀 | 達成 | 工作包 2；Dart 契約（3.1 五層、4.5 四個週次） |
| P0 的 11 條 canonical rules 全部有正向與負向測試 | 達成（一條例外） | R13 定稿句存在（正向）＋R12 禁用詞（負向），Dart 同步；§12.3 第 12 條「回覆速度不得要求固定等待時間」沒做成字串規則（3.2 引用流行說法會誤殺），由 5.8 定稿句與禁用詞守（§19.9） |
| 第 4、7 冊使用同一套種子、提案、確認與拒絕流程 | 達成 | 工作包 4；Dart「第 4、7 冊用同一句定義種子」 |
| 「行為 ＞ 情緒 ＞ 字面」「拒絕階梯」「沒有否認就算訊號」等舊規則不存在 | 達成 | R12 0；Dart 禁用詞測試 |
| 390 pt、320 pt 與文字縮放 1.0／1.3／2.0 視覺 proof 通過 | 本包實作，待 CI 與 Eric 看圖 | `ebook_copy_matrix_proof_test.dart`；base 改 main 後 PR CI 才會跑；圖要在 WSL 跑出來看 |
| 相關 Flutter tests 與 analyze 全綠 | 待 CI | 容器沒有 Flutter，這包沒有本機跑過 Flutter |
| 5 位未參與編寫者試讀；2 人以上卡在同一段就重改 | 未達成（人做） | 待辦，不在任何工作包裡 |
| Eric 完成實機閱讀驗收 | 未達成（人做） | 交棒 `next:eric-ai`；看 §13.1 那張表 |

## 請 Eric 拍板

1. 8 個章名的寫法（上表；都保留原意、≤14 字）。
2. 付費說明三處的最終字：鎖卡一般分支、Essential 分支、試讀卡（試讀卡交接沒列，是這包加的）。
3. 繼續閱讀卡改兩行後書架高度會多一行；不接受的話，章名已縮到 14 字內，改回一行也放得下（320 pt × 2.0 除外）。
4. §17 剩兩筆 ≥120 字的條目內段落要不要再拆。
5. 真機看 §13.1 那張表（書架入口、繼續閱讀卡、6.5 spine 呼吸、7.5／7.6 界線優先）。

## 沒改什麼

- 大標、副標、單元 layout；購買、權限、訂閱判斷；章 id、`contentVersion`；第 1–4 冊內容；閱讀器、閘門與書卡的其他文案。
- `docs/snapshot.md`：沒有電子書文案優化的階段描述，不另加。
- `docs/reviews/2026-09-03-ebook-copy-audit-baseline.md` 的基準數字是 main `ff17e04f` 的，不改寫。

## 驗證命令

```
python3 -m unittest discover -s tools/content/tests
python3 tools/content/normalize_ebook_copy.py --check
python3 tools/content/audit_ebook_copy.py assets/learning/ebooks --baseline tools/content/audit_baseline.json
python3 tools/content/audit_ebook_copy.py assets/learning/ebooks --baseline tools/content/audit_baseline.json --parent-baseline <main 的 audit_baseline.json>
python3 tools/content/compare_ebook_import.py --official <53bd993 的七冊目錄> --candidate assets/learning/ebooks
flutter test test/unit/features/learning/ test/widget/features/learning/ test/visual_proof/ebook_copy_matrix_proof_test.dart
flutter analyze lib test
```
