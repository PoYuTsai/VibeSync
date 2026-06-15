# AI Arbitration Queue

> Shared live queue for Eric, Bruce, Claude, and Codex.
> Keep newest OPEN item on top. This is not a changelog.

## Status Values

- `OPEN`
- `IN_REVIEW`
- `WAITING_ON_ERIC`
- `APPROVED`
- `CLOSED`

## Rules

- One queue item = one decision, handoff, or blocker.
- Update the existing item instead of appending every tiny round.
- Claims about "safe", "better", or "fixed" need evidence: file path, commit, test/log, or runtime observation.
- Product taste and business priority are Eric-final.
- If the result becomes a durable rule, move it into `docs/shared-agent-rules.md`, `docs/bug-log.md`, or `docs/decisions.md`.

---

## Live Queue

## [2026-06-15] OCR side：nested-screenshot guard + single-side fallback gate（Eric 拍板方向，待 TDD）
Status: OPEN — **Track 2 step-2＝Path A client-only SHIPPED `5a54ae1`（push origin/main，無 Edge deploy，待新 TF build＋Eric/Bruce 目檢）**；server only_right default 已實作+TDD 後**依 Eric 撤回**（見下）；Track 1 nested-screenshot guard 仍 OPEN（另案）。
**🚢 Track 2 step-2 DONE（2026-06-15）——產品前提重設＋Path A 出貨**：
- **Eric 產品前提重設**：截圖匯入＝建立/補充互動紀錄、重點是「她說」；「我說優化」是分析頁草稿功能、**不經截圖 OCR**，不該拿來限制截圖 default。∴ 不再做「偵測假 mixed→自動翻側」（量測 B 證 per-bubble/幾何零獨立訊號、自動翻側會誤傷正常雙側），改把安全壓在 **截圖匯入 UX**。
- **Path A client-only SHIPPED `5a54ae1`**（`screenshot_recognition_dialog.dart`，純 client、零 server/分析/資料變更、無 Edge deploy）：①假 mixed（同時有我說/她說）不再印「方向看起來很穩」安撫框（會誘導跳過檢查）——只收這顆框、compact 其餘行為不動＝正常雙側零額外摩擦；②預覽層顯眼一鍵「全部都是對方說的」（有任何我說才出現）一次整段改回對方、可逆、需主動點、不自動改資料。TDD 紅→綠 dialog widget **16/16**、flutter analyze 乾淨。**需新 TF build 才到 dogfood**。
- **server only_right default＝撤回（Eric 拍板，不混進本輪）**：曾實作「only_right 截圖匯入→全她說/left + importPolicy=confirm + 文案『已先按對方說處理，可手動改成我說』」（抽 `single_side_recognition_default.ts` 純函式、Deno 6/6、最終覆蓋套在 finalMessages 後避免 geometryDecisive 翻回，deno check 乾淨、零新失敗）。**但實查 golden：`only_right` 單元＝0**（pattern 只有 mixed×10/only_left×1，坐實量測 A＝暗色失敗全長成 mixed），∴ server only_right 修法在現有 golden 與真實暗色失敗上**＝no-op**、只保護「真 only_right 截圖」這個目前無樣本族群。Eric 判：OCR server 高風險、不把理論安全網混進本輪→**git checkout 全撤、刪 helper+test**。**待真 only_right 樣本/新 golden 後另開一輪 TDD＋Codex**。
- **殘留暴露面（如實）**：暗色 fake-mixed 仍**未被自動修**（Eric 知情取捨：mixed 不碰、靠 client 一鍵手動兜底）；圖中圖另走 Track 1 nested guard。
**（前態保留）** 設計定案、**先量後寫**。Eric 方向＝gated fallback 非全域 default；不要再 prompt-whacking，走 parser/post-process＋必要時簡單幾何 detector。
**現況數字**（harness `tools/ocr-golden/results/2026-06-14-15-57-32-local.json`，全暗色、N 小、labels 未正式校對，僅方向性）：暗色雙側 side=100%、暗色單側 quoted_card 61.5%／sticker_media 31.6%／long_screenshot 0%。淺色單側**目前無乾淨量測**（舊「淺色單側 3/8」已被 Eric 推翻＝圖中圖）。`finalUnknownRate=0`＝暗色單側是模型**自信吐錯右**、非棄權（∴「unknown→左」字面改法無效）。
**掛點**：`index.ts:2850 applySingleVisibleSpeakerPattern` 已在 `only_left/only_right` 強制收側，但**無條件信任模型挑的側**→ 暗色「我方先驗」被放大往右釘死。現成材料：`isGeometrySideDecisive`(3133)、`RIGHT|LEFT_HORIZONTAL_THRESHOLD`(3077-78)、`sideToIsFromMe`(3147)、`VisibleSpeakerPattern`(666)。
**Track 1 — nested-screenshot guard**：外層 LINE 泡含內嵌聊天截圖→只抽外層泡、內嵌一律 `[screenshot]`/`[photo]` placeholder，不遞迴轉錄成對話。⚠️**做不到純 parser**（pipeline 無像素 bbox，內外層文字事後不可分）＝機制須一條原則性 prompt 規則，parser/golden 當洩漏護欄。第一步＝拿原始外層檔建 golden leakage 案量基線。
**Track 2 — single-side fallback gate**：偵測「真正單側同欄 且 無可靠右/我方 anchor」→ force left＝她說（產品先驗：單側截圖通常對方連發，比讓模型腦補一來一往安全）。**不套**：mixed 對話／right-only 我說優化／image-in-image。detector 沒把握→ `importPolicy: confirm`＋強提醒、不硬判。⚠️第一步＝先量失敗暗色單側單元模型實吐什麼（`only_left`+逐泡翻 isFromMe vs `only_right`+假右幾何），才能定義「可靠右 anchor」，否則 gate 看不到目標。
**驗收閘**：golden 須證暗色單側↑ 且淺色 standard/交友 app balanced 桶**零回退**；高風險＝Codex 雙審 APPROVED 才宣稱 dogfood safe；OCR 隔離、bake 期不 push。
**前置待辦**：撤換 `.env.golden` local key＋bench `CLAUDE_API_KEY`（見 memory ops 案）。
**🔬 Track 2 step-1 量測 DONE（2026-06-15，run `2026-06-15-03-04-03-local.json`，harness 加幾何欄位持久化後重跑；暗色、N 小、labels DRAFT 僅方向性）——兩個結果直接修正設計**：
- **(A) 失敗型態＝假 mixed，不是 `only_right`**：暗色單側（全 gt=left＝對方連發）被誤讀成 `screenSpeakerPattern=mixed`——部分泡幻覺成 green/right/isFromMe=true、其餘正確 dark_gray/left。模型**從不**在這些失敗吐 `only_right`。⟹ **trigger 不能 key 在 `only_right`**（會完全抓不到真失敗）；偵測對象是「真單欄被誤拆成 mixed」。
- **(B) 可靠右 anchor 在現有 vision 輸出＝證偽**：幻覺右泡的 `horizontalPosition`≈72-75／`outerColumn`=right／`isFromMe`=true／`bubbleFillColor`=green，與**真**右泡（兩側對話我方）**逐欄相同**；fill/hPos/outerCol/isFromMe **全與 rawSide 共動＝零獨立訊號**；`senderNameX` 幾乎不吐且其缺席無法分辨幻覺右 vs 真右。⟹ Eric 例外清單「有可靠綠泡/右幾何 anchor 就不翻」在暗色**危險**——那個 anchor 正是 bug 偽造出來的。唯一還算可信的對方訊號＝`color=dark_gray`+`hPos`≈25-30，但模型不穩定（會把對方泡漆綠）。
- **數字**：S__5480452 0/5、S__5513242_0 1/3、S__5513243_0 2/6、S__42237983 1/5（皆假 mixed）；控制組 S__5513241_0 4/4＝唯一被讀成 `only_left` 的單側；雙側暗色（dark_bruce_1 11/11、mid-dark 7/7…）全對＝兩側並存時 color 是可靠判別。
- **設計轉向**：Track 2 不能靠 per-bubble anchor。要嘛走更高層偵測（單欄性／對話連貫性／「一整段被標 right 卻是對方連發口吻」），要嘛把安全全壓在 `confirm`+一鍵 revert UX 上（限制 1/4 兜底）。下個 session 設計 detector 時須以「假 mixed」為標的，不是 only_right。

## [2026-06-13] OCR ③ 鬼訊息 strip-gap 修復（CONFIRMED REAL dogfood 污染 bug）
Status: CLOSED — **②blockType 路線 SHIPPED 上 prod（2026-06-13，bake-off arm-2 勝出）**：S__5513242 鬼洩漏已修＝`headline leak=0／qpTagged 0→2`。出貨＝兩 commit 連發已 push origin/main＋auto-deploy 成功（`Deploy Edge Function` run `27473626905`＝success，52s，C live on prod）：①`42236e5`＝blockType fold＋legacy residual 安全網（B-prime，模型忠實全吐＋標 `blockType`、parser 確定性向後折，幾何閘零改動）；②`3c79e2a`＝C prompt few-shot 教模型認**暗色 under-name 引用行＝quoted_preview**（刻意用合成文字非 5513242 原文、保 held-out 防 overfit）。驗證（前 session 記錄）：balanced 26 單元零偽陽、Codex APPROVE。**Eric 停損鐵律（未來退化時生效）**：若 5513242 再回 `qpTagged=0` 就停 prompt-whacking、改走 deterministic/legacy heuristic 路線。**未結 side-flip 獨立 track**（dark 圖 side acc 低）不在本案 scope。下為方案A／bake-off 前態全保留。<br>**方案A（strip-gap 局部化）已被 ②blockType 取代（2026-06-13，Eric 拍板，bake-off arm-2）**：新設計＝`docs/plans/2026-06-13-ocr-blocktype-schema-design.md`（commit `d18c4ca`）。bake-off scope=(A) 先只做 blockType 一根（baseline vs blockType 兩臂），暗色預處理延後（早期訊號 exactText 95%+ → 瓶頸在契約非可讀性）。**核心翻轉**：把「合併引用卡」從模型手上拿掉——模型只忠實全吐＋標 `blockType:message|quoted_preview`，parser 確定性向後折（無主/異側一律丟、舊 `stripQuotedReplyPreviewMessages` 降 fallback、幾何閘零改動）。**下一步＝開新 session 進 TDD＋Codex 雙審＋同 session 多輪跑分；bake-off 期間絕不 push**。舊 key 不 rotate、用原本的跑（`.env.golden` 就緒）。下為方案A前態（保留）。設計＋invariants＋failure matrix＝`docs/plans/2026-06-13-ocr-ghost-strip-gap-design.md`（commit `c872ba4`，Eric 已拍板方案A／下刀位置／N=5／failure matrix）。**問題**：S__5513242 prod raw 親驗——OCR 把兩張單行純漢字引用卡（`這小孩也太刺激`／`北鼻我睏睏想躺一下`）吐成獨立 live 訊息、真 owner `quotedReplyPreview` 欄空、`stripQuotedReplyPreviewMessages`（`supabase/functions/analyze-chat/index.ts:3267`）完全沒攔（telemetry `quotedPreviewRemovedCount=0`）⟹ analyze-chat 收 5 則含 2 鬼＝舊引用脈絡被當她剛丟的新球。**根因**：單行純漢字預覽列兩條 strip 路徑都漏——explicit path 要 ≥2 行卡片結構（單行鬼只 1 行 false）；body-only path 因短漢字句被 `isLikelyQuotedReplyPreviewNameLine` 誤當聯絡人名提早 return false。**修法（A 局部化）**：絕不全域收緊 `isLikelyQuotedReplyPreviewNameLine`（會傷 explicit path 長暱稱辨識）；只在 body-only 候選裡把「≥5 連續漢字 run（無空格無拉丁）」視為句子非名→放行成鬼候選（`這小孩也太刺激`(7)/`北鼻…`(8) 過、`早安`(2)/`謝謝你`(3) 受保護）。**Invariants**：①首訊息永不 strip（`!!previous` 不放寬）②explicit path 零改動 ③strip 只搬不丟（掛 next `quotedReplyPreview`）④side 連續 guard 不放寬。**剩餘暴露面（如實揭露）**：must-NOT ④ 真訊剛好 5+ 漢字＋前有側翻＋next 短續/媒體會誤 strip，N=5 與 guard 病態巧合無法 100% 排除，靠負向測試＋Codex 雙審盯。**下一步（TDD 紅→綠）**：export helper→鏡射 S__5513242 must-strip ＋ must-NOT ①〜④ 負測→最小修 body-only 候選→`deno test`/`deno check` 綠→修後 dark/quoted 多輪跑分（回報 `quotedPreviewLeakTotal`→0、side/recall/exactText/quotePreviewAccuracy before/after）→**Codex 雙審 APPROVED＋Eric 確認後才 push**（幾何閘 9f74885 已上 prod，本案 push 只帶鬼訊息修法）。

