# 工作包 3：第 5–7 冊結構降密度 報告

日期：2026-09-03　基底：main `9cdd6d0`（PR #62、#63 合併後；分支原本自工作包 2 的 head 切出，兩個 PR 合併後 rebase 到 main）　分支：`claude/ebook-copy-wp3-density`
規格：`docs/plans/2026-09-03-ebook-copy-readability-final-implementation-plan.md` 第 8 節「工作包 3」與第 9.5–9.7 節帳本裡的結構項；交接文件 `docs/plans/2026-09-03-ebook-copy-wp3-handoff.md`。

## 一句話

不改立場、不改字，只讓手機閱讀有停頓：一個欄位塞兩三段的全部拆開（R04 14 → 0）、超過 120 字的段落拆成兩三段（第 5–7 冊 R06 50 → 5）、內嵌「✕／✓」的段落改成 comparison、藏在句子裡的清單改成 bulletList、第 5 冊第 6 章切成「先辨認互動感受」「再選擇回應方式」兩段、第 6 冊 6.3 的對照表拆成兩張。第 1–4 冊 0 變動。

## 怎麼做的

- 依 block id 逐一改正式 JSON。拆段用「在指定句子開頭切開」，切完的片段串回去必須等於原文（腳本斷言），所以字沒有動；只有變成 label 或清單結構的記號（「✕」「✓」、「你說」、「第一種是」、「第一個是」、「硬框架：」、括號）從內文移走。
- 新段落的 id 一律 `<原id>-p2`、`-p3`；改型別保留原 id；殘留問題留在原 id 上（`--baseline` 新發現 0）。
- 改完跑 `normalize_ebook_copy.py --write`（0 欄位需要改）；不升 `contentVersion`。
- 一次性腳本不進 repo；差異清單可用 `compare_ebook_import.py --official <main 9cdd6d0 的七冊> --candidate assets/learning/ebooks` 重算（第 5–7 冊在 #63 之後沒有其他變動）。

## 規模

| | 工作包 2 之後 | 工作包 3 之後 |
|---|---:|---:|
| 區塊（全套） | 541 | 606（新增 65、改動 55、刪除 0） |
| 第 5 冊區塊 | 129 | 150 |
| 第 6 冊區塊 | 83 | 114 |
| 第 7 冊區塊 | 84 | 97 |
| 條目／前往按鈕／章數 | 112／21／39 | 不變 |
| 超過 120 字的 paragraph（全套） | 52 | 5（見「刻意不動」） |

## 逐章變更

### 第 5 冊《內核 · 吸引怎麼發生》

| 章 | 變更 |
|---|---|
| 5.1 | `c1-p5` 拆 2 |
| 5.2 | `c2-p1` 拆 2；`c2-p2` 拆 3（方向盤／炸雞比喻／套到聊天——比喻獨立成段，工作包 6 要刪就刪整塊） |
| 5.3 | `c3-p1`、`p5`、`p7` 各拆 2 |
| 5.4 | `c4-p5`「見面的時候也有跡象」→ 四項 bulletList＋結語段 `p5-p2` |
| 5.5 | `e2-p1`、`e3-p1`、`p2` 各拆 2 |
| 5.6 | 加 heading `h1`「先辨認互動感受」（六種感覺前）、`h2`「再選擇回應方式」（撩 vs 對前）；`p1`、`p3` 各拆 2；四個畫面本來就是 entryList，不動 |
| 5.7 | 三軸：`axis-1-p1`、`axis-2-p1` 依空行拆 2；`axis-1-p2`、`axis-2-p2` 的「✕ 她：…→ 你（…）」兩行改 comparison（label 用原文括號裡的字：先過濾一遍／直接講、全盤托出／留了門），前後各一段 |

### 第 6 冊《框架 · 這段關係誰在主導》

| 章 | 變更 |
|---|---|
| 6.1 | `c1-p2` 拆 3（定義／殺價比喻／回到交友軟體）；`c1-p3`、`p4` 各拆 2 |
| 6.2 | `c2-p2` 拆成定義段＋「她臨時說「週末陪我」，但你早就跟朋友約好」comparison（硬框架／軟框架是兩種功能不分好壞，用 neutral）＋提醒段；`c2-p3` 拆 2；`c2-p4` 拆 3（問題＋定義／名牌包比喻／反過來說）；`c2-p5` 拆 3 |
| 6.3 | `c3-p3`、`p5`、`p7` 各拆 2；`comp-responses` 拆成「她臨時取消約會」「她已讀三小時沒回」兩張，label 改成回應方式「加碼的人／加自己的人」 |
| 6.4 | `c4-p1`、`p6` 各拆 2；`c4-p5` 內嵌 ✕／✓ → comparison（把家人拖進來／只講這件事）；`el1-e2-p2` 兩行 ✕／✓ → comparison |
| 6.5 | `c5-p1`～`p6` 依空行拆開（3／3／3／3／3／2 段） |
| 6.6 | `c6-p4` 拆成引言＋「兩種陷阱」清單（討好／打壓）；`c6-p7`、`p8` 各拆 2；`c6-p1` 不動（見下） |

