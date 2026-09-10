# 練習室「她們的動態」配圖 V2：個人攝影風格與圖文忠實度——優化報告與實作計畫

一句話：**讓 100 位角色各自有固定的「拍照習慣」，每張圖先忠於當篇貼文，再由相容的拍攝配方提供變化；以 `MOMENT_IMAGE_VISUAL_V2_PERCENT` 旗標分流、預設 0，V1 路徑逐位元不變。**

- 日期：2026-09-10
- 查核基準：`PoYuTsai/VibeSync main@957cdbb`（2026-09-08 報告的基準是 `ed6eaa5`，差異見 §1.3）
- 前身：2026-09-08《圖片多樣化與個人風格：優化實作報告》與 2026-09-01 附件 `practice-moments-image-style-v2-final.md`。本文取代前者：保留其裁決、以現行 HEAD 重新查證、修正細節，並補上可直接分工的實作計畫。
- 對應文件：`docs/plans/2026-08-25-practice-moments-generated-images.md`（生圖架構）、`docs/practice-moment-image-activation-runbook.md`（kill switch 與健康線）、`docs/plans/2026-08-25-practice-moments-image-duplication.md`（撞圖研究）
- 本次交付：唯讀原始碼查核＋本文件。未修改產品程式、未部署、未呼叫付費圖片 API、未讀取正式環境圖片與費用。

---

## 0. 給 Eric 的三句話

1. 問題不是「大家都拍咖啡」，而是「不管誰拍什麼，都像同一個攝影師」：全域前綴、場景指令、62 句題材模板三處，在生圖之前就把手機質感、柔暖光、台北、置中構圖釘死了。
2. 解法是三層分工：貼文事實決定「畫什麼」；角色固定的主／次配方與兩個取景習慣決定「怎麼拍」；相容性篩選後的種子抽選決定「這一張的變化」。不換模型、不改發文節奏、不改 UI、零 migration。
3. 分三個 PR 落地，旗標預設 0；先做 80 案 160 張離線對照與縮圖／角色連續性評分，過門檻才進 10% 有限試行。你要在真機確認的是：**看得出不同的人在拍，但同一個人還是同一個人。**

---

## 1. 查證結果（以 `main@957cdbb` 為準）

### 1.1 三處固定風格來源（與 9/8 報告相同，位置已更新）

| 來源 | 位置 | 現況 | 影響 |
| --- | --- | --- | --- |
| 全域前綴 `MOMENT_IMAGE_STYLE_PREFIX` | `moments_image_gen.ts:169` | 固定 amateur smartphone、Taipei、soft and slightly warm、lifted shadows、lens softness、grain、中央 4:3 安全區 | 角色差異在生圖前就被統一 |
| 場景指令 `describeScene()` | `moments_image_gen.ts:363-376` | 規則 5 再要求 phone camera、Everyday Taipei life | 只改前綴仍會被場景描述帶回原風格 |
| 題材模板 `THEME_SCENE_LINES` | `moments_image_gen.ts:185-316` | 62 句同時當 DeepSeek 的 `sceneHint` 與失敗退路 | 模型成功時也受固定杯子／桌面／暖光影響；失敗時整句照用 |

其餘現況：`MomentImageJob` 只有 `profileId / isoDate / slot`（`:83`）；handler 持有 `day_part` 但 job 不帶；場景呼叫 `maxTokens: 150`、`temperature: 0.4`、`jsonMode`、10s（`:386-389`）；fal 固定 `landscape_4_3`、單張、`enable_safety_checker: true`、seed 混入 attempt（`:429-438`）；fal 請求體自 `:440` 起；失敗走 release，最多 2 attempts。

### 1.2 這次新確認、9/8 報告沒寫的事（實作前必須知道）

| 項目 | 事實 | 對 V2 的意義 |
| --- | --- | --- |
| 配圖資格閘門 | `wantsImage = momentImagesForTags(theme.imageTags).length > 0 && roll < IMAGE_PROBABILITY(0.2)`（`moments_schedule.ts:42, 982-984`） | 62 題材中 **3 個沒有 `imageTags`**（`night_thoughts`、`interest_current_fixation`、`money_habit`），現行排程永遠不會為它們生圖。V2 場景規格：62 個都要過 parity 測試（向前相容），設計投入集中在 59 個 |
| 自拍 sentinel | 只有「候選收斂後只剩自拍」才走圖鑑照片、不生圖（`moments_handler.ts:203-208`）；帶 `self` 標籤的 4 題材（`weekend_outing`、`workout_done`、`style_note`、`coach_day`）同時帶其他標籤，仍會進生圖 | 這四個題材的場景候選同樣不得畫人；不需要為它們另開分支 |
| 寵物線索 | 排程層已有 `hasPetOwnerClue()`（`moments_schedule.ts:345`）：只吃明確或日常飼主標籤，`pet_groomer` 沒線索就不排飼主題材 | V2 投影直接沿用它決定 `pets` motif，**不再從興趣標籤猜一次**；Sasha（074，寵物美容師、興趣有「寵物」但無飼主線索）因此不會拿到 `pets` motif |
| 名冊新增欄位 | 9/8 起 `PracticeGirlProfile.photoScene`（她大頭照的描述，server-only）；022 lifestyle「顧貓→顧狗」 | `photoScene` 是人物照片描述，**必須列入投影排除欄位**；moments 自拍分支指令改了，但與生圖路徑無關 |
| 預算鏈與限流 | 場景 10s＋fal 60s＋下載 15s＋上傳 15s＝100s ≪ 租約 180s；孤兒帳本寬限 600s 也依此鏈；每人 3/min、20/day；每請求最多排 2 個 job；每 slot 2 attempts | V2 場景呼叫回更大的 JSON，但**不得**動 `MOMENT_IMAGE_SCENE_TIMEOUT_MS`；只調 `maxTokens` 並實測延遲 |
| Freshness 補位 | feed 最新可見貼文超過 24h 才觸發（`moments_handler.ts:407`），走同樣的 slot／attempts／配圖機率 | 觀測要分「一般排程」與「補位」；補位不是額外流量來源 |

### 1.3 測試與 CI 的三個坑

1. **CI 白名單**：`.github/workflows/flutter-ci.yml` 的「Run Edge contract tests」逐檔列出 deno 測試；新測試檔不加進白名單＝從未在 CI 跑過。PR A/B/C 每新增一支測試都要同步加。
2. **原始碼守門** `moments_generated_only_source_test.ts`：`moments_handler.ts` 可執行碼不得出現 `fallback`／`Fallback`／`canned`；`moments_image_gen.ts` 不得 import `./prompt.ts`／`./hint.ts`／`./moments_memory.ts`／`./debrief_card.ts`，不得出現 `fallbackImage`／`placeholderImage`／`DEFAULT_IMAGE`／`canned`，且 `userId` 出現次數受限。因此 V2 的「退路」一律以 `degraded`／`safe` 命名；新模組要加進這支守門，而不是繞開它。
3. **V1 契約已被釘住**：`buildImagePrompt` 必須是「STYLE 前綴＋場景句」、場景 user message 含 `sceneHint:`、fal body 的 seed／尺寸／safety（`moments_image_gen_test.ts:125, 400-447`）。V2 走**另一組**函式，不改這些函式的行為；旗標 0 時舊測試一條都不必改。

### 1.4 與 9/8 報告基準的差異

`ed6eaa5..957cdbb` 在 practice-chat 只動了 `practice_persona.ts`（`photoScene`、022）、`moments_prompt.ts`（自拍指令）、`hint.ts`、`prompt.ts` 與對應測試；`moments_image_gen.ts`、`moments_handler.ts`、`moments_schedule.ts`、`handler.ts:2329-2336` 的 kill switch、Flutter tile 皆無變更。9/8 報告的診斷全部成立；主分支仍沒有附件所指的 `tools/moments-style-census/`、`moments_visual_plan.ts`、`moments_scene_specs.ts`。

### 1.5 靜態統計（本次以 HEAD 重算，與 9/8 一致；新增三列）

| 指標 | 結果 | 口徑 |
| --- | ---: | --- |
| 角色／職業／persona／城市 | 100／43／5×20／10（台北 34、台中 16、高雄 12、台南 10、新北 9、桃園 8、新竹 8、花蓮 1、嘉義 1、台東 1） | `GIRL_SEEDS` |
| 不同興趣標籤 | 90 | 原字串去重 |
| 題材場景句 | 62（其中 59 可被排程配圖） | `THEME_SCENE_LINES` 鍵數；`imageTags` 非空者 |
| 含 table／desk | 26／62（41.9%） | 英文完整字比對 |
| 含 cup／cups／mug／mugs | 17／62（27.4%） | 不計 bowl、bottle |
| 明寫 Taipei | 5／62（8.1%） | 未計全域前綴 |
| 含 soft／softly／warm | 27／62（43.5%） | 未計全域前綴 |
| **含 lamp／light／lit** | **26／62** | 光線描述已寫死在模板 |
| **明寫「兩只杯子」** | **3／62**（`relationship_pace`、`relationship_reciprocity`、`relationship_disagreement`） | 觀點題材以杯子作通用隱喻，是撞款與尷尬圖的來源 |
| **V2 分流桶數** | percent 10→11 位、25→27 位、50→51 位 | 以正式 `fnv1a(profileId + "\|moment_image_visual_v2") % 100` 對 100 個 ID 靜算；是角色數不是流量比例 |