## [2026-06-13] OCR 左右判讀 ~60% 根因鎖定：layoutFirst parser 級聯翻面——待量測消融
Status: CLOSED — **幾何閘 `9f74885` 結案＝accepted-with-evidence＋已 push 上 prod（2026-06-13，Eric 拍板）**：Codex BLOCK（「永不翻」非 end-to-end、姊妹啟發式 parser 前後仍能翻明確側）由 Eric 以**證據**裁決為**刻意安全閥非缺陷**——hPos 幾何決定性側別在 dark 78.3%／quoted 68.8% 不可靠，full-gating（全鎖 ~6 翻面點）會釘死 vision 誤讀；∴維持 parser-only scope。證據：整體 side **61.8%→90.6%**、平衡集 baseline 6/10·8/11 → fixed **10/10·11/11 全對**、dark/quoted「下滑」證為**測試集左偏假象**。**不再對未改碼重跑 Codex（＝label-shopping，違反 shared-rules）**。push 含 `9f74885`（prod 幾何閘）＋跑分工具＋docs，auto-deploy 已觸發。**OCR 拆四軌**：①左右判讀 ≥95%（golden 96.9／平衡 99.3，對草稿標、方向性）＝本案 SHIPPED；②鬼訊息 strip-gap bug＝另開新案（見上方 OPEN item）；③dark vision 誤讀＝獨立 track（parser-only 不動）；④標註校對＝Bruce21→承瑋22，校完才有真數字。下為前態全保留。<br>**③④ 跑分驗證（2026-06-13 新 session）：鬼訊息 CONFIRMED REAL＋① 計分工具實裝（commit `a1bf600`，本機 only 未 push）**：①計分層四修法 land（媒體歸一/emoji 容差/引用預覽欄＋洩漏分桶/活動卡雜訊，TDD 17 測綠、deno check 乾淨，tools-only）⟹ dark exactText 70%→~100%，證**媒體/emoji 確是量測假象、已除**。**③鬼訊息實錘（推翻下方「量測假象為主」框架）**＝S__5513242 prod raw 親驗：OCR 把兩張引用卡（`這小孩也太刺激`／`北鼻我睏睏想躺一下`）吐成**獨立 live 訊息**、真訊息 `quotedReplyPreview` 欄空、`stripQuotedReplyPreviewMessages` 完全沒攔（telemetry `quotedPreviewRemovedCount=0`）⟹ analyze-chat 收 5 則含 2 鬼（舊引用脈絡被當她剛丟的新球）＝**真 dogfood 污染 bug**。根因＝單行純漢字預覽列兩條 strip 路徑都漏（explicit 要 2 行名稱+內文卡片結構；body-only 又因短漢字句符合 `isLikelyQuotedReplyPreviewNameLine` 被當聯絡人名擋掉），`index.ts:3267`。**∴ dark 三層並存**：媒體/emoji 假象（已除）＋真鬼訊息 bug（待修，OCR prod code 高風險）＋side 級聯變異（9f74885 治、prod 未上；實測 5513243 兩輪 100%↔0%）。**下一步（依 Eric 拍板）**：開「③ strip-gap 修復」新案（TDD＋Codex 雙審，絕不本輪 push）→ 修後全集多輪跑分當 before/after（labels 仍 DRAFT、單輪 variance 大，只方向性）。下為前態保留。<br>**深色背景調查＝量測假象為主（2026-06-13，Eric 拍板「深色＝夥伴 LINE 常態，先解決」）**：讀實際 prod 17 單元跑分 diff＋親眼看 `S__5513242` 圖驗證——(1) 真實深色單元側別**全對**（4/4·2/2·3/3·7/7；聚合 dark 87% 是被**1 個合成 midline 單元** 4/7 拉低，非深色問題）；(2) 主氣泡=亮白 on 近黑=**高對比、OCR 讀對**，深色≠低對比；(3) 跑分 dark recall 66%/exactText 70% 約 **8 成是量測假象**＝媒體 token 雙重扣分（label `[sticker]` vs OCR「[sticker: dog…]」=1missed+1halluc）＋引用預覽存 `quotedReplyPreview` 欄卻被 OCR 當訊息吐=halluc＋活動卡讀對卻格式判錯＋emoji 變體（😯/😲、🫶🏻/🙌）；(4) **唯一真實深色弱點**＝引用預覽 dim 灰小字偶讀錯（實例 `睏睏`→`眯眯`），範圍窄、連人眼吃力。**三推論**：①幾何左右閘（9f74885）治側別、與深色痛點是兩條軸**沒解到**；②「校對 label→重跑」單靠校對**救不了深色數字**（問題是表示法契約對不上＋計分把豐富描述當幻覺，不是 label 對錯）；③**最可能真 dogfood 痛點＝OCR 把引用預覽/媒體描述當訊息灌進 analyze-chat（鬼訊息＋雜訊污染分析）**。**下一步（新 session 開工，紅區未動碼）＝③→①**：③查引用預覽/媒體有沒有漏進 analyze-chat 輸入（parser `quotedPreviewRemovedCount/AttachedCount` 在深色引用卡對不對）→①修跑分計分層（媒體 token 歸一/引用對 `quotedReplyPreview` 欄/emoji 容差/活動卡當文字，`tools/ocr-golden` 零 prod 風險）→才信任深色數字。**證據邊界**：只看舊 17 單元集 5 個深色單元（4 diff＋1 看圖），60 單元 41 新標未逐張看、labels 仍 DRAFT；機制結構性會重演。下為左右閘前態保留。<br>**跑分量完＝scope 定 parser-only（2026-06-13）**：baseline(prod) vs fixed(9f74885 parser-only) golden 跑完——整體 side **61.8%→90.6%**（standard 56→97、typo 60→95、overlap 51→97、midline 73→100、adversarial 57→100；compare_runs layoutAdj baseline 翻 3~14 次／fixed 全 0）。dark 88.5→54.5、quoted 100→33「下滑」＝**測試集左偏假象**（全左群 baseline snap-to-dominant 假性修對；5513243 純 dark vision run-to-run 變異）。**throwaway probe（已還原 index.ts）直答「horizontalPosition 難圖準不準」＝幾何決定性側別準確率 midline 100%／dark 78.3%／quoted 68.8%⟹真實 dark/quoted 不可靠⟹full-gating(全鎖 ~6 翻面點)會釘死 vision 誤讀＝不安全**。**∴ 維持 parser-only（=Codex BLOCK 回應：姊妹啟發式能翻 dark 是安全閥非缺陷）**。**平衡集鐵證**：新標 Bruce 淺色均衡兩單元 baseline 6/10·8/11 → fixed **10/10·11/11 全對**，證 dark 下滑是測試集偏差、平衡資料修法純贏。**Eric 二次拍板（依建議）**：(1) 標註先 Bruce 21 驗流程再 承瑋 22；(2) dark vision 誤讀獨立 track，parser-only 不動，平衡集數字做實再決定 dark 碰排除；(3) 目標 ≥95% CI；(4) 維度＝次序/誰引用誰/圖中圖/貼圖/emoji 作者。**已落地**：run_benchmark.ts 加「誰引用誰」指標（quotedReplyPreviewIsFromMe，deno check 綠/8 測過）＋manifest 接 174/175（labels DRAFT gitignored 待校對）。**⚠️絕不 push**：branch ahead 2 含 9f74885，push 會 auto-deploy 未審 OCR 進 prod。**下一步**：drafting 剩 Bruce 19+承瑋 22 labels（vision 草稿→Eric 校對）→平衡集逼 ≥95%→Codex 再審清 BLOCK→才 dogfood-safe。下為前態保留。
前態：commit `9f74885`（本機 only，**未 push／未部署**）＝layout_parser 加 `geometryDecisive` 鎖（明確空間側 outerColumn／horizontalPosition 過 ≥58/≤42 閘＝永不翻；字串 fallback／中段／unknown 才開放救援），TDD 紅→綠（5513245 級聯重現）、Deno 433/0、deno check 乾淨；設計 `docs/plans/2026-06-13-ocr-geometry-lock-design.md`。**Codex 雙審＝BLOCK（已在碼確認屬實）**：parser-local 鎖正確但「永不翻」非 end-to-end——姊妹啟發式在 parser 前（only_left/right／media／grouped／sideRun）與後（`applyTrailingSpeakerHeuristics` :3565 翻、:3899 在 parser 後跑）仍能翻明確側。**Eric 拍板「跑分量過再決定 scope」**：先量 horizontalPosition 在 dark/quoted 可不可靠＝決定要不要把 ~6 翻面點全加閘（可靠→全鎖清 BLOCK；不可靠→全鎖 regress dark/quoted）。**JWT 卡關已解**：`~/.vibesync-bench.env` 自足（anon key＋測試帳號帳密），下一 session 可自跑 baseline-vs-fixed golden（聚焦 dark/quoted/cascade 逐單元）。**未宣稱 dogfood-safe**（未跑 golden、Codex BLOCK 未清）。下為原診斷（前態保留）。Claude 評估：標準版面可行（baseline 中 parser 未碰單元 17/17 全對），交友軟體版面/中線模糊/圖中圖是難尾巴；路徑＝parser 修復（預估先回 ~85-90%）→ golden set 量測迭代逼近，非一步到位。**憑證已解鎖（2026-06-13）**：CLAUDE_API_KEY 已存本機 `~/.vibesync-bench.env`（600，API 驗證 200）——消融跑分可直接開工：`supabase functions serve analyze-chat --no-verify-jwt --env-file ~/.vibesync-bench.env` ＋ `tools/ocr-golden/run_benchmark.ts --endpoint http://localhost:54321/...`，先跑未改碼 local baseline 對齊 prod，再跑 layoutFirst 消融版對照。key 在對話史出現過，bench 案收尾後建議 Console 撤銷換新。**量測維度清單（Eric 點名）**：她說/我說、圖中圖、引用回覆準確度（`quotedReplyPreviewIsFromMe` 可單獨算）、emoji、圖中大貼圖、表情貼圖。根因證據如下。
證據（零 API 成本，全可重跑）：①baseline results（`tools/ocr-golden/results/2026-06-12-02-21-38-prod.json`）分佈分析＝**layoutFirstAdjustedCount=0 的單元 17/17 全對；>0 的單元 63 錯、準確率 ~57%**；②錯誤方向 87%（55/63）是 right→left（我方被吞成她方；Eric 觀察到的「全變我方」是同機制鏡像，方向由 dominant side 決定）；③機制確定性重現＝`layout_parser.ts` 的夾心翻面規則（:328-338）把模型明確標 `right/isFromMe:true` 的我方短訊息整 run 翻面——`isLikelyShortContinuationContent` 把 ≤16 字單行全當 flexible（中文聊天大半如此），`while(changed)` 跑到不動點造成級聯塌縮（demo：7 則含 2 則明確 right → 全變 left）。
**消融跑分完成（2026-06-13，零 prod 變更）**：機制證實＋修法方向證實。三輪 17/17 單元全跑（results/ gitignored，檔名 `2026-06-12-19-57-42-local`＝未改碼 baseline、`2026-06-12-20-03-08-local`＝消融版）：①**local baseline 對齊 prod 成立**＝side acc 61.7% vs prod 61.3%（recall/precision/CER 全持平）；②**消融版（只填 unknown、砍三條翻面規則）side acc 61.7%→91.3%（+29.6pp）**，文字指標不動（layoutFirst 不碰 content，符合預期）；③級聯塌縮單元全面回復：S__5513249 5/13→13/13、251 4/10→10/10、overlap-251-252 9/17→16/16、mid-dark/stress 4/7→7/7、adversarial 57%→100%；④**預測風險同時命中**：S__5480452（baseline 8–11 次修復確實在救模型錯誤）4/4→1/4，dark_mode 群 87.5%→59.1%、quoted_card 100%→40%——全砍不行，dark/quoted 版面需要更窄的救援規則；⑤**噪音警示**：S__5513243 兩輪 layoutAdj 皆=0 卻 7/7→3/7＝模型對 dark 版面 run-to-run 變異大，該群單元單輪數字不可單獨採信，迭代時需多輪取樣。
下一步（>98% 路徑，新 session 開工）：設計窄規則版 layoutFirst＝「絕不推翻明確側」為主幹＋dark/quoted 限定救援（候選：side/isFromMe 自相矛盾修復、僅 unknown 填充擴充），TDD＋golden set 迭代＋Codex 雙審後 land。量測缺口待補：benchmark 尚未計 `quotedReplyPreviewIsFromMe`（labels 無此欄、計分未實作），圖中圖/emoji/貼圖維度同樣缺專屬計分——入迭代案 scope。
本機 bench 環境（無 Docker 機器可重跑）：`tools/ocr-golden/bench_auth_proxy.ts`（auth 改寫 proxy，function code byte-for-byte 不動）＋`compare_runs.sh`（多輪對照）；labels 仍是 AI 草稿未校對，方向性對照夠用、正式數字仍待 Eric 校對。bench 收尾後 CLAUDE_API_KEY 建議 Console 撤銷換新（key 曾入對話史）。
另：3a 編輯 UI 已改唯讀預覽＋編輯功能鍵（8fd5a97 含 Codex P2 修復），不動 OCR code path。

