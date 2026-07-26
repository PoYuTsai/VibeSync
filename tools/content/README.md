# 電子書內容轉換器

`assets/learning/ebooks/*.json` 的四本內容是**產生**出來的，不是手寫的。
來源是夥伴那份單檔 HTML 指引（2026-07-26 版）。

```
parse_partner_guide.py        # HTML → 有結構的節點 JSON（不改任何一個字）
build_ebooks_from_guide.py    # 節點 JSON → 四本電子書 JSON（章節映射在檔內 BOOKS）
```

## 為什麼用轉換器而不是手打

原文約 18,000 字。手抄一次的錯字風險遠高於寫映射規則，而且之後夥伴更新原檔時
可以重跑，不必再校對一遍。轉換規則只做結構映射：

| 原檔 | 我們的 block |
|---|---|
| `<p>` | paragraph |
| `<ul>` / `<ol>` | bulletList |
| `.ws`（弱／強對照）+ `.wswhy` | comparison（wswhy 變 caption） |
| `.case`（對話案例） | dialogue + callout(info 註解) + callout(fix 修正) |
| `.warn` | callout(warning) |
| `.grad` | callout(principle) |
| `table.data` | entryList（3 欄以上）或 bulletList（2 欄、或在條目內） |

## 重跑方式

```bash
# 1. 取得原檔（放在 scratchpad 或任何本機路徑），改 parse_partner_guide.py 的 SRC
python3 tools/content/parse_partner_guide.py     # 產出 bruce_nodes.json
python3 tools/content/build_ebooks_from_guide.py # 覆寫四份 assets JSON
flutter test test/unit/features/learning/        # 內容不變量必須全綠
```

## 章節映射在哪裡改

`build_ebooks_from_guide.py` 的 `BOOKS` 常數：四本 × 五章，每章列出要吃哪幾個
節點索引（`lead`）、哪一段要做成條目庫（`entries`）。節點索引可以用
`parse_partner_guide.py` 的輸出對照。

漏斗區塊（`funnel_block.json`）是我們自己的內容，不在原檔裡，由 `funnel: True`
的章插入。
