# 抽卡揭曉動畫 V3「全息典藏揭曉」實作規格（2026-10-15）

> **狀態**：§1 的 D1–D9 於 2026-10-15 由 PR 作者照「建議」欄先定，待 Eric 在 PR review 確認（Gate-1）。第一刀（結構）與第二刀（外觀）已實作，見 §16.1、§16.2；第三刀（聲音）開工前先再確認 D3。
> **基準**：HEAD `2aae192`；`lib/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart`（3556 行，V2：10 秒兩段升階）。
> **參考**：
> 1. 夥伴提供的參考片 `gemini_generated_video_11D7DA2F.mp4`（1280×720、24fps、240 幀、10.005 s、AAC 48 kHz 立體聲；下稱「參考片」）。
> 2. 夥伴文字提案「V3 旗艦級抽卡動畫」＋工程 prompt（下稱「文字提案」）。
> 3. 前代參考片 `音檔.mp4` 與其復刻紀錄：`docs/plans/2026-06-27-card-draw-replication-design.md`、`docs/plans/2026-06-27-card-draw-replication-storyboard.md`。
>
> **範圍**：只動揭曉儀式的畫面、聲音、觸覺，以及圖鑑頁接住結果的方式。**不動**抽卡 API、額度、扣費、機率、server、DB、Edge。
> **風險等級**：R1（純 UI）。若實作途中碰到 `practice_chat_providers.dart` 的抽卡邏輯或任何額度判斷，改列 R2。

---

## 0. 摘要

一句話：把 V2 的「翻出白卡預覽 → 翻回卡背 → 再翻一次」改成「卡背蓄力、依稀有度變色 → **只翻一次** → 資訊依序落位 → **停住等使用者點** → 化成光球飛進圖鑑那一格」。

| 項目 | V2（現在） | V3（本規格） |
|---|---|---|
| 翻牌次數 | 3 次轉動（白卡預覽、翻回、正式） | 1 次 |
| 從 server 回來到看清結果 | 約 7.25 s | 1.8 s 翻開、2.7 s 全部落位 |
| 從按下到可以點 | 10 s 後自動收掉，不能自己決定 | 最快 3.2 s（server 0.5 s 內回來時），之後停多久由使用者決定 |
| 背景 | 只有暗化，開場與收場刻意讓 UI 透出 | 高斯模糊＋85% 暗化，整段看不到底下的字 |
| 稀有度預告 | 卡背固定金紫，翻開後才有 badge | 卡背銀色起跳，R 變藍、SR 再變金，只會升到真實稀有度 |
| 收場 | 整張卡半透明淡出疊在圖鑑上 | 卡縮成光球，沿弧線飛進那一格，那一格發光 |
| 圖鑑新卡發光 | 固定等 10 s 才亮 | 光球落進去的那一刻亮 |

需要 Eric 決定的事集中在 §1；其他都有建議預設值，可以直接照做。

---

## 1. 拍板項目（Gate-1：2026-10-15 PR 作者照「建議」欄先定，待 Eric 確認）

| # | 題目 | 選項 | 建議 |
|---|---|---|---|
| D1 | 節奏 | A 文字提案：server 回來後 2.7 s 全部落位（按下到可點最快 3.2 s）／B 照參考片：從蓄力到全部落位約 5.5 s | **A**。參考片在藍→金之間多轉一次、資訊分三段慢慢進，這兩處正是要修的地方 |
| D2 | 卡背素材 | A 拿現有卡背調色成中性石墨銀，另外做發光遮罩，執行時依稀有度染色（構圖、徽記不變）／B 重新生成一張 | **A**。現有卡背是金框紫徽記，一開始就像 SR，做不出「銀→藍→金」 |
| D3 | 音效來源 | A 依新時間軸重做 N／R／SR 三條揭曉配樂＋一個收卡音（自製或授權）／B 從這支參考片的音軌剪（授權要比照 `音檔.mp4` 再確認一次；時間點要整個重排） | **A**；B 可以先拿來做 Gate-2 預覽片 |
| D4 | 集滿後再抽到重複角色 | A 一樣飛進原本那一格並發光／B 原地收掉不飛 | **A**（現在重複角色不會捲動也不會發光） |
| D5 | 稀有度牌形狀 | A 金屬膠囊（文字提案；和圖鑑卡同一套語彙）／B 六角銘牌（參考片） | **A** |
| D6 | 資訊欄排版 | A 兩行：名字／基本資訊＋右側星星，只顯示亮星（參考片）／B 三行＋5 格含空星（文字提案＋現行圖鑑卡） | **A**。揭曉當下 N 卡出現 3 顆空星，觀感偏負面；圖鑑卡維持現狀 |
| D7 | 停住期間的動態 | A 提示字淡入後整個畫面靜止／B 提示字與星塵持續呼吸 | **A**。持續動畫會讓全螢幕模糊每幀重算（耗電、發熱），也讓 widget test 的 `pumpAndSettle` 收不了 |
| D8 | 觸覺密度 | SR 一輪 13 下（§9）：全留／拿掉蓄力 3 下與烙印 1 下 | 先全開，真機再刪；兩組都是單一常數開關 |
| D9 | R 的顏色 | A 揭曉用較亮的電光藍 `#38BDF8→#818CF8`，圖鑑維持 `#64B5F6`／B 揭曉也用圖鑑的 `#64B5F6` | **A**（只在儀式裡更亮，圖鑑 2026-08-09 的配色決定不動） |

---

## 2. 參考片拆解

### 2.1 逐格（4 fps 抽格；對照圖見 §19）

| 時間 | 畫面 | V3 怎麼處理 |
|---|---|---|
| 0.00–1.90 | 石墨銀卡背（銀框＋迷宮立方徽記）浮在壓暗的圖鑑上，輕微 3D 擺動；1.5 s 微放大 | **採用**：等待 server 期間＝銀色呼吸、沒有聲音 |
| 2.00 | 中央徽記白光一閃 | **採用**：蓄力起點 |
| 2.25–3.00 | 徽記與外框染成電光藍，冒藍色粒子 | **採用**：R 階預告 |
| 3.25 | 卡片轉到側面，轉回來變成金色卡背 | **不採用**：等於第二次翻轉。改成原地染金 |
| 3.50–4.25 | 金色卡背＋十字光芒＋金粉氣流 | **採用但改時點**：十字光刃放到翻牌轉到 90° 那一刻 |
| 4.25–4.75 | 翻到正面（Kira） | **採用**：全程唯一一次翻牌 |
| 4.75–5.75 | 正面落定，左上角掛「N」小牌，名字已經出現 | **修正**：這是 SR 卡，先掛 N 是錯的。稀有度牌在烙印前不存在，絕不先顯示別的稀有度 |
| 6.00–6.25 | 大號六角「SR」從畫面外砸進左上；資訊欄變毛玻璃，**寬度超出卡片** | **採用撞擊感**；**修正**：牌與資訊欄都限制在卡片範圍內 |
| 6.75–7.50 | 資訊欄右側星星逐顆點亮（4 顆） | **採用** |
| 8.00–8.25 | 停留，背景換成圖鑑格子 | **採用停留**，但改成等使用者點 |
| 8.50 | 卡片開始縮小、拉出金色拖尾，這時才出現「點擊任意處繼續」 | **修正**：提示要在停留時出現，收卡要在點擊之後 |
| 8.75–9.25 | 卡片收成細線→金色弧線→光球落進一格 | **採用** |
| 9.50–9.75 | 落點環形脈衝，格子裡只有一個箭頭圖示，然後淡出 | **採用脈衝**；**修正**：那一格要露出真正的角色卡 |

參考片是 1280×720 橫式（像是桌面渲染的示意），卡片和螢幕的比例不要照抄；卡片尺寸沿用現有 `practiceCeremonyCardSize()`（已在 390×844 上調過）。

### 2.2 參考片音軌（125 ms 窗 RMS）

| 時間 | RMS | 對應畫面 |
|---|---|---|
| 0.00–2.00 | −98 dB（靜音） | 銀色等待 |
| 2.125 | −43.9 dB | 聲音進場＝白閃 |
| 2.375 | **−26.0 dB** | 第一擊＝染藍 |
| 2.6–3.9 | −35 → −31 dB | 藍色蓄力持續 |
| 4.0–4.625 | 爬升到 **−16.5 dB（全片最大）** | 翻到正面 |
| 5.9–6.4 | −21.4 dB | SR 牌砸入 |
| 7.0–7.4 | −19.4 / −18.8 dB | 星星逐顆點亮 |
| 9.0 | −25.3 dB | 光球落位 |
| 9.4–10.0 | 淡出至靜音 | 收場 |

可以照搬的結論：等待期完全無聲（和 `docs/bug-log.md` 2026-07-16「等待期只留一次性咻聲」一致）；主峰落在唯一一次翻牌；稀有度牌、星星、落位各有一個小重音。

---

## 3. 現況（V2）診斷：痛點對到程式碼