## [2026-06-13] 球數標準要不要加下限（連發 N 球至少出 M 段）？
Status: **CLOSED（2026-06-13）— fail-soft 定稿，dogfood 達標，重設計主動劃掉**。轉折：硬閘在 dogfood 第2張圖把真實分析擋成「請重新分析」（guard 非 generator，模型不服從時倒楣的是用戶）→ Eric 拍板改 fail-soft（`f417bd8`：閘只 console.warn 不丟 option、不終局 INCOMPLETE），接球率改由 (b)(c)(b2) prompt 提升。dogfood 重測第2/3張圖**全過、Eric＋夥伴確認回覆品質達標**。**「閘軟著陸重設計」新案主動劃掉**（2026-06-13 Eric 拍板）＝重進丟段＋扣費高風險區去解一個 dogfood 已不存在的問題＝YAGNI，且會再引入剛拔掉的風險。**拆引信清債（純註解、零行為改動、deno check 過）**：reframer.ts 閘 block 改標為永久 observability canary（verdict.ok=false 的 log＝prompt 退步免費預警、絕不改回丟 option）；stream_prompt.ts line 39「server rejects/forces a retry」加註解標明字面已非真實但刻意保留（compliance 壓力源、改字串＝動高風險 prompt 必黑箱重驗）。**P3 follow-up 降級 defer**：`parseBallInventory.catchableCount` 按 row vs distinct sourceIndex 偏差，現只餵 log＝連觀測都幾乎無影響。下為硬版過程記錄（前態，保留供脈絡）。<br>原硬版 = server disposition 閘（`0a571ae`）＋compliance/callback prompt（`ef9c601`）＋選中風格強化 b2（`7cee711`）＋Codex P2 修（`7380a29`）。**治好 (b)＋(c)**：黑箱重打 golden（b2 ×3＋P2 confirm）選中風格穩定 ≥3 段真接球、零 INCOMPLETE、第 3 段非湊水段；msg1「只喜歡江果先」從略變每次接、模型會撩回（run3/P2run coldRead 含 idx1）。**Codex 雙審**：review APPROVED 0 findings（`task-mqbx7wu2-3xjnj1`）；adversarial r1 P2（下限沒數 distinct 真球）→ 修 → adversarial r2 APPROVED 0 findings（`task-mqbxg2mj-b57fgo`）。**紅線守住**：sanitizeReplySegments／丟段路徑 byte-for-byte 零改動（閘在 reframer 轉發上游）、扣費時機不變、null 盤點 fallback 不驗證不誤殺。**P3 follow-up（非阻斷，Codex 說 later）**：`parseBallInventory` 的 catchableCount 按 row 累加（應按 distinct sourceIndex），僅在模型 emit 重複 sourceIndex 列時才偏差，正常流量每訊息列一次＝零影響。**Eric 知情決策留 prod live 邊修；dogfood-safe**。下方為原修法一/軟版過程記錄（前態，保留供脈絡）。
**修法一 few-shot 黑箱 FAILED（2026-06-13，commit `ddce074` few-shot 範例3 已 deploy prod，`run_baseline.sh` 重打 golden ×3＝15 style 輸出）**：只 1/15 達 ≥3 段，選中風格 coldRead 每次 2 段（srcIdx 6,5＝未接視訊+到家），msg1 從沒接、晚餐照(4) 只偶爾（run2 extend 唯一 3 段）。finalRecommendation.reason＝「她主動打視訊是這輪最高價值的球…」**證模型根本沒做盤點、直奔單一最熱球、靜默吞球**。few-shot 正例與三件套散文同命被略過。診斷：盤點寫在 reason（決策後才填的事後辯解欄）＝先選球再補理由，所以吞球。
**修法二＝盤點逼進輸出契約（Eric 拍板 2026-06-13 brainstorming：軟先、只動 stream、中文標籤 接/併/略）**：新事件 `analysis.inventory` 最先 emit（在 `analysis.decision` 之前）列全 N 球各標 接/併/略+理由，**機制＝強迫分類在選球之前（autoregressive 生成順序），吞不掉**；一次全域非每風格；server 純放行不驗證、完全不碰 `sanitizeReplySegments` 丟段路徑（軟本質、守上輪紅線）；reframer 須容忍 `analysis.inventory`＝known-optional 不炸不阻斷（TDD 第一紅燈）；legacy 本輪不做（YAGNI，dogfood 走 stream）。完整設計＋TDD 順序＝`docs/plans/2026-06-13-ball-inventory-contract-soft-design.md`。驗收 gate 不變（黑箱選中風格 ≥3 段含 msg1+msg4、reply 有素材＋Codex 雙審才宣稱 dogfood-safe）。軟版若仍不達標再升級硬驗證（server 驗 segments 只來自接/併球、接數達下限，會碰丟段路徑、需重評風險）。
**修法二實作＋黑箱證據（2026-06-13，commit `c782e98` 已 deploy prod，TDD 紅→綠 analyze-chat Deno 409 passed/0 failed＋deno check）**：①stream_events 新增 `analysis.inventory` known-optional 型別；②`buildStreamSystemPrompt` step 0 最先 emit inventory 列全 N 球標接/併/略＋三態範例行、decision 降 step 1 並要求 segments 只來自接/併球；③reframer 純放行（拔型驗 teeth 確認非空測）、不當扣費錨/不碰 segments/不污染 finalResult；client `default:break` 已驗安全忽略。**偏離設計 §3-bullet2**：SYSTEM_PROMPT 不加「emit inventory」句（與非 stream rollback 路徑 index.ts:6382 共用會汙染），instruction 全集中 stream wrapper、守「只動 stream」。**黑箱重打 golden ×3（prod，`baselines/verify_inventory_run1-3.ndjson`）三次完全一致**：inventory 機制**成功**＝模型顯式列全 6 球、dispositions 穩定 `1略 2併 3接 4接 5接 6接`（不再靜默吞球）；**但 gate 仍 FAILED**＝選中風格每次都 coldRead 2 段（srcIdx 6,5），全 5 風格皆 2 段。**根因精準二分**：(a)~~盤點時靜默吞球~~已修（inventory 顯式標 4 顆接）；(b)**inventory→reply 斷層**＝模型標 4 顆接卻只寫 2 段 reply、公然違反自己的盤點＋「segments 只來自接/併球」指令；(c)**msg1（江果先 callback）誤判 略**＝模型不認 partnerSummary 延續球（reason「語境不明…無可接球點」）。兩次軟 prompt（few-shot＋inventory）皆無法閉合 inventory→reply 斷層＝**soft 路徑已盡**，照設計 pre-registered 升級 server 硬驗證（碰丟段路徑、需 Eric 重評風險、新 session 開 invariants＋failure-matrix）。soft 版 land 為 KEEP（硬版的地基，非 throwaway）；對 live 用戶無回歸（仍 2 段＋一個被忽略的 inventory 事件，僅多 token）。**未宣稱 dogfood-safe**（gate 未過、未跑 Codex 雙審——待硬版過黑箱才雙審）。
**修法一原始黑箱證據（2026-06-13，測試帳號 curl prod，payload `golden_anchor_recon.json`）**：兩條不同程式路徑同結果——stream（dogfood 走這條，`buildStreamSystemPrompt(SYSTEM_PROMPT)` index.ts:6710）5 風格全 2 段、選 srcIdx 5,6（未接＋到家）；legacy（純 `SYSTEM_PROMPT` 無串流契約 index.ts:6352）也 2 段、同 srcIdx 5,6。**排除 ②server 丟段**：`sanitizeReplySegments` 只在 source 缺失時丟，msg1（糖糖梗）/msg4（晚餐照）index 合法（1/4）不可能被丟＝模型根本沒為它們出段；且 legacy 模式無「thin reason」限制，模型自由可寫盤點清單卻一個球都沒盤點（reason＝「它順著目前最值得接的球往下聊」淺一句）。**排除 ③改錯 prompt**＝stream 確實吃改過的 SYSTEM_PROMPT；**排除 ④串流契約壓制**＝legacy 無契約也同行為。**結論①確立**：模型對盤點先行/段數下限/邀約埋點三段散文完全不理，行為逐字＝改前（抓最後 1-2 顆、出通用罩句）。**P3 contract 風險不成立**＝斷點在模型不在 contract，修法不碰丟段路徑。
**修法定稿（Eric 拍板 2026-06-13，brainstorming）＝few-shot 正例**：改 `SYSTEM_PROMPT` 末尾加 `【示範】` worked example（一個**虛構非 golden 的 6 球情境**——⚠️ 絕不用糖糖/晚餐那張測試圖本身，否則模型照抄、golden 失去 held-out 驗收意義），示範「完整盤點→接 ≥3 顆→每段引原句＋素材鉤子（callback/埋約/懸念）、reply 是可直送真句非罩句」，同解段數＋品質兩痛點。**驗收真正 gate＝黑箱重打 golden（held-out）：srcIdx 須含 msg1＋msg4、≥3 段、reply 有用素材；單元 string-anchor 測試只是護欄、證不了 live**。風險＝AI prompt 高風險區須 Codex 雙審才宣稱 dogfood-safe（但不碰 contract）。Eric 補充：≥3 顆是硬預期，當前 2 顆「到家就好🫶」品質也不滿意。
（前態，碼仍 land 在 `2fbcccc`）三件 land＋Codex 雙審 APPROVED（review `task-mqbsq2ic-7rs1g2`＋adversarial `task-mqbsq2zk-e2np4p` 各 0 findings、皆自跑 Deno 403/0）——但雙審只證指令鎖住，未證 live 行為，dogfood 即推翻 live 效果。
實作（2026-06-13，TDD 紅→綠，analyze-chat Deno 全套 403 passed / 0 failed，scope = analyze-chat SYSTEM_PROMPT only，OPENER_PROMPT/quick_prompt 不動）：①**§1.3 盤點先行（強制步驟）**＝寫回覆前先把每句／每個 marker 列盤點清單、逐項標「接／併／略」加理由，併球只限同情緒/同片段相鄰句，堵「6 球縮 2 球」吞球後門；對象歷史延續球（糖糖梗）務必入清單；盤點結論只進 finalRecommendation.reason、不外溢 messages/replySegments（Codex 驗 `index.ts:1454`）。②**§1.3 優先接 #5 邀約埋點素材**＝生活分享（晚餐照/場景）不只回應分享慾、是埋邀約鉤子素材，串既有詞彙表（模糊邀約/約會幻想/合作框架）＋冷場/她剛放掉邀約時不硬約（同 case1 pushy 教訓）。③**§1.5 段數下限（檢核錨）**＝連發 ≥4 句通常 ≥3 段＋反水段（每段接盤點真球、嚴禁湊水段、同球例外要說明），與既有「不要把每個流水帳都拆成一段」並存不衝突。3 新 contract 測試（盤點先行/邀約埋點素材/下限＋反水段）。
**Codex 雙審證據（2026-06-13，scope `759b1cb..HEAD` @ `2fbcccc`，gpt-5.5 read-only）**：review job `task-mqbsq2ic-7rs1g2` ＝APPROVED 0 findings；adversarial job `task-mqbsq2zk-e2np4p` ＝APPROVED 0 findings。兩審皆自跑 `deno test analyze-chat/` = 403 passed/0 failed，並逐項驗：下限與流水帳/同球例外不矛盾、盤點不外溢、邀約埋點重用既有詞彙、OPENER/quick scope 未碰、stale cap 守門（最多 3 段/顆、2-3 則）無誤殺。**共同 P3（非阻斷，dogfood watch 點）**：contract 測試是字串錨，鎖指令但不證 Sonnet 實際會出 ≥3 段好段、不出水段——須 Eric/Bruce 看實機輸出驗「素材使用率↑且不過度拆段、token 體感可接受」。
（原診斷）**Eric 拍板（2026-06-13）：下限「連發 ≥4 句至少出 3 段」要加**；golden 預期＝GPT 回覆（golden1.mp4，Claude 已抽幀全讀），目標「至少不比它差」。**Golden 反推三缺口**：①真差距是**素材使用率**不是段數——我方高手版單句幾乎逐字等於 GPT 高手版，但 GPT 用掉她 6 球中 4 顆（糖糖梗callback→撩、晚餐照→邀約埋點、未接來電→懸念、到家→關心），我們只用 2 顆，糖糖梗＋晚餐照整組丟掉（prompt 1458「對象歷史=高價值延續球」沒被執行）；②缺「選球盤點先行」強制步驟（GPT 先列訊號清單再寫回覆），併球裁量在無盤點時變吞球後門（6球→2球）；③下限是檢核錨，但單加下限模型會出水段應付——**盤點＋下限＋「生活分享=邀約埋點素材」入優先接清單，三件一起上**。voice dogfood 污染風險 Eric 知情接受。原診斷如下。
現行標準（c3f3ac6 已訂）：「預設每顆有內容的球都接，上限 5」＋併球規則（同生活片段算一球、貼圖 emoji 不佔額）。Bruce 案 7 連發只出 2 段＝模型用併球裁量把 7 句併成 2 球（截圖輸入強制 Sonnet，非 Haiku 鍋）；server 丟段零 telemetry 無法驗屍。已修：client `.take(3)` 漏改（991f202，模型出 4-5 段不再被剪）。
決策點：①要不要加 prompt 下限「對方連發 ≥4 句有內容時 replySegments 通常 ≥3 段」？利＝接住投入感；弊＝與「技巧密度原則／不硬出招」拉扯＋**voice Game 化 dogfood 進行中，現在動 SYSTEM_PROMPT 會污染體感回報**。建議：等 voice 案 CLOSE 再動，屆時連 server 丟段 telemetry（log-only）一起上。②或先只加 telemetry 觀察一週再判。

