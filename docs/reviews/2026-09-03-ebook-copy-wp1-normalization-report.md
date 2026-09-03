# 工作包 1：標點與空白正規化 報告

日期：2026-09-03　基底：main `c323be2`（PR #61 合併後）　分支：`claude/ebook-copy-wp1-punctuation`
規格：`docs/plans/2026-09-03-ebook-copy-readability-final-implementation-plan.md` 第 8 節「工作包 1」與第 11.2 節「正規化工具」。

## 一句話

七冊 CJK 語境的半形標點與符號改全形、行首行尾空白清掉、四處「2:1」改成文字、第 7 冊的簡體字與用字修正、書架群組卡的斜線格式——**不改一個字的意思**，reviewer 可用工具重跑驗證。

## 工具

`tools/content/normalize_ebook_copy.py`：依 `ebook_schema.py` 明確列出的可見欄位逐一正規化，id／enum／目標 id／sourceRefs 一律不碰，含 URL 的欄位整欄跳過，永遠不會把欄位清空。規則 N01–N10 見 `tools/content/README.md`；每條規則都有 fixture 測試（`tests/test_normalize_ebook_copy.py`，含冪等、URL、時間、代碼、emoji、全形空白、寫入拒絕目錄）。

驗證方式：把 main 的七份 JSON 放到任何目錄，跑 `--write`，輸出應與本 PR 的正式檔只差下表「人工修改」那四個欄位。

## 對 main 七冊單次執行的結果

| 冊 | 改動欄位 | 主要替換 |
|---|---:|---|
| book_1_bottleneck | 87 | `,` 77、`( )` 72、`:` 20、`?` 20、`/` 12、`+` 10、`;` 3、`!` 1、括號旁空白 4 |
| book_2_conversation | 152 | `( )` 178、`,` 164、`:` 74、`+` 15、`?` 10、`/` 6、`=` 3、`…` 2、`;` 1、括號旁空白 19、行首行尾空白 6 |
| book_3_rescue | 96 | `,` 130、`( )` 74、`:` 43、`?` 16、`/` 9、`;` 4、`[ ]` 2、`=` 1、Line→LINE 3、括號旁空白 3 |
| book_4_meeting | 113 | `,` 145、`( )` 58、`:` 37、`?` 22、`;` 13、`/` 11、`+` 7、`>` 2、`…` 2、括號旁空白 2、行首行尾空白 6 |
| book_5_core | 0 | — |
| book_6_frames | 0 | — |
| book_7_chat | 6 | `>` 3、信號→訊號 2、勾子→鉤子 1、升温→升溫 1 |
| **合計** | **454** | **1,294 處** |

替換總表：`,` 516、`(` 191、`)` 191、`:` 174（另 7 個「數字:數字」保留）、`?` 68、`/` 38、`+` 32、`;` 21、括號與全形標點旁空白 28、行首行尾空白 12、`>` 5、`=` 4（另 6 個 `V=0` 保留）、`…` 4、Line→LINE 3、訊號 2、`[ ]` 2、`!` 1、鉤子 1、溫 1。

第二次執行 0 diff。研究報告的舊 dry-run 是 449 個欄位；重新計數為 454，多出的 5 個是第 7 冊的三個用字修正與第 3 冊「Line→LINE」的兩個欄位（舊 prototype 沒有用字規則）。

## 人工修改（四個欄位，依計劃 8.1「2:1 這類比例不保留符號」）

| 欄位 | 改前 | 改後 |
|---|---|---|
| `ebook-4-c3-grad9.text` | 種子數與具體提案數的比例不超過 2:1 | 種子最多是具體提案的兩倍 |
| `ebook-4-c4-lib-e4.summary` | 比例超過 2:1 → 你在逃避 | 種子超過具體提案的兩倍 → 你在逃避 |
| `ebook-4-c4-lib-e4-b2.text` | 比例超過 2:1 → 你在逃避 | 種子超過具體提案的兩倍 → 你在逃避 |
| `ebook-3-c5-tbl3-e8-b1.text` | 種子：提案 ≤ 2:1 | 種子最多是具體提案的兩倍 |

