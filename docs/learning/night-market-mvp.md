# 台灣夜市 Sydney 情境練習 MVP

> 文件狀態：可 review 的劇本與驗收整理。本文不把影片、音訊、poster 或真機驗收寫成已完成；目前依 repo 內的 finite story source 整理。劇本資料來源：`lib/features/night_market/data/night_market_story.dart`。

## 範圍與入口

- 這是一段有限互動影片練習，不是自由 3D 場景。共 14 個 video beats；各路徑片段 duration 以媒體 QA 為準。實際一輪還包含選項閱讀、語音與方法卡，產品入口標示約 4 分鐘。
- Learning 順序是 Hero 後的獨立小卡「和 Sydney 逛夜市」，副文為「一起逛攤位，練習開口與接話。約 4 分鐘」，點擊 `/practice-night-market`。
- 路由建立 `NightMarketScreen`；選項與結果在本頁完成，不新增 session、quota 或 chat context。Leah CTA 使用中性文案「開啟 Leah 文字陪練」；`startSessionWithProfile` 若已有 Leah 開啟中的對話則恢復該對話，否則建立新的對話，且不注入夜市影片 context。
- 原生依賴是 `video_player` 與 `audioplayers`。影片與聲音採 bundle manifest 路徑；目前約定根目錄為 `assets/videos/night_market/`、`assets/audio/night_market/`、`assets/images/night_market/`，不依賴 localhost 或遠端 URL。

## 目前 story source 的完整一輪

以下以 `night_market_story.dart` 現行 source 為準：Sydney 先陪玩家進場（`establish`），再於 `hesitate` 引導吐氣，玩家可走近或繼續逛。走近後依序經過開場、自我介紹與推銷疑慮（`opening → concern`），回答來意後交換工作資訊（`work`），再以陶杯故事接話（`craft → tease`）。茶攤叫號與 Leah 等茶（`call`）後，由預先指定的 `available` 或 `busy` run variant 決定時間情境，並非玩家替 Leah 選擇。

- `available`：Leah 表示朋友二十分鐘後才到、還能逛一下並問陶杯；`invite_craft_stall → date → decline → coach`（一起看杯後友善道別），或 `leave_available → decline → coach`。
- `busy`：Leah 表示朋友在前面等，但說杯子故事蠻好笑；`offer_contact → contact → coach`，或 `respect_busy_bye → decline → coach`。
- `hesitate` 的 `keepwalking` 直接進 text-only `pause_ending`，只做文字復盤，不播放 coach 影片。
- `coach` 提供 `retry_earliest → opening` 與 `retry_callback → craft`；重練時清除該段之後的本輪選項與方法卡答案。

14 個 video beat 為 `establish, hesitate, opening, concern, work, craft, tease, call, available, date, busy, contact, decline, coach`；`pause_ending` 是額外的 text-only ending。完整對白與 caption timing 以 source 為單一真實來源。

## 角色與影片元素

- Sydney：場外教練，開場、遲疑與結尾回顧提供提示。
- Leah：夜市中被搭話的真人角色；片段包含她的回應、工作、陶杯話題與時間狀態。
- 使用 original elements 的驗收重點：原生 16:9 影片保持完整畫面；直式手機上方顯示電影框，下方顯示字幕、提示與選項；字幕不可遮住人物臉部。缺 poster 或 media 時只能顯示可讀文字 fallback。

## Flow 與 14 clips

主流程為 `establish → hesitate → opening → concern → work → craft → tease → call → (available | busy)`；`available`、`busy` 各自再進入結果片，最後到 `coach`。`hesitate` 另有 `keepwalking → pause_ending`；所有選項只能在該片完成後出現。