### 第 7 冊《進階聊天 · 讀懂反應再出手》

| 章 | 變更 |
|---|---|
| 7.1 | `c1-p4` 三要素 → 引言段＋編號清單 `p4-list`＋「順序是」段；`c1-p6` 拆 2 |
| 7.2 | `c2-p5` 拆 2（炸雞比喻獨立）；四條止損線 `e1`–`e4` 的 ✕／✓ 兩行 → comparison |
| 7.4 | `c4-p2`、`p5` 各拆 2；`dlg1` 第 4 句 86 字的教練旁白移出對話，改成對話後的一段 `dlg1-note`（對話句上限 80 字） |
| 7.5 | `c5-p2` 拆 3；`c5-p4` 拆 2 |
| 7.6 | `c6-p1`、`p4`、`p5` 各拆 2；`c6-p3`、`p6` 不動（見下） |

## 刻意不動

- `ebook-6-c6-p1`（143 字）、`ebook-7-c6-p3`（142 字）、`ebook-7-c6-p6`（155 字）：三段都帶著工作包 4 的禁用詞 key（「她冷的不是你」「改天約妳喝杯咖啡」「拒絕階梯／下次奶茶妳請」），而且句子在段尾，拆開會讓 key 換到新 id、被棘輪當成新發現；三段本來就排在工作包 4 整段重寫（§5.4、§5.7、§9.6、§9.7 P0），到時一起處理。
- 章名 5.6（23 字）、7.4（25 字）是工作包 7。
- 既有 comparison 裡「✕ 對／✓ 撩」這類 label 的記號沒有動；新做的 comparison 有原文括號或短語就拿來當 label，沒有就沿用「✕」「✓」，工作包 6 可以改成回應方式。
- caption、annotation、summary 全部在門檻內，這次沒動。

## 稽核前後

| 規則 | 工作包 2 之後 | 工作包 3 之後 |
|---|---:|---:|
| R04 單段欄位含雙換行 | 14 | 0 |
| R06 欄位過長 | 52 | 7（第 1–4 冊 2、章名 2、上面三段） |
| R09／R10／R12／R13（工作包 4／5） | 40 | 40 |
| **合計** | **106** | **47** |

`--baseline` 新發現 0、已解決 59；baseline 重新產生（106 → 47）；`--parent-baseline` 對 main（716）與工作包 2（106）都無放大。

## Dart 內容契約

- 新增「paragraph、caption、annotation 不再一個欄位塞好幾段」（§12.3 第 2 條）與「5.6 有兩個 heading：先辨認互動感受、再選擇回應方式」。
- 既有契約不受影響：五個查閱型章節、案例 A–N、章層級字數 < 3,000（5.6 加了兩個 heading 後最密的一章約 2,410 字）、畢業標準恰 5 個、無原課本指涉、無「｜」。
- 視覺證明測試（`ebook_reading_layout_proof_test.dart`）拿 5.1 全章與 6.3 全章在 SingleChildScrollView 裡拍，區塊變多不會 overflow。

## 需要 Eric／Bruce 看一眼

1. 5.6 兩個 heading 的文字（規格 §8 給的）。
2. 6.2 的硬／軟 comparison 用 neutral 兩欄（不是弱／強）——原文說「兩種功能，不是好壞兩端」。
3. 5.7 兩張 comparison 的 label（先過濾一遍／直接講、全盤托出／留了門）取自原文括號。
4. 7.4 教練旁白改成對話後一段。

## 驗證命令

```
python3 -m unittest discover -s tools/content/tests                     # 46 passed
python3 tools/content/normalize_ebook_copy.py --check                   # exit 0
python3 tools/content/audit_ebook_copy.py --baseline tools/content/audit_baseline.json   # 新發現 0
python3 tools/content/compare_ebook_import.py --official <工作包 2 的七冊目錄> --candidate assets/learning/ebooks
flutter test test/unit/features/learning/ test/widget/features/learning/ test/visual_proof/
```