| 痛點 | V2 實況 | 位置 |
|---|---|---|
| 雙重翻牌 | `_reveal` 10 s：3.0–3.6 s 翻出白卡預覽 → 5.0–6.0 s 翻回卡背 → 6.5–7.25 s 再翻正式卡 | `practice_draw_ceremony.dart:35-49`、`:724-799` |
| 背景穿透 | 只有徑向暗化、沒有模糊；開場 0–0.5 s、收場 8.2–10 s 暗化只剩 0.12（刻意復刻「亮 UI」） | `:75-88`、`:554-572` |
| 頂部 AppBar 永遠清楚可點 | 儀式掛在 `Scaffold.body` 的 Stack 裡，`extendBodyBehindAppBar: true` 的 AppBar 畫在 body 之上，標題與返回鍵都蓋在儀式上面 | `practice_collection_screen.dart:510-541`、`:668-670` |
| 收卡半透明殘影 | 8.2–10 s 整張卡用 `Opacity` 淡出、微縮下沉，疊在圖鑑上 | `:518-529`、`:1442-1448` |
| 時間到自動收 | `_reveal` 跑完直接 `_toHidden()`，沒有點擊繼續 | `:335-339` |
| 稀有度在翻開後才出現 | 卡背不分稀有度；badge 與星等只在第二張正式卡、和資訊一起淡入 | `:1313`、`:1412-1421` |
| 卡背素材無法升階 | 素材本身是金框＋紫徽記 | `assets/images/practice/practice_draw_card_back_base.png`、`_neon.png` |
| 等待字樣 | 抽牌中固定顯示「正在為你翻牌…」，揭曉後換「今日對象登場」 | `:623-638` |
| 圖鑑新卡發光固定等 10 s | `kCollectionHighlightWait = kPracticeRevealDuration` | `practice_collection_screen.dart:27-48` |
| 集合變化就捲動高亮 | 監聽解鎖集合變大就挑第一張新卡捲動＋發光；重新整理時也會誤觸，重複角色不會觸發 | `practice_collection_screen.dart:495-505` |
| 聲音綁死 10 s | 一條 10 s 配樂 bed，三個重音都在 bed 裡 | `practice_draw_audio_sfx.dart`、`practice_draw_sfx.dart` |
| 特效層過多 | 十多個 CustomPaint 特效層依時段開關，外加全幅爆炸圖與全幅閃光 | `:854-1085`、`:588-617` |

保留不動的好東西：`drawStatus` 單一狀態機驅動、零 Timer、唯一會 `repeat()` 的是嚴格把關的 `_waiting`、失敗只淡出不慶祝、reduce-motion 路徑、`practiceCeremonyCardSize()`、聲音的 lazy＋guarded 實作、`AudioContext` ambient（尊重靜音鍵）。

---

## 4. V3 時間軸（單一真相）

記號：**T** = 按下翻牌；**R0** = 揭曉起點 = server 成功回來 **且** 卡背入場（500 ms）已完成；**A0** = 使用者點擊收卡。

### 4.1 總覽（server 在 0.5 s 內回來時）

| T | R0 | 事件 |
|---|---|---|
| 0 | — | 點擊；觸覺 `light()`；咻聲；預載揭曉音效 |
| 0–300 | — | 背景模糊 σ 0→24、暗化 0→0.85 |
| 100–500 | — | 卡背入場 |
| 500 | 0 | 揭曉開始：咻聲淡出、播對應稀有度的配樂、預快取照片、通知圖鑑頁捲到目標格 |
| 500–1100 | 0–600 | 蓄力：縮小、後仰、銀光增強 |
| 1100 | 600 | R／SR：染成電光藍 |
| 1350 | 850 | SR：爆閃升級為香檳金＋全息彩光 |
| 1600–1850 | 1100–1350 | 翻牌前半（加速） |
| 1850 | 1350 | 卡片側立 90°：光刃＋星塵爆發；最重的一下觸覺 |
| 1850–2300 | 1350–1800 | 翻牌後半（高阻尼減速）＝正面落定 |
| 2000–3200 | 1500–2700 | 照片 1.08→1.00 緩縮 |
| 2200–2900 | 1700–2400 | 全息斜向掃光 |
| 2350–2650 | 1850–2150 | 毛玻璃資訊欄浮現 |
| 2500–2750 | 2000–2250 | 稀有度牌烙印 |
| 2650–3110 | 2150–2610 | 星星逐顆點亮（間隔 80 ms） |
| 2900–3200 | 2400–2700 | 「點擊任意處繼續」淡入 |
| 3200 | 2700 | 進入停住（holding），畫面完全靜止 |
| 點擊 | A0 | 收卡：0–150 坍縮成光球 → 150–450 弧線飛行 → 450 落位、那一格發光 → 550 儀式收掉 |

server 在 0.5 s 內回來時，T 欄就是文字提案「黃金 4.0 秒」的時間，逐點對齊。server 慢的時候，差別只在卡背多呼吸一陣子，R0 之後的節奏完全一樣。

### 4.2 drawing（以 T 為 0）

| 屬性 | 數值 | 曲線 |
|---|---|---|
| 背景模糊 σ | 0 → 24（0–300 ms） | `AppMotion.easeOut` |
| 背景暗化 α | 0 → 0.85（0–300 ms） | 同上 |
| 卡背 scale | 0.85 → 1.00（100–500 ms） | `AppMotion.easeOut` |
| 卡背 translateY | +30 → 0 px（100–500 ms） | 同上 |
| 卡背 opacity | 0 → 1（100–300 ms） | linear |
| 等待呼吸（`_waiting`，2600 ms 一圈，只在入場完成後疊上） | 上下 ±3 px、scale 1→1.010、yaw ±2°、徽記銀光 0.30–0.45 | sin |
| 等待字樣「正在為你翻牌…」 | 只有等超過 900 ms 才淡入（900–1200 ms）；R0 起 200 ms 淡出 | linear |

### 4.3 revealing（以 R0 為 0，`_reveal` 共 2700 ms）

| 段落 | ms | 屬性：起 → 迄 | 曲線 |
|---|---|---|---|
| 姿態接手 | 0–150 | 從等待呼吸當下的位置、縮放、亮度，線性混到蓄力姿態（避免跳格） | linear |
| 蓄力 | 0–600 | scale 1.00→0.92；pitch(rotateX) 0→6°；yaw(rotateY) 0→−8°；徽記銀光 0.35→0.80；外框銀光 0.25→0.60 | `Curves.easeInOutCubic` |
| 停頓 | 600–1100 | 姿態維持 0.92／6°／−8° | — |
| 染色（N） | 600–800 | 不變色，只做一次銀光脈衝 0.80→1.00→0.85 | easeOut／easeIn |
| 染色（R、SR 第一段） | 600–720 | 徽記＋外框 銀 → 電光藍漸層；徽記亮度衝到 1.0；背後環境光放大 1.00→1.15 | `AppMotion.easeOut` |
| 染色（SR 第二段） | 850–1000 | 藍 → 香檳金；徽記白色爆閃 120 ms；外框疊上全息彩虹描邊；環境光 1.15→1.35；金色星塵開始飄 | `AppMotion.easeOut` |
| 翻牌前半 | 1100–1350 | yaw −8°→90°（`easeInBack` 會先往回拉約 10° 再衝） | `Curves.easeInBack`＝`Cubic(0.6, −0.28, 0.735, 0.045)` |
| 翻牌峰值 | 1350 | 卡片正好側立：光刃 250 ms＋星塵爆發（§6.7、§6.3） | — |
| 翻牌後半 | 1350–1800 | yaw 90°→180°；scale 0.92→1.00；pitch 6°→0° | `AppMotion.easeOut`＝`Cubic(0.23, 1, 0.32, 1)` |
| 照片緩縮 | 1500–2700 | 照片 scale 1.08→1.00（1350–1500 維持 1.08），縮放中心 `Alignment(0, −0.3)` 保住臉 | `Curves.easeOut` |
| 全息掃光 | 1700–2400 | 斜向光帶 translateX −120%→+120% | `Curves.easeInOut` |
| 資訊欄 | 1850–2150 | opacity 0→1；translateY +12→0 | `AppMotion.easeOut` |
| 稀有度牌 | 2000–2250 | scale 1.6→1.0（會略微壓過 1.0 再回彈＝撞擊感）；opacity 0→1（前 100 ms） | `Curves.easeOutBack`（celebrate 檔） |
| 星星 | 2150＋80·i 起，每顆 220 ms | scale 0→1.25（前 60%）→1.00（後 40%）；同時一次發光脈衝 | easeOut／easeInOut |
| 提示字 | 2400–2700 | 「點擊任意處繼續」opacity 0→0.72、translateY +6→0 | `AppMotion.easeOut` |

翻牌正反面判斷：`yaw > 90°` 才畫正面（正面內層再 `rotateY(π)` 鏡像回來，沿用 V2 做法）；yaw 剛好 90° 時卡片側立看不見，由光刃遮住換面。

### 4.4 holding 與點擊規則

| 階段 | 點擊／Android 返回 |
|---|---|
| drawing | 點擊吞掉、不穿透到底下的圖鑑（背景已模糊看不清，誤點卡片會跳進練習室）；不攔截返回（離開頁面＝儀式 dispose，聲音照現有出口收乾淨） |
| revealing，R0 < 1800 ms | 忽略點擊；返回鍵吞掉 |
| revealing，1800–2700 ms | 跳過：剩下的對拍點全部標成已觸發（不補震、不補聲），`_reveal.animateTo(1.0, 180 ms, easeOut)` 快轉到落定 |
| holding | 開始收卡 |
| archiving | 忽略 |