### 1.6 還沒查、也不能宣稱的

本次沒有讀正式環境圖片、流量、成功率、旗標值與費用，沒有取得 fal 即時單價，沒有收到新的截圖。附件中的 69–77% 靜物、38–42% 撞款、每日 5–11 張、盲測門檻，仍是**未驗證的估計**；設計文件 §11 的「~11 張/天、$0.04/張」是 2026-08-25 的排程模擬與當時報價，本文只當算例。

---

## 2. 對附件與 9/8 報告的裁決

| 建議 | 裁決 | 原因／替代 |
| --- | --- | --- |
| 共用限制／角色偏好／拍攝計畫／場景分層四層分工 | 保留 | 分清誰決定內容、誰決定拍法，避免提示互相覆蓋 |
| handler 先做安全資料投影 | 保留並補強 | 逐欄建立新物件、執行期驗 enum；**排除欄位補上 `photoScene`** |
| 場景 `temperature 0.4`、10s timeout | 保留為控制變因 | 多樣性先來自資料與選擇規則；不動模型隨機度與預算鏈 |
| 移除 Taipei／phone／全站柔暖光 | 保留，並修正為「不寫城市名；戶外／街區場景才給國家級線索」 | 城市名是刻板來源；但完全不給地域線索會讓街景漂向歐美。`contemporary everyday setting in Taiwan` 只在 `environment=outdoor/transit` 且 `locationScope ≠ travel` 時加入（待 Eric 確認，§8） |
| 失敗走 V2 自己的退路 | 保留並修正 | 先保住貼文明確事實，不能把預選錯誤主體照樣送出；命名用 `degraded` |
| 每維度獨立 hash namespace | 保留 | 但先做相容篩選，再抽選；不獨立亂抽所有維度 |
| 十個 family | 改為八種攝影配方 | 原表混用風格、主題、景別；工作過程是內容、材質特寫是取景，不與暖色、閃光並列 |
| persona 池＋43 職業分組＋45% 閘門 | 不採用 | 把聊天個性、職業與攝影美學綁太緊；45 是舊資料調參結果 |
| 不收咖啡／看書／美食興趣 | 不採用全面排除 | 差異來自「同樣喜歡咖啡，拍什麼角度」；興趣提供場景線索，不決定濾鏡 |
| 由興趣推 `pets` motif | 改用排程層 `hasPetOwnerClue()` | 既有正式函式，語意已經過 Eric 複審（P2-2） |
| 發文 dayPart 決定合法光線 | 改為拍攝時間優先 | 晚上補發早上照片很正常；室內光也不只看時段 |
| 直閃只准晚上 | 改為場景相容性 | 看近遠、隔玻璃、環境與主體；日間補光並非不可能 |
| 城市線索固定 35% | 延後 | 居住地不等於拍攝地，也不是個人風格主要來源 |
| 每 family 3%–20% 分布門檻 | 改為觀測值 | 平均分布不等於自然 |
| 完整 signature 唯一率 ≥95% | 不作門檻 | 欄位一多就容易「不重複」，實圖可能仍相似 |
| 62 題材全部設計候選 | 修正：parity 62、設計 59 | 3 個題材沒有 `imageTags`，現行不會生圖（§1.2） |
| 4:3 圖完全不裁 | 修正 | tile 高度上限 180 會裁上下（§5） |
| 10／30 次成功即放量 | 改為有限試行檢查點 | 少量成功不能證明失敗率與 p95 |
| 每張 $0.04、成本不變 | 改為待核實單價 P 與實測 | 呼叫次數相同不代表每張成功圖成本相同 |

---

## 3. 產品設計：同一件事，不同的人怎麼拍

### 3.1 個人風格的三層

| 層次 | 白話 | 穩定度 |
| --- | --- | --- |
| 注意力 | 她容易注意整個空間、物件的使用痕跡、顏色，還是局部細節 | 大致穩定；不得覆蓋貼文主體 |
| 拍照習慣 | 近拍、平視、偏一邊、留環境 | 有偏好，不必張張相同 |
| 處理習慣 | 接近原色、偏柔、反差較大、略帶顆粒 | 跨篇穩定；強度受場景限制 |

例：三位角色都寫「這杯咖啡有夠酸」。Mia 拍喝到一半的杯緣與咖啡痕、靠得近；Chloe 把杯子放畫面側邊、讓吧台線條與陰影成構圖；Ivy 保留旁邊一小塊有顏色的外帶袋、像臨時停下來拍。三張都必須有咖啡；把其中一張改成海邊來製造「差異」，是圖文關聯退步。

### 3.2 八種攝影配方（`VisualStyleId`，待實圖驗證的起點）

| ID | 看起來的特徵 | 優先適用 | 限制 |
| --- | --- | --- | --- |
| `neutral_snapshot` | 接近原色、普通曝光、自然偏位 | 多數日常 | 不附帶全站暖色、柔焦、顆粒 |
| `warm_soft` | 溫暖但保留原色、適度柔和反差 | 居家、飲食、柔和室內光 | 不把冷白燈或陰天改成夕陽 |
| `clean_graphic` | 清楚線條、少雜物、輪廓可辨 | 建築、展覽、設計細節 | 不要求對稱或商品照 |
| `daylight_color` | 日光下明確顏色、大色塊、開放感 | 戶外、花材、有顏色的物件 | 不加霓虹、不改食物本色 |
| `quiet_muted` | 飽和度稍低、色階自然、觀察式 | 巷弄、陰天、生活痕跡 | 不壓成灰褐 |
| `crisp_contrast` | 亮暗分明、質地清楚、直接 | 方向性光源、街景、硬質表面 | 光源不足不硬生太陽影子 |
| `flash_diary` | 近處直閃、背景較暗、抓拍感 | 合適的近距離室內／夜間 | 隔玻璃、遠景、白天不用；白天僅另有相容配方時 |
| `soft_grain` | 輕微顆粒、自然色差、柔一點 | 靜態紀錄、低強度懷舊 | 顆粒是輔助；不加底片框與日期字樣 |

夜景是場景條件不是人格風格；工作過程、寵物、材質近拍留在內容與取景層。

### 3.3 每人兩種相近偏好＋兩個取景習慣

`MomentVisualProfile` 至少含：`primaryStyle`、`secondaryStyle`（≠ 主）、`preferredShots`（兩個）、`tidiness`（`lived_in / ordinary / tidy`）、`processingStrength`（`low / medium`，第一輪不開高）。兩者都適用時以主 70／次 30 的相對權重抽選（初始實驗值，不是小樣本必須達成的比例）；只有一種適用用該種；都不適用回相容的中性配方。

| 主要配方 | 可用次要配方 |
| --- | --- |
| neutral_snapshot | warm_soft、quiet_muted |
| warm_soft | neutral_snapshot、soft_grain |
| clean_graphic | quiet_muted、neutral_snapshot |
| daylight_color | neutral_snapshot、crisp_contrast |
| quiet_muted | neutral_snapshot、soft_grain |
| crisp_contrast | neutral_snapshot、quiet_muted |
| flash_diary | neutral_snapshot、daylight_color |
| soft_grain | warm_soft、quiet_muted |

其餘角色以 `profileId` 固定 hash 從經驗證的「主＋次＋取景」組合清單選一組；允許個別覆寫。演算法版本（`plannerVersion`）與個人設定版本（`identityVersion`）分開，改題材不會讓 100 人一起換習慣。

### 3.4 第一批人工指定的角色（資料已對 HEAD 名冊核實）

