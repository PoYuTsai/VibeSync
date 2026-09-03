# 工作包 3 交接：第 5–7 冊結構降密度（2026-09-03）

給下一個 Claude Code session 的開工包。先讀這份，再視需要讀規格的指定小節；不要整份規格重讀。

## 0. 一句話

工作包 0–2 已各自成 PR；工作包 3 的分支 `claude/ebook-copy-wp3-density` 已推上遠端（#62／#63 合併後已 rebase 到 main），這份文件是它的第一個 commit。工作包 3 的範圍是「第 5–7 冊只降密度、不改立場」：一欄多段拆開、內嵌 ✕／✓ 改 comparison、長清單改 bulletList、第 5 冊第 6 章加兩個 heading、caption／annotation／summary 只留一句。P0 語意改寫（canonical rules）是工作包 4，口吻與比喻是工作包 6，不要順手做。

## 1. 現況

| 項目 | 狀態 |
|---|---|
| 規格 | `docs/plans/2026-09-03-ebook-copy-readability-final-implementation-plan.md`；工作包 3 讀 §8「工作包 3」、§9.5–9.7、§4.3–4.4、§12.3；已完成紀錄在 §19.1–19.7 |
| PR #61 工作包 0 | 已 Squash Merge 進 main（`c323be2`）；ADR #45 生效，正式 JSON 是唯一真源 |
| PR #62 工作包 1 | 已 Squash Merge 進 main（`7666010`），分支已刪 |
| PR #63 工作包 2 | 已 Squash Merge 進 main（`9cdd6d0`），分支已刪；Eric 在合併前補了 4 個 commit（工具：`V = 0` 帶空白也保留），標籤改 `next:bruce`（Bruce 校對 1–4 冊） |
| 工作包 3 分支 | `claude/ebook-copy-wp3-density`，原自 `1a665d9` 切出，#62／#63 合併後 rebase 到 main `9cdd6d0`；PR 直接以 main 為 base，CI 會跑 |
| 分支授權 | Eric 在 PR #61 留言：工作包 1 起每包開新分支、一包一 PR。session 的預設分支 `claude/advanced-interaction-guide-optimization-d0c43k` 不再使用 |
| 環境 | 容器沒有 Flutter：Dart 測試只在 PR CI 跑（且只有 base=main 的 PR）。本機門檻：工具單元測試、`normalize --check`、`audit --baseline`、`compare` |

## 2. 工作包 3 的範圍（只取 §9.5–9.7 裡的結構項）

| 冊 | 做 | 不做（留給工作包 4／6／7） |
|---|---|---|
| 第 5 冊 | c2-p2 拆段；第 3 章長段拆段；c4-p3／p5「四個跡象」改 bulletList；c5-e1-p1／p2 拆段；第 6 章保留 chapter id、加兩個 heading「先辨認互動感受」（六種感覺前）「再選擇回應方式」（撩 vs 對前）——四個畫面已經是 entryList `ebook-5-c6-el2`（4 條）不用動；第 7 章 `axis-1／axis-2` 的 p1／p2 拆段（R04 ×4） | c1-p2「7／38／55」假精準（P0）、供養者／情人改名（P0）、三軸改名（P0）、「撩 vs 對」與「流氓般的紳士」改寫、五種類型白話標題、脆弱範例、傲慢 callout 刪除 |
| 第 6 冊 | c2-p2～p5 內嵌例子改 comparison＋拆段（R04 ×4）；第 3 章 comparison 相同情境拆兩組、label 寫回應方式；c5-p1～p6 拆段（R04 ×6）；第 1 章重複定義只留一次（拆段時順手，但刪比喻是工作包 6） | 「不舒服不代表我做錯」、硬／軟定稿、吵架 canonical、附和 canonical、d1-l6、c5-p3 回覆速度、第 6 章標題與結論 |
| 第 7 冊 | c1-p4 三要素改 bulletList；第 2 章長段內嵌對照改 comparison；第 4～6 章長段拆段；c4-dlg1-l4 86 字對話句（拆成兩則或留待工作包 6，看內容） | 反應等級 canonical、行為＞字面、拒絕階梯整段刪除、種子與第 4 冊同義、「先當朋友」案例、7／3 比例、章名 |