holding 期間**零動畫幀**（D7=A）：整個畫面靜止，直到使用者點擊。沒有任何計時器，也不會自己收掉。

### 4.5 archiving（以 A0 為 0，`_archive` 共 550 ms）

| ms | 內容 | 曲線 |
|---|---|---|
| 0 | 播收卡音；配樂 bed 250 ms 淡出 | — |
| 0–80 | 資訊欄、稀有度牌、星星淡出 | linear |
| 0–150 | 卡片 scale 1.0→0.15；卡面疊一層稀有度色的徑向光，透明度 0→1，像整張卡變成光；60–150 卡片本體淡出 | `Curves.easeInCubic` |
| 90–150 | 光球在卡片中心長出（核心 14→18 px、外暈 48 px） | `AppMotion.easeOut` |
| 150–450 | 光球沿二次貝茲曲線飛向目標格中心，半徑漸縮到 10 px；拖尾＝10 個沿路徑回推的殘影，外加 8 顆沿途灑落的星點 | `Curves.easeInOutCubic`（作用在路徑參數 t） |
| 150–500 | 背景模糊 σ 24→0、暗化 0.85→0，底下的圖鑑慢慢清楚 | `Curves.easeOut` |
| 450 | 落位：呼叫 `onArchived(profileId)`，圖鑑那一格開始發光脈衝；觸覺 `light()` | — |
| 450–550 | 落點光環從 0 擴到目標格對角線的 0.6 倍、透明度 0.9→0；光球 60 ms 縮到 0 | `Curves.easeOut` |
| 550 | `_toHidden()` | — |

找不到目標格（沒建出來、不在畫面內）時：光球不飛，150–350 ms 在原地縮到 0 並柔閃一下；背景照常淡出；450 ms 照常呼叫 `onArchived`。**不採用**文字提案「飛到第一格」，因為已解鎖的卡排在前面，第一格通常不是剛抽到的人，飛過去會誤導。

### 4.6 曲線對照

| 文字提案（CSS） | Flutter | 說明 |
|---|---|---|
| `cubic-bezier(0.6, −0.28, 0.735, 0.045)` | `Curves.easeInBack` | 完全相同 |
| `cubic-bezier(0.16, 1, 0.3, 1)` | `AppMotion.easeOut`＝`Cubic(0.23, 1, 0.32, 1)` | 肉眼幾乎一樣；DESIGN.md §6 要求動效曲線從 `AppMotion` 拿，不另開魔術數字 |
| 星星 0→1.25→1.0、稀有度牌撞擊 | `Curves.easeOutBack` | DESIGN.md §6：彈感只准 celebrate 檔，這兩處屬於慶祝時刻 |
| `perspective: 1200px` | `Matrix4.identity()..setEntry(3, 2, 1 / 1200)` | V2 是 0.001（≈1000 px） |

---

## 5. 狀態機與 controller

### 5.1 階段轉移

`hidden → drawing → revealing → holding → archiving → hidden`

| 從 | 條件 | 到 | 動作 |
|---|---|---|---|
| hidden | `!prev.isDrawing && next.isDrawing` | drawing | 觸覺 `light()`、`playWhoosh()`、`preloadReveal()`、`_intro.forward(from: 0)`、`_caption.forward(from: 0)`、`_waiting.repeat()`。reduce-motion：`_intro.value = 1`、`_caption.value = 1`（背景直接定在 σ24／α0.85、等待字樣直接顯示），不跑 `_waiting` |
| drawing | 仍是 drawing 的其他狀態更新（練習室的提示、拆解剛好回來） | drawing | 不理：不是結果，不能當成失敗淡出 |
| drawing | 抽成功（`isRevealed && errorMessage == null && girl != null`），非 reduce-motion | revealing | 若 `_intro` 尚未完成，先記 `_pendingReveal`，等 `_intro` completed 再開始（儀式還是 hidden 時——抽牌中離開圖鑑又回來——接著 `_intro.forward()` 把入場走完，不重播咻聲與觸覺）；開始時抓等待姿態與等待字樣當下的透明度、`_waiting.stop()`、`_caption.stop()`、`stopWhoosh()`、`playRevealBed(girl.rarity)`、`precacheImage(照片)`、`onRevealTarget(girl)`、`_reveal.forward(from: 0)` |
| drawing | 抽成功，reduce-motion | hidden | 觸覺（SR `celebrate()`，其餘 `medium()`，沿用現有）、`onRevealTarget(girl)`、`onArchived(id)`、`stopWhoosh()`（沒有配樂可以交棒）、`_toHidden()` |
| drawing／revealing | 失敗（error／402／429／換一位失敗） | hidden | 停 `_waiting`、`_caption`；`stopWhoosh()`、`stopRevealBed()`；清 `_pendingReveal`；`_intro.reverse()`（最長 500 ms 淡出；reduce-motion 或 `_intro` 為 0 時直接 `_toHidden()`） |
| revealing | `_reveal` completed | holding | 只 `setState` 一次 |
| holding | 點擊／返回鍵 | archiving | 解析目標格、`playArchive()`、`_archive.forward(from: 0)` |
| archiving | `_archive` completed | hidden | `_toHidden()`（收掉所有聲音、清對拍紀錄、歸零 controller） |

dispose：停所有聲音、dispose 所有 controller；dispose 之後不得再呼叫任何 callback（每個 callback 前檢查 `mounted`）。

### 5.2 Controller

| controller | 長度 | repeat | 用途 |
|---|---|---|---|
| `_intro` | 500 ms | 否 | 背景模糊／暗化進場、卡背入場；失敗時 `reverse()` 當淡出 |
| `_caption` | 1200 ms | 否 | 等待字樣（900–1200 ms 淡入）；揭曉或失敗時 `stop()` |
| `_waiting` | 2600 ms | **是**，只在 drawing 且非 reduce-motion | 銀色呼吸 |
| `_reveal` | 2700 ms | 否 | 蓄力 → 提示字 |
| `_archive` | 550 ms | 否 | 坍縮 → 飛行 → 落位 |

鐵則沿用：儀式檔內**零 `Timer`、零 `Future.delayed`**；唯一 `repeat()` 是 `_waiting`。holding 期間沒有任何動畫，所以 `pumpAndSettle` 會停在 holding 收斂，測試要自己點「繼續」才會收掉（§14）。

### 5.3 對拍點（beats）

沿用 V2「`_reveal` 每個 tick 比門檻、集合確保只觸發一次」的機制，換成新的點：

| beat | R0 ms | 觸發內容 |
|---|---|---|
| `chargeTick0/1/2` | 0／200／400 | 觸覺 `tick()` |
| `dyeBlue` | 600 | R：`light()`；SR：`tap()` |
| `dyeGold` | 850 | SR：`light()` |
| `srBuild` | 1150 | SR：`celebrate()`（三下共 200 ms，第三下重擊落在 1350） |
| `flipPeak` | 1350 | N、R：`medium()` |
| `stamp` | 2000 | `tap()` |
| `star0…star4` | 2150＋80·i | 只對亮星觸發 `tick()`（N 2、R 3、SR 4） |
| `archiveLand`（`_archive`） | A0＋450 | `light()`、`onArchived(profileId)` |

所有聲音重音都做在配樂 bed 裡（§8），對拍點只負責觸覺與 callback。

### 5.4 邊界情況

| 情況 | 行為 |
|---|---|
| server 比卡背入場還快回來 | 等 `_intro` 完成（500 ms）才開始揭曉，保證有入場 |
| server 很慢 | 卡背持續呼吸；900 ms 後出現等待字樣 |
| 揭曉或停住中離開頁面 | dispose 收掉聲音；不呼叫 callback |
| 抽牌中離開圖鑑又回來 | 新掛上的儀式還是 hidden；結果回來時接著把卡背入場走完再揭曉，不重播咻聲與觸覺 |
| 圖鑑的 +1 比揭曉起點晚一兩幀 | 揭曉中的這張卡先當成已解鎖來排序，捲動估算與光球目標都指向它解鎖後的位置 |
| 同一頁連續抽 | 收卡完成回到 hidden 才能再按翻牌（overlay 期間攔住所有點擊） |
| 目標格不在畫面內 | 原地收束（§4.5） |
| 開著稀有度 filter、新卡被濾掉 | `onRevealTarget` 先收 filter（現有邏輯搬過來） |
| SR 翻牌券 | 和一般 SR 同一條路 |
| 文字放大（Dynamic Type） | 卡面用 `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3)`，名字與基本資訊單行省略 |
| VoiceOver | 停住時整層是一個按鈕：label「已抽到 {名字}，{稀有度} 卡」、hint「點兩下收進圖鑑」；資訊欄不設 `liveRegion`（停住時整層已主動唸出抽到誰，兩邊都設會連唸兩次）。儀式不是 hidden 時整層包 `BlockSemantics`（比照 ModalBarrier），讀屏碰不到底下的翻牌鈕與返回鍵 |
| Android 返回鍵 | 依 §4.4；用 `PopScope(canPop: false)`，只在 revealing／holding／archiving 生效 |

**稀有度誠實規則**：染色只會升到真實稀有度。N 全程銀；R 只會出現銀→藍；SR 才會出現金。不做「先金後退回藍」之類的假動作。這條要有測試釘住（§14）。