## [2026-06-12] 主 prompt 全面 few-shot 化 = voice few-shot 化（高手感/幽默感缺口）
Status: OPEN — **方向重設（2026-06-12 深夜，Eric 拍板）：盲測退役，轉 Game 體系化**。設計定稿 `docs/plans/2026-06-12-voice-game-system-design.md`（brainstorming 逐節 OK）：①差異化改判＝不比回覆品質（GPT 賽道打不贏且單次變異大），改驗「體系感」＝技巧名可見標注（既有欄位內嵌文字，零 client 工）；②範例換血檔位制＝承瑋 Wen 局進（12 標籤、冷開→升溫→模糊邀約完整弧線）、小雲退役**接手冷局 smoke**（測試資產對調，wen_cold_smoke 開卷作廢）、golden 留守；③詞彙表 8–10 詞＋顯現規則（名詞必須有顯現出口，B 砍刀教訓反向）＋Apple 三層線（中性詞可見／紅丸PUA等內部 only／性·歧視連 prompt 都禁）；④新 gate 四關＝契約＋anchor＋Eric/Bruce 體系感目檢（不盲不比 GPT）＋Codex 雙審。round2 盲測表（`blind/fix_round2_*.md`）作廢不評、留檔。承瑋 18 標籤提案併入本案 §2 結案。產品定位分層入檔：analyze-chat/opener=技巧導向 Game、Coach 1:1/follow-up=真誠流教練（本案只動 analyze-chat，opener 下一案）。**刀 1 完成（2026-06-12）**：Wen 局 10 張目檢 10/10 吻合零修正（`b7e279a`，補標 `yawen_0619` IG PII）；快照點拍板 S1（她回「酒吧／哈哈」，承瑋合作框架原句 verbatim 進 pick）；五槽映射 **Eric 逐句定稿「全過」**，定稿全文＝設計檔 §5（進 prompt 即抄該節）。**Eric 補拍板（刀 1 後）：技巧密度原則**＝技巧是時機性不是密度性，平聊佔真實對話大宗、AI 須判斷時機，沒觸發就正常聊不硬出招不硬標名（入設計檔 §2；gate 3 目檢改雙向：看得到體系＋不會硬出招）——刀 3 顯現規則須含反向禁令「不得為了標名而出招」。**刀 2 完成（2026-06-12，`229eabe`）**：範例 2 換血（小雲→Wen §5 定稿照抄，標題改「陌生冷開局→升溫中（真實高手實戰局）」）；TDD 紅→綠（新錨：組隊/合作框架定義/看素材不看字數/實戰後續＋反向錨小雲舊文零殘留＋PII 守門 yawen 字串與台灣手機 regex）、Deno 374 綠；測試資產對調＝wen_cold_smoke.json 刪除（開卷作廢）、小雲 payload（case2_min_first_night.json）接手冷局 smoke（held-out）、README 改現役資產表＋blind/ 標作廢留檔；push 後 auto-deploy 已觸發。**詞彙表 10 詞 Eric「OK」全過定稿（2026-06-12）＝設計檔 §6**（懸念鉤進表／callback 不佔額直接標／試探維持判讀詞／失格出口最弱、零觸發時砍它優先——Eric 知情保留）。**刀 3 完成（2026-06-12，`057568f`）**：§6 十詞表照抄入 prompt（場景觸發矩陣旁）＋顯現規則硬指令（分析欄位標名＋一句為什麼／messages 不夾名／反向禁令「不得為了標名而出招」／平聊零標籤合格）＋Apple 三層線取代舊禁詞表（第 2-3 層黑名單詞從 prompt 本體**清零**改類別描述——連帶改寫「不補 PUA 技巧庫」「可見輸出不要寫技巧名」「我用了 DHV / 冷讀」三句舊規則，§(DHV) 標題去縮寫；legacy schema key `psychology.shitTest` 保留＝client 契約）；範例 1 analysis 改標注版（reason 標懸念鉤、humor 標懸念鉤變體、extend 標模糊邀約、**resonate 刻意不標＝平聊示範**）、範例 2＝Eric §5 定稿零改動；TDD 紅→綠：4 新契約測試（十詞表格列錨＋定義/反例抽查／顯現規則錨／第 2-3 層黑名單 18 詞＋IOI/IOD regex 零出現、範圍切片只測 SYSTEM_PROMPT 不誤殺 opener／範例標注錨），全套 Deno 636 綠。**兩個披露點待 Eric 目檢**：①§6 反例 8/9 的內部出處括號（round1 case2 教訓／case2 修字原句）沒抄進 prompt（對模型是噪音）；②舊禁詞表的「推拉」解禁（與 §5 定稿 tease 槽「角色反轉式輕推拉」可見標注衝突，從黑名單拿掉）。**刀 4 機器三關完成（2026-06-12）**：關 1 契約＝Deno 636 綠 0 failed；關 2 anchor＝golden＋小雲冷局 smoke 實跑 prod 兩條 `check_contract.sh` PASS（golden 重現定稿 pick=coldRead 懸念鉤＋糖糖 callback、extend 標合作框架＋模糊邀約、resonate 不標＝平聊示範如設計；小雲冷局不 pushy 不裝熟、5 槽僅 1 處表內標注＝技巧密度原則守住；兩條 messages 零夾技巧名、黑名單詞＋失格零出現；輸出在 `baselines/gate4_*.ndjson`）；關 4 Codex 雙審＝review **0 findings**＋adversarial **needs-attention 1 high**（job review-mqb5avrp-zu3vsw）＝`OPENER_PROMPT`（同檔 index.ts:2148-2358）仍含玩咖/PUA——**與既有拍板一致**（opener Game 化＝下一案、刀3 測試刻意只切 SYSTEM_PROMPT），非新缺陷，處置選項入目檢表披露點 3（推薦＝本案範圍明示 analyze-chat SYSTEM_PROMPT only＋opener 案加全 prompt 常數 blocking 掃描）。另一處如實披露：小雲局 coach_hint 教「一個問題不連問」但 extend 主推薦連問兩題（輕微、單次取樣，目檢判）。**三披露點 Eric 裁決「照建議」（2026-06-12）**：①§6 反例出處括號維持不進 prompt；②「推拉」解禁維持（與 §5 定稿 tease 可見標注一致）；③本案 Apple 三層線範圍**明示＝analyze-chat SYSTEM_PROMPT only**，adversarial 1 high 即此既有切割——**opener Game 化案開工時必加「掃全部 production prompt 常數」blocking 測試**（含 OPENER_PROMPT 玩咖/PUA 清理）。零 code 變更。**關 3 目檢：Eric＋Bruce 雙 PASS（2026-06-12）＝四關全過、dogfood safe ✅**（prompt 已在 prod，不需 rebuild/deploy，直接用 app 測）。**Eric 拍板收尾方式：主要看 dogfood 實測再判斷——本 item 維持 OPEN 等 Eric/Bruce dogfood 體感回報（體系感有沒有出來／會不會硬出招）才 CLOSE**。後續已排：opener Game 化案（必加全 prompt 常數 blocking 掃描＋OPENER_PROMPT 玩咖/PUA 清理）；prompt caching 小案（雙審後排程，現在可開）。
（前態）修字兩題已 land＋部署＋復測 PASS（ec357ba＋f9f655e）。case1 pushy guard（新節「對方的局不是你的局」：第三方既定行程不插隊不帶隊、展示自己行程、鉤子留下次、明確被邀才走情境6）＋case2 框架原則（情境2.6：被貼標籤自己給定性、禁「算加分還是扣分」「妳給我一個說法」句式）。TDD 紅燈先行、Deno 374 綠；prod 黑箱復測 7/7 契約 PASS：case1 修字生效（推薦句展示自己行程＋低壓窗口，avoid 欄反向教「不要說我帶你們去——那是她的局」）、case2 不再丟評價權；anchor 零誤傷（golden 懸念鉤+糖糖 callback、小雲 byte 級重現、Wen 冷局不 pushy）。**round2 盲測表：`blind/fix_round2_sheet.md`（Eric）＋`fix_round2_bruce_sheet.md`（Bruce，A/B/C 重洗牌）；ChatGPT 欄沿用第一輪逐字稿（同輸入固定參照）。門檻：修字版>舊版 case1+case2 兩題都過才發 Codex 雙審。**
（前態）盲測 round1 不過門檻（Eric+Bruce 雙評，072ae2c 後回填）。新>舊未達 3/3：case1 兩人一致新版輸（pushy「我帶你們去」，熱絡局誤讀成可帶隊）；case3 兩人一致新版全場最佳（few-shot 方向實錘有效）；case2 兩人對沖→**Eric 拍板照 Bruce＝新版輸**（「妳給我一個說法」把評價權丟給對方、框架弱，列入修字）。**Codex 雙審不發、不說 dogfood safe**。下一案＝修字兩題：case1 熱絡局 pushy guard（升溫≠可帶隊）＋case2 框架修正（不把評價權丟給對方），修完 case1+case2 重盲測過了才雙審。完整評語＋夥伴另輪 GPT share 連結在 `tools/voice-benchmark/blind/blind_sheet.md`。Bruce 版匿名表＝`bruce_sheet.md`＋`bruce_key.md`。
（前態）砍 A+B 已 land＋部署＋復測三件套全 PASS ✅（128d00e 砍刀、f94435d 復測＋盲測表）。TDD 紅燈先行、Deno 372 綠；SYSTEM_PROMPT −1162 字元，兩刀淨增 +2856→+1694（≈+6.7%，略高於 audit 預估 +4~5%——B 組多為短 bullet，如實報告）。復測：黑箱契約 9/9 PASS（五槽零 error、source contract 乾淨）；golden anchor 重現定稿（懸念鉤 pick=coldRead＋糖糖老師 callback，⚠️ payload 是重建版非逐字同源；**舊 run「再到夜市」範例洩漏實錘，新 run 歸零**）；小雲 anchor byte-identical 重現定稿；Wen 冷局 smoke 不 pushy（humor 低壓、明示不推進邀約）。**盲測表就緒 `tools/voice-benchmark/blind/blind_sheet.md`**（3 case × 甲/乙隨機去識別＋ChatGPT 欄留白；answer_key 評完才開）。第一刀 c64bbed（範例1+2 進場、schema 占位句換血、callback 挖掘指令）。**下一步：Eric 拿 chatgpt_paste/ 餵 free ChatGPT 貼回盲測表 → 盲測評分（不輸 ≥2/3 且 >舊版 3/3）→ Codex 雙審**。prompt caching 另案（盲測後）；承瑋 18 處戰術標籤用法提案仍 open。原兩個拍板（Eric）：
1. **盲測全換 held-out**：few-shot 範例輸入（golden/小雲）進盲測=開卷背誦會失真 → 盲測三題改 case 1'=承瑋 R 局（升溫）、case 2'=肉伊（陌生早期）、case 3=Ashley 試探球；golden＋小雲降級非盲 anchor 檢查；承瑋 Wen 冷啟動段當冷局 smoke test（倖存者偏誤防呆）。
2. **prompt 刪減=審計後砍實證冗餘**：Claude 先列刪減候選+證據給 Eric 過目再砍；12 場景判斷區不動。
新素材（Eric 補充）：**承瑋案例 22 張 3 對象**（`OCR測試圖片/承瑋(幾年前案例)有3個人)`）——真人高手、自帶 18 處戰術標籤+紅筆步驟編號，**輸出可參考**（與小雲/Bruce「只取輸入」不同）；含失敗分支筆記（「模糊邀約沒反應→轉話題」）。轉寫完成+抽查目檢：`tools/voice-benchmark/{case3-bruce,chengwei}-transcript-draft.md`（⚠️ S__42246217 有真實手機號，素材化前必匿名）。Baseline：3 盲測題+小雲 anchor 各 2 輪、全五槽零 error，`tools/voice-benchmark/baselines/`；runner=`run_baseline.sh`。下一步：TDD 改 prompt（範例 1+2 進 prompt+占位句換血+audit 刪減+承瑋筆記用法提案）→ 黑箱契約復測+anchor/冷局 smoke → 盲測（ChatGPT 欄需 Eric 餵 free ChatGPT）→ Codex 雙審。
Request-Type: design → implementation
Design: `docs/plans/2026-06-12-voice-fewshot-design.md`
Raised-By: Eric（實測 verdict：結構贏、voice 輸 free ChatGPT）
Owner: Claude（brainstorming → 設計 → 實作）→ Codex 雙審 → Eric/Bruce 盲測

開案依據（Eric 實測 2026-06-12，同一場對話正面對決）：
- golden.mp4 = **ChatGPT 免費入口**對同截圖的輸出：點名用戶自造梗（糖糖老師）、分層變體（最推薦/幽默版/往約會推進/高手版）、rationale 是洞察句（「既像開玩笑，又是埋邀約」）、回覆有推拉懸念。
- VibeSync Phase 1 後輸出：結構全對（segments/missed call 接住/複製分段）但 reply 是「禮貌模板」（「到了就好，路上還順？」）、零 callback、rationale 是標籤句。
- 驗收標準（Eric 定）：**不求贏 OpenAI，至少不輸**——人腦肉眼主觀「哦！還不錯蠻高手的、很幽默」。

方向（待 brainstorming 定稿）：
1. 砍規則稅換 voice few-shot：大段 schema/判準散文 → 2-3 個 golden 級完整範例（reply 帶推拉懸念、rationale 寫洞察句）。
2. Callback 挖掘指令：用件2 對象歷史餵料挖用戶自造梗/暱稱/重複元素，至少一段 callback。
3. 高光球分層（與 Phase 2 策略意圖選項合流評估）。
4. Voice benchmark loop：golden 對決案落檔，每次 prompt 改動 side-by-side 給 Eric/Bruce 盲測。

Scope: analyze-chat stream_prompt（高風險區：AI 行為）
Close Condition: 設計拍板 + 實作 land + Codex 雙審 APPROVED + Eric/Bruce 盲測「不輸 ChatGPT」

---

## [2026-06-12] 方案二：分析輸出 Golden 形狀重構（策略意圖選項 + 真一球一回）
Status: OPEN — **Codex r2 APPROVED（0 new findings）** → WAITING_ON_ERIC：Eric 確認 + Bruce 實測有感才 CLOSE
Request-Type: implementation（Phase 1）+ design（Phase 2 brainstorming）
Raised-By: Eric（拍板 2026-06-12，背景：golden 影片 = ChatGPT 同截圖輸出，品質勝過產品現狀，定位 P0）
Owner: Codex（雙審 d868b6d..a9cfb80）→ APPROVED 後 Eric 確認 + Bruce 實測有感才 CLOSE

實作進度（2026-06-12，TDD 全程紅燈先行，Deno 全測 364 passed / 0 failed）：

- `9cb3484` 件5 contract 堵漏：matchBallIndices 唯一性，併球指紋（≥2 匹配）不放行；exact 優先防 OCR 重疊球誤判。
- `467362e` 件3+件4 原子 land：stream 協議 v2（segments[] 一等公民、瘦 recommendation、few-shot、D4 server join）+ reframer 扣卡回填（buffer→回填→舊順序轉發、safety 後移驗 join 全文、emitDone 守門已扣費無輸出、廢除雙軌、瘦 precharged 不直接回放）。
- `c3f3ac6` 件1 球判準：預設全接 cap 3→5，prompt 全處 cap 字樣同步 + sanitizeReplySegments slice 5。
- `91511aa` 件2 marker 語意小節 + 對象歷史餵料 + cap 殘骸清掃。
- `a9cfb80` 黑箱 r1 修：模型省略瘦卡（視為與 decision 重複）→ prompt 標 REQUIRED+瘦卡 few-shot + reframer late-bind/合成韌性網。

Prod 黑箱復測（測試帳號 curl stream，多球+marker golden case）：
- r1（修韌性網前）：五 reply_option 帶 segments ✓ 但模型沒出 recommendation → MISSING_COMPLETION_ANCHOR（已修）。
- r2：全鏈通過 decision→recommendation（回填 message+replySegments+expectedReaction）→5 reply_option（每風格 segments 2 段、source 全過 contract）→done；finalRecommendation 與推薦卡一致（雙軌已廢）。
- **Marker 實證翻轉**：`[Missed video call]` 五張卡全部優先接（修前 A/B 判「別提」）。

審查重點（給 Codex）：扣費路徑時序（pendingThin 先掛再扣費 / emitDone 守門 / 合成卡不改扣費錨點）、D3 契約凍結（build 256 事件順序與形狀）、late-bind 順序偏移（rec 晚於 option）對 client 的影響、prompt 砍稅是否誤刪判斷資產。

Codex r1（task-mqahqt1v-0ltt6q，2026-06-12）：**REVISE_REQUIRED — 1 P2、無 P0/P1**。
- P2：瘦卡 fallback 扣費（錨在 recommendation、message 空）存進 ledger 後，retry loader `streamRecommendationFromRun` 因 `message.length === 0` 回 null → STREAM_RUN_NOT_RETRYABLE，已扣費 run 不可續跑（reframer/handler 的 thin-resume 支援被 loader 擋在門外）。
- r1 已確認無虞：build 256 解析（server join 相容欄位、Dart parser 拿得到 rec message）、late-bind 順序、post_process ambiguity 為 intended fail-closed、prompt 內部一致。
- P2 修復 `3fff1b9`：loader 放行合法瘦卡形狀 thinResume + reframer init 防 ledger 損壞瘦卡靜默完成；紅燈先行、Deno 366 passed。r2 複審範圍 `a9cfb80..3fff1b9`。

Codex r2（2026-06-12）：**APPROVED，0 new findings**。逐點驗證：loader 只收合法瘦卡形狀（malformed 空 message 仍擋）、retry 不重複扣費（shouldCharge 排除 retry mode + resume chargeCompleted=true）、瘦卡不直接外流 client、replay fresh 驗證後綁卡回填。