| clip | 內容（完整字幕取自 story source） | 選項與下一片 |
|---|---|---|
| `establish` | Sydney：「你剛剛不是說只吃一攤？好啦，先逛一圈。前面有家手作攤。」 | 自動 `hesitate` |
| `hesitate` | Sydney：「有想認識她？先吐口氣。三、二、一。從她看得到的地方過去，我在這裡。」 | `approach` 走到她看得到的側前方 → `opening`；`keepwalking` 先繼續逛夜市 → `pause_ending`（文字復盤） |
| `opening` | 使用者：「嗨，妳這件米色外套搭得很好看，剛剛經過就注意到了。我想來跟妳打個招呼。」 Leah：「喔，嗨。」 | `introduce` 我叫阿澤，剛下班來逛逛。→ `concern`；`pressure_wait` 等一下，妳先不要走。→ `decline` |
| `concern` | Leah：「你不是在賣東西吧？剛剛好多人在發傳單。」 | `answer_intent` 不是，我沒有東西要賣；就是想跟妳聊兩句。→ `work`；`challenge_sales` 妳看我像推銷員嗎？→ `decline` |
| `work` | Leah：「喔，原來是這樣。我叫 Leah。你是做什麼的？」 | `share_product_design` 我做產品設計，把亂的東西整理成好用的流程。妳呢？→ `craft`；`ask_demographics` 就上班啊。妳幾歲？→ `decline` |
| `craft` | Leah：「我做職能治療。下班有時去做陶杯。」使用者：「我第一次拉坯，杯子歪得很有個性。」Leah：「那是杯子還是花盆？」使用者：「介於兩者，老師說很有個人風格。」 | `share_pen_holder` 現在拿來放筆了，放在桌上剛剛好。→ `tease`；`share_pen_holder_light` 老師人很好，至少我做出了一個筆筒。→ `tease` |
| `tease` | Leah：「至少還用得上。你很常這樣跟女生打招呼嗎？」 | `first_today` 今天第一個。→ `call`；`hungry_vendor` 我比較常跟老闆搭話，因為我肚子餓。→ `call` |
| `call` | Leah：「至少你有先說來意。」攤主：「十七號，無糖烏龍！」Leah：「我的茶好了，等我一下。」 | 自動依 run variant 進 `available` 或 `busy` |
| `available` | Leah：「我朋友還要二十分鐘才來，還能逛一下。旁邊那家是在賣陶杯嗎？」 | `invite_craft_stall` 要不要去旁邊逛兩分鐘手作攤？→ `date`；`leave_available` 那我們先各自逛，今晚玩得開心。→ `decline` |
| `date` | Leah：「好啊，去看一下。」使用者：「這杯子比我的直很多。」Leah：「拉坯要慢一點，急了就會歪。」使用者：「那今天先欣賞就好。」Leah：「先不要把它碰倒。」 | 重用 `decline` 友善道別片 → `coach`；此分支不是拒絕 |
| `busy` | Leah：「朋友在前面等我了。不過剛剛那個杯子的故事蠻好笑的。」 | `offer_contact` 妳願意的話我留我的，改天喝無糖烏龍；不用現在回。→ `contact`；`respect_busy_bye` 了解，祝妳今晚逛得開心，再見。→ `decline` |
| `contact` | Leah：「好啊，我掃你。下次可以看看那個很有個性的杯子。我要先走了，掰掰。」 | 自動 `coach` |
| `decline` | Leah：「謝謝，我先走了。祝你們逛得開心。」 | 自動 `coach` |
| `coach` | Sydney：「剛剛哪一句，讓你最想急著解釋？先接住對方說的，再選你真的想說的。這個比背台詞重要。」 | `retry_earliest` 再練一次開場 → `opening`；`retry_callback` 再練一次話題延伸 → `craft` |

## 三種結果與重練

1. `date → decline`：有空情境下一起看杯後友善道別；`decline` 是共用的內部 asset ID，此路徑不是拒絕。
2. `contact`：忙碌情境下交換一次聯絡方式後道別。
3. 其他 `decline`：包含尊重離開、施壓後修復、質疑推銷或漏接問題等友善／明確收尾；結局回顧依本輪完整選項歷史顯示具體練習點。
4. `keepwalking` 是遲疑時的獨立尊重自己步調路徑，直接進已完成的 `pause_ending` text-only ending，只顯示文字回顧，不播放帶有「剛剛哪一句」提問的 coach 影片。

重練 opening 或 craft 時，應清除該段之後的本輪選項與方法卡答案；上一輪的錯誤不可帶入新一輪回饋。結果頁可切換 busy/available 重新開始一輪，不能把時間狀態交給玩家在對話中任意選出。

## 方法卡與學習循環

結果頁內嵌三張短方法卡，對應既有學習文章 ID `1`、`11`、`21` 的主題；短卡提供練習與回放，全文入口沿用既有文章 read gate。

- 文章 1／開場：先說你觀察到的現場，再簡短說明來意。
- 文章 11／傾聽：先回應她實際分享的資訊，再接一個相關問題。
- 文章 21／低壓邀約：把活動、時間感和可拒絕空間放進一句話。

目前短題是「她說朋友快到了，你會怎麼做？」二選一；答題後顯示解釋並可重試關鍵點。短卡全文入口沿用既有文章 read gate；不以裸 push 繞過 gate。Leah 文字 CTA 顯示「開啟 Leah 文字陪練」；已有 Leah 開啟中的對話就恢復，否則建立新的對話，不宣稱帶入夜市上下文。