---

## 6. 圖層與元件規格

### 6.1 圖層順序（下 → 上）

| 層 | 元件 | 出現時段 |
|---|---|---|
| L0 | `RevealBackdrop`：`BackdropFilter` 模糊＋暗化＋暗角 | drawing → archiving 前段 |
| L1 | `AmbientGlow`：卡片背後的稀有度色徑向光 | drawing → archiving 前段 |
| L2 | `BokehDust`：環境星塵＋翻牌爆發星塵（同一個 painter） | drawing → holding |
| L3 | `Card3D`：卡背／卡面（含照片、掃光、稀有度牌、資訊欄、星星） | drawing → archiving 0–150 |
| L4 | `LightBlade`：垂直光刃（SR 加橫向十字） | R0 1350–1600 |
| L5 | `Caption`／`ActionHint`：等待字樣／點擊提示 | 見 §4 |
| L6 | `ArchiveOrb`：光球、拖尾、落點光環 | archiving |
| L7 | 全螢幕點擊層（drawing 只吞點擊；revealing 起處理跳過與收卡）＋`Semantics`＋`PopScope`（revealing 起） | drawing → archiving |

整個儀式外層包 `Material(type: MaterialType.transparency)`（移到 Scaffold 之外後沒有 Material 祖先，否則文字會出現除錯底線）。

### 6.2 RevealBackdrop

- `BackdropFilter(filter: ImageFilter.blur(sigmaX: σ, sigmaY: σ))`，σ 依 §4 動畫；**不要**把 BackdropFilter 包在 `Opacity`／`FadeTransition` 裡，直接動 σ 與暗化色的 alpha。
- 暗化：`#08070F` × α（最高 0.85）。
- 暗角：`RadialGradient(center: Alignment(0, −0.06), radius: 0.95, colors: [transparent, black@0.55], stops: [0.55, 1.0])`。
- 底下的圖鑑在儀式期間除了捲動到目標格之外是靜態的；模糊＋0.85 暗化之後，捲動只剩極淡的移動感。若真機效能不過，改用 §12 的 Plan B（一次性截圖模糊）。

### 6.3 AmbientGlow 與 BokehDust

- AmbientGlow：圓形徑向漸層，顏色＝主題 `glow`，α：N 0.22、R 0.32、SR 0.45；半徑＝卡高 × 0.75 × scale（scale 依 §4.3）。
- 環境星塵：14 顆，向上漂 8–14 px/s，大小 1–3 px，α 0.15–0.45；holding 期間凍結（D7=A）。
- 爆發星塵（R0＋1350 起）：N 20、R 26、SR 34 顆。尺寸分布：65% 1.5–2.5 px、28% 3–5 px、7% 9–14 px 失焦大光斑（α ≤ 0.25，用徑向漸層畫，**不用** `MaskFilter.blur`）。初速 120–260 px/s、阻尼 k＝2.5/s、向上漂 18 px/s、壽命 900–1400 ms。
- 位置全部由時間解析計算（`r(τ) = v/k·(1 − e^(−kτ))`，角度用 golden angle＋index），**零 Random**、可重現、測試可直接比對。

### 6.4 Card3D

```
Transform(
  alignment: Alignment.center,
  transform: Matrix4.identity()
    ..setEntry(3, 2, 1 / 1200)
    ..rotateX(pitch)
    ..rotateY(yaw),
  child: Transform.scale(scale: s, child: yaw > 90° ? 鏡像正面 : 卡背),
)
```

- 尺寸：沿用 `practiceCeremonyCardSize()`（寬 0.90×螢幕、上限 390、2:3、卡高上限 0.64×螢幕高）。位置 `Alignment(0, −0.08)`，下方留給提示字。
- 圓角：卡背、卡面都是 24（DESIGN.md §4）。
- 揭曉開始時抓等待姿態（float、縮放、亮度），前 150 ms 線性混到蓄力姿態。

### 6.5 卡背（中性石墨銀＋執行時染色）

素材（D2=A）：由現有 `practice_draw_card_back_base.png` 離線調色產出，構圖與迷宮立方徽記不變。

| 檔案 | 內容 |
|---|---|
| `practice_draw_card_back_v3_base.webp` | 石墨拉絲底＋銀色倒角框＋銀色徽記（全中性，不帶金紫） |
| `practice_draw_card_back_v3_emblem_mask.webp` | 徽記＋星軌線條的白色遮罩（透明底） |
| `practice_draw_card_back_v3_frame_mask.webp` | 外框發光遮罩 |
| `practice_draw_card_back_v3_glow.webp` | 預先模糊好的徽記＋外框光暈（白，透明底） |

組合：底圖 → 遮罩用 `ShaderMask(blendMode: BlendMode.srcIn)` 套主題漸層（`backTint → backTintDeep`），透明度＝亮度值 → 光暈圖用 `ColorFiltered` 染色後疊加（`BlendMode.plus`）。SR 金階再疊一層彩虹 `SweepGradient` 描邊（α 0.35）。全部預先做好、執行時只染色，不在逐幀 painter 裡做模糊。大小目標：四張合計 < 600 KB（webp）。

### 6.6 卡面

| 元件 | 規格 |
|---|---|
| 外框 | 1.5 px 雙層倒角：外層 1.5 px 漸層描邊（主題 `frameLight → frameDeep → frameLight`，135°）＋內層 1 px 高光（左上白 @0.28 → 透明）；外光 `BoxShadow(主題 glow @0.35, blurRadius 24)` |
| 照片 | `PracticeGirlPhoto`，內圓角 22；緩縮只作用在照片（在 clip 內 `Transform.scale`） |
| 全息掃光 | 115° 斜帶：transparent 20% → white@0.40 45% → `#FFD778`@0.30 50% → transparent 80%（文字提案原值）；`BlendMode.softLight`（不夠亮再試 `screen`）；強度 N 0.35、R 0.55、SR 0.85。SR 另加兩道 ±6% 偏移的細彩邊（`#22D3EE`、`#EC4899` 各 @0.18，`BlendMode.plus`） |
| 稀有度牌（D5=A） | 膠囊（圓角 999），左上 16／16，高 24、左右內距 10；字 `AppTypography.caption`（12）w900、字距 1.2、色 `brandInk`；底色依主題漸層；上緣 1 px 白 @0.55 內高光、下緣 1 px 深色 @0.5、黑色陰影 @0.35 blur 6 y 2；**烙印前不存在** |
| 資訊欄（D6=A） | 卡內左右下各內縮 12、圓角 18、內距 12×16；底 `#0F0E16`@0.68＋模糊的照片副本（見下）；邊框 1 px 白 @0.12。第一行名字：`titleLarge`（19）w800 白；第二行：基本資訊 `caption`（12）w600 白 @0.78（彈性寬度、單行省略）＋右側亮星 |
| 星星 | 只畫亮星：N 2、R 3、SR 4；尺寸 16、間距 4、顏色＝主題 `star`；`Icon(shadows:)` 做發光 |

- 文字提案的 18 px／13 px 不在字級尺度內，依 DESIGN.md §3 改為 19／12。
- 資訊欄的毛玻璃不用 `BackdropFilter`：在資訊欄範圍內 clip 一份同位置、同緩縮的照片，外包 `ImageFiltered(ImageFilter.blur(σ 16))`。這樣在 3D transform 裡也正確，也不會和全螢幕模糊搶 backdrop。
- 對比：最壞情況（照片純白）下，白 @0.78 的基本資訊對底色約 4.8:1、名字約 6.6:1，符合 DESIGN.md §8 的 4.5:1。
- 名字仍單獨成行、基本資訊用「 · 」串（沿用 V2：刻意避開練習室 hero 的「名字，年齡」字串，測試靠它找 hero）。

### 6.7 LightBlade（R0＋1350，250 ms）

- 畫在螢幕座標、卡片中心的垂直軸上（不進 3D transform，保持銳利）。
- 高 1.2×卡高；上下 15% 漸隱。
- 核心：白色 2 px→1 px。外暈寬度 W(t)：0→卡寬×0.5（前 60 ms，easeOut）→0（後 190 ms，easeIn）；橫向漸層 transparent → 主題 tint @0.55 → white @0.95 → tint @0.55 → transparent。
- SR 加一道橫向十字：寬 0.9×卡寬、核心 3 px、外暈 24 px、180 ms。
- 只用漸層，不用 `MaskFilter.blur`。

### 6.8 文字

| 文字 | 位置 | 樣式 |
|---|---|---|
| 「正在為你翻牌…」 | 卡片下方 24 | `caption`（12）w600、白 @0.60、字距 1.5，沒有底框 |
| 「點擊任意處繼續」 | 底部安全區＋24，置中 | `caption`（12）w600、白 @0.72、字距 2.0，沒有底框 |

「今日對象登場」退役。

### 6.9 ArchiveOrb

- 起點 P0＝卡片中心；終點 P2＝目標格中心（ceremony 本地座標）。
- 控制點：`mid ± n × 0.35 × |P2 − P0|`（n 為弦的單位法向量），取水平方向比較靠近畫面中線的那一側，避免弧線飛出螢幕；再夾在畫面內縮 24 px 的範圍內。
- 光球：核心白、外暈主題 `orb` 色；拖尾 10 個殘影取 `path(t − k × 0.035)`，α ×(1 − k/10)²、半徑 ×(1 − k/12)；8 顆星點在 t＝0.1·i 灑出，向外漂 20 px、300 ms 淡出。
- 落點光環：細圓環，450–550 ms 擴散淡出。