| 角色 | 名冊摘要 | 建議主／次配方 | 穩定取景習慣 |
| --- | --- | --- | --- |
| `practice_girl_002` Ivy | 台中、大學生、音樂祭／拍照／美食 | daylight_color／neutral_snapshot | 中距離留一點環境、自然偏位 |
| `practice_girl_003` Zoe | 新北、醫院護理師、看書／做菜／寵物 | neutral_snapshot／warm_soft | 生活使用痕跡、適量背景 |
| `practice_girl_004` Mia | 台北、咖啡師、咖啡／選物／夜景散步 | crisp_contrast／neutral_snapshot | 近拍主體狀態、斜側角度 |
| `practice_girl_005` Chloe | 台北、設計師、藝術／文青展覽／咖啡 | clean_graphic／quiet_muted | 線條、偏位、少量留白 |
| `practice_girl_068` Flora | 台中、美甲師、做指甲／甜點／拍照 | daylight_color／flash_diary | 彩色小物、俯斜拍；不出現手部 |
| `practice_girl_071` Luna | 高雄、攝影師、攝影／海邊／街頭小吃 | quiet_muted／crisp_contrast | 中遠景、光影與環境細節 |
| `practice_girl_073` Noelle | 台中、甜點師、甜點／烘焙／老派咖啡 | warm_soft／soft_grain | 食材質地、實際製作痕跡 |
| `practice_girl_074` Sasha | 新北、寵物美容師、寵物／拍照／甜點 | neutral_snapshot／daylight_color | 低角度、偶發生活細節；無飼主線索，不把客人寵物當她的 |
| `practice_girl_081` Aileen | 台北、花藝師、花藝／市場散步／老屋咖啡 | clean_graphic／daylight_color | 花材色塊、包裝或使用痕跡 |
| `practice_girl_097` Hana | 台東、衝浪教練、衝浪／海邊／日出 | crisp_contrast／daylight_color | 開闊景別、岸邊近處細節 |

攝影偏好是本文新增的產品設計建議，不是名冊欄位，也不是「該職業必然如此」。

### 3.5 六種取景配方（`ShotRecipeId`）

| Recipe | 適用 | 不適用例 |
| --- | --- | --- |
| `context_eye_level` | 場景加主體，平視 | 需要辨認食物紋理卻拍太遠 |
| `offset_medium` | 主體偏位、保留合理背景 | 小主體被推到框外 |
| `close_oblique` | 食物、器材、材質的斜側近景 | 海岸全景、雲層 |
| `overhead_detail` | 真正可從上方拍的平面物件 | 建築立面、天際線 |
| `wide_environment` | 海邊、山徑、街道 | 主題是小物件卻看不出主體 |
| `low_environment_detail` | 路面、浪線、地面用品 | 無來由的極低角度、虛構人物視角 |

每個 recipe 固定合理的距離、視角與構圖，再從相容光線選一個。動態以靜態或輕微自然動態為主；流動只在水、蒸汽、窗簾等真有理由的地方。有可讀文字風險時改取景避開標示、封面、收據、介面，不要求整張糊掉。

### 3.6 光線＝拍攝時間 × 場域

新增 `capturePeriod`（`TaipeiDayPart` 七值＋`unknown`）與 `timeSource`（`explicit_post / historical / posted_default / unknown`），由同一次場景呼叫回傳並驗證。

| 貼文情形 | timeSource | 光線處理 |
| --- | --- | --- |
| 「早上的海，現在才有空發」 | explicit_post | 早晨；發文是深夜也不配夜景 |
| 「剛下班，路邊吃宵夜」 | explicit_post | 當下夜間 |
| 「上週那次爬山」 | historical | 不強制現在天色，用場景合理光線 |
| 無時間資訊的日常文 | posted_default | 發文時段是弱預設，不冒充明確拍攝時間 |
| 室內物件、沒說窗外 | unknown | 合理室內光，不強迫天空、夕陽、街燈 |

| capturePeriod | 戶外候選光 | 室內候選光 |
| --- | --- | --- |
| dawn | 日出前環境光、既有街燈 | 室內燈、弱窗光 |
| morning／noon／afternoon | 側光／日照／遮蔭／陰天漫射 | 窗光、普通室內燈 |
| early_evening | 暮色、餘暉、環境燈 | 室內燈、剩餘窗光 |
| evening／late_night | 街燈、店面環境光；近景才考慮閃光 | 室內燈、局部燈；合適近景可閃光 |
| unknown | 以已知場景為準，不宣稱特定日照時刻 | 普通室內光 |

這是候選集合，下雨、無窗、隔玻璃、主體距離還要再過濾。回溯早晨照片不代表修改發文排程，也不解除現有 dawn 發文限制。

### 3.7 城市與興趣：只補背景，不決定濾鏡

- `homeCity` 只表示居住城市；貼文明確指向在地情境才考慮城市線索；旅行、機場、海邊或地點不明時不帶城市；外地情境不得用居住城市覆蓋；不把高雄自動變港口、台南自動變老屋。
- 興趣 motif 用精確 allowlist（每個字串都在現行 90 個標籤內；未收錄不投影、不做模糊搜尋）：

| motif | 精確來源標籤 |
| --- | --- |
| coffee | 咖啡、手沖咖啡、老屋咖啡、老派咖啡、深夜咖啡 |
| food | 美食、小吃、街頭小吃、宵夜、深夜食堂 |
| cooking | 做菜、料理、家庭料理、家常菜、健康料理、健康飲食 |
| baking | 烘焙、甜點 |
| reading | 看書、閱讀、獨立書店、獨立漫畫 |
| visual_arts | 藝術、文青展覽、展覽、字體、插畫 |
| architecture | 建築、空間設計、老屋 |
| photography | 拍照、攝影 |
| music | 音樂、獨立音樂、貝斯、音樂祭 |
| audio | Podcast |
| urban_walk | 城市散步、散步、老街散步、市場散步、夜景、夜景散步、城市夜景 |
| outdoor | 戶外爬山、戶外散步、慢跑 |
| sea | 海邊、海邊散步、沙灘陽光、潛水或海邊活動、衝浪、日出 |
| fitness | 健身、重訓、瑜珈、跳舞 |
| plants | 植物、花藝 |
| craft | 手作、陶藝、手帳 |
| style | 穿搭、選物、保養、做指甲、髮型 |
| pets | **不由標籤決定**：`hasPetOwnerClue(girl)` 為 true 才給 |
| travel | 旅行、自助旅行、小旅行 |
| technology | 科技產品 |
| drinks | 茶、調飲、紅酒課 |

motif 只提供場景線索，不能宣告她參加過活動或擁有某物；`pets` 不含物種、毛色、名字。

---

## 4. 生成流程與資料契約

### 4.1 流程（與 V1 的差別只在步驟 1、3–6）

| 步驟 | 使用資料 | 產出與約束 |
| --- | --- | --- |
| 1. handler 建 image job | 已驗證角色、日期、slot、發文時段 | V1 或 V2 job；V2 只帶安全投影；兩個建構點共用 `buildMomentImageJob()` |
| 2. 原子 claim | 既有 RPC 與限流 | 以 claim 回傳的 committed body、theme、attempt 為準 |
| 3. 整理場景意圖 | body、theme、已篩選的場景 hint | **一次** DeepSeek 呼叫，回英文 scene＋有限 metadata |
| 4. 驗證與退路 | 結構、enum、貼文關鍵事實、禁詞 | 失敗走具事實保護的 V2 退路（§4.5） |
| 5. 選拍攝方式 | 已確認場域／時間、角色固定偏好 | 先篩相容 recipe 與 style，再用固定 seed 選 |
| 6. 組 prompt | 場景＋拍法＋共用限制 | 無互相矛盾的光線、鏡位、城市；長度受控 |
| 7. 生成、下載、儲存、commit | 既有 fal 與 Storage 流程 | 租約、token fencing、清掃、失敗語意一字不改 |

**拍攝計畫必須在場景意圖確認後才完成**，否則會先抽出「戶外、遠景、霓虹」，最後才發現貼文說的是家裡蒸蛋。

### 4.2 事實優先順序（固定）

1. 既有圖片限制與允許輸入範圍 → 2. 貼文明講的主體、活動、否定、時間、地點 → 3. 題材限定情境 → 4. 角色興趣能補充但不新增經歷的細節 → 5. 固定攝影偏好 → 6. 變化抽選。

「今天不喝咖啡，改喝熱茶」不能因 theme 是 `coffee_start` 就畫咖啡；「只是幫朋友餵狗」不能因角色有寵物興趣就設定她養貓。

### 4.3 型別（新增 `moments_visual_types.ts`；供 handler 與 generator 共用）