UI：`ebook_shelf_section.dart` 單元群組卡「n/m 本已開始」→「已開始 n／m 本」（計劃 8.1 與 8.7），連同 `ebook_shelf_section_test.dart`、`learning_screen_ebook_hierarchy_test.dart` 七處斷言。

## 稽核前後

| 規則 | 說明 | 工作包 0 基準 | 工作包 1 之後 |
|---|---|---:|---:|
| R01 | 半形標點 | 431 | 0 |
| R02 | 半形符號 | 57 | 0 |
| R03 | 行首行尾空白／連續換行 | 5 | 0 |
| R04 | 單段欄位含雙換行 | 15 | 15 |
| R05 | 表格殘留「｜」 | 58 | 58 |
| R06 | 欄位過長 | 64 | 64 |
| R07 | summary 與內文重複 | 4 | 4 |
| R08 | 簡體字／用字不一致 | 7 | 0 |
| R09 | 第 1 冊未定義代碼 | 8 | 8 |
| R10 | 五變數 glossary 缺漏 | 5 | 5 |
| R11 | 原課本指涉 | 35 | 35 |
| R12 | 禁用詞 | 17 | 17（另 1 筆 allowlist） |
| R13 | P0 定稿句缺漏 | 10 | 10 |
| R14 | 結構契約 | 0 | 0 |
| **合計** | | **716** | **216** |

- `tools/content/audit_baseline.json` 以 `--write-baseline` 重新產生（716 → 216）；`--baseline` 新發現 0；`--parent-baseline`（main 的 baseline）無放大。
- allowlist 一筆：`ebook-4-c3-cmp4-s` 的「週四晚上七點，我訂位」——正規化前是半形逗號、禁用詞比對不到，正規化後才被抓到，不是新內容；工作包 4 依計劃 §5.5 改寫後移除。
- 工具修正：R12／R10／R13 的 finding key 原本含片語字面，正規化會讓同一個問題換身分而被「baseline 只准縮小」當成放大；改成 key 對標點寬度與空白不敏感，新舊格式的 baseline 都對得上（有測試）。

## 契約與結構

- Python 鏡射的內容契約（章數、id 唯一、漏斗、條目庫、否定框架、案例 A–N、六個功能位、五變數、權限、章層級字數、crossRef 目標）：PASS。
- `compare_ebook_import.py` 拿 main 的七冊當「正式」、本 PR 當「候選」比對：沒有任何新增／刪除／型別／位置變動，只有文字欄位變動（區塊 45／61／52／69／0／0／5，條目 9／14／26／5／0／0／0）。
- `contentVersion` 不升（ADR #45 第 7 點）。

## 取捨與已知

- 全形「＋」「／」與括號旁的半形空白一律拿掉，包括第 1 冊漏斗 verdictText 這段我們自己寫的字（「東西 ＋ 你自己」→「東西＋你自己」），與第 5–7 冊既有寫法一致。
- 括號後接英文代碼時空白也拿掉（「側面）E↑（自嘲」）；這些註解在工作包 2／5 會改成中文判讀。
- 「V=0、E=0、R=0」與時間「10:00」保留半形，符合計劃。
- 沒跑 Flutter 測試（容器沒有 Flutter）；由 PR CI 的 `test-and-analyze` 與 `ebook-content-audit` 提供證據。

## 驗證命令

```
python3 -m unittest discover -s tools/content/tests -v          # 46 passed
python3 tools/content/normalize_ebook_copy.py --check           # exit 0（0 diff）
python3 tools/content/audit_ebook_copy.py --baseline tools/content/audit_baseline.json
flutter test test/unit/features/learning/ test/widget/features/learning/
```