---

## 7. 稀有度主題（`PracticeRevealTheme`）

顏色常數放 `lib/core/theme/practice_reveal_palette.dart`（DESIGN.md 棘輪只豁免 `lib/core/theme/` 的 `Color(0x…)`），對應表放 feature 內的 `practice_reveal_theme.dart`。

| token | N | R | SR |
|---|---|---|---|
| `base`（＝`practiceRarityColor`，圖鑑同色） | `#A9B0B8` | `#64B5F6` | `#FFB34D` |
| `backTint` → `backTintDeep`（卡背染色） | `#E2E8F0` → `#94A3B8` | `#38BDF8` → `#818CF8` | `#FDE68A` → `#F59E0B` |
| 全息彩邊 | — | — | `#22D3EE`／`#8B5CF6`／`#EC4899` |
| `frameLight` → `frameDeep`（卡面外框） | `#F1F5F9` → `#94A3B8` | `#7DD3FC` → `#6366F1` | `#FDE68A` → `#B7791F` |
| `glow`（環境光／外光） | `#CBD5E1` | `#38BDF8` | `#F5C451` |
| 環境光 α | 0.22 | 0.32 | 0.45 |
| 爆發星塵數 | 20 | 26 | 34 |
| 星塵色 | 銀／白 | 藍／白 | 金／白（5% 粉） |
| 掃光強度 | 0.35 | 0.55 | 0.85 |
| 稀有度牌底 | `#F8FAFC` → `#A9B0B8` | `#BAE6FD` → `#38BDF8` | `#FDE68A` → `#F59E0B` |
| `star` | `#CBD5E1` | `#7DD3FC` | `#FFD166` |
| `orb`（光球／落點脈衝） | `#E2E8F0` | `#7DD3FC` | `#F5D58D` |
| 翻牌觸覺 | `medium()` | `medium()` | `celebrate()` 提前 200 ms |

暗化底色 `#08070F` 是文字提案原值；若想保留品牌紫調，可換成由 `brandInk` 推的 `#0A0612`，只改 palette 一行。

---

## 8. 音效

### 8.1 架構

| 時點 | 呼叫 | 說明 |
|---|---|---|
| 點擊翻牌 | `playWhoosh()`、`preloadReveal()` | 咻聲沿用現有 v2 檔；預載三條稀有度配樂＋收卡音 |
| R0 | `stopWhoosh()`、`playRevealBed(rarity)` | 咻聲有最長 5.5 s 的暖尾巴，V3 揭曉只有 2.7 s，不淡掉會糊在一起；`stopWhoosh()` 已內建 0.5 s 淡出 |
| A0 | `playArchive()`、`stopRevealBed()` | `stopRevealBed()` 改成播放中 250 ms 淡出再停（比照 `stopWhoosh()` 的做法） |
| hidden／失敗／dispose | `stopRevealBed()`、`stopWhoosh()` | 沿用現有出口 |

為什麼每個稀有度一條 bed、而不是每個重音各播一個短音效：audioplayers 起播延遲每次不一樣（數十 ms），80 ms 間隔的星星琶音用短音效一定會糊；V2 也是因此改成一條預先對好拍的 bed。

### 8.2 素材規格（D3=A）

| 檔案 | 長度 | 重音時點（ms） |
|---|---|---|
| `practice_draw_reveal_v3_n.m4a` | ≤ 4.0 s | 0 起蓄力 → 1350 翻牌（輕）→ 2000 烙印 → 2150／2230 星星 → 2700 後殘響 ≤ 1.3 s |
| `practice_draw_reveal_v3_r.m4a` | ≤ 4.0 s | 同上，加 600 染藍；1350 中等；星星 3 顆 |
| `practice_draw_reveal_v3_sr.m4a` | ≤ 4.0 s | 同上，加 600 染藍、850 金色升級、1350 最大；星星 4 顆；殘響較長 |
| `practice_draw_archive_v3.m4a` | ≤ 0.8 s | 0 起輕柔上升 → 450 晶亮落點 |

- 蓄力用**有音高的上升音**，以中低頻為主。文字提案寫「高頻聚氣音效」，這和 `docs/bug-log.md` 2026-07-16 衝突（寬頻高頻顆粒聲就是「西西簌簌」的來源，F2 用 2.1 kHz crossover 濾掉）。可以有清脆的鐘聲泛音，不可以有沙沙聲。
- 等待 server 期間除了一次性咻聲之外不得有任何聲音（同一條 bug-log）。
- 響度：比照 bed v4 母帶 −18 LUFS、true peak ≤ −1 dBTP；總大小 < 500 KB（沿用授權文件的預算）。
- 授權與來源寫進 `assets/audio/practice_draw/licenses/practice_draw_audio.md`。

### 8.3 介面變更（`PracticeDrawSfx`）

```dart
abstract class PracticeDrawSfx {
  void playWhoosh();
  void stopWhoosh();
  void preloadReveal();                          // 改：預載 N／R／SR 三條＋收卡音
  void playRevealBed(PracticeGirlRarity rarity); // 改：帶稀有度
  void stopRevealBed();                          // 改：播放中 250 ms 淡出再停
  void playArchive();                            // 新增
  void playWaitingLoop();                        // 不動：固定 no-op（bug-log 防回歸）
  void stopWaitingLoop();                        // 不動
  // 移除：playFlipSnap()（紙聲併進 bed）、playRevealChime()（已無呼叫點）
}
```

`NoopPracticeDrawSfx`、`AudioPlayersPracticeDrawSfx`、所有測試 spy 一起改。

---

## 9. 觸覺

`AppHaptics` 目前的階梯：`tick`＝selectionClick（自帶 70 ms 節流）、`tap`＝lightImpact、`light`＝mediumImpact、`medium`＝heavyImpact、`celebrate`＝輕→中→重三下共 200 ms。

| beat | 時點 | N | R | SR |
|---|---|---|---|---|
| 點擊翻牌 | T | `light()` | `light()` | `light()` |
| 蓄力 ×3（可關） | R0＋0／200／400 | `tick()` | `tick()` | `tick()` |
| 染藍 | R0＋600 | — | `light()` | `tap()` |
| 染金 | R0＋850 | — | — | `light()` |
| 翻牌峰值 | R0＋1350 | `medium()` | `medium()` | `celebrate()`（R0＋1150 起，第三下落在 1350） |
| 烙印（可關） | R0＋2000 | `tap()` | `tap()` | `tap()` |
| 星星 | R0＋2150＋80·i | `tick()` ×2 | `tick()` ×3 | `tick()` ×4 |
| 光球落位 | A0＋450 | `light()` | `light()` | `light()` |

- 稀有的手感必須不同（V2 已有的原則）：SR 多一下染金、翻牌是三連漸強。
- reduce-motion 沒有儀式：抽中當下 SR `celebrate()`、其他 `medium()`（不變）。
- 跳過時剩下的觸覺全部不補。
- 文字提案提到 iOS Core Haptics 的連續漸強，現有 `HapticFeedback` 做不到（`app_haptics.dart` 註解已寫明要第三方套件），V3 不加套件，用三下 `tick()` 近似。

---

## 10. 圖鑑頁連動（新契約）

### 10.1 掛載位置

`PracticeCollectionScreen.build` 改回傳 `Stack(children: [Scaffold(...), Positioned.fill(child: PracticeDrawCeremony(...))])`，讓儀式蓋住 AppBar 與狀態列區域。onboarding 引導層留在 body 裡不動（引導顯示時根本按不到翻牌）。

### 10.2 Callback

```dart
const PracticeDrawCeremony({
  super.key,
  this.onRevealTarget,
  this.archiveTargetRect,
  this.onArchived,
});

/// 揭曉開始（reduce-motion 為抽中當下）：收 filter、標記並捲到這張卡。新卡與重複角色都會呼叫。
final ValueChanged<PracticeGirlProfile>? onRevealTarget;

/// 收卡起飛前查目標格的 global rect；null 或不在畫面內 → 原地收束。
final Rect? Function(String profileId)? archiveTargetRect;

/// 光球落位（收卡 450 ms；reduce-motion 為抽中當下）：點亮那一格的脈衝。
final ValueChanged<String>? onArchived;
```

三個都是可選參數，`const PracticeDrawCeremony()` 照樣能用（練習室測試 host 不用改掛法）。

### 10.3 圖鑑頁要改的地方

| 項目 | 改法 |
|---|---|
| 捲動＋標記 | 由 `onRevealTarget` 觸發：沿用 `_onProfileUnlocked` 的收 filter、設 `_highlightProfileId`、兩段捲動，但**不再**啟動發光 |
| 解鎖集合監聽（`:495-505`） | 移除高亮用途。好處：重新整理圖鑑不會再亂捲亂亮；重複角色也能被標記（D4） |
| 目標 rect | `_highlightCardKey.currentContext` → `RenderBox` → global rect；不在可視範圍回 null |
| 發光 | 由 `onArchived` 觸發 `_highlight.forward(from: 0)` |
| 時長 | `_highlight` 只剩發光段 1500 ms；刪 `kCollectionHighlightWait` |
| 強度曲線 | `collectionHighlightIntensityAt`：0–8%（120 ms）快速亮起、到 40% 停留、之後淡出；顏色改用主題 `orb`（現在固定 `#FFC24D`） |

