# OCR 幾何閘鎖定（geometry lock）設計

> 狀態：實作中（2026-06-13）。brainstorming 已定稿、Eric 拍板選「幾何閘鎖定」。
> 目標：side 判讀方向準確率 ≥98%（golden，待 Eric 校對 labels/real/ 後採信官方數字）。
> 前置消融證據：commit `759b1cb`，side acc 61.7%→91.3%（只填 unknown＋砍三條翻面規則），但 dark/quoted 群下滑＝全砍不行，需窄救援。

## 根因（再聚焦）

側別在 `normalizeBubbleSide`（index.ts:3034）已用三層優先序折進 `side`：

1. `outerColumn`（明確左/右欄）
2. `horizontalPosition`（數值；≥58 右、≤42 左）
3. `side` 字串 fallback
4. 否則 `unknown`

但 index.ts:3857 建 `NormalizedRecognizedMessage` 時**只留 side，把數值 horizontalPosition／outerColumn 丟掉**。下游 `applyLayoutFirstParser`（八啟發式之一，呼叫點 index.ts:3889）再用鄰居 pattern／dominant side 推翻明確側＝級聯翻面（失敗集 5513245／5513249：明確 right 整 run 被吞成 left）。

## 修法＝把幾何「決定性」帶下去

新增布林 `geometryDecisive`，定義＝側別由**無歧義空間訊號**決定：

- `outerColumn` ∈ {left, right}，或
- 數值 `horizontalPosition` ≥58 或 ≤42（=`normalizeBubbleSide` 的同一門檻）。

**非**決定性（仍可被救援翻面）：side 來自字串 fallback、horizontalPosition 落中段 (42,58)、或 unknown。

不變量：`geometryDecisive === true` ⟹ side ∈ {left, right}（決定性必有明確側）。

### 鎖死規則

`applyLayoutFirstParser` 內 **`geometryDecisive` 訊息永不翻面**。救援（neighbor／dominant／quoted／unknown-fill）只作用在**非決定性**訊息上——即 unknown／中段／字串 fallback 來源。dark/quoted 救援因此自然保留（那些單元側別多來自非決定性訊號）。

## 範圍（這輪）

只動兩處，姊妹啟發式鏈（continuity/grouped/trailing/sideRun telemetry）在失敗單元 adjustedCount≈0、無肇事證據，越權留第二刀：

1. **`layout_parser.ts`**
   - `LayoutFirstMessage` 加 `geometryDecisive?: boolean`。
   - `applyRunSide`：跳過 `geometryDecisive === true` 的訊息（never flip）。
   - while 迴圈：四分支改為「`applyRunSide` 實際翻動 >0 才 `changed=true` 並 break」，否則續查——**防止全決定性 run 造成 0 變更卻 `changed=true` 的死迴圈**（原碼因 branch 條件保證必翻所以無此風險，加鎖後必須補這道閘）。
2. **`index.ts`**
   - 抽共用門檻常數 `RIGHT_HORIZONTAL_THRESHOLD=58`／`LEFT_HORIZONTAL_THRESHOLD=42`，`normalizeBubbleSide` 與新 helper 共用（防門檻漂移）。
   - 新 pure helper `isGeometrySideDecisive(record)`。
   - `NormalizedRecognizedMessage` 加 `geometryDecisive?: boolean`；index.ts:3857 建物件時填 `isGeometrySideDecisive(record)`。

`sanitizeReplySegments`／丟段路徑／扣費時機**零改動**。

## TDD 順序

1. **紅燈**（`layout_parser_test.ts`）：
   - 幾何決定性 right run 在 dominant=left＋鄰居 left 時**不被翻**（5513245 級聯重現）。
   - 非決定性 right run 在同情境**仍被救援翻面**（證鎖是條件性、非全鎖）。
   - unknown 夾在決定性側之間：unknown 被填、決定性錨不動。
2. 綠燈：實作上述兩檔。
3. Deno 全套綠（`deno test` analyze-chat/）＋`deno check`。
4. **bench 型別擴充**：`run_benchmark.ts` 的 `RecognizedMessage` 加 `horizontalPosition?`/`outerColumn?`/`geometryDecisive?`（probe 用），函式回應 messages 增 debug 欄位（telemetry-only，不污染產品 schema）。
5. **probe**（第一輪 local bench）：capture 每則被翻訊息是否 geometryDecisive，證 horizontalPosition 在失敗集（5513245/5513249）可靠。
6. **golden 測試集補洞**（設計級必做）：現集左偏（幾乎全左她說）會獎勵 snap-to-dominant 壞 parser。補合成均衡雙向局＋我引用她＋她引用我；夥伴 quoted 翻面圖（held-out「她引用」案）wire 進 manifest.json＋草稿 label。
7. golden 迭代（dark 版面 run-to-run 變異大，多輪取樣），目標 side ≥98%。
8. Codex 雙審（OCR 高風險區，land 前必跑 golden、changes stay isolated）。

## 紅線

- OCR 高風險＝動 code 必 Codex 雙審＋land 前跑 golden。
- bench 無 Docker＝`bench_auth_proxy.ts`＋deno 直跑；`CLAUDE_API_KEY` 在 `~/.vibesync-bench.env`，每跑 ~US$0.15 不扣 quota，案收尾 Eric 去 Console 撤銷換新。
- `labels/real/` 待 Eric 校對＝官方 98% 數字前提；迭代可用草稿（方向性夠），不得在校對前宣稱官方數字。