驗收（§8）：paragraph 不再含雙換行；既有 spine 版型不變；warning／safety 仍完整框線；390 pt 與 2.0 文字縮放沒有 overflow（後兩項靠 PR CI 的 widget／visual proof 測試）。

## 3. 現況數字（工作包 2 之後，第 5–7 冊）

- R04 單段欄位含雙換行：14（第 5 冊 4、第 6 冊 10，全部是 paragraph.text）；另有 5 個單換行 paragraph（第 6 冊 1、第 7 冊 4）不在 R04 但也該拆。
- R06 欄位過長：50 = paragraph 超過 120 字 47（14／21／12）＋章名 2（5.6 23 字、7.4 25 字，工作包 7）＋對話句 1（`ebook-7-c4-dlg1-l4` 86 字）。
- 內嵌 ✕／✓：26 個欄位（comparison items 16、dialogue lines 2、paragraph 8）；規格說的「9 組內嵌文字改 comparison」對應那 8 個 paragraph。
- R12 禁用詞 15（全是工作包 4 的 P0）。R09／R10／R13 與第 5–7 冊無關。
- 章層級字數 1,118–2,398（Dart 契約上限 3,000）；5.6 最密（2,398，11 個區塊）。拆段不增加字數，但加 heading 會。

逐章清單（id.欄位（規則 現況））：

| 章 | 待處理欄位 |
|---|---|
| 5.1 | c1-p5（R06 138） |
| 5.2 | c2-p1（128）、c2-p2（168） |
| 5.3 | c3-p1（129）、c3-p5（161）、c3-p7（128） |
| 5.5 | c5-e2-p1（133）、c5-e3-p1（126）、c5-p2（127） |
| 5.6 | c6-p1（136）、c6-p3（130）、章名 23 字 |
| 5.7 | c7-axis-1-p1（R04 2 段、171）、axis-1-p2（R04 3 段、189）、axis-2-p1（R04 2 段）、axis-2-p2（R04 3 段、214） |
| 6.1 | c1-p2（179）、c1-p3（151）、c1-p4（151） |
| 6.2 | c2-p2（R04 4 段、181）、c2-p3（R04 2 段、132）、c2-p4（R04 3 段、220）、c2-p5（R04 3 段、168） |
| 6.3 | c3-p3（132）、c3-p5（138）、c3-p7（136） |
| 6.4 | c4-p1（142）、c4-p6（126） |
| 6.5 | c5-p1（R04 3 段、135）、c5-p2（R04 3 段、182）、c5-p3（R04 3 段、190）、c5-p4（R04 3 段、135）、c5-p5（R04 3 段、178）、c5-p6（R04 2 段） |
| 6.6 | c6-p1（143）、c6-p4（131）、c6-p7（132）、c6-p8（159） |
| 7.1 | c1-p4（144）、c1-p6（121） |
| 7.2 | c2-p5（143） |
| 7.4 | c4-dlg1-l4 對話句 86、c4-p2（140）、c4-p5（128）、章名 25 字 |
| 7.5 | c5-p2（194）、c5-p4（158） |
| 7.6 | c6-p1（140）、c6-p3（142）、c6-p4（169）、c6-p5（176）、c6-p6（155） |

id 前綴省略 `ebook-N-`；長度是不含空白的字元數（`audit_rules.json` lengthLimits）。用 `python3 tools/content/audit_ebook_copy.py --verbose --json out.json` 可重算。

## 4. 做法（照工作包 2 的流程）