```ts
export type VisualStyleId =
  | "neutral_snapshot" | "warm_soft" | "clean_graphic" | "daylight_color"
  | "quiet_muted" | "crisp_contrast" | "flash_diary" | "soft_grain";
export type ShotRecipeId =
  | "context_eye_level" | "offset_medium" | "close_oblique"
  | "overhead_detail" | "wide_environment" | "low_environment_detail";
export type VisualEnvironment = "indoor" | "outdoor" | "transit" | "unknown";
export type CapturePeriod = TaipeiDayPart | "unknown";
export type TimeSource = "explicit_post" | "historical" | "posted_default" | "unknown";
export type LocationScope = "home_city" | "travel" | "unspecified";
export type MomentVisualCity =
  | "taipei" | "new_taipei" | "taoyuan" | "hsinchu" | "taichung"
  | "chiayi" | "tainan" | "kaohsiung" | "hualien" | "taitung";

export interface MomentVisualProfile {
  profileId: string;
  identityVersion: string;
  primaryStyle: VisualStyleId;
  secondaryStyle: VisualStyleId;          // ≠ primaryStyle，執行期驗證
  preferredShots: readonly [ShotRecipeId, ShotRecipeId];
  tidiness: "lived_in" | "ordinary" | "tidy";
  processingStrength: "low" | "medium";
  homeCity: MomentVisualCity | null;
  motifs: readonly MomentVisualMotif[];
}

export type MomentImageJob =
  | { profileId: string; isoDate: string; slot: number; visualVersion: "v1" }
  | {
      profileId: string; isoDate: string; slot: number; visualVersion: "v2";
      postedDayPart: TaipeiDayPart;
      visualProfile: MomentVisualProfile;
    };

export interface SceneVariant {
  id: string;                              // 穩定內部 ID，不靠陣列順序
  mode: "literal_activity" | "detail_trace" | "ambient_personal";
  subjectKey: VisualSubjectKey;            // 明確列舉
  environment: VisualEnvironment;
  safeScene: string;                       // 經驗證的英文正向描述（退路用）
  compatibleShots: readonly ShotRecipeId[];
  localCueAllowed: boolean;
}
export interface MomentSceneSpec {
  variants: readonly [SceneVariant, SceneVariant, ...SceneVariant[]];
  avoidUnmotivatedSubjects: readonly VisualSubjectKey[];   // 「不無故添加」，不是禁止貼文明講的物件
}
```

實作要求：

- 投影函式逐欄建立新物件；不用 `{ ...girl }`，不用 `as MomentVisualProfile` 假裝清理。
- **排除欄位**：`selfIntro`、`reactionModel`、`signalStyle`、`professionPrompt`、`relationshipGoal`、`photoScene`、`personalityTags`、`displayName`、`age`、`zodiac`。城市與 motif 在執行期驗 enum。
- 生圖模組不 import 名冊；`userId` 仍只進 claim 限流。
- 新設定錯誤（enum 不合、主次相同）→ 以 V1 job 安全退回並記 `visual_profile_invalid`，不讓整個 feed 拋錯。
- `profileId`、版本、內部 ID 不進 prompt，只轉成已審核的具體拍法。

### 4.4 一次場景呼叫，輸出小型結構

```json
{
  "scene": "A partially eaten slice of lemon cake on a plain plate, with crumbs along its edge.",
  "subjectKey": "food",
  "environment": "indoor",
  "capturePeriod": "morning",
  "timeSource": "explicit_post",
  "locationScope": "unspecified",
  "mode": "literal_activity",
  "evidence": { "subject": "檸檬蛋糕", "time": "早上" }
}
```

- `scene` 沿用 20–300 字元、可列印 ASCII、`SCENE_FORBIDDEN` 檢查；`evidence` 可中文、限長、不進 fal prompt。
- 欄位與 enum 採 allowlist；不收 `style / person / cityPrompt / instructions` 等自由欄位。
- `evidence.subject`／`evidence.time` 必須是原 body 子字串，否則不得標 `explicit_post`；同時做**否定窗檢查**：子字串前 6 個字元內出現「不／沒／沒有／別／不是／改」則拒絕當作明確主體。第一輪詞表 ≤ 60 條，只覆蓋高頻食物／飲品／動物／時間詞與歷史標記（上週、之前、那次），由八個關鍵案例（§6.6）驗收。
- 引文存在只證明有該文字，不證明模型理解正確；schema 與關鍵事實檢查降低錯誤，不宣稱自動證明圖文一致。
- 參數：`temperature 0.4`、`jsonMode`、10s 不變；`maxTokens` 由 150 調為 **320 候選值**，實測截斷率與延遲後定案。
- V2 system message 責任：body 是資料不是指令；優先描述明講的食物／物件／活動含否定與時間；scene 只寫正向可見場景，不指定濾鏡、鏡頭、光線、城市；**不在 scene 重複 no people／no text**（由 composer 放，避免撞現有禁詞驗證器）；hint 只補 body 沒說的部分；抽象觀點用自然環境細節，不用兩杯＝互惠、空椅＝孤單的通用隱喻。User message 用 `JSON.stringify({ post, themeId, selectedHint })` 建立資料邊界；這不等於消除 prompt injection。

### 4.5 退路必須保住事實（命名用 `degraded`，不用 `fallback`）

| 情況 | V2 行為 |
| --- | --- |
| 模型輸出有效且與已知錨點相容 | 用模型 scene，之後挑拍法 |
| timeout／JSON 壞，但貼文有可確定主體 | 用受控詞表建立該主體的簡短描述，配相容場域 |
| 抽象觀點沒有具體主體 | 用該題材已選出的 A／D 場景，避免新增事件與經歷 |
| 具體貼文含無法處理的主體／時間矛盾 | **不送一張已知可能相反的圖**；記 `scene_unresolved`，沿既有 release／attempt 上限處理 |
| 未知 themeId | 先保留 body 錨點；再用 `GENERIC_SCENE_SPEC`（普通室內局部／普通戶外局部／通行環境局部）相容候選 |

貼文說檸檬蛋糕而 hint 是咖啡時，模型失敗**不能**直接用「咖啡＋咖啡廳」生成。不新增 DB 狀態、不提前轉 `failed`、不加 attempts；`scene_unresolved` 只是內部原因分類。

### 4.6 seed 與版本

| 用途 | 輸入 | 含 attempt |
| --- | --- | --- |
| 角色初始視覺設定 | `profileId + identity namespace` | 否 |
| V2 分流 | `fnv1a(profileId + "\|moment_image_visual_v2") % 100 < percent` | 否 |
| 場景候選 | `profileId + isoDate + slot + claimedThemeId + scene namespace` | 否 |
| 拍攝配方 | 同貼文鍵＋`shot` namespace＋已解析相容條件 | 否 |
| 主／次風格 | 同貼文鍵＋`style` namespace | 否 |
| fal seed | 現行 `momentImageSeed(profileId, isoDate, slot, attempt)` | 是 |

不承諾跨 attempt 的完整場景／shot／prompt 位元相同：DeepSeek 每次重新呼叫可能回不同 metadata。要完全重播必須持久化已接受的 scene intent，屬另一份資料保存規格；本輪零 migration，不假裝具備此能力。

### 4.7 最終 prompt 與模型參數

composer 順序：場景事實 → 角色拍法 → 合法光線與畫面處理 → 共用限制。所有段落先做衝突處理，不指望「最後一句覆蓋前一句」。同為咖啡的兩種拍法（待測範例，非效果保證）：

```text
A partly finished coffee in a plain ceramic cup on a cafe counter.
An oblique close view, with the cup slightly off-center and a small coffee stain visible at the rim. Neutral color and clear local contrast under ordinary indoor light.
Photorealistic everyday photograph. No people, faces, hands, body parts or silhouettes. No readable text, logos, watermarks or recognizable screen interfaces.
```

```text
A partly finished coffee in a plain ceramic cup on a cafe counter.
A medium view with the cup toward one side, using the counter edge as a simple line. Restrained color, natural contrast and ordinary indoor light; keep small everyday irregularities.
Photorealistic everyday photograph. No people, faces, hands, body parts or silhouettes. No readable text, logos, watermarks or recognizable screen interfaces.
```

- 完整 prompt 內部上限 1,600 字元（工程預算，非 fal 限制）。
- 不全站加 cinematic、studio、perfect、luxury、editorial、強 bokeh、柔光。
- V2 驗證器只驗場景段；不把含 `No people` 的完整 prompt 送進同一禁詞正則。
- fal 端維持 `landscape_4_3`、`num_images 1`、`max_images 1`、`enable_safety_checker true`；API 沒有 `negative_prompt`／`style_strength`（`moments_image_gen.ts` 檔頭註解已查證），不虛構參數。

### 4.8 觀測欄位

在既有 `practice_moment_image_*` log 加結構化欄位：`visualVersion / plannerVersion / identityVersion / styleId / shotRecipeId / sceneVariantId / sceneMode / subjectKey / environment / capturePeriod / timeSource / locationScope / degradedReason / attempt / failureClass / durationMs / bytes`。沿用既有 profile／slot 識別；**不記** body、evidence、完整 prompt、聊天、暱稱、userId。提供供應商請求攔截測試，不只靠 source 字串檢查。

---

## 5. 前端：本輪不改 UI，但用真實尺寸驗收

`practice_moment_tile.dart:27-34, 176-178`：`width = 文字欄寬 × 0.72`、`height = min(width ÷ 4/3, 180)`、`BoxFit.cover`。寬度超過 240 時高度被夾在 180、顯示框比 4:3 更寬，會裁上下。故可移除舊「中央 4:3＋左右留空」規則，但不能承諾完全不裁。第一輪：保留尺寸、圓角、載入與錯誤行為；重要主體不緊貼邊界；同時看原圖與 App 縮圖；只有證明高度限制傷到主體才另開 UI 修正。