---

## 11. 設計憲法與 lint 合規

| 規則 | 怎麼遵守 |
|---|---|
| 字級 12／15／19／24／30／38（DESIGN.md §3） | 名字 19、其餘 12；沒有 < 12 的字 |
| 圓角 18／22–24／999（§4、`slop_scan.dart` 的 `kAllowedRadii`） | 卡 24、照片內圓角 22、資訊欄 18、稀有度牌 999、光球用 `BoxShape.circle` |
| 間距 4／8／16／32＋12／24＋2／6（§5） | 牌 16、資訊欄內縮 12、星距 4、提示 24 |
| 動效曲線來源（§6） | 曲線只用 `AppMotion` 與 Flutter 內建 `Curves`；揭曉時間常數集中在 `PracticeRevealTiming` |
| 彩色光暈要登記（§7） | DESIGN.md §7 新增一列「抽卡揭曉 V3（卡背染色光、全息掃光、光刃、星塵、收卡光球）」；新檔若有彩色 `BoxShadow`，加進 `kColoredShadowAllowedFiles` |
| `Color(0x…)` 棘輪 | 所有顏色放 `lib/core/theme/practice_reveal_palette.dart`；儀式檔現在基準 21，搬完會下降，照規定用 `slop_baseline_generator.dart` 鎖緊（還債可以重產，新增不行） |
| 視覺改動要先給對照圖（§10） | 先出改前／改後 PNG（`test/visual_proof/`）給 Eric 看過才 commit |

---

## 12. 效能

| 規則 | 理由 |
|---|---|
| 全螢幕只有一個 `BackdropFilter` | 資訊欄的毛玻璃用照片副本＋`ImageFiltered`，不讀 backdrop |
| 逐幀 painter 不用 `MaskFilter.blur` | 光暈一律用漸層或預先模糊好的素材 |
| 只有階段切換才 `setState` | 逐幀只重建 `Transform`／`Opacity`／`CustomPaint`；照片、文字、卡背圖片以 `child` 傳進 builder（plan 014 的做法） |
| `RepaintBoundary` | Card3D、BokehDust、Backdrop 各一個 |
| holding 零動畫幀 | 全螢幕模糊在有動畫時每幀都要重算，停住期間可能長達十幾秒 |
| 預快取 | drawing 開始 `precacheImage` 卡背四張；R0 `precacheImage` 照片（距離正面出現還有 1350 ms） |
| 粒子 | 單一 painter、每幀 ≤ 60 顆、解析計算、不保留狀態 |

驗收：Eric 沒有 Mac，不能在本機對 iPhone 跑 DevTools。所以是「TestFlight 真機目視不卡（重點看翻牌 90° 那一刻與收卡飛行）」＋「可以的話在 Android 或桌面用 DevTools 當參考，目標 UI build < 4 ms、raster < 8.3 ms」。

**Plan B**（真機卡頓才做）：drawing 開始時把圖鑑頁 `RepaintBoundary.toImage(pixelRatio: 0.5)` 截一張、離線模糊一次，儀式期間畫這張靜態圖取代即時 `BackdropFilter`；收卡時再交叉淡出回即時畫面。代價是要多一個 GlobalKey 與非同步截圖，且截圖完成前的 1–2 幀先只用暗化。

---

## 13. 檔案清單

### 13.1 修改

| 檔案 | 內容 |
|---|---|
| `lib/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart` | 改寫：五階段狀態機、五個 controller、新圖層；保留類別名與 `const` 建構子；保留 `practiceCeremonyCardSize()` 與尺寸常數 |
| `lib/features/practice_chat/presentation/screens/practice_collection_screen.dart` | 掛到 Scaffold 之上、三個 callback、高亮新契約（§10） |
| `lib/features/practice_chat/presentation/widgets/practice_draw_sfx.dart` | 介面（§8.3） |
| `lib/features/practice_chat/presentation/widgets/practice_draw_audio_sfx.dart` | 新素材、預載四個 player、bed 淡出 |
| `DESIGN.md` | §7 登記 |
| `test/lint/slop_scan.dart`、`test/lint/slop_baseline.json` | 新檔白名單、鎖緊基準 |
| `assets/audio/practice_draw/licenses/practice_draw_audio.md` | 新音檔來源與授權 |

`pubspec.yaml` 不用改：`assets/images/practice/` 與 `assets/audio/practice_draw/` 已整個目錄註冊。`practice_rarity_style.dart` 不改（圖鑑配色不動）。

### 13.2 新增

| 檔案 | 內容 |
|---|---|
| `lib/core/theme/practice_reveal_palette.dart` | 所有 V3 顏色 |
| `lib/features/practice_chat/presentation/widgets/practice_reveal_timing.dart` | `PracticeRevealTiming`＋姿態／進度純函式（widget 與測試共用） |
| `lib/features/practice_chat/presentation/widgets/practice_reveal_theme.dart` | `PracticeRevealTheme.of(rarity)` |
| `lib/features/practice_chat/presentation/widgets/practice_reveal_card.dart` | 卡背、卡面、稀有度牌、資訊欄、星星 |
| `lib/features/practice_chat/presentation/widgets/practice_reveal_painters.dart` | 星塵、光刃、掃光、光球、暗角 |
| `assets/images/practice/practice_draw_card_back_v3_*.webp` ×4 | §6.5 |
| `assets/audio/practice_draw/practice_draw_reveal_v3_{n,r,sr}.m4a`、`practice_draw_archive_v3.m4a` | §8.2 |
| `test/unit/features/practice_chat/practice_reveal_timing_test.dart` | 時間軸與純函式 |
| `test/widget/features/practice_chat/practice_draw_reveal_v3_test.dart` | 儀式行為 |
| `test/visual_proof/practice_draw_v3_proof_test.dart` | 改前／改後對照 PNG |

### 13.3 刪除（最後一刀，V3 上線且真機通過後）

- 儀式檔內 V2 專用的 painter 與函式：`_OrbitalHaloPainter`、`_EnergyBorderPainter`、`_NeonTraceFramePainter`、`_FrameParticleFlowPainter`、`_FrameParticleSprayPainter`、`_ParticleBloomPainter`、`_VolumetricBurstPainter`、`_BreathHoldVignettePainter`、`_GlassWipePainter`、`_FinalPolishPainter`、`_AfterglowPainter`、`_SettlePulsePainter`、`_ReferenceRimGlowPainter`、`_MysticBackPainter`、`_CyberFramePainter`、`_StarfieldPainter`、`kPracticeRevealFlip1Start…HoldEnd`、全部 `practiceCeremony*()` 曲線函式與 `debug*Painter` seam、`PracticeHaloHalf`。
- 素材：`practice_draw_card_back_base.png`、`practice_draw_card_back_neon.png`、`practice_draw_explosion_reference.webp`（約 2.4 MB）；`practice_draw_reveal_bed.mp3`、`practice_draw_flip_snap_{1,2,3}.wav`、`practice_draw_reveal_chime.wav`。
- `kCollectionHighlightWait`；`kPracticeRevealDuration`（改用 `PracticeRevealTiming.reveal`，圖鑑頁不再需要知道儀式多長）。

---

## 14. 測試計畫

### 14.1 會受影響的既有測試

| 檔案 | 影響 |
|---|---|
| `test/widget/features/practice_chat/practice_chat_screen_style_test.dart` | 儀式段約 80 個 case（第 3191–4906 行）：兩段升階、軌道光環、10 s 對拍、各 painter 的 case 隨 V2 刪除；狀態機、失敗、reduce-motion、聲音出口類改寫成 V3 版。凡是「`pumpAndSettle` 後儀式已收掉」的 case，都要先點 `practice-draw-ceremony-continue` |
| `test/widget/features/practice_chat/practice_collection_screen_test.dart` | 高亮等待 10 s 的 case 改成「`onArchived` 才亮」 |
| `test/widget/features/practice_chat/practice_draw_reveal_rarity_test.dart` | seam 改為 `debugCeremonyCardFront(settled: true)` |
| `test/unit/features/practice_chat/practice_draw_audio_sfx_test.dart` | SHA-256 鎖改成新素材 |
| `test/tools/ceremony_preview_recorder_test.dart`、`test/tools/card_back_still_recorder_test.dart` | 改掛圖鑑頁、改長度（揭曉 2.7 s＋停住 1 s＋點擊＋收卡 0.55 s）、卡背出 N／R／SR 三張 |

### 14.2 新測試要釘住的行為