剩餘 close 條件：Eric 確認 + Bruce 實機測「有感」（多球截圖分析應出 2-5 段、推薦卡完整、missed call 被接住）。非阻斷尾巴（r1 註記）：post_process ambiguity 為 intended fail-closed；Phase 2 client UI 另立 item。

Eric 實測 verdict（2026-06-12）：**結構目標達成**（實機截圖：missed call 五卡優先接、逐球引用、複製分段全到位）；但同對話對決 free ChatGPT（golden.mp4），**voice 主觀判輸**（對方更幽默、有 callback、有分層變體）。voice 缺口**轉新案**「主 prompt 全面 few-shot 化」（見 queue 頂），不算 Phase 1 reopen。本 item 保持 WAITING：Bruce 實測尚未回報。
Scope: analyze-chat stream_prompt / reframer / post_process contract / client UI（高風險區：AI 行為 + Edge schema）
Design: `docs/plans/2026-06-12-golden-reshape-phase1-design.md`（2026-06-12 設計定稿，Eric 逐項確認：cap 5 / bind 瘦推薦卡+reframer 扣卡回填 / server→client 契約凍結 / 主 prompt 砍稅+加料全掃）。Phase 1 純 server 出貨。

拍板內容（Eric 2026-06-12）：

- 終局形狀 = golden：固定 5 風格槽 → 模型按局勢選 3-4 個策略意圖選項（穩接/幽默/推進/高手），每個附「為什麼」+「她可能怎麼回」，最推薦內嵌（bind）。
- Prompt 價值重定義：「管格式是稅、教判斷+餵專有 context（OCR marker 語意、對象歷史）才是資產」。指揮越少、餵料越多。

Phase 1（先 land，Bruce 立刻有感；皆為 Phase 2 地基、不是死工）：

1. 球判準重寫：預設每顆有內容的球都接，僅純貼圖/單 emoji 可併鄰球；cap 3 放寬。
2. Marker 語意進 prompt：`[Missed video call]` = 高價值升溫訊號、`[Photo]` = 分享慾訊號（A/B 實測：marker 形式會讓模型把該球判成「別提」，自然語言則正確優先接）。
3. Stream 協議 v2：reply_option/recommendation 事件以 `segments[]` 為一等公民 + few-shot；flat `message` 降為相容欄位。
4. Bind：recommendation 指向選中 style、共用其 segments，不再雙軌生成文字。
5. Contract 堵漏：`/` 併球 sourceMessage 不得再被 containment fuzzy match 放行（實測兩輪都靠此漏洞通過）。

Phase 2（需 brainstorming + Eric 再拍板 UI 細節）：5 風格槽 → 策略意圖選項的 client schema/UI 改造、訂閱分層展示。

成本評估：output token 約 +60~100%（≈ +$0.02/次）；latency 現狀 46-52s、預估 +10-15s，stream 逐卡片 UX 吸收。模型呼叫次數不變。

Close Condition: Phase 1 land + Deno 測試綠 + Codex 雙審 APPROVED + Bruce 實測有感；Phase 2 設計案另立 item。

---

## [2026-06-12] #12 一球一回 OCR 路徑單段化「敷衍」— 品質調查
Status: CLOSED（root cause 定位 ✅ + 修法拍板 ✅ = 方案二，見上方新 item；Eric 拍板 2026-06-12）

調查結論（prod 黑箱 A/B 實測，OCR 雜訊 vs 乾淨文字各一輪）：

- **主嫌假說推翻**：contract 一段都沒剪。兩組皆為模型出 flat 單句 + `/` 併球 quotedContext。
- 真 root cause：`stream_prompt.ts:31,34` 事件協議本身只定義 flat `message`+`quotedContext`；#12 分段規格只在 :39 一句話要求塞 finalResult，:40 又叫模型 compact——格式指令打架，模型 2/2 輪未出 replySegments。`reframer.ts:430` 以 quotedContext 合成單一假段（指紋：label="recommended"、psychology==reason，實測輸出吻合）；contract containment fuzzy match 將 `/` 併球 sourceMessage 修出 sourceIndex 放行；段數 <2 → `post_process.ts:729` 回退 replies[pick] 合併單句。**#12 規格從未真正部署到 stream（產品實際路徑）**。
- 附帶發現（球判準）：`[Missed video call]` marker → 模型判「別提」；同語意自然語言 → 模型當主動球優先接。OCR marker 無語意教學是判準缺陷主因之一。

原始 item（歷史紀錄）：

Request-Type: investigation
Raised-By: Bruce（Eric 轉達）
Owner: Claude（新 session 調查）→ 結論後決定送 Codex 與否
Scope: analyze-chat post_process segments contract / OCR 文字對齊（高風險區：AI 行為）

現象（Bruce 2026-06-12，build 256，P0 修復後）：

- 截圖 OCR 餵多球對話（糖糖老師梗 / 加料 / 晚餐照片+茄汁牛肉飯 / missed call / 到家🤲🤲🤲）。
- 兩輪分析皆只出 1 段推薦回覆（「到家了，茄汁牛肉飯有撐到嗎」單句兩球串接 / 「平安回家了✓」只接一球）；五維展開細節亦無分段。Bruce：「對方回那麼多只有一個，太敷衍」。

主嫌假說（未驗證，依 code 結構）：

1. `post_process.ts` `enforceReplySegmentSourceContract`（b14ea0c 防幻覺交叉驗證）對 OCR 文字過嚴：貼圖/照片/emoji（🤲）造成 sourceMessage 對不上 ballList → 全段 drop → 回退合併單句（code 註解明示此回退）。
2. 次嫌：模型只出 1 段（球判斷把貼圖/照片當低價值球略過）——需 server log 或黑箱重現分辨。

調查路徑：黑箱重現手法見 memory `p0-stream-reply-option-fix-2026-06-12`（測試帳號 + curl stream），用「帶 emoji/貼圖雜訊的 OCR 風格訊息」對照「乾淨文字」兩組，看 raw stream 的 reply_option segments 數 vs 最終 finalRecommendation.replySegments 數，即可定位是 contract drop 還是模型未出段。

Close Condition: root cause 定位 + 修法拍板（若動 contract 屬高風險須雙審）。

---

## [2026-06-12] P0 stream 分析必炸 hotfix（reply_option 段落陣列被丟棄）— Codex 雙審
Status: CLOSED（Codex r1 APPROVED 0 findings + prod 黑箱復測過 + Bruce 實機回測 OK「這次可以」兩輪完整跑完，Eric 轉達 2026-06-12）
Request-Type: review
Raised-By: Claude
Owner: Codex (雙審) → Eric 確認後關閉
Scope: analyze-chat reframer（高風險區：analyze-chat / AI 行為 / 扣費已發生後的 stream 完成判定）
Branch/Commit: `main` @ `167e26a`（已 push，auto-deploy 生效）

背景與證據：

- Bruce 2026-06-12 早回報「分析又失敗」（build 256、Essential 季繳、額度正常 774/800）。截圖：分析內容有渲染但結尾「這次分析沒順利完成，請重新分析一次」→ 重試亦炸 →「無法再重試」。
- Edge request log：Bruce 的請求全程 HTTP 200（streaming 錯誤藏在 stream 內），dashboard 無異常。同時段 17× 400 burst 經查為 Eric 本機 OCR golden set 跑分工具（order 0-based 修復前），與本案無關。
- 黑箱重現（prod + 測試帳號，多球對話「茄汁牛肉飯」+「到家🤙🤙🤙」）：stream 射出 5 個 reply_option（五風格齊全）後，結尾收到 `analysis.error` `STREAM_INCOMPLETE_REPLY_OPTIONS` missingStyles=[extend,tease,humor,coldRead]。
- Root cause：#12 一球一回強制式 prompt 下，≥2 顆球的對話 reply_option 事件只帶 `messages` 段落陣列、無頂層 `message` 字串（stream_prompt 規格要求 `message`，模型未遵守）；`reframer.ts` assembler absorb 只認 `message` 字串 → 五風格全被靜默丟棄 → emitDone 誤判缺風格。守門函式 `findMissingRequiredReplyStyles` 本就支援 segments，兩層寬容度不一致。
- 影響：多球對話 100% 必炸且重試必炸（deterministic）；recommendation 已扣費後才炸（quota 照扣、無 refund 路徑觸發）。單球對話不受影響。觸發窗口：#12 prompt 上線起，Sonnet 4.6（157f2af）後模型更遵守強制分段 → 發生率上升。

變更內容（167e26a，reframer.ts +49/reframer_test.ts +59）：

- absorb reply_option：`message` 缺失時回退 `messages ?? messageGroup ?? replySegments` 段落 join（與 findMissingRequiredReplyStyles 同一套 `reply ?? content ?? text` 寬容規則），並保留原始段落陣列進 `replyOptions[style].messages`（原本為合成單段）。
- 新增紅燈測試：鏡射 prod 事件序列（recommendation 帶 message + 5 reply_option 只帶 messages 陣列）→ 修前 STREAM_INCOMPLETE_REPLY_OPTIONS、修後 analysis.done。

Tests: analyze-chat Deno 全測 341 passed / 0 failed。Prod 黑箱重現 curl 修後復測證據見 queue 更新。

審查重點（給 Codex）：

1. segments join 用 `\n` 接 `replies[style]` 字串——client `AnalysisResult.fromJson` 對多行 reply 與多段 `replyOptions[style].messages` 的相容性。
2. 保留原始段落陣列（含 sourceIndex/sourceMessage）外溢進 finalResult 是否與 #12/#13 client 接口一致。
3. prompt 規格 vs 模型實際輸出的長期解法：是否該同步收緊 stream_prompt 或放寬規格文字（本修走 server 寬容、prompt 未動）。
4. 扣費後才炸的舊案例：是否需要補償機制（本修未處理，僅止血）。

Close Condition: Codex 雙審 APPROVED + prod 復測通過 + Eric 確認。APPROVED 前不得宣稱 dogfood safe。

---

## [2026-06-12] AI 模型全面升級 Sonnet 4 → 4.6 — Codex 雙審
Status: CLOSED（Codex r1 APPROVED 0 findings + Eric 確認 2026-06-12。Bruce 實測由 Eric 人工協調，另開 session 回報）
Request-Type: review
Raised-By: Claude
Owner: Codex (雙審) → Eric 確認後關閉
Scope: AI model / opener / analyze-chat / coach-chat / coach-follow-up（高風險區：AI 行為）
Branch/Commit: `main` @ `157f2af`（已 push，auto-deploy 生效）

背景與證據：

- Bruce 回報 opener「context 理解不夠」並貼出 Claude app 對照（同 profile，前沿模型輸出明顯較佳）。
- Claude 離線 A/B：臨時 Edge Function（已滅成 410 stub `tmp-model-ab`，可從 dashboard 刪）、同 prod OPENER_PROMPT byte-for-byte、Bruce golden case bio（毛茸犬/不怕蟑螂/幫殺蟲）、各模型兩輪。
- 結果：Sonnet 4 兩輪皆產「妳這反差好可愛」模板 + coldRead 原文複述 bio（prompt 明文禁止旁路冷讀不得複述——模型守不住規則）；Sonnet 4.6 兩輪皆抓到她自留鉤子（幫我把蟲蟲殺光）做交換條件/共逃 frame，與 Claude app 神回同構。結論：瓶頸為模型代差，非 prompt。
- Eric 拍板（2026-06-12）：全 repo Sonnet 換 4.6；Haiku 4.5 已是最新不動。

變更內容（12 files, +32/-30）：

- `claude-sonnet-4-20250514` → `claude-sonnet-4-6` 全 repo 零殘留：analyze-chat（index.ts 9 處 + fallback.ts 降級鏈 + logger.ts）、coach-chat/generation.ts、coach-follow-up/generation.ts、Deno 測試檔、dart doc comment（coach_follow_up_result.dart:16，僅註解）。
- logger.ts TOKEN_COSTS 保留舊 Sonnet 4 key（歷史 log/在途請求計價）。
- 同價 $3/$15；max_tokens、temperature、prompt 全不動。

Tests: Deno 全測 598 passed / 0 failed（commit 前本機自跑）。

審查重點（給 Codex）：

1. fallback.ts 降級鏈 key 換名後 sonnet→haiku 降級路徑是否仍成立。
2. index.ts VALID_MODELS / forceModel（測試帳號）換名後測試路徑一致性。
3. 是否有遺漏的 model id 引用（docs/客戶端 fixture 刻意不動，理由：非 runtime）。
4. #12 一球一回 golden case 明天 Bruce 實測會同時吃到新模型——確認 segments contract/sanitizer 對模型不敏感。

Close Condition: Codex 雙審 APPROVED + Eric 確認。APPROVED 前不得宣稱 dogfood safe。

Codex evidence（r1 = APPROVED, 2026-06-12）：

- 注：首發背景 r1（`task-mqa0dcay-her2k8`）被 session rotation 的 SessionEnd lifecycle hook 殺掉且紀錄全刪（plugin 行為：背景 job 綁 sessionId，session 結束即 terminate + 從 state 移除）。本筆為同步重跑，scope `a208fd7..157f2af`。
- 審查重點逐項驗證：(1) fallback.ts:38 降級鏈 `claude-sonnet-4-6 → claude-haiku-4-5-20251001` 成立；(2) index.ts:672 `VALID_FORCE_MODELS`/forceModel 只接受 Haiku 4.5 + Sonnet 4.6，舊 id 400 擋下；(3) runtime 舊 id 零遺漏，僅 logger.ts:4 歷史計價 key（刻意保留）；(4) #12 segments contract 在 deterministic post-process 層（cap 3、sourceIndex/sourceMessage 交叉驗證、全 drop fallback），對模型不敏感。
- Codex 自跑 targeted Deno：153 passed / 0 failed（analyze model/prompt/stream/post_process、coach-chat/coach-follow-up generation+telemetry、submit-feedback fixture）；`git diff --check` passed。

---