---

## 6. 實作計畫

### 6.1 三個 PR（一 PR 一目的，各自可測、可合、可退）

| PR | 單一目的 | 合併條件 | 正式環境影響 |
| --- | --- | --- | --- |
| **A：接好可關閉的 V2 入口** | 型別、投影、固定角色偏好、旗標 parser、兩個 job 建構點、V1 等價測試 | V1 request snapshots 逐位元不變；100 位角色都能建立設定；`percent` 未設＝0 | 零（V2 分支尚無 composer，旗標為 0 時走原函式） |
| **B：完成 V2 場景與拍攝規劃** | 62 題材場景規格、結構化場景呼叫、事實保護退路、相容 recipe、composer、metadata | 所有新契約測試通過；無舊風格污染；正式仍 0 | 零（旗標 0） |
| **C：可重跑的圖片驗收與 runbook** | 離線實圖對照工具、census、縮圖／角色組圖、評分表、放量 runbook | 留下全部案例、失敗、版本、評分、成本 | 零；完成後才由 Eric 決定進 10% |

依賴：B 依賴 A 的型別與 job；C 依賴 B 的純函式。A 可先合；B 未合前 V2 分支不得被啟用（A 內以 `percent` parser 存在但 V2 路徑直接委派 V1，並有測試釘住）。

### 6.2 PR A 細節

**新增**

- `moments_visual_types.ts`：§4.3 全部型別＋`PLANNER_VERSION`、`IDENTITY_VERSION` 常數。
- `moments_visual_profiles.ts`：
  - `VISUAL_STYLE_ADJACENCY`（§3.3 表）、`DEFAULT_VISUAL_COMBOS`（經審的主＋次＋取景組合清單）。
  - `VISUAL_PROFILE_OVERRIDES: Record<string, ...>`（§3.4 十位）。
  - `MOTIF_ALLOWLIST`（§3.7 表，`pets` 除外）。
  - `projectMomentVisualProfile(girl: PracticeGirlProfile): MomentVisualProfile`：逐欄建立；`homeCity` 由 `girl.city` 中文對 enum；`motifs` 由 `interestTags`/`lifestyleTags` 精確比對＋`hasPetOwnerClue(girl)` 決定 `pets`；主／次由 `fnv1a(profileId|identity|primary)` 與 `fnv1a(profileId|identity|secondary)` 兩個 namespace 決定，覆寫優先。
  - `validateMomentVisualProfile(raw: unknown): MomentVisualProfile`（執行期 enum、主≠次）。
- `moments_visual_profiles_test.ts`：100 位都能投影且合法；覆寫十位正確；投影結果不含排除欄位（以 `Object.keys` 白名單斷言）；`hasPetOwnerClue` 決定 `pets`（074 無、022 有）；同一角色跨日期／使用者／attempt 不變。

**修改**

- `moments_image_gen.ts`：`MomentImageJob` 改為 §4.3 union（V1 shape 完全相容）；`generateMomentImage` 內以 `job.visualVersion` 分路，V2 暫時委派 V1 的 `describeScene + buildImagePrompt`（PR B 才換），並在 log 加 `visualVersion`。
- `moments_handler.ts`：新增 `buildMomentImageJob({ girl, profileId, isoDate, slot, dayPart, visualV2 })` 供 `:335`（pending 接手，用驗證過的 `row.day_part`）與 `:565`（新 commit，用 `item.plan.dayPart`）共用；投影失敗記 `practice_moment_image_visual_profile_invalid` 並退 V1 job。`MomentsHandlerDeps` 加 `imageVisualV2Percent: number`。
- `handler.ts:2329-2356`：新增 `parseVisualV2Percent(raw: string | undefined): number`——只接受 0–100 整數字串，其餘回 0；注入 deps。維持 `MOMENT_IMAGE_GEN_ENABLED === "true"` 語意不變。
- `moments_generated_only_source_test.ts`：把 `moments_visual_types.ts`、`moments_visual_profiles.ts` 納入「不得 import 對話／記憶模組」與「不得出現 `photoScene`／`selfIntro`／`reactionModel`／`professionPrompt` 於投影輸出」的守門；`moments_image_gen.ts` 的 `userId` 計數規則不變。
- 新增 `moments_image_visual_flag_test.ts`：parser 邊界（空、空白、負、小數、`101`、`abc`、`"10"`）；`percent=0` 時 job 為 V1 且 fal body／DeepSeek messages 與現行 golden 逐位元相同（比照 `agency_flag_off_equivalence_test.ts` 的四個面：messages、fal request body、RPC params、telemetry 形狀）；`percent=100` 時 job 為 V2 但（PR A 階段）供應商請求仍等於 V1。
- `.github/workflows/flutter-ci.yml`：白名單加 `moments_visual_profiles_test.ts`、`moments_image_visual_flag_test.ts`。

**完成條件**：既有 `moments_image_gen_test.ts`、`moments_image_flow_test.ts`、`moments_handler_test.ts`、`moments_generated_only_source_test.ts` 一條不改仍全綠；新測試在 CI 白名單；`deno test --allow-env --allow-read supabase/functions/practice-chat` 本地全綠。

### 6.3 PR B 細節

**新增**

- `moments_scene_specs.ts`：`SCENE_SPECS: Record<string, MomentSceneSpec>`（附錄 A 的 62 題材；3 個無 `imageTags` 題材只給最低兩個候選）、`GENERIC_SCENE_SPEC`、`SUBJECT_VOCABULARY`（≤ 60 條中英關鍵事實與否定／歷史標記）、`coveredSceneSpecThemeIds()`。
- `moments_visual_plan.ts`（純函式，零 I/O）：
  - `selectSceneVariant({ spec, profile, themeId, key })`：依 body 錨點與 motif 篩選後以 `scene` namespace 選一個 hint。
  - `resolveSceneIntent({ raw, body, themeId, hint })`：解析、驗證（§4.4），失敗回 `{ kind: "degraded", reason }` 帶事實保護結果，或 `{ kind: "unresolved" }`。
  - `compatibleShots(intent)`、`compatibleStyles(intent, profile)`、`lightingOptions(intent)`。
  - `planShot({ intent, profile, key })`：先篩再以 `shot`／`style` namespace 選；回 `{ styleId, shotRecipeId, lighting, processing }`。
  - `composeV2Prompt({ intent, plan, profile })`：§4.7 順序；長度 ≤ 1,600；回 prompt 與 metadata。
- `moments_scene_specs_test.ts`：parity（`MOMENT_THEME_IDS` 每個都有 spec，且 spec 沒有多餘題材；不手抄 62 個 ID）；每個 `safeScene` 通過 `validateSceneLine`；`compatibleShots` 非空；`avoidUnmotivatedSubjects` 不含該題材自己的主體。
- `moments_visual_plan_test.ts`：相容性（隔玻璃不選直閃、遠景不選俯拍、夜間不出太陽、居家不選戶外霓虹、`unknown` 時段不宣稱日照）；八個關鍵案例（§6.6）；退路不回舊杯桌模板、不換已知主體；同一已解析輸入下規劃一致；prompt 無 `Taipei`／`smartphone`／`lifted shadows` 等 V1 字串、無互相矛盾光線；長度上限。

**修改**

- `moments_image_gen.ts`：`describeSceneV2()`（一次呼叫、`maxTokens` 320 候選、10s、`jsonMode`）；V2 分支：claim → `selectSceneVariant` → `describeSceneV2` → `resolveSceneIntent` → `planShot` → `composeV2Prompt` → 既有 fal／下載／上傳／commit；`unresolved` 走既有 release，記 `scene_unresolved`；log 加 §4.8 欄位。V1 分支與 `buildImagePrompt`、`themeSceneLine`、`validateSceneLine` 行為不變。
- `moments_image_gen_test.ts`：新增 V2 harness 測試——請求攔截檢查 DeepSeek messages 不含 `photoScene`／`selfIntro`／`userId`／暱稱；fal prompt 不含 V1 前綴字串；timeout 時退路保住主體；`unresolved` 時零 fal 呼叫並 release；attempt 2 時 profile 偏好不變、fal seed 改變。
- `moments_generated_only_source_test.ts`：納入 `moments_scene_specs.ts`、`moments_visual_plan.ts`；斷言 `moments_image_gen.ts` 可執行碼不含 `Everyday Taipei life` 以外的新城市名硬編碼（V1 字串保留在 V1 函式內）。
- `.github/workflows/flutter-ci.yml`：白名單加 `moments_scene_specs_test.ts`、`moments_visual_plan_test.ts`。

**完成條件**：§6.6 測試矩陣全綠；`percent=0` 等價測試仍綠；`deno lint`／`deno fmt --check` 對新檔通過；正式 `MOMENT_IMAGE_VISUAL_V2_PERCENT` 未設。

### 6.4 PR C 細節