1. 在 scratchpad 寫一支依 block id 操作的一次性腳本（不進 repo；正式 JSON 是真源、diff 是紀錄）。拆段的新 id 用 `<原id>-p2`、`-p3`；改型別保留原 id；殘留問題留在原 id 上，不換身分。新區塊必須在門檻內（bullet 100、paragraph 120、callout 160、caption 100、summary 40，不含空白）。不升 `contentVersion`（ADR #45 第 7 點）。
2. 跑完腳本一定再跑 `python3 tools/content/normalize_ebook_copy.py --write <三個檔案>`，再 `--check` 確認 0 diff（腳本組出來的字串常有括號旁半形空白；正規化會把「3. 「」」變成「3.「」」）。
3. `python3 tools/content/audit_ebook_copy.py --baseline tools/content/audit_baseline.json` 必須「新發現 0」；再 `--write-baseline`；再分別用 `--parent-baseline` 對 `git show origin/main:tools/content/audit_baseline.json` 與 `git show 1a665d9:tools/content/audit_baseline.json` 確認只縮小。
4. `python3 -m unittest discover -s tools/content/tests`（46 條，含「正式資產必須維持正規化」）。
5. `python3 tools/content/compare_ebook_import.py --official <工作包 2 的七冊目錄> --candidate assets/learning/ebooks --json out.json`：七冊用 `git show 1a665d9:assets/learning/ebooks/<檔名>` 倒出來；報告的新增／刪除／型別變動清單從這裡來。
6. Dart 契約要守（本機跑不了，先用 Python 鏡射）：章層級字數 < 3,000；`test/visual_proof/ebook_reading_layout_proof_test.dart` 拿 `book_5` 第 1 章「第一個 checklist 之前的區塊」與 `book_6` `chapters[2]`（6.3）整章在高度 3,000 內拍——6.3 別長太多；`ebook_content_invariants_test.dart` 工作包 2 的新契約：內文無原課本指涉（pattern 同 `audit_rules.json` textbookRefs）、無「｜」、標題含「畢業標準」的 callout 一律 goal 且全套恰 5 個（第 5–7 冊不要新增這種 callout）。
7. 新增 Dart 契約（§12.3 第 2 條）：paragraph、caption、annotation 不得含雙換行——工作包 3 之後 R04 應為 0，把它寫進 `ebook_content_invariants_test.dart`；可再加「5.6 有兩個 heading」。
8. 報告 `docs/reviews/2026-09-03-ebook-copy-wp3-density-report.md`（格式照工作包 2 的報告）＋規格 §19.8；三個 commit（內容＋baseline／Dart 契約／文件），繁中訊息；`git push -u origin claude/ebook-copy-wp3-density`；PR base `claude/ebook-copy-wp2-structure`，標籤 `next:eric-ai`，PR 說明要寫「base≠main 所以還沒有 CI」。

## 5. 坑

- audit 的 finding key 是（規則、id、欄位名折疊後）：把長段拆成 `-p2` 之後原 key 自然消失；但如果第一段留在原 id 仍超過 120 字，key 不變、不算新發現（CI 會過但不該這樣留）。
- 條目展開後 summary 仍顯示在標題下（`ebook_entry_list.dart`），內文第一段不要跟 summary 同一句。
- 教練深連結（`learning_link_resolver.dart`、`dating_knowledge_links.dart`）只指章 id；章 id 不能改，區塊 id 可改但閱讀進度以區塊 id 為 key，改 id 等於該區塊重置為未讀。
- Dart 測試 `ebook_routes_test`／`ebook_block_renderer_test` 只引用 `ebook-2-c5-lib-e11` 與 `ebook-1-c1-quiz-1`。
- 跑過 Python 測試會留下 `tools/content/__pycache__`，不要 commit。
- Stop hook 會催 commit／push，在這條分支上照做即可。
- 上下文太長會被壓縮：把中途結論寫進 scratchpad 的 notes 檔或這份文件，不要只留在對話裡。

## 6. 留給 Eric 的決定

- 工作包 3 的 PR 也會先以工作包 2 分支為 base（沒有 CI），或改成等 #62／#63 都合併後再開 PR？預設：照工作包 2 的做法先開，方便 review。
- 5.6 兩個 heading 的文字採規格 §8 給的「先辨認互動感受」「再選擇回應方式」；不同意就在 PR 講。