1. **只翻一次**：揭曉期間每 50 ms 取樣，正面一出現之後卡背不得再出現；R0＋1350 之前只有卡背。
2. **稀有度誠實**：對 N／R／SR 每 50 ms 取樣卡背染色，N 只有銀、R 只有銀與藍、SR 才有金。
3. **稀有度牌首幀就正確**：稀有度牌在 R0＋2000 前不存在，出現時 label 等於 `girl.rarity.label`。
4. **版面不重疊**：稀有度牌與資訊欄的 rect 完全落在卡片 rect 內；星星在資訊欄內。
5. **停住**：`_reveal` 跑完後儀式還在、提示字可見、`pumpAndSettle` 能收斂；點擊後收卡、收掉，`onArchived` 只被呼叫一次且帶正確 id。
6. **跳過**：R0＋2000 點擊 → 直接落定，剩餘觸覺不補；R0＋1800 之前點擊無效。
7. **收卡目標**：給 rect → 光球終點在 rect 中心（painter seam 驗證）；不給 → 原地收束；兩種都會在 450 ms 呼叫 `onArchived`。
8. **失敗**：402／429／error 在 drawing 中回來 → 淡出、不揭曉、不播 bed、不呼叫任何 callback。
9. **reduce-motion**：沒有儀式畫面；`onRevealTarget`、`onArchived` 立即呼叫；觸覺照舊。
10. **聲音**：點擊時預載一次；R0 `stopWhoosh()`＋`playRevealBed(對的稀有度)`；點擊收卡 `playArchive()`；hidden／失敗／dispose 都 `stopRevealBed()`；全程不呼叫 `playWaitingLoop()`。
11. **入場保底**：server 立即回來時，揭曉等卡背入場完成才開始。
12. **圖鑑頁**：重複角色也會捲動並發光；重新整理圖鑑不會觸發高亮。
13. **純函式**：`practiceRevealPose(1350)` 的 yaw = 90、`(1800)` = 180；各段邊界連續；粒子同一時間點兩次計算結果相同；貝茲曲線 t=0／1 落在端點。
14. **抽牌中的邊界**：仍是 drawing 的狀態更新不讓儀式淡出；抽牌中離開圖鑑又回來，結果回來照樣揭曉；圖鑑 +1 晚一兩幀才到，光球仍飛向那一格；reduce-motion 抽中時咻聲收掉。

注意：`AppHaptics.tick()` 用真實時間節流，widget test 不要斷言 tick 次數；`celebrate()` 內部有 `Future.delayed`，測試結尾照現有慣例 `pump(250 ms)`。

### 14.3 指令

依 `.agent/environment.json` 的 resolver 在 WSL 跑：

```
flutter analyze
flutter test test/unit/features/practice_chat/ test/widget/features/practice_chat/ test/lint/
```

---

## 15. 驗收與 Gate

| Gate | 內容 | 誰看 |
|---|---|---|
| Gate-1 | 本規格＋§19 參考片對照圖，§1 九題拍板 | Eric |
| Gate-2 | 本機預覽片：錄製器輸出 V3 全程（N／R／SR 各一支），和參考片並排；改前／改後 PNG | Eric |
| Gate-3 | TestFlight 實機（Dogfood-approved 另計） | Eric 的 iPhone |

功能完成條件（全部滿足才叫完成）：

1. 只翻一次，揭曉中途看不到底下任何文字。
2. 稀有度變色只升到真實稀有度；稀有度牌與資訊欄不超出卡片、星星不壓字。
3. 停住等點擊；1.8 s 後可跳過；返回鍵行為符合 §4.4。
4. 光球飛進真正的那一格並發光；沒有半透明卡片殘留在圖鑑上。
5. 聲音、觸覺依 §8、§9；等待期除了咻聲沒有其他聲音。
6. 失敗路徑（402／429／錯誤）與 reduce-motion 行為不退步。
7. 真機翻牌與收卡看不出卡頓。
8. slop 棘輪、analyze、相關測試全綠。

---

## 16. 交付切片與審查

| 刀 | 內容 | 可單獨驗證的結果 |
|---|---|---|
| A 結構 | 五階段狀態機、單次翻牌、停住／點擊／跳過、收卡飛行（先用現有素材與簡單光球）、圖鑑頁新契約、測試 | 行為全對，外觀還是舊皮 |
| B 視覺 | 背景模糊、稀有度主題、新卡背素材＋染色、光刃、星塵、掃光、稀有度牌、資訊欄、星星；DESIGN.md §7、lint 白名單；對照 PNG | Gate-2 預覽片 |
| C 聲音觸覺 | 三條 bed＋收卡音、介面變更、觸覺對拍、授權文件 | 預覽片含聲音 |
| D 清理 | 刪 V2 painter、素材、測試；更新錄製器 | 套件變小、測試只剩 V3 |

- 一個目的一個 PR 的規則下，可以是一個 PR 四個 commit（每個 commit 一件事），也可以拆成四個 PR；由 Eric 決定。
- 審查：一般 PR，一位非作者模型的獨立 AI reviewer；Eric 做正式 GitHub review 與合併決定。
- 實作分派由 Eric 決定（2026-07-05 曾把 SR 專屬大特效分給 Codex，見 `docs/plans/2026-07-05-practice-rarity-gacha-design.md`）。

### 16.1 第一刀實作紀錄（2026-10-15）

做了：

- `practice_reveal_timing.dart`：§4 的時間軸常數與純函式（姿態、各層進度、收卡路徑），widget 與測試共用。
- 儀式狀態機改成 hidden → drawing → revealing → holding → archiving；五個 controller（§5.2）；server 比入場快時等入場走完；單次翻牌；停住零動畫；1.8 s 後可跳過；返回鍵依 §4.4；停住時整層是 VoiceOver 按鈕。
- 收卡：卡片坍縮 → 簡單金色光球沿弧線飛向目標格 → 落位光環；找不到目標格就原地收束。
- 圖鑑頁：儀式移到 Scaffold 之上（蓋住 AppBar）；三個 callback；發光改成光球落位才亮（捲動未到位就等到位）；拿掉「集合變大就高亮」的監聽；重複角色也會標記。
- 觸覺：抽牌、蓄力三下、翻牌峰值（N／R 重擊、SR 提前 200 ms celebrate）、光球落位。
- 聲音（過渡）：v4 bed 剪成 bed v5（4.95–8.25 s，高潮落在單次翻牌），v4 檔移除；翻牌紙聲改在卡片側立時播；收卡時 bed 0.25 s 淡出、咻聲 0.5 s 淡出。

和原規劃不同的地方：

- 只屬於 V2 雙翻時間軸的特效（軌道光環、能量邊框、霓虹描框、框邊粒子、粒子綻放、體積光爆、屏息暗角、落定脈衝、玻璃掃光、收尾光澤、餘暉、全幅爆點疊圖與其素材）在第一刀就刪掉：它們的啟動曲線只對 10 s 雙翻成立，留著也是死碼。卡背、正面卡、資訊欄、星光、閃光保留舊皮，第二刀再換。
- 染色觸覺（R／SR）、烙印與星星的 tick 等第二刀和它們的畫面一起上。
- 儀式行為的測試併進既有的 `practice_chat_screen_style_test.dart` 與 `practice_collection_screen_test.dart`（§14.1 本來就要大改），沒有另開 `practice_draw_reveal_v3_test.dart`。

還沒做：背景模糊、稀有度染色與新卡背、光刃、星塵、全息掃光、膠囊稀有度牌、兩行資訊欄與星星逐顆點亮（第二刀）；N／R／SR 三條配樂與收卡音（第三刀；v4 時 Bruce 要求 SR／R／N 聲音一致，D3 改成分稀有度，開工前再確認一次）。

審查後補修（2026-10-15，自審找到的邊界）：

- 抽牌中仍是 drawing 的狀態更新（練習室的提示、拆解剛好回來）原本被當成失敗把卡背淡掉；改成不理（§5.1）。
- 抽牌中離開圖鑑又回來，新掛上的儀式還是 hidden，原本結果回來時揭曉整個掉了；改成接著把卡背入場走完再揭曉（§5.4）。
- 圖鑑的 +1 要等抽卡流程存完草稿才到，比揭曉起點晚一兩幀，原本捲動估算用它未解鎖時的位置、光球找不到目標；改成揭曉中的這張卡先當成已解鎖排序（§5.4）。
- reduce-motion 抽中時沒有配樂接手，咻聲的暖尾巴原本會留在圖鑑上；改成抽中當下一起收掉（§5.1）。

第二輪審查（另一個工作階段）後修正：

- 儀式蓋住整頁時擋掉底下的讀屏節點（§5.4）：原本停住時 VoiceOver 還能按到底下的翻牌鈕與返回鍵，付費用戶會直接再抽一次、用掉免費換人。
- 揭曉配樂起播不再多等一次 setVolume：收卡淡出走完就把音量設回，只有淡出被新的一抽打斷時才在起播前補設。
- D1–D9 改寫成「作者照建議先定、待 Eric 確認」（標頭、§1）。
- 補一個 reduce-motion 下圖鑑 +1 晚到的測試（上面「先當成已解鎖排序」也走這條路）。

### 16.2 第二刀實作紀錄（2026-10-15）

做了：