- `tools/moments-style-census/census.ts`：**import 正式** `projectMomentVisualProfile`、`selectSceneVariant`、`planShot`、`momentPlanFor`、`momentPostedAtFor`；`planning` 模式統計角色偏好、可選配方、相容性退路、題材覆蓋（標示為規劃模擬）；`observed` 模式讀離線評分 CSV 或不含原文的生成 metadata。名冊完整分布、不同解鎖組合、實際近期出圖角色分開；一般排程與 freshness 補位分開標示。`deno run --allow-read`，零網路。
- `tools/moments-style-compare/`：離線 V1／V2 配對生成腳本（需 `FAL_API_KEY` 與 `DEEPSEEK_API_KEY` 環境變數、`--allow-net`、明確 `--max-images` 硬上限與逐張費用累計；**執行需 Eric 當次授權付費呼叫**）。固定 body、theme、日期、slot、端點、尺寸與 fal seed，只改規劃與 prompt；輸出原圖配對、App 尺寸縮圖（0.72 欄寬與 180 高度上限兩種）、同角色四篇並排、混合 feed 連續圖，以及 `cases.json`（含失敗與重試、耗時、bytes、metadata，不含 key）。
- `docs/practice-moment-image-visual-v2-runbook.md`：旗標名與 parser 規則、分流公式、計量口徑（§7.6）、放量階段與回退、與 `MOMENT_IMAGE_GEN_ENABLED` 的差異、每次版本紀錄。
- `docs/reviews/`：80 案評分表模板與結果（盲測、平手計入分母）。

**完成條件**：80 案 160 張完成且失敗未剔除；門檻表（§7.2）逐項填寫；census planning／observed 兩模式可重跑；runbook 完成；Eric 看過縮圖與角色組圖後決定是否進 10%。

### 6.5 檔案修改地圖

| 檔案 | PR | 工作 |
| --- | --- | --- |
| 新增 `moments_visual_types.ts` | A | 風格、鏡位、場域、時間、投影與 job 型別；版本常數 |
| 新增 `moments_visual_profiles.ts` | A | 固定角色設定、十位覆寫、motif allowlist、安全投影、執行期驗證 |
| `moments_handler.ts` | A | 共用 `buildMomentImageJob()`；投影錯誤隔離；deps 加 percent |
| `handler.ts` | A | 嚴格 percent parser；deps 注入；kill switch 語意不變 |
| `moments_image_gen.ts` | A→B | job union 與分路（A）；結構化場景呼叫、退路、規劃、composer、metadata（B） |
| 新增 `moments_scene_specs.ts` | B | 62 題材相容候選、GENERIC、subject vocabulary |
| 新增 `moments_visual_plan.ts` | B | 相容篩選、固定 seed 選擇、光線規則、composer（純函式） |
| `moments_generated_only_source_test.ts` | A、B | 新模組納入邊界守門 |
| 新增四支 focused tests | A、B | 見 §6.2／§6.3 |
| `.github/workflows/flutter-ci.yml` | A、B | 白名單加新測試 |
| 新增 `tools/moments-style-census/`、`tools/moments-style-compare/` | C | planning／observed 分析；離線配對生成 |
| 新增 runbook 與評分表 | C | 放量、回退、計量口徑、結果 |

**不動**：`moments_schedule.ts` 發文節奏與 `IMAGE_PROBABILITY`、`moments_image_catalog.ts`、`moments_prompt.ts`（已區分觀點文與具體生活文；只有 V2 實測證明上游造成特定矛盾才另列範圍）、`moments_constants.ts` 預算鏈、migrations、Storage path 與清掃、Flutter feed contract 與 tile。

### 6.6 測試矩陣

| 測試群 | 必須證明 |
| --- | --- |
| V1 等價 | `percent=0`／未設／非法值時，固定輸入下 DeepSeek messages、fal request body、RPC params、telemetry 形狀與現行逐位元相同；動態 token／時間以注入固定 |
| 投影邊界 | `photoScene`、`selfIntro`、`reactionModel`、`professionPrompt`、對話、記憶、userId、暱稱不出現在任何供應商請求；新模組納入 source 守門 |
| 完整覆蓋 | 62 題材都有 spec 且無多餘；100 位角色都能投影；城市／時間 enum 有 `unknown` 路徑 |
| 相容性 | 隔玻璃不直閃、遠景不俯拍、夜間不出太陽、居家不戶外霓虹、`unknown` 不宣稱日照 |
| 圖文事實 | 八個關鍵案例（下） |
| 退路 | timeout、格式錯誤、未知題材不回舊杯桌模板、不換已知主體；`unresolved` 零 fal 呼叫 |
| 穩定性 | 角色偏好不因日期／使用者／attempt 改變；相同已解析輸入規劃一致 |
| 成本與故障 | 每 job 一次場景呼叫、一次 fal 單張；無「覺得不好看就重生」；claim／release／token／清掃契約照舊 |

八個關鍵案例（PR B 必含）：

1. `coffee_start`：「今天不喝咖啡，改喝熱茶。」→ 主體是茶，不是咖啡。
2. `pet_moment`：「只是幫朋友餵狗，我家沒有養。」→ 可畫狗相關用品或狗，不得標記她養寵物、不得換成貓。
3. 深夜發文：「早上的海，現在才有空發。」→ `capturePeriod=morning`、`timeSource=explicit_post`，不配夜景。
4. `travel_plan`：「還沒訂機票，先想想而已。」→ 準備物件，不憑空生成已抵達照片。
5. `relationship_reciprocity`：「不是每件事都要算誰付出比較多。」→ 不擺兩杯。
6. 室內文（下午）：「窗簾拉起來，開小燈看書。」→ 室內燈，不強塞日光。
7. 同角色第二次 attempt：偏好不變；fal seed 改變；不宣稱模型重解析結果必然相同。
8. 未知題材但 body 寫「檸檬蛋糕」：退路保留蛋糕，不退咖啡或無關街道。

### 6.7 審查、交付與協作規則（依 `AGENTS.md`）

- 三個 PR 都動 AI 成本（DeepSeek token、fal 呼叫）與 Edge，屬高風險類：**Codex 與 Claude Code 兩個 AI reviewer 都要看**；若一方做了實質修正，另一方快速複審最終 diff。
- 協作者走分支＋PR、Squash Merge；handoff 只用一個 `next:` 標籤；Eric 提交正式 GitHub review。
- 合併到 `main` 後由 push-triggered `Deploy Edge Function` 部署，**不重複部署**；本案零 migration。
- 旗標 `MOMENT_IMAGE_VISUAL_V2_PERCENT` 是 Supabase secret／env；設定與回退屬 runbook 操作，值不進 log。付費對照（PR C 的 160 張）需 Eric 當次授權。
- 開始 Git／測試前讀當時的 `.agent/environment.json`；本地驗證用 `deno test --allow-env --allow-read <測試檔>`，Windows 側依環境解析器。

### 6.8 開發者完成定義

- [ ] 同一角色固定視覺偏好，不因使用者、日期或 attempt 重設。
- [ ] 十位指定角色的取景差異可在 App 縮圖辨認；未覆寫角色有合理預設。
- [ ] 三處 V1 風格污染在 V2 路徑全數移除；V1 路徑逐位元不變。
- [ ] 62 題材 spec parity；主體與場域候選成對；未知題材向前相容。
- [ ] 明確主體、否定、時間、物種、所有權不被 hint 或退路覆蓋。
- [ ] 補發照片與居住地／拍攝地情境正確；光線由時間與場域共同決定。
- [ ] 正常與退路 prompt 均經長度、禁詞、相容性檢查。
- [ ] 投影與供應商 payload 測試證明無自由角色描述、無 `photoScene`、無使用者資料流入。
- [ ] 每 job 一次場景呼叫、單張 fal 輸出；無額外美感重試。
- [ ] claim、attempt、token、Storage、清掃回歸測試全綠；新測試在 CI 白名單。
- [ ] 80 案實圖配對含失敗紀錄；縮圖與角色連續性評分完成。
- [ ] 統計分清模擬／實際、job／attempt、成功／全部請求，公開 N。
- [ ] runbook 寫清旗標回退、已執行工作與既有圖片的行為。
- [ ] Eric 真機確認「看得出不同的人在拍，但同一個人仍像同一個人」。

---

## 7. 驗收與放量

### 7.1 離線實圖對照（80 案／160 張，PR C 執行）

| 組別 | 設計 | 要回答 |
| --- | --- | --- |
| A：控制主體 | 8 配方 × 4 相同貼文場景＝32 案，每案 V1／V2 各一張 | 同樣內容，拍法是否真的不同 |
| B：角色連續性 | 12 位角色 × 4 篇不同內容＝48 案（含 §3.4 十位＋兩位未覆寫） | 同一人跨內容仍有風格；不同人不會又變成同一攝影師 |

