# 電子書內容工具

`assets/learning/ebooks/book_1_bottleneck.json` … `book_7_chat.json` 是 App 使用的
**唯一正式文案真源**（ADR #45，2026-09-03）。這個目錄的工具只做三件事：把夥伴來源轉成
候選檔、比對候選檔與正式檔、稽核正式檔。**沒有任何工具會寫正式檔**——正式檔只能由人
編輯，再由 PR 審查。

2026-07-27 之前，第 1–4 冊是由夥伴的單檔 HTML 指引產生、直接覆寫正式 JSON 的；那條路
已經關掉：`build_ebooks_from_guide.py` 的輸出路徑落在 `assets/learning/ebooks`（含子目錄）
會直接失敗，沒有旗標可以繞過。

## 流程

```
候選匯入 → 比對 → 人工合併 → audit → Flutter tests
```

| 步驟 | 工具 | 產出 |
|---|---|---|
| 1 候選匯入 | `parse_partner_guide.py`（HTML → `bruce_nodes.json`，一字不改）→ `build_ebooks_from_guide.py`（節點 → 四份候選 JSON） | `build/ebook_import_candidate/*.json`＋`candidate_summary.json`（含相對正式檔的差異摘要） |
| 2 比對 | `compare_ebook_import.py` | 依 book／chapter／block／entry 穩定 id 列出新增、刪除、文字變動、區塊型別變動、sourceRefs 變動 |
| 3 人工合併 | 編輯 `assets/learning/ebooks/*.json` | 由人決定要併哪些差異；不整份覆寫 |
| 4 audit | `audit_ebook_copy.py` | 標點、符號、空白、長度、重複、術語、原課本指涉、禁用詞、定稿句、結構契約 |
| 5 Flutter tests | `flutter test test/unit/features/learning/ test/widget/features/learning/` | 內容不變量、catalog、widget 與 visual proof |

`bruce_nodes.json` 與 `build/` 都不進 repo。原 HTML 不在 repo 裡；來源追溯只留
`partner_guide_source_manifest.json` 的 digest 與版本標記（在有原檔的機器上跑
`python3 tools/content/parse_partner_guide.py --write-manifest` 補 SHA-256）。

## 命令

```bash
# 候選匯入（原檔位置用 PARTNER_GUIDE_HTML 指定；預設讀 Eric 桌面那份）
python3 tools/content/parse_partner_guide.py            # 產出 tools/content/bruce_nodes.json
python3 tools/content/build_ebooks_from_guide.py        # 寫到 build/ebook_import_candidate/
python3 tools/content/build_ebooks_from_guide.py --out /tmp/cand --nodes path/to/nodes.json

# 比對候選與正式
python3 tools/content/compare_ebook_import.py                       # 報告
python3 tools/content/compare_ebook_import.py --json diff.json      # 完整結果
python3 tools/content/compare_ebook_import.py --fail-on-diff        # 有差異就 exit 1

# 稽核正式內容（唯讀）
python3 tools/content/audit_ebook_copy.py                                        # 摘要
python3 tools/content/audit_ebook_copy.py --verbose                              # 全列
python3 tools/content/audit_ebook_copy.py --check                                # 有任何發現就 exit 1
python3 tools/content/audit_ebook_copy.py --baseline tools/content/audit_baseline.json   # CI 用：只擋新發現
python3 tools/content/audit_ebook_copy.py --write-baseline tools/content/audit_baseline.json
python3 tools/content/audit_ebook_copy.py --json out.json --markdown out.md

# 工具本身的測試（標準函式庫，不裝套件）
python3 -m unittest discover -s tools/content/tests -v
```

## 稽核規則

規則 id 固定，baseline 與 allowlist 都靠它；門檻、禁用詞、定稿句都在
`audit_rules.json`，改設定不改程式。