## [2026-06-12] #12 一球一回 replySegments 實作 — Codex 實作雙審
Status: APPROVED（Codex r2 2026-06-12 — 0 P0/P1/P2；r1 兩 P2 驗證解除、340 Deno 全綠 Codex 自跑。**server-only 已自動部署，現有 TF build 即可測**——剩 golden case Bruce 實測 + Eric 確認後關閉）
Request-Type: review
Raised-By: Claude
Owner: Codex (實作雙審) → Eric/Bruce (APPROVED 後 dogfood)
Scope: analyze-chat prompt/schema + sanitizer（高風險區）— **server only，client 零變更**
Branch/Commit: `main` @ `1fd4f5c` + `a6bc654` + `4143895` + `b91ee77` + `0a39621`；計畫 `docs/plans/2026-06-12-reply-segments-implementation.md`；設計 `docs/plans/2026-06-11-reply-segments-one-ball-one-reply-design.md`（設計把關 r2 APPROVED @ `435e6a1`，cap 3）

**實作內容（依設計七點規格）**：

1. **Sanitizer 三層缺 source 規則**（`1fd4f5c` + `a6bc654`）：`post_process.ts` 新增 `extractPartnerBallList`（球清單 = trailing partner run，1-based；vision 優先 `result.recognizedConversation.messages`；run 空時回退最近 10 則對方訊息）+ `enforceReplySegmentSourceContract`（①sourceIndex 缺/越界 → sourceMessage 正規化文字回查修復（exact → 雙向 substring、≥4 字门槛）②修不回 → drop 該段 ③全 drop → content 回退 drop 前換行合併版，絕不空 source 流出）。接線 `ensureNonEmptyAnalysisOutput` + `postProcessAnalysisResult` Step 3 兩處輸出點；`index.ts` 三呼叫點（:6395 full / :6677 stream markDone / :7159 legacy+vision）傳 `requestMessages`。contract 只在 `!recognizeOnly && !isMyMessageMode` 啟用。球清單不可得時防衛路徑只驗形狀（sourceIndex≥1 + sourceMessage 非空）不驗範圍。
2. **SYSTEM_PROMPT 條件式 → 強制式**（`b91ee77`）：§1.5 改「一球一回」——≥2 顆值得接的球**必須**分開回、每球一段、cap 3 挑互動價值最高、每段必填 sourceIndex（她這輪連發第幾句，1-based，與 server 球清單同語意）+ sourceMessage、各段獨立成立、content 仍填換行合併版（規格 #4）；「同一情緒/生活片段算同一顆球」防過度拆段。§1.2 範例消滅兩球串一句示範；§1.3 加指向 + 五句連發=同一行程球註記；§1.5 範例升級三球三段（Bruce golden case 同構）；vision Multi-Message Reminder（:1135）鏡射強制式；schema 範例擴 2 段。
3. **Stream contract 堵 compact 掉段**（`0a39621`）：偵察發現 streaming（現行產品路徑）segments 唯一通道 = `analysis.done.finalResult`，而舊 contract「compact finalResult」是反向拉力 → 明定多球時 `finalResult.finalRecommendation.replySegments` REQUIRED、Never omit to save tokens。
4. **規格 #4 已存在**：content 換行 join 本來就在（`post_process.ts` 兩處 `join("\n")`），新增測試上鎖。

**測試證據**：Deno 全套 **335 passed**（新增 sanitizer 7 + 接線 2 + 換行 join 1 + stream contract 1 + index_test 字串鎖更新）；style-pair 鎖 `effective_style_prompt_builder_test.dart` **10/10 原樣通過**——本案只動 server prompt，client builder 一字未碰，**byte-for-byte 鎖實際未破**（比設計文件保守假設的「知情破鎖重立基準」更強，如實記載）；quick mode 測試零變更通過（quick 用獨立 `QUICK_SYSTEM_PROMPT`，規格 #3 天然成立）。

**過程透明**：`a6bc654` 曾帶著 index_test 一個紅燈 push（字串鎖釘舊接線 `replySegments: safeRecommendationSegments`），同分鐘內 `4143895` 修復——紅燈期間僅字串鎖測試紅，無行為缺陷；prod 部署的 code 本身一致。

**審查重點建議**：

1. 球清單語意：trailing partner run + 空 run 回退最近 10 則——「我已回一半再分析」案例的 sourceIndex 語意是否可接受（index 對 run 計，回退清單時可能與模型認知偏移；display 主鍵是 sourceMessage，`analysis_screen.dart:4372`）。
2. Contract 誤殺風險：文字回查的 ≥4 字 substring 門檻、短訊息（「好啊」「哈哈」）球的修復成功率；防衛路徑（球清單空）只驗形狀是否夠保守。
3. 三層回退與既有 precedence 互動：`replies[pick]` 優先於 segment 合併版（既有行為，測試已釘）；全 drop 時 content 用 drop 前合併版的位置（ensureNonEmpty :segmentMappedContent / Step 3 :segmentRecommendationContent）是否漏。
4. Prompt 一致性：§1.2/1.3/1.5/vision reminder/schema 範例五處同步後有無殘留反向拉力（「精簡」「一句總回」類指令）；§1.3 ✅ 範例與強制式的「同一片段=同一球」調和是否清楚。
5. Stream contract 措辭是否會讓模型在單球時硬湊多段（regression 方向：N=1 不變）。
6. Golden case（行程/電量/吃飯三球 → 3 段）為 **TF 行為驗收**，單元測試只能鎖 prompt 字串與 sanitizer——server-only 變更已隨 push 自動部署，**現有 TestFlight build 即可測**（client 零變更，無需新 build）。

**Round 1（2026-06-12）= REVISE_REQUIRED（0 P0 / 0 P1 / 2 P2）**：
- [P2a] 規格 #4 claim 不成立於常見路徑：Step 3 `replies[pick]` 優先於 segment join——模型 replies 仍逗點大句而 segments 正常時，舊 client content 還是逗點串；原測試用 `recognizeOnly: true` 繞過常見路徑，證據力不足。
- [P2b] source contract 漏交叉驗證：`sourceIndex` 合法時不檢查 `sourceMessage` 是否真屬該球——錯位引用/幻覺引用可流出（UI 引用主鍵是 sourceMessage）。
- Codex 驗證成立的 claims：球清單三模式抽取 / contract gating / 三呼叫點接線 / prompt 五處同步無殘留反向拉力 / quick 獨立不動 / Deno 335 全綠（Codex 自行重跑）。Flutter style-pair 鎖因 sandbox 唯讀無法重跑，採實作方證據。

**Claude 修訂（同日 `b14ea0c`）**：
- P2a：兩輸出點（ensureNonEmpty + Step 3）改「contract 後 ≥2 段且 pick 未 remap → content = 段落換行 join」；單段維持既有 precedence（守規格 #2 N=1 現狀）。contract 段只可能來自 pick 未 remap 的 preferred segments 或 safe pick 自己的 replyOptions messages，無 pick 錯配風險。
- P2b：indexValid 時交叉驗證——message 與 index 球不符 → 回查別球修 index（message 是 UI/#13 主鍵，信 message）；全都匹配不到（幻覺）→ 以 index 球 canonical 回填 sourceMessage。兩方向都保證流出真實引用。
- 測試：新增 5 案（P2a 多球 join + N=1 guard；P2b 修 index / canonical 回填 / fragment guard）；全套 **340 passed**。

**Round 2（2026-06-12）= APPROVED（0 P0/P1/P2）**：Codex 驗證 r1 兩 P2 解除——P2a 兩輸出點對稱（ensureNonEmpty `post_process.ts:595` + Step 3 `:729`）、N=1 precedence 測試鎖住、pick remap 路徑不受影響（preferred segments 僅在 pick 未 remap 時使用）；P2b 交叉驗證三分支完備（同球/fragment 通過、別球修 index、全不 match canonical 回填，`:216`）。Codex 自跑全套 `340 passed / 0 failed`。

最終 commits：`1fd4f5c` + `a6bc654` + `4143895` + `b91ee77` + `0a39621` + `b14ea0c`。

Close Condition: ~~Codex 實作雙審 APPROVED~~（達成）+ golden case Bruce TF 實測（一球一回體感）+ Eric 確認。

---

## [2026-06-11] Smoke 兩修（quota 429 分流 + 實扣常駐）— Codex 實作雙審
Status: APPROVED（Codex r2 2026-06-11 — 0 P0/P1/P2；r1 兩 P2 驗證解除。可回 Bruce；⚠️ client 修須新 TestFlight build 才測得到）
Request-Type: review
Raised-By: Claude
Owner: Codex (實作雙審) → Eric/Bruce (APPROVED 後 dogfood)
Scope: quota / paywall / 429 / analyze UI（高風險區）— client only，server 免改
Branch/Commit: `main` @ `de7b1bb`（P1）+ `12b5895`（P2）；計畫 `docs/plans/2026-06-11-smoke-quota-display-fix.md` @ `d8604ae`

**P1（de7b1bb）quota 429 分流升級卡**：
- 根因鏈：retryFull 撞 429 保留 preview → failedAfterRecommendation → `_streamRetriesRemaining` 對 upgrade 落 0 → 「無法再重試」；legacy `_runFull` generic catch 同病。
- **計畫外發現**：ADR #19 `buildQuotaExceededPayload` 無條件雙 limit，client 三處 429 解析 `dailyLimit != null` 先判 → 月爆誤報日。修法：收斂單一 `_quotaExceptionFrom429`，雙 limit 用 `monthlyRemaining < quotaNeeded` 判別（server 月先查），無法判別偏 monthly；exceptions 補 `remaining`/`quotaNeeded`。
- notifier `QuotaExceededInfo` 入 state（兩條失敗路捕獲、全清空點配對）；UI 分流 `QuotaExceededUpgradeCard`（剩 N/需 M + 查看方案接 `_showPaywall`）。

**P2（12b5895）實扣顯示常駐**：
- `AnalysisUsageSummaryLine` 常駐結果區，讀 `rawResponse['usage']`（隨快照持久化，回看顯示）；顯示條件與 SnackBar 一致；「剩餘」為快照當下值（已註記非即時）。

**測試證據**：notifier quota 6 案 + service 雙 limit 判別 3 案 + widget 升級卡 3 案 + 常駐行 6 案；targeted 全綠；`flutter analyze` 乾淨（僅既有 `test/visual_proof` info）。

審查重點建議：429 判別 heuristic 的邊界（opener 雙 limit + quotaNeeded=0、remaining 缺失 fallback）、quotaExceeded 清空點是否漏（殘留舊卡）、P2 顯示條件與 hydration 去重互動、快照 remaining 過期語意是否可接受。

**Round 1（2026-06-11）= REVISE_REQUIRED（0 P0 / 0 P1 / 2 P2）**：
- [P2] fresh-start quota 429（failedBeforeRecommendation）notifier 有設 quotaExceeded 但 screen 兩個 handler 沒鏡射 `_quotaExceededInfo` → 不顯示新升級卡（仍走舊 error 卡 + paywall，不會回到「無法再重試」，但分流不完整）。
- [P2] `_showPaywall` 無重入防護，quota 卡新增高頻入口，快速連點可 push 多個 paywall route。
- Codex 驗證成立的 claims：429 heuristic 對 server 三種 payload（單 monthly/單 daily/雙 limit）正確；opener 429 走 OpenerService 自己解析、不受影響；quotaExceeded 清空點主路徑完整；failedAfter 卡互斥正確；P2 顯示條件與 SnackBar 一致、Map round-trip 安全。

**Claude 修訂（同日）**：兩個 failedBeforeRecommendation handler（hydrate + live）quota 分流——非 null 時設 `_quotaExceededInfo` + `_resetErrorState()`（不走 generic error 卡），render gate 擴 `_fullErrorMessage != null || _quotaExceededInfo != null`；`_showPaywall` 加 `_isPaywallInFlight` guard（try/finally 復位）。targeted 42 案重跑全綠。

**Round 2（2026-06-11）= APPROVED（0 findings）**：Codex 驗證 r1-P2a/P2b 解除——before-rec 兩 handler 對稱鏡射 + `_resetErrorState` 無 banner 死路（`analysis_screen.dart:785-810/:3674-3700/:5119`）、render gate 與卡片互斥正確（:5810-5826）、`_isPaywallInFlight` guard try/finally 復位且覆蓋全部 11 個 `_showPaywall` 呼叫點（:216-227 + :271/:614/:2564/:3703/:3729/:3790/:3797/:3805/:5823/:6165/:6391）。

Close condition 達成：APPROVED → 回 Bruce。最終 commits：`de7b1bb`（P1）+ `12b5895`（P2）+ `e241471`（r1 修訂）。

---

## [2026-06-11] 候選 #12 一球一回 replySegments — Codex 設計把關（實作前）
Status: APPROVED（Codex r2 設計綠燈 2026-06-11 — 0 findings，r1 四項全數驗證解除；實作另開 item 走高風險雙審）
Request-Type: review
Raised-By: Claude
Owner: Codex (design review) → Eric/Claude (依結論定實作)
Scope: analyze-chat prompt/schema（高風險區）+ 破 style-pair byte-for-byte 鎖（eebef91）— 設計階段，無 code 變更
Branch/Commit: `main` @ `728f670`（設計定案文件）

**請 Codex 審**：`docs/plans/2026-06-11-reply-segments-one-ball-one-reply-design.md`（46 行，含七點規格 + client 現況事實 + #13 接口預留）。

審查重點（依設計文件）：

1. 七點規格有無設計層面的洞——特別是 #1（cap 4 溢出挑球規則是否會讓模型輸出不穩定）、#4（舊 client fallback 改換行 join 的相容性）、#5（prompt 目標式 audit 範圍是否足夠/過寬）。
2. **破鎖風險**：prompt 變更破 style-pair 主風格 byte-for-byte 鎖（2026-06-10 eebef91）。設計文件已明寫知情破鎖 + 重新驗證義務（規格 #6）；請確認驗收清單（golden case 3 球 3 段 + N=1 回歸 + quick 不變 + style-pair 重驗）是否完備。
3. #13 接口預留（每段穩定非空 `sourceMessage`/`sourceIndex`，schema 層驗證）是否足以支撐「採用回填」而不過度設計。
4. Client 現況事實已驗證（`ReplySegment` model + 分段渲染 + 每段複製鈕都已存在），本案主戰場限 server prompt/schema——請確認「幾乎不動 client」的範圍判斷沒有遺漏。