同一配對固定 body、theme、日期、slot、端點、尺寸與 fal seed；V1／V2 左右隨機、隱藏版本，由 Eric／Bruce 各自評分；交付原圖配對、App 尺寸配對、同角色四篇並排、混合 feed 四種檢視；失敗圖不剔除、首次失敗與重試分開；調參用少量開發樣本，正式驗收保留未用於調參的貼文。

### 7.2 第一輪產品門檻（待執行的初始值，不是實測結果）

| 項目 | 門檻 |
| --- | --- |
| 圖文核心事實 | 指定食物、動物、時間、地點無明確相反；逐件修正 |
| 既有圖片限制 | 人物、可讀個資阻擋問題為 0；文字、Logo、UI 違規逐件記錄修正 |
| 真人日常感 | 1–5 分平均 ≥ 4，且不低於 V1 |
| 同角色四篇一致性 | 平均 ≥ 4；不要求同構圖或同主體 |
| 相同主體跨角色差異 | 平均 ≥ 4；不得靠換食物、換場景作弊 |
| 縮圖改善 | 多數原圖差異在 App 縮圖仍可見，平均 ≥ 4 |
| 盲測偏好 | V2 勝出 ≥ 60%；平手計入分母 |
| 成功與速度 | 列各版本請求數、成功數、失敗分類與耗時；不得只展示成功樣本 |

### 7.3 重複率：粗特徵＋人工確認

記錄主體類型、景別／視角、主要色光三項；以連續五張有圖貼文為視窗，統計三張以上被人工標為三項都近似的視窗比例；V1／V2 同一批貼文與排序，分別看每個角色與混合 feed。相對 V1 減少 30% 為改善目標；視窗重疊，不當獨立樣本。pHash／embedding 只輔助排序供人檢查，不裁決個人風格，第一輪不做線上即時比對與重生。

### 7.4 放量節奏

| 階段 | 動作 | 決策依據 |
| --- | --- | --- |
| 0：離線 | 三個 PR 合併，正式 `percent` 未設 | 契約測試、80 案對照、角色與縮圖審查 |
| 1：10%（11 位角色） | 觀察 ≥ 72 小時，逐張看早期 V2 輸出 | 全部已認領工作、失敗、耗時與案例；初步 review 至少 10 個已結束 jobs、4 位角色（發現問題的檢查點，不是統計樣本） |
| 2：50%（51 位） | 階段 1 無阻擋問題後，再 ≥ 72 小時 | V2 累積 ≥ 30 個已結束的不同 post image jobs（含失敗），覆蓋 ≥ 8 位角色、白天／夜間與主要題材 |
| 3：100% | 人工接受，且故障、成本、延遲無明顯退步 | 仍屬可回退改版 |

時程以觀測資料估：若沿用設計文件的 ~11 張/天且流量按角色比例分配，10% 階段取得 10 張約 9–20 天，50% 再取 30 張約 5–12 天，未計失敗與覆蓋不足。不為湊數提高正式配圖率；低頻場景用離線驗收集。

### 7.5 回退，以及與 kill switch 的差異

- 人物／可讀個資阻擋問題或確認的嚴重圖文矛盾：立即停止擴大，涉及新策略時 `percent` 回 0。故障集中、timeout 增加、每張成功圖成本明顯上升：停止放量並回查。「成功率下降 5 個百分點」「p95 增加 25%」只在樣本足夠後當調查門檻；baseline 為 0 時看絕對次數。
- `percent` 回 0 是 **runbook 操作**，沒有自動回退；只影響之後才選策略的工作，已執行的背景工作不一定中止，已生成圖不會改回，隨 14 天窗淡出；不批次重生。
- `MOMENT_IMAGE_GEN_ENABLED=false` 讓新配圖**回 bundled 候選路徑**、不隱藏已存在的遠端圖（runbook §4），不是「只停圖」，也不等於 `percent=0`。

### 7.6 計量與成本口徑

- job 成功率＝成功完成的不同 post image jobs／觀察窗內已結束 jobs；attempt 成功率＝成功 attempts／已結束 attempts；場景退路率＝進入 V2 退路的場景呼叫／全部 V2 場景呼叫；fal 呼叫數、DeepSeek 呼叫數、每張成功圖片實際費用；queued／租約中的工作單獨列示。10 或 30 個樣本不估 p95，早期逐筆看 timeout、最長與中位數，並始終列 N。
- 成本：80 案 160 × P；8 案探針 16 × P；線上每 job 一次場景呼叫＋一次 fal，呼叫流程數不因 V2 增加。以設計文件 P=$0.04 為算例：160 張 $6.40、16 張 $0.64，**非本次核實報價**；V2 場景 schema 變長，token 與延遲可能增加，以測量報告，不以「張數不變」推導「成本不變」。

---

## 8. 待 Eric 拍板（實作前確認即可）

1. 八種配方與十位角色初始設定（§3.2、§3.4）是否接受為第一輪起點。
2. 戶外／街區場景是否保留國家級線索 `contemporary everyday setting in Taiwan`（§2 第 4 列）；或完全不給地域線索。
3. 3 個沒有 `imageTags` 的題材維持不生圖（本文建議維持；改動屬配圖率與成本決策）。
4. 放量以 `percent` hash 分流（本文建議），或改為第一階段固定十位覆寫角色的 allowlist（觀測更集中，但多一個旗標）。
5. 80 案 160 張離線對照的付費授權與執行時點（PR C）。
6. 門檻表（§7.2）數值是否接受為初始值。

---

## 9. 第一輪不做

| 暫不做 | 原因／何時再議 |
| --- | --- |
| 直接換模型 | 上游固定風格已查證；先同模型隔離因素，改完仍不達標再拿同一驗收集比供應商 |
| 每張抽八種風格、油畫／動漫混入 | 失去角色連續性與寫實社群定位 |
| 人人一個 LoRA／人物參考模型 | 本輪問題是無人物配圖的攝影習慣 |
| 自拍／合照生成 | 現有產品排除人物；需另處理臉部一致性、內容邊界與樣本驗收 |
| 線上 CLIP／pHash 重複檢測後重生 | 延遲、費用與共享 feed 協調問題；先用離線證據 |
| 依觀看者已看過的圖換圖 | 共用貼文不應因觀看者不同而改變 |
| 批次重生舊圖 | 新圖隨 14 天窗進入即可 |
| 重做動態 UI | 主要成因在生成前的決策；先在既有小圖證明改善 |

無人物照片仍無法重現真人社群的自拍與互動；本輪改善的是**她會注意什麼、如何取景、怎麼處理照片**。

---

## 附錄 A：62 題材場景候選（L＝實際活動、D＝細節／使用痕跡、A＝不硬做象徵的環境；A、B 擇一）

共同規則：貼文有具體食物、物種、地點、活動時以貼文取代預設；不知道時不可假裝知道。標 `※` 者無 `imageTags`，現行不會生圖，只需最低兩個候選過 parity。