| 規則 | 檢查 | 說明 |
|---|---|---|
| R01 | CJK 語境的半形 `, : ; ! ? ( )` | 「數字:數字」（10:00、2:1）與「數字,數字」例外 |
| R02 | CJK 語境的半形符號 `... / + = > < [ "` | `V=0` 這種英數之間的不算 |
| R03 | 行首／行尾空白、三個以上連續換行 | 原 HTML `<br>` 縮排的殘留 |
| R04 | paragraph／caption／annotation 內的雙換行 | 一個欄位塞多段 |
| R05 | 「｜」 | 表格攤平的殘留 |
| R06 | 欄位長度 | 章名 22、summary 40、對話句 80、註解 80、caption 100、bullet 100、paragraph 120、callout 160；長度＝不含空白的字元數 |
| R07 | 條目 summary 與內文第一段相同 | 展開後看到同一句兩次 |
| R08 | 簡體字、用字一致 | 信號→訊號、勾子→鉤子、升温→升溫、Line→LINE |
| R09 | 第 1 冊提前使用 V／F／E／I／R 代碼 | 圖例在第 2 冊 2.1 |
| R10 | 第 2 冊 2.1 的五變數 glossary 名稱 | 名稱定義在 `audit_rules.json` |
| R11 | 原課本指涉 | 課本 6.1、見第六節、階段 2.6、類型 A、見案例 X、DHV |
| R12 | 禁用詞與已廢止的教學句 | 例如「行為＞情緒＞字面」「拒絕階梯」 |
| R13 | P0 跨冊定稿句必須存在 | 整套教材至少出現一次 |
| R14 | 結構契約 | id 唯一、crossRef／漏斗目標存在、條目庫 ≥2 條且不巢狀、單選題恰一正解、查閱型章節維持條目庫 |

## baseline 棘輪與 allowlist

- `audit_baseline.json` 是目前正式內容「已知問題」的清單。CI 跑
  `--baseline`：只有清單以外的**新發現**才會失敗。每個工作包修掉一批後，用
  `--write-baseline` 重新產生（它只會變小），**不得手動加項目**。PR CI 另外用
  `--parent-baseline`（main 的 baseline）檢查它真的只變小：既有規則多出項目就失敗，只有新加的規則可以第一次登錄既有發現。
- `audit_allowlist.json` 是具名例外：每一筆都要有 `rule`、`id`、可選的 `field` 與
  `reason`。不允許整本書或整條規則的例外；要放寬門檻請改 `audit_rules.json` 並在 PR 說明。
- `--check` 是嚴格模式（任何發現都失敗），給內容全部清乾淨之後用。

## 章節映射在哪裡改

`build_ebooks_from_guide.py` 的 `BOOKS` 常數：四本 × 五章，每章列出要吃哪幾個
節點索引（`lead`）、哪一段要做成條目庫（`entries`）。節點索引可以用
`parse_partner_guide.py` 的輸出對照。

漏斗區塊（`funnel_block.json`）是我們自己的內容，不在原檔裡，由 `funnel: True`
的章插入。

轉換規則只做結構映射：

| 原檔 | 我們的 block |
|---|---|
| `<p>` | paragraph |
| `<ul>` / `<ol>` | bulletList |
| `.ws`（弱／強對照）+ `.wswhy` | comparison（wswhy 變 caption） |
| `.case`（對話案例） | dialogue + callout(info 註解) + callout(fix 修正) |
| `.warn` | callout(warning) |
| `.grad` | callout(principle) |
| `table.data` | entryList（3 欄以上）或 bulletList（2 欄、或在條目內） |
| 「見案例 K」「課本 6.1」「見第六節」 | 原句不動，後面補一顆 crossRef 前往按鈕 |

交叉指涉（`link_cross_refs`）是四本都建好之後才跑的一道 pass；解不到目標一律中止 build。

## 為什麼不再由轉換器覆寫正式檔

- 這次的內容優化（`docs/plans/2026-09-03-ebook-copy-readability-final-implementation-plan.md`）
  不是十幾個字串，而是標點、遺失標題、區塊型別、跨冊規則與六十多段改寫；重跑一次
  轉換器就會整批消失。
- 原 HTML 與 `bruce_nodes.json` 都不在 repo，完整重建本來就無法由 repo 自己重現。
- 正式 JSON 已有穩定 id，適合直接做產品編輯與 diff。

`ebook_schema.py` 是所有工具共用的「哪些欄位是使用者看得到的字」；新增 block type
時要先在那裡補欄位，否則工具會 fail closed（與 Dart parser 同一種態度）。