**Round 1（2026-06-11）= REVISE_REQUIRED（0 P0 / 2 P1 / 2 P2）**：
- [P1] cap 4 與現況硬衝突：既有全鏈 cap 3（client `analysis_models.dart:241` `.take(3)`、server `post_process.ts:136` `slice(0,3)`、prompt `index.ts:1464`、`index_test.ts:257`）。改 4 動四處且舊 client 掉第 4 段——「幾乎不動 client」前提不成立。
- [P1] 規格 #5 audit 範圍過窄：實際讓 cap/source 生效的是 `post_process.ts` `sanitizeReplySegments`（:130/:443/:580），只審 prompt 會漏行為決定層。
- [P2] #13 source contract 不可驗收：現況 sanitizer 只驗 `reply` 非空，`sourceIndex` 可省略、`sourceMessage` 可空（:142/:147/:155），缺 source 處理未定。
- [P2] 驗收清單缺 cap overflow + schema validation case；style-pair 重驗未明列 golden（鎖在 `effective_style_prompt_builder_test.dart:124`）。
- Codex 已實際對照 client：ReplySegment model / 解析 / 分段渲染 / 每段 copy 確認存在。

**Claude 修訂（同日，已入設計文件）**：#5 audit 範圍加 sanitizer 層；#13 補三層缺 source 規則（sourceIndex 回查修復 → drop 該段 → 全 drop 回退單段，絕不空 source 流出）；驗收清單擴充 cap overflow + schema case + 明列 style-pair byte-for-byte 鎖測試重新基準化。

**Eric 拍板（2026-06-11）**：**cap 3**——與現況全鏈對齊、client 完全不動、golden case 3 球已滿足；cap 4 增益無真實案例。規格 #1 已改寫定案。

**Round 2（2026-06-11）= APPROVED（0 P0/P1/P2）**：Codex 驗證 r1 四項全數解除——cap 3 與 `.take(3)`/`slice(0,3)`/prompt 對齊（`analysis_models.dart:241`、`post_process.ts:136`、`index.ts:1464`）；audit 範圍含 sanitizer 層（`post_process.ts:130/:443/:580`）；#13 三層 source 規則 + `quotedReplyPreview` 欄位存在（`message.dart:23`）；驗收清單完備、style-pair 鎖測試在案（`effective_style_prompt_builder_test.dart:124`）；「幾乎不動 client」在 cap 3 下成立（`analysis_screen.dart:4316/:4422`）。

Close condition 達成：設計 APPROVED。實作另開 item 走高風險雙審（規格 #6 雙軌）。

---

## [2026-06-11] ADR #19 字數合併計費 — Codex 設計把關（實作前）
Status: CLOSED（Eric 確認 2026-06-11 深夜；全 close condition 達成：設計把關 APPROVED + 實作 land + 實作雙審 APPROVED 0 findings + Eric 確認）
Request-Type: review
Raised-By: Claude
Owner: Codex (design review) → Claude (實作) → Codex (實作雙審) → Eric (關閉)
Scope: quota / Edge schema / AI cost（高風險區）— 設計階段，無 code 變更
Branch/Commit: `main` @ ADR #19（`docs/decisions.md`）

Eric 拍板（2026-06-11）：analyze-chat 扣費改全對話字數合併 `ceil(總字數/200)`、整次最少 1。
本 item 是**實作前設計把關**。

**Round 1（2026-06-11）= REVISE_REQUIRED**：
- [P1] 原 fallback「缺 `previousAnalyzedCharCount` 即整段全額計費」使 server-first 不安全（舊 client 補 5 字可能被扣 11 則 / 觸 429）。
- 其餘：quotedReplyPreview 計費定義缺失、UTF-16 需明寫不 normalize、recognizeOnly 日上限需 server-side atomic gate、單一 helper + requestMessages baseline 前提。

**Claude 修訂（同日）**：ADR #19 規格 #1 改三層 fallback（新欄位 → 舊欄位推導 baseline 只扣字數差 → 全缺失才全額+log）、#4 補 normalization/zero-width 定義 + mirror tests、#5 安全論證改依賴推導 fallback、新增 #7 quotedReplyPreview 不計費、#8 單一 helper + baseline 對應 requestMessages、recognizeOnly 閘門明寫 server-side atomic + vision 前擋。

**Round 2（2026-06-11）= REVISE_REQUIRED（剩 1 P1）**：
- [P1] summary/clipped payload：舊 client 長對話壓縮後 requestMessages 可能只剩 10 則但 N=30，原規格把 N>payload.length 當越界全額——對舊 client 是合法路徑，仍會隱形多扣。
- Codex 確認其餘 r1 修訂全部到位（UTF-16/quotedReplyPreview/helper 單一化/requestMessages baseline/recognizeOnly atomic gate）。

**Claude 修訂（同日）**：規格 #1 fallback 加 clipped 分支——N>payload.length 且有 `conversationSummary`/clipped 訊號 → user-safe：baseline=當次 payload 全字數、只扣 floor 1、log `legacy_count_exceeds_payload_clipped`；無訊號才全額+log。已驗證 client clipped 路徑存在（`analysis_service.dart:1080-1287`）。測試矩陣同步加 clipped 案。

**Round 3 確認（2026-06-11）= 設計把關通過，無剩餘 P0/P1**：
> Codex 確認 ADR #19 @ `ee20949`：r2 P1 已補到位，clipped/summary 舊 client 路徑改為 user-safe floor 1 + log；無剩餘 P0/P1。設計綠燈，Claude 可開實作；實作後另跑高風險雙審。

**Round 4 = r3 參數修訂 + 定案（2026-06-11 PM~晚，夥伴新需求 → Eric 全數拍板，規格凍結）**：
- 公式改 `clamp(ceil(字數/40), 1, 10)`、400~2000 緩衝帶一律 10 則、**>2000 一律固定 20 則需確認**（乙案）。
- 預覽改靜態區間文案「依對話複雜度使用 1–10 則」（不再 pre-flight 精確值）；分析後顯示實扣。
- 月額度 30/300/800 不調（cap 10 推理：各層保證次數均高於舊制，原「燒快 5 倍」係忽略 cap 的誤導）。
- 邊界 4 條：額度檢查先於確認框 / client 預警+server 守門（`confirmation_required` + `confirmedOvercharge` 旗標）/ 舊 client >2000 → user-safe cap 10 + log `legacy_over2000_capped` / soft_cap 每次分析各自算。
- r2 三層 compat fallback、字數定義（UTF-16、quotedReplyPreview 不計費）**全部保留不重開**。
- 全文見 `docs/decisions.md` ADR #19 🔴 r3 + 🟢 r3 定案區塊。

**Round 5 = Codex r3 把關第一輪（2026-06-11 晚）= REVISE_REQUIRED（0 P0 / 3 P1 / 2 P2）**：
- [P1-1] 缺 client capability contract：首次分析無 baseline 欄位，新 client >2000 可能被誤判 legacy cap 10、繞過確認。
- [P1-2] legacy cap 10 與 r2 clipped floor 1 有 precedence 衝突，可能把 1 抬成 10、重開隱形多扣。
- [P1-3] `confirmedOvercharge` 未綁 payload、無 idempotency → 確認後內容變更/重送可錯扣或重扣 20。
- [P2] 40/400 邊界重疊；保證次數文字須限定 ≤2000。

**Claude 修訂（同日）**：定案 #6 加 capability contract（`billingProtocolVersion: 3` 必送、無訊號才算 legacy）+ legacy precedence 三段順序（clipped floor 1 永不被 cap 覆蓋）；定案 #5 加確認綁定 `billableChars`/hash（不符回新 `confirmation_required`）+ idempotency key；公式改整數閉區間；保證次數加 ≤2000 前提 + 禁止 pricing/送審文案裸引用。

**Round 6 = Codex r3 把關第二輪（2026-06-11 晚）@ `ad10718` = APPROVED，設計綠燈**：
> 3 P1（capability contract / legacy precedence / 確認綁定+idempotency）+ 2 P2（閉區間 / ≤2000 前提）全數確認解除，無新問題。實作建議：確認綁定優先 payload hash（已記入 ADR 定案 #5）。註：本輪未審 worktree 既存 code 草稿（index.ts / billing.ts）。

**APPROVED 後補遺（2026-06-11 晚 · 夥伴終確認）**：補 **4000 字硬上限**（4001+ 一律 reject「請分批」不扣費、新舊 client 一視同仁；20 則帶收窄為 2001~4000）。背景：pricing-final 原寫 5000 但 code 從未實作（grep 驗證），原緩衝帶上不封頂 = 成本洞。屬風險收斂、無新計費路徑，不重開設計輪，**實作雙審一併驗收**；實作 commit 同步把 pricing-final 5000 改 4000。

**Round 7 = 實作 land（2026-06-11 · Claude）**：

- **Server** `f6e8eec`：billing.ts 全改寫（分段帶閉區間 / capability contract / legacy precedence：clipped floor1 永不被 cap 覆蓋 / legacy >2000 cap10+log）+ index.ts 閘門順序「則數 → 4001+ reject(400 不扣費) → 額度 429 → 功能 403 → 確認 409」+ overcharge_claims.ts idempotency（claim-at-gate，失敗方向 = 用戶免費 user-safe；RPC 不可用 fail closed 503 不扣費）+ migration `20260611120000`（claim RPC，INSERT ON CONFLICT 原子、60min replay window）。pricing-final/cost-optimization 同 commit。死碼清除：index.ts 舊 countMessages + index_test.ts 殭屍複本。
- **Client** `f095603`：MessageCalculator 鏡像 + JS/Dart 共用 fixture 對拍（`test/fixtures/adr19_billing_mirror_vectors.json`，生成器 `tools/billing/`，含 sha256("abc") 外部常數釘）+ 靜態區間預覽 / >2000 確認框（精確 20、額度先行、Free 日上限 15<20 自然擋）/ >4000 本地擋 / 實扣 toast + Hive `lastAnalyzedCharCount`(field 16) + `billingProtocolVersion:3` 全請求必送（wire-contract tests）。
- **測試證據**：Deno 323 passed（billing 41 + claims 5 含內）；Flutter calculator 17 + dialog 13 + notifier/hydration 61 + analyze modes 29 全綠。
- **設計取捨（雙審重點）**：①hash mismatch 不做 client auto-rebind，409 fail-loud 要求重按分析（防拿舊確認綁新內容；mirror 漂移屬 bug 須 fail loud）②4000 上限作用對象 = billableChars（計費字數差），payload 總長另有既有 20000 守門 ③Dart/JS trim 對 U+0085 行為差異 = 已知接受（409 自癒路徑）④replay 時 messagesUsed 回 0（該次呼叫實扣 0，原確認已扣 20）。
- **部署順序**：edge 已隨 push 自動部署（舊 client 走 user-safe legacy 路徑，server-first 安全 = 規格 #5）；**migration 必須在新 App 上架前手動 `supabase db push`**——未套用前新 client 送確認會收 503 不扣費（fail closed，無扣費風險）。

**Round 8 = Codex 實作雙審（2026-06-11 深夜）= APPROVED，0 P0 / 0 P1 / 0 P2**：

> 8 條 implementer claims 逐項確認成立（claim-at-gate user-safe / 409 不 auto-rebind / 4000 上限作用 billableChars + 20000 payload 守門 / replay messagesUsed=0 / hash+billableChars 雙比對 / TTL 60min / U+0085 已知接受 + 409 自癒 / skipPreview 仰賴 server 守門），各附 file:line 證據。測試矩陣覆蓋足夠；Codex 自行重跑 Deno billing+claims 46 passed 驗證；Flutter targeted tests 因 sandbox 唯讀無法重跑，採實作方提供之 120 全綠證據（queue R7）。

**狀態**：**實作雙審 APPROVED → WAITING_ON_ERIC（close condition 最後一關：Eric 確認後關閉）**。計費新制具備 dogfood 條件（雙審證據在案）；⚠️ 唯 migration `20260611120000` 須在新 App build 發 TF 前手動 `supabase db push`。

Close Condition: Codex r3 設計把關通過 + 實作 land + 實作雙審 APPROVED + Eric 確認後關閉。

---

## [2026-06-10] Style Pair（主+副互動風格）— Codex 把關
Status: OPEN
Request-Type: review
Raised-By: Claude
Owner: Codex (review) → Eric (確認後關閉)
Scope: AI prompt 行為（高風險區）+ Hive schema 演進
Branch/Commit: `main` @ `eebef91`

依 `docs/plans/2026-06-10-style-pair-design.md` 全鏈落地（一個 commit `eebef91`）。
動到高風險區 `EffectiveStylePromptBuilder` → 需 Codex review evidence 才能說 dogfood/build safe。

Review 重點（按風險排序）:

1. **Prompt 回歸**：主-only 輸出 byte-for-byte 不變（`effective_style_prompt_builder_test.dart` 有完整字串快照鎖）；主+副 新格式「以X為主、Y為輔；主全力 prompt。副點綴 prompt」+ 降權措辭是否會被 LLM 平均掉。
2. **Hive 零遷移**：UserProfile field 6 / PartnerStyleOverride field 5；legacy write-only adapter 測試證明舊 binary 讀出 secondary=null。
3. **原子合併**：partner 有主 → (主,副) 整組贏，含「partner 主-only 時全域副不得漏入」防混搭 case。
4. UI 點擊狀態機 5 規則 + 不變量（`style_pair_draft_test.dart`）。

Evidence: 177 targeted tests green（user_profile unit+widget+integration spec2）、`flutter analyze` clean。

Close Condition: Codex review APPROVED + Eric 確認。

---

## [2026-06-09] Pre-Launch UI Audit Round 1 — follow-ups
Status: CLOSED
Request-Type: handoff
Raised-By: Claude
Owner: Eric (decided) / Claude (next-session execution)
Scope: copy / UX / paywall / onboarding / analyze-chat error contract
Branch/Commit: `main` @ `352aebb`

Closed by Eric (2026-06-09): A-01 onboarding wiring DONE + Codex APPROVED (`295bd2d`); P2 analyze.error sanitize DONE + Codex APPROVED (`1a085f4`). 需 TestFlight rebuild 後 dogfood；無 Edge deploy。

Round 1 (low-risk cleanup) DONE + pushed (`b2b6f6c..58ebf71`), all `flutter analyze` clean, 81 targeted tests green:

- COPY-01 額度訊息去「免費」; COPY-02 分析/串流錯誤全去工程語彙; DATA-01 opener 錯誤不漏原始例外; DATA-02 opener loading 教練口吻; B-01 opener SafeArea; C-01 image picker 深底對比; H-03 booster 工程語彙。
- Codex evidence: 3 rounds. `task-mq6hawar` + `task-mq6hf9ct` REVISE_REQUIRED (COPY-02 漏網串流字串) → 已全清。