| themeId | 模式 | 候選 A（主體／場域） | 候選 B（主體／場域） |
| --- | --- | --- | --- |
| morning_commute | L／D | 車窗邊緣與窗外街道／大眾運輸 | 通道扶手與地面／通勤空間 |
| coffee_start | L／D | 實際飲品與杯緣／簡單飲用位置 | 萃取出口與接液杯／咖啡設備，僅咖啡情境 |
| work_grind | D／L | 未完成材料或工具／符合貼文的工作位置 | 用過的紙張邊角與文具／工作區，無可讀內容 |
| lunch_break | L／D | 貼文明講的午餐／用餐位置 | 餐點局部與用過的餐具／用餐位置 |
| afternoon_slump | D／L | 貼文提到的點心斷面／零食附近 | 拆開的包裝與碎屑／無品牌局部 |
| off_work_walk | L／A | 步道轉角／下班途中 | 樹影與人行道材質／街道局部 |
| sunset_catch | L／D | 天色與屋簷邊界／戶外 | 晚霞在窗面的反光／建築外側 |
| dinner_simple | L／D | 實際晚餐／用餐位置 | 貼文支持的料理狀態／廚房 |
| home_unwind | D／A | 鬆開的毯子和沙發局部／居家 | 窗簾邊緣與地面光線／居家，不額外加飲料 |
| night_thoughts ※ | A／D | 窗面和室外少量燈光／夜間環境 | 局部燈光落在牆面／室內 |
| late_snack | L／D | 實際宵夜／用餐位置 | 吃到一半的餐點局部／用餐位置 |
| rainy_mood | A／D | 雨滴和玻璃邊緣／遮雨處 | 濕地面與水痕／騎樓或雨後路面 |
| social_ai_everyday | D／L | 文中具體設備的外觀局部／使用環境 | 無具體設備時普通環境細節／不強塞筆電 |
| social_after_hours | A／D | 走廊末端與關上的門／公共過渡空間 | 室外天色在窗面的反光／無精確位置 |
| social_online_comparison | A／D | 陽台植物和空間一角／日常環境 | 牆面材質與光線／室內，不強塞手機 |
| social_public_courtesy | L／A | 公共通道地面與欄杆／通行空間 | 車廂門邊局部／無可讀標示，不預設台北捷運 |
| relationship_pace | A／D | 窗簾與自然垂墜／室內一角 | 路邊植物和牆面／普通街道 |
| relationship_reciprocity | A／D | 衣料或毯子皺摺／居家局部 | 步道邊緣與樹影／普通戶外 |
| relationship_own_life | A／D | 有貼文支持的個人活動物件／活動位置 | 無活動錨點時的窗邊景物／普通環境 |
| relationship_disagreement | A／D | 一段牆面和落影／室內 | 雨後窗面或植物局部／普通環境，不擺兩只杯子 |
| value_time | A／D | 光線移動的亮暗邊界／日常環境 | 出入口局部材料與影子／不預設時鐘 |
| value_reliability | D／A | 文中提到的準備物件／相關位置 | 無具體事件時的日常環境局部／不編造赴約 |
| value_spending | D／A | 貼文提到的舊物使用痕跡／日常位置 | 包的布料或拉鍊局部／不預設發票、金額 |
| value_unfilled_time | A／D | 雲和建築邊界／戶外 | 紗簾與通風的輕微形變／室內 |
| interest_current_fixation ※ | L／D | 受控興趣選出的物件／對應活動位置 | 同興趣的局部過程／相容位置，不混整桌嗜好 |
| weekend_brunch | L／D | 實際早午餐／用餐位置 | 餐點切面與餐具／用餐位置 |
| weekend_outing | L／A | 文中外出地點的合理景物／戶外 | 公共步道或植栽細節／一般外出環境 |
| weekend_slow | D／A | 寢具自然皺摺／居家 | 窗邊地面與柔和環境光／居家 |
| cafe_hunt | L／D | 店內飲品或咖啡設備／無店名咖啡空間 | 吧台材料與實際飲品／局部畫面 |
| home_kitchen | L／D | 文中食材的加工狀態／廚房 | 烤盤、鍋緣或食物紋理／料理位置 |
| book_note | D／L | 書本側邊與書籤／閱讀位置 | 闔上的書和椅墊局部／不露可讀封面 |
| screen_night | D／L | 遙控器和沙發使用痕跡／觀影位置 | 無可辨識內容的反射色光／居家，不生品牌 UI |
| live_music | L／D | 樂器和音箱局部／舞台設備附近 | 線材與踏板／演出空間局部，不出人物 |
| photo_walk | L／D | 建築表面或街角／貼文相容街區 | 水面或玻璃反射局部／步行途中 |
| travel_plan | D／L | 行李收納局部／準備空間 | 素面旅行用品／準備空間，不生成已抵達照片 |
| sea_day | L／D | 海浪與岸邊／貼文相容海岸 | 浪退後的沙面或石面／同海岸類型 |
| workout_done | D／L | 貼文提到的器材／健身空間 | 用過的墊子或毛巾局部／運動位置 |
| trail_day | L／D | 山徑與植被／步道 | 石階或泥土路面／步道局部 |
| pet_moment | L／D | 文中明講的動物／相容環境 | 無物種與事件錨點時寵物用品局部／中性照護環境 |
| pet_house_rules | D／L | 文中提到的生活痕跡／居家位置 | 受影響的墊子或毯子／不擅自補另一物種 |
| pet_care_detail | D／L | 文中用品／清潔或照護位置 | 梳具、毛巾局部／相容環境 |
| pet_owner_routine | D／L | 文中照護物件／相關位置 | 用過的用品細節／不由興趣推論擁有寵物 |
| food_find | L／D | 實際發現的食物／用餐位置 | 切面、表面或吃過的痕跡／同餐點 |
| exhibition_visit | L／D | 展場空間結構／展示環境 | 展件材質局部／無可讀說明與品牌，不複製指定作品 |
| style_note | D／L | 貼文提到的衣料或配件／自然放置位置 | 縫線、扣件、材質／近景，無人物身體 |
| night_walk | L／D | 夜間步道／既有環境光 | 燈光在路面或水面的反射／相關夜間環境 |
| money_habit ※ | D／A | 貼文支持的耐用物品／日常位置 | 包或收納物件的使用痕跡／不以金錢符號配圖 |
| audio_note | D／L | 耳機或音訊器材／使用位置 | 耳罩材質、線材或旋鈕局部／相容環境 |
| making_things | L／D | 單一手作項目的未完成材料／工作位置 | 同項目的邊緣與製作痕跡／近景，不混多種活動 |
| tech_curiosity | L／D | 貼文提到的科技產品外觀／使用環境 | 連接埠、外殼或按鍵局部／無品牌與介面 |
| city_detail | D／L | 牆面、磚面或窗框／城市步行環境 | 路緣植栽與建築接縫／同類環境 |
| shift_end | D／L | 貼文提到的下班物件／相容場景 | 外套或包的局部／過渡空間，不固定便當＋熱飲 |
| clinic_day | D／A | 普通收納和材料局部／非識別性室內 | 接待區植物與表面／無病歷、病人、可讀資料 |
| layover | D／L | 行李箱與窗邊／停留空間 | 行李收納或窗外無定位景物／禁套用居住城市 |
| campus_grind | D／L | 文中讀書材料／學習位置 | 文具使用痕跡與書本邊緣／學習位置 |
| lab_grind | D／L | 實驗情境支持的器材／實驗空間 | 玻璃器皿或設備局部／無可讀標籤，不預設咖啡 |
| shop_open | L／D | 文中店務設備／店內位置 | 備料或設備狀態／同種店務，不硬塞咖啡機 |
| deadline_night | D／L | 當篇工作材料／夜間工作位置 | 用過的工具或材料局部／相容工作位置 |
| class_done | D／L | 貼文支持的上課用品／相容教室 | 教室地面與設備局部／不一律瑜珈 |
| coach_day | D／L | 文中訓練器材／運動空間 | 訓練後器材狀態／相容運動位置 |
| flower_shop | L／D | 單一花材或花束／花藝工作位置 | 剪下的花梗和包裝材料／同一工作過程 |
| grooming_day | D／L | 受控梳具和用品／寵物照護位置 | 毛巾和用品使用狀態／不杜撰客人寵物外貌 |

咖啡、觀點類、科技桌面、寵物、夜景等容易出問題的題材優先加第三、四個候選；不為湊數讓每種都有六七個。對照使用正式 `MOMENT_THEME_IDS`，parity test 指出差異，不在測試內手抄 62 個 ID。

## 附錄 B：可重查來源

| 來源 | 用途 |
| --- | --- |
| `supabase/functions/practice-chat/moments_image_gen.ts@957cdbb` | 前綴、62 場景句、驗證器、DeepSeek、fal、重試與儲存流程；檔頭註解確認無 `negative_prompt` |
| `moments_handler.ts@957cdbb:203-208, 335, 407, 565, 695` | 生圖判定、兩個 job 建構點、freshness 補位、排程 |
| `moments_schedule.ts@957cdbb:42, 318-352, 676, 804, 982-984` | 配圖機率、飼主線索、題材清單、fnv1a、配圖資格閘門 |
| `moments_image_catalog.ts@957cdbb` | 20 張素材標籤與 `momentImagesForTags` |
| `moments_constants.ts@957cdbb` | attempts、timeout、租約、寬限、尺寸、14 天窗 |
| `practice_persona.ts@957cdbb` | 100 角色、43 職業、10 城市、90 興趣、`photoScene` |
| `handler.ts@957cdbb:2329-2373` | kill switch 與 deps 注入 |
| `lib/features/practice_chat/presentation/widgets/practice_moment_tile.dart@957cdbb:27-34, 176-178` | 圖寬比、高度上限、cover |
| `moments_generated_only_source_test.ts`、`moments_image_gen_test.ts`、`moments_image_flow_test.ts` | 現有守門與 V1 契約 |
| `.github/workflows/flutter-ci.yml` | deno 測試白名單 |
| `docs/plans/2026-08-25-practice-moments-generated-images.md` §9、§11、§14 | 安全邊界、成本模型、已定案 |
| `docs/practice-moment-image-activation-runbook.md` | kill switch 語意與健康線 |
| `docs/bug-log.md` 2026-09-08 | `photoScene` 的由來 |
| fal Seedream 4.5 API：https://fal.ai/models/fal-ai/bytedance/seedream/v4.5/text-to-image/api | 公開參數契約 |
| GenEval：https://arxiv.org/abs/2310.11513 | 不以單一整體相似度取代逐項驗收 |

本次靜態統計以 HEAD 檔案用 Python 對名冊欄位與場景字詞計數；分流桶數以正式 `fnv1a` 實作重算。沒有跑產品測試、建置或任何模型呼叫。