## 聲音、字幕與資產完整性

- 每個有 spoken text 的選項使用 `assets/audio/night_market/<choiceId>.mp3`；影片原音、選項語音、SFX、ambient bed 不可同時以重疊音量播放。
- `market-bed.mp3` 是選項等待與男主語音期間的低音量環境底噪；mute 應設 volume 0，背景與 route cover pause，回前景 resume；缺檔時直接降級，不阻塞選項流程。
- 每個片段應有 16:9、720p 或同等完整構圖影片；poster 使用 Sydney、Leah 或 Leah-cup 對應素材。字幕 timing 以 story captions 為來源，字幕區必須可讀且不洩漏尚未播放台詞；影片錯誤時才顯示完整文字 fallback。
- 素材到位後的唯讀完整性檢查：逐一核對 14 個 `.mp4`、所有非空選項 `.mp3`、`hesitate-heartbeat.wav`、`ui-cue.wav`、poster 圖片、pubspec asset roots 與 story manifest 路徑；確認沒有 localhost/remote URL、空檔或大小寫不一致。

## 研究索引狀態

研究邊界、20 片完整索引（片號、標題、來源 URL、OCR 跨跨度狀態、時間定位與產品可取方向）集中在 [night-market-research/README.md](night-market-research/README.md) 與 [course-synthesis.md](night-market-research/course-synthesis.md)。最新 v3 拍攝 prompt 的文字副本在 [night-market-video-prompts-v3.json](night-market-research/night-market-video-prompts-v3.json)；v2 僅作早期草稿保留。5 份研究摘要未攜入原片、原始 OCR 或簽名下載 URL；研究中也明確標示未完成全片逐秒聽打、全量聲調核驗與全量身體動作標註，不能把研究索引當成影片或真機驗收證據。

## 從淺溝通到可觀察的表演細節

研究最適合轉成玩家可看見、可練習的行為線索，而不是讀取角色內心：

- 入場時 Sydney 走在玩家身邊，讓出動線；`hesitate` 的三、二、一是教練鼓勵玩家採取小步行動，不是科學門檻或倒數規則。
- 接近 Leah 應從她看得到的側前方進入，不突然拍肩、不追上去；片段只呈現有限站位與對話，不提供自由移動或觸碰操作。
- Leah 一開始的自然 surprise、眼神、停頓、拿茶與朋友訊息，是影片中可觀察的表演或場景細節；不應由產品推導成喜歡、同意或固定心理狀態。
- 選項把疑慮、共同玩笑與明確拒絕分開：先回答推銷疑慮，再接真實資訊；共同話題可用陶杯與叫號；拒絕或朋友在等時清楚離場。
- 可練的行為是說明來意、適量自我揭露、真正接住對方資訊，再提出一次具體且可拒絕的邀約。`available` 與 `busy` 是兩條預先設定的時間路徑；忙碌時可低壓留下聯絡方式，也可直接道別。
- 復盤看清楚表達、互惠接話、尊重時間與界線，不以是否收號或 Leah 是否繼續互動計分。

上述「可觀察」只指本輪影片片段與文字提示實際呈現的內容；prompt 中的理想站位、表情或動作不等於已在每片視覺驗收。MVP 沒有自由操作、自由走位或觸碰系統，不能把這些未實作能力寫成產品功能。

## 明早 iPhone 驗收路徑

1. 從 Learning Hero 往下看到「和 Sydney 逛夜市」小卡，確認 Sydney 16:9 橫幅與 fallback。
2. 點入 `/practice-night-market`，確認首屏有 poster、說明、開始按鈕與 mute，不會自動出聲。
3. 走 `approach → opening → introduce → concern → answer_intent → work`，確認每片播完才出選項，語音完成後才進下一片。
4. 各跑一次 `available`（`invite_craft_stall → date → decline`）與 `busy`（`offer_contact → contact`），再跑 `keepwalking` 與其他 `decline`，確認三種正常結尾回顧文字具體且不讀心。
5. 在影片中手動 pause/resume、選項語音中 mute、切背景再回來、route cover 再返回；確認不重播、不跳過、不永久卡住，ambient 與語音同步。
6. 點「再練一次開場／話題延伸」及「試試另一種時間情境」，確認後續歷史與方法答案已清除；確認 Leah CTA 顯示為「開啟 Leah 文字陪練」，既有對話恢復、沒有既有對話時才建立新的對話。
7. 開啟 iPhone Dynamic Type 大字級，檢查 16:9 畫面、字幕、按鈕與方法卡沒有 overflow，人物臉部不被選項遮住。