- 色票 `lib/core/theme/practice_reveal_palette.dart`、稀有度主題 `practice_reveal_theme.dart`（§7，含卡背染色當下的顏色插值）；卡片元件 `practice_reveal_card.dart`、特效 painter `practice_reveal_painters.dart`；時間軸補上染色、光刃、掃光、烙印、星星、收卡變光與星點的純函式。
- 卡背素材四張（§6.5）：`tools/practice-draw-card-back-v3/make_card_back_v3.py` 從原卡背離線產出，合計約 234 KB。執行時遮罩用 ShaderMask 套主題漸層，光暈圖染色墊在線條下面；SR 金階加全息彩虹描邊。
- 背景：BackdropFilter 模糊 σ 0→24＋暗化 0.85＋暗角，不包 Opacity。
- 卡背：等待呼吸（±3 px、1.010、±2°、徽記 0.30–0.45）、蓄力增亮、N 銀光脈衝、R／SR 染藍、SR 染金＋白色爆閃；環境光與環境星塵跟著染色走。
- 翻牌峰值：光刃（SR 加十字）＋爆發星塵。
- 卡面：1.5 px 漸層倒角框＋外光＋內層高光、照片緩縮、全息掃光（SR 加兩道細彩邊）、膠囊稀有度牌（2.0 s 前不存在）、兩行毛玻璃資訊欄（照片副本模糊，不用 BackdropFilter）、只畫亮星並逐顆點亮；卡面文字放大上限 1.3。
- 收卡：資訊 80 ms 淡出、卡面變成稀有度色光、光球改用主題 orb 色並沿途灑 8 顆星點；圖鑑那一格的發光也改成同一色。
- 觸覺補上：R 染藍 `light()`、SR 染藍 `tap()`＋染金 `light()`、烙印 `tap()`（單一常數可關）、亮星 `tick()`。
- 等待字樣與提示字照 §6.8；卡片位置 `Alignment(0, −0.08)`，等待字樣在卡片下方 24。
- 錄製器改掛圖鑑頁、N／R／SR 各錄一支；卡背靜態圖出 N／R／SR 三張。

和原規劃不同的地方：

- 爆發星塵畫在卡片前面，不在卡片後面（L2）：照原數值（初速 120–260 px/s、阻尼 2.5）最遠只飛約 100 px，卡片轉正後幾乎全被卡面擋住。改成畫在前面、往兩側噴（縱向壓到 0.65）、初速 160–320 px/s、阻尼 2.0，很快離開臉的位置。壽命改成 900–1300 ms（原 900–1400），停住前全部燃盡，停住畫面才是乾淨的靜止。環境星塵仍在卡片後面，鋪滿整個畫面。
- 舊的徑向白閃由光刃取代，舊卡背、舊卡面一起刪掉。只剩測試 seam 在用的 V2 painter（神秘卡背、賽博外框、星光場）與舊卡背 PNG，留到第四刀清理。
- 掃光在柔光（softLight）之外再疊一層很淡的 screen 光帶：只用柔光時，暗部幾乎看不到光帶。
- 錄製器原本用 `setSurfaceSize` 定 390×844，但 MediaQuery 仍是測試預設的 800×600：卡片被算小，圖鑑捲動估算也會算錯（遠處的卡收卡時找不到格子）。改用 `tester.view` 定尺寸。這是錄製器的問題，app 本身的估算是對的。
- 測試沒有另開 §13.2 列的 `test/visual_proof/practice_draw_v3_proof_test.dart`（儀式行為照第一刀接著寫在既有檔）：純函式在 `practice_reveal_timing_test.dart`、`practice_reveal_visuals_test.dart`；改前／改後對照圖由錄製器逐幀輸出再合成。

還沒做：N／R／SR 三條配樂與收卡音（第三刀，開工前先確認 D3）；V2 painter、舊卡背 PNG 與相關測試的清理（第四刀）。真機要特別看模糊背景與資訊欄毛玻璃的效能（§12；卡頓才做 Plan B）。

審查後補修（2026-10-15）：

- 點擊提示原本只有淡入，補上 §4.3 的上浮 6 px（和淡入共用同一條曲線，停住與收卡時定在原位）。
- 抽牌中離開圖鑑又回來、由揭曉接著走卡背入場時，比照按下翻牌那一刻先解碼四張卡背素材。

---

## 17. 不做的事與後續可選

不做：

- 抽卡機率、額度、扣費、server、DB、Edge 的任何改動。
- 陀螺儀傾斜（要加感測器套件）。
- 人物與背景分離的 2.5D 視差（100 張照片都要做分割遮罩）。
- Lottie／Rive。
- 「略過整段儀式」的設定。

後續可選：

- 陀螺儀跟手的高光（V3.1）。
- reduce-motion 使用者目前完全看不到結果卡，只看到圖鑑那一格發光；可以做一個無 3D、無閃光的淡入版結果卡＋點擊繼續。
- 停住時加「開始聊天」捷徑。

---

## 18. 附錄：程式草圖

### 18.1 時間軸常數

```dart
import 'package:flutter/animation.dart';

import '../../../../core/theme/app_motion.dart';

/// V3 揭曉時間軸的單一真相。各段 ms 以各自 controller 的起點為 0。
abstract final class PracticeRevealTiming {
  // drawing（以點擊為 0）
  static const intro = Duration(milliseconds: 500);
  static const introBackdropEndMs = 300.0;
  static const introCardStartMs = 100.0;
  static const caption = Duration(milliseconds: 1200);
  static const captionFadeStartMs = 900.0;

  // revealing（以 R0 為 0）
  static const reveal = Duration(milliseconds: 2700);
  static const chargeEndMs = 600.0;
  static const dyeBlueMs = 600.0;
  static const dyeGoldMs = 850.0;
  static const srBuildMs = 1150.0;
  static const flipStartMs = 1100.0;
  static const flipPeakMs = 1350.0;
  static const flipEndMs = 1800.0;
  static const skipFromMs = 1800.0;
  static const kenBurnsStartMs = 1500.0;
  static const sheenStartMs = 1700.0;
  static const sheenEndMs = 2400.0;
  static const infoStartMs = 1850.0;
  static const infoEndMs = 2150.0;
  static const stampStartMs = 2000.0;
  static const stampEndMs = 2250.0;
  static const starsStartMs = 2150.0;
  static const starStaggerMs = 80.0;
  static const starPopMs = 220.0;
  static const hintStartMs = 2400.0;

  // archiving（以點擊收卡為 0）
  static const archive = Duration(milliseconds: 550);
  static const collapseEndMs = 150.0;
  static const landMs = 450.0;
  static const backdropOutStartMs = 150.0;
  static const backdropOutEndMs = 500.0;

  static const Curve charge = Curves.easeInOutCubic;
  static const Curve flipIn = Curves.easeInBack; // = Cubic(0.6, -0.28, 0.735, 0.045)
  static const Curve settle = AppMotion.easeOut; // ≈ 提案的 Cubic(0.16, 1, 0.3, 1)
  static const Curve stamp = Curves.easeOutBack; // celebrate 檔
  static const Curve flight = Curves.easeInOutCubic;
}
```

### 18.2 卡片姿態

```dart
double _seg(double ms, double from, double to) =>
    ((ms - from) / (to - from)).clamp(0.0, 1.0);

/// [ms]＝_reveal 經過的毫秒。yaw／pitch 單位是度。
({double yaw, double pitch, double scale}) practiceRevealPose(double ms) {
  final charge = PracticeRevealTiming.charge
      .transform(_seg(ms, 0, PracticeRevealTiming.chargeEndMs));
  if (ms < PracticeRevealTiming.flipPeakMs) {
    final flipIn = ms <= PracticeRevealTiming.flipStartMs
        ? 0.0
        : PracticeRevealTiming.flipIn.transform(_seg(
            ms,
            PracticeRevealTiming.flipStartMs,
            PracticeRevealTiming.flipPeakMs,
          ));
    // easeInBack 前段會略小於 0：卡片先往回拉一點再衝，這是刻意的預備動作。
    return (yaw: -8 * charge + 98 * flipIn, pitch: 6 * charge, scale: 1 - 0.08 * charge);
  }
  final out = PracticeRevealTiming.settle.transform(_seg(
    ms,
    PracticeRevealTiming.flipPeakMs,
    PracticeRevealTiming.flipEndMs,
  ));
  return (yaw: 90 + 90 * out, pitch: 6 * (1 - out), scale: 0.92 + 0.08 * out);
}
```

### 18.3 收卡路徑

```dart
Offset practiceArchiveControlPoint(Offset p0, Offset p2, Size stage) {
  final d = p2 - p0;
  final len = d.distance;
  if (len < 1) return p0;
  final n = Offset(-d.dy / len, d.dx / len);
  final mid = (p0 + p2) / 2;
  final a = mid + n * (0.35 * len);
  final b = mid - n * (0.35 * len);
  final cx = stage.width / 2;
  // 往畫面中線那側鼓，弧線不會飛出螢幕。
  final p1 = (a.dx - cx).abs() <= (b.dx - cx).abs() ? a : b;
  return Offset(
    p1.dx.clamp(24.0, stage.width - 24),
    p1.dy.clamp(24.0, stage.height - 24),
  );
}

Offset practiceQuadBezier(Offset p0, Offset p1, Offset p2, double t) {
  final u = 1 - t;
  return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t);
}
```

---

## 19. 參考資料位置

- 參考片原檔：本次 session 上傳（未入庫）。
- 參考片標註對照圖（12 格，綠＝採用、黃＝修正、紅＝不採用）：本次 session 暫存、未入庫；Gate-1 若要留存，再決定是否放進 `docs/`。
- 逐格抽圖（4 fps）與音軌量測方法：`ffmpeg -vf fps=4`；RMS 用 `astats`（125 ms 窗）。