Eric decisions (2026-06-09):

- **G-03 = CLOSED false positive.** 雷達圖實際存在且 gated Starter/Essential (`analysis_screen.dart:5702`, `// 五維度剖析 (Starter / Essential only)` + `subscription.isPremium`); `dimension_radar_chart.dart` / `partner_radar_summary_card.dart` 渲染; pricing-final/paywall 承諾正確。audit G-03 grep 只搜 `lib/features/report` 故誤判。不改 code/docs。
- A-01 onboarding + analyze.error sanitize 不混入本輪低風險 cleanup。

Action Items (next session, each its own scoped task + Codex review):

- [x] **A-01 onboarding wiring** — DONE @ `295bd2d` (pushed). post-login first-run，未登入 auth gate 維持同步不變。redirect 決策抽成純函式 `resolveAppRedirect`（`routes.dart:34`）+ `OnboardingService.isCompletedSync` 記憶體快取（`main()` 啟動時 `load()` 預載，避免回訪用戶冷啟動被誤導回 onboarding）。Tests: 17 redirect-matrix unit + 6 router widget 全綠；`flutter analyze` clean。Codex read-only review = **APPROVED (no P0/P1/P2)**，逐項驗證 5 條 invariant + 無 redirect loop + 快取 ordering 正確。（注：`onboarding_test.dart` demo enthusiasm label 失敗為既有 stale rot，clean main 亦失敗，非本次 regression。）
- [x] **P2 analyze.error 伺服器 message sanitize** — DONE @ `1a085f4` (pushed)。`analysis.error` 串流事件改走既有 `_isReadableUserMessage` 閘門（含中文才顯示，與 HTTP 路徑 `_mapAnalysisHttpError`、opener DATA-01 同一套），非中文/工程字串回固定繁中 fallback「這次分析沒順利完成，請稍後再試一次。」；raw message 改走 `_debugLog`（僅 kDebugMode），不進 UI。只重寫 `message`，`code`/`recoverable`/`retriesRemaining` 原封不動，quota/paywall 路由不被誤吃。未改 Edge Function、未改 quota 邏輯、未加「不扣額度」承諾。Tests: 既有 `'Quota failed'` 測試改為驗 fallback + 保留 code/retries，另加 可讀中文原樣／JSON 片段→fallback／缺 message→fallback 共 4 分支，全綠（28 passed）；`flutter analyze` clean。Codex read-only review (`task-mq6m4gzz-airaso`, scope `23cc3a0..1a085f4`) = **APPROVED (no P0/P1/P2)**，逐項驗證 sanitizer + 測試 + Edge emitter/contract（`analyze-chat/index.ts`、`stream_handler.ts`、`reframer.ts`）。（注：`analysis_error_widget_test.dart:135` `parses RATE_LIMITED code` 失敗為既有 stale rot，clean `23cc3a0` 亦失敗，非本次 regression。）

Close Condition:

- 兩個 action item 各自 land + Codex 評估，Eric 確認後關閉。

---

## [2026-06-07] Preflight Secret Gap + 409 Coverage (C5/C6)
Status: OPEN
Request-Type: decision
Raised-By: Codex
Owner: Eric (decided) / Claude (carry follow-ups)
Scope: subscription / 429 / ops / launch-hardening
Branch/Commit: `main` @ `9cf72ad`

Decision (Eric-final, 2026-06-07):

- **C1 (P1)** — fixed in `9cf72ad`. No remaining code-level P0/P1 per CC second review.
- **C5** — Eric accepts short-term option (a): GitHub secret smoke + Supabase secret-name check + manual GitHub ↔ Supabase sync discipline.
- This is **accepted debt, not "safe / launch-safe"**: the shipped preflight still cannot verify the Supabase live secret *value*.
- **C6** — handler-level 409 integration test deferred as **P2**. Helper / source / stream tests pass; the 409 gate still lacks handler-level coverage.

Explicit non-claims:

- Do NOT claim safe dogfood / safe build from this code review alone.

Action Items (deferred to launch / App Review final hardening — do NOT open in red zone):

- [ ] Add post-deploy **live runtime probe** that verifies the Supabase live secret value (closes the C5 gap).
- [ ] Add **handler-level 409 integration test** (C6, P2).

Close Condition:

- Both follow-ups landed and Eric confirms launch-hardening for this scope is complete.

---

## [2026-05-14] Dogfood Frontline Stabilization
Status: OPEN
Request-Type: handoff
Raised-By: Codex
Owner: Claude
Scope: bug / ops / review
Branch/Commit: `main` @ latest

Question:

- Eric and Bruce are dogfooding TestFlight. Claude/CC should handle first-line bug reports, while Codex provides read-only review for high-risk fixes.

Current Product Truth:

- Coach 1:1 is shipped into dogfood.
- Current phase is TestFlight dogfood / App Review stabilization.
- Do not treat archived roadmap labels or old planning tracks as current default work unless Eric explicitly asks.

Recent Context:

- Opener, paywall, quota, RevenueCat, and subscription sync have had repeated P0/P1 fixes.
- 2026-05-15 Eric accepted keeping the `restorePurchases()` paid-to-free snapshot guard during dogfood; do not "fix" it without an explicit new decision. See `docs/integrations/revenuecat.md`.
- 2026-05-15 auth/logout/delete-account local cleanup patches were reverted after repeated Codex `REVISE_REQUIRED` loops. Do not patch that scope again without a design/failure matrix.
- 2026-05-15 Support URL finding was closed by live evidence: `curl -I -L https://vibesyncai.app/support` returns 301 -> 200 OK.
- `!cc-rotate` is implemented for mobile session rotation.
- `!codex` Phase 1 is implemented as a read-only Discord review gate.
- WSL Codex CLI may still need one-time `codex login --device-auth`; verify with `!codex setup`.

High-Risk Areas:

- subscription / paywall / quota / RevenueCat / 429
- auth / account deletion / Hive persistence
- `analyze-chat` / opener / OCR / Edge response schema
- AI prompt changes affecting quality, safety, token/cost, or App Review stability

Operating Rules:

- If Bruce or Eric reports a bug, acknowledge the reporter and ask for missing repro details if needed.
- For screenshots: inspect and fix if repro is clear.
- For videos: ask for key screenshots, timestamps, expected vs actual, and steps before deep judgment.
- If Eric says "queue it", append the pending intake under this item instead of inventing root cause.
- After a high-risk hotfix commit/push, trigger Codex review before saying it is safe to build/test.

Evidence:

- `docs/snapshot.md`
- `docs/shared-agent-rules.md`
- `git log --oneline -30`
- `docs/bug-log.md` newest 2026-05 entries
- `tools/cc-rotate/README.md`
- `tools/codex-bridge/README.md`

Open Risks:

- RevenueCat sandbox and product mapping still need real-device matrix smoke after each paywall/subscription change.
- Free users must be able to use opener/analyze/coach until quota is actually exhausted.
- Opener/analyze must never show raw JSON.
- Format failure must not charge quota.
- Auth/logout/delete-account/local Hive isolation remains baseline behavior and needs design-first treatment before launch hardening.

Action Items:

- [ ] Keep first-line dogfood bug intake here when Eric is mobile.
- [ ] For high-risk fixes, run Codex review on the actual hotfix range, not blindly `latest`, and record the job/result.
- [ ] Close this item only after Eric says the current dogfood stabilization window is complete.

Close Condition:

- Eric confirms the current TestFlight dogfood bug wave is stable enough to move on.

---

## Recently Closed / Reference

Closed items before 2026-05-14 were intentionally pruned from this live queue. Use git history and `docs/reviews/` files for older review records.

## OPEN — 2026-06-13 stream 形狀守門補強（Codex adversarial 2 high + 2 medium）

**脈絡**：dogfood P0（free/Haiku 分析收尾必炸）root cause 已修＋prod 黑箱驗證 PASS（06954f8，repro 在 tools/voice-benchmark cases/repro_haiku_small.json）。Codex 雙審對該修復 0 否定，但 adversarial 找到同類漏網路徑，需補強＋紅燈先行：

1. **high** reframer.ts absorbReportSection：`result[section] = payload` 未過 coerceRecordOnlyValue——section=gameStage/psychology 等且 payload 為字串可繞過守門。
2. **high** `warnings` 不在守門清單：done finalResult `warnings: "字串"` 會 clobber 陣列，client `as List?` throw。需「array-only key」守門。
3. **medium** enthusiasm float（72.5）→ client `as int?` 仍炸；coerce 時 Math.round。
4. **medium** 巢狀形狀未驗：`psychology.shitTest` 為字串時 client 硬 cast Map 仍 throw。
5. **gate 缺口**（root cause 的測試面）：anchor/黑箱套件加 forceModel=haiku 案例＋「client 形狀」驗證器，免費層模型列入必測。

**判定**：1+2 先做（同一手法：擴大 coerce 守門），3 順手，4 評估範圍（巢狀驗證器 vs client 寬容），5 開工前排。

**Codex 雙審迭代至 approve（2026-06-13）**：11c7052 → r2 needs-attention（1H5M 全實錘：strategy 無守門 high／enthusiasm string score／qualificationSignal bool／healthCheck bool/num／coachActionHint／finalRecommendation 巢狀）→ `01a3eff` ad-hoc 分支翻轉成**宣告式 CLIENT_RECORD_FIELD_SHAPES 表**（client fromJson 硬 cast 的 server 端轉錄，錯型丟欄位走 client 預設、表外放行）→ r3 needs-attention（1H5M：replySegmentsFrom 入口 conform high＋optimizedMessage/myMessageAnalysis/recognizedConversation/dimensions/dogfoodComparison 轉錄缺口）→ `6aff7d8`（新 shape kind recordArray＋replyOptions 動態 key 逐 value conform）→ r4 僅 1M（enthusiasm.level as String?）→ `dbd329b` → **r5 approve（A/B 輪皆無 findings，client 硬 cast 表面全覆蓋）**。每輪 findings 逐條對 client 源碼驗證後才動手，全程紅燈先行，最終 Deno 400 綠。

**1–4 完成（2026-06-13，`11c7052`）**：①absorbReportSection 改走 coerceClientShapeValue（原 coerceRecordOnlyValue 改名）；②warnings 入 ARRAY_ONLY 守門＝字串包單元素陣列、物件丟棄、陣列過濾非字串元素（`[42]` 也炸 client 的 List<String>.from）；③enthusiasm 全寫入路徑 Math.round（metrics heat／record 直寫／done merge record 內 float）；④範圍評估結論＝目標式 server 守門（不做全巢狀驗證器＝過度工程；不等 client 寬容 cast＝要 rebuild 舊 build 不受益，同 06954f8 拍板邏輯）——psychology.shitTest 非物件丟 key（字串語意不可靠，可能說「沒有測試」，誤映射比丟棄糟）＋healthCheck.issues/suggestions 同 warnings 手法（評估時新發現的同家族巢狀漏洞，Codex 清單外）。TDD 紅燈先行 7 條（含 1 條 record 形狀 regression pin），Deno 387 綠。**剩**：⑤anchor/黑箱套件 forceModel=haiku＋client 形狀驗證器（下一案開工前排；本補強 Codex 雙審已 r5 approve，⑤ 純 tools 測試基建免雙審）。

**⑤ 開工計畫（2026-06-14 scoped，Eric 拍板留新 session 執行）**：拆兩塊。
- **(a) client 形狀驗證器（env-free，可純 TDD）＝SHIPPED（2026-06-14）**：reframer.ts 五張表加 `export`（`CLIENT_RECORD_FIELD_SHAPES`／`REPLY_OPTION_FIELD_SHAPES`／`ClientFieldShape`＋`ARRAY_ONLY_FINAL_RESULT_KEYS`／`STRING_ONLY_FINAL_RESULT_KEYS`——後兩張為涵蓋 warnings／strategy／reminder 入口必需，純附加行為中性）。新模組 `client_shape_validator.ts`＝偵測版（只看不改）：`findClientShapeViolations(finalResult)`＋`findRecordShapeViolations(record,shapes,basePath)`，驗 string／boolean／int=Number.isInteger／number／stringArray／record／recordArray；**欄位層 undefined/null 放行**（client nullable cast），但 **recordArray／stringArray 的元素層不放行 null/錯型**（client `.map((m)=>fromJson(m as Map))`／`List<String>.from` 對元素是非 nullable cast）。CLI `tools/voice-benchmark/check_client_shape.ts` 讀 ndjson、取 `analysis.done.finalResult`＋每個 `analysis.reply_option` 走 REPLY_OPTION 表，有 violation 退非零。TDD 紅→綠 17 測（good 合成 fixture 零 violation＋5 bad＋null/undefined 放行＋表外 key 忽略＋dynamic replies/replyOptions），合成 fixture（**未用既有 baselines 當 good**）。全套 Deno 474 綠、`deno check` 乾淨。CLI 實證：`gate4_golden_anchor`（守門前 psychology 裸字串）FAIL exit1、`case1_chengwei`（psychology=object）PASS exit0＝坐實「baselines 不可當 good fixture」。**純 tools 測試基建、無任何 prod runtime import（只 test＋CLI 引用）＝免 Codex 雙審**。
- **(b) forceModel=haiku 真實 baseline ＋接 CI（需 bench 環境，Eric 跑）＝待辦**：用 (a) 的 CLI 當斷言。`cases/repro_haiku_small.json` 已有 forceModel=haiku；跑 haiku baseline ndjson → 過 `check_client_shape.ts` 必須零 violation → 存進 baselines/ 當免費層 must-test 錨 → check_contract.sh 旁併 check_client_shape 一起跑（現有 baselines 多為守門前產物會 FAIL，故 wiring 待 fresh haiku baseline 才接）。
- **(b) forceModel=haiku 真實 baseline ＋接 CI（需 bench 環境，Eric 跑）**：`cases/repro_haiku_small.json` 已有 forceModel=haiku；用 `supabase functions serve analyze-chat --no-verify-jwt --env-file ~/.vibesync-bench.env` 跑出 haiku baseline ndjson → 過 (a) 驗證器必須零 violation → 存進 baselines/ 當免費層 must-test 錨 → check_contract.sh 旁併 check_client_shape 一起跑。haiku＝最易吐壞型，列入必測才補上 root cause 測試面。
