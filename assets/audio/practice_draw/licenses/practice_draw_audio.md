# 每日翻牌音效 — 素材授權清單（practice_draw audio）

> **狀態：已 bundle（Batch 4.7B 實裝）。** `practiceDrawSfxProvider` 預設已換成會真的播放的
> `AudioPlayersPracticeDrawSfx`（audioplayers），三組音檔已放進 `assets/audio/practice_draw/`
> 並於 `pubspec.yaml` 註冊為 asset。授權／來源見下表，僅存於本 repo 文件，**不**塞進 app UI。

## 來源與授權（provenance）

whoosh／waiting loop／reveal chime 三個音檔是 **Codex 於 2026-06-26 為 VibeSync 以原創程式化 synthesis（procedural synthesis）生成**。
**沒有使用任何第三方 sample、沒有抓取遊戲／影片音源、沒有外部 loop。**

> Original procedural synthesis generated for VibeSync; no third-party samples.

非 CC0、非第三方授權素材 —— 為 VibeSync 原創生成，著作權歸專案所有，可商用 app bundling。

### Batch D4：riser／settle（2026-06-27，**已於 E2 退役、檔案移除**）

D4 曾從 `音檔.mp4` 切出 riser（5.95–7.10s）／settle（6.95–8.00s）兩段離散 accent 音。E2 改版判定
離散 accent 合成感重、與音樂不同步，**已退役並從 repo 移除**（見下）。歷史記錄保留於 git。

### E2 改版：整條揭曉配樂 bed 取代 riser／settle（2026-06-27）

第 2 輪 dogfood 對標 `音檔.mp4` 拍板：揭曉音效改成**一條與揭曉時間軸 `_reveal`（~9s）同長同步的連續
配樂 bed，直接取自 `音檔.mp4` 的音軌**（揭曉起播一次、走完整條即收）。因此：

- **`practice_draw_riser.wav`／`practice_draw_settle.wav` 已退役並從 repo 移除**；介面方法
  `playRiser()`／`playSettle()` 一併刪除，改為 `playRevealBed()`／`stopRevealBed()`。
- 新增 `practice_draw_reveal_bed.mp3`：`音檔.mp4` 0–~9s 全段音軌，normalize（原片 mean −33dB 偏小）後
  以 mp3 編碼（~9s wav 會爆 <500KB 預算）。**素材同 D4：夥伴用 Google Gemini 生成的 AI 原創內容、
  非第三方 sample、非可辨識第三方原聲**，符合下方授權鐵則本意。
- **殘留風險（誠實記錄）**：同 D4——生成式 AI 理論上可能無意重現受版權音樂；此為泛用浪漫 ambient bed、
  無可辨識旋律，風險低。需零風險時可改程式化合成替換（介面／接線不變，僅換音檔）。
- **音量常數** `_kRevealBedVolume`（預設 0.75）集中於實作檔，真機目檢直接調；bed 仍 `respectSilence`
  （尊重靜音鍵）＋`mixWithOthers`（不中斷背景音樂）。
- **bundle 狀態：已 bundle**（2026-06-27）。ffmpeg 抽 `音檔.mp4` 0–9s → **線性 peak-normalize +8.9dB**
  （刻意不用 loudnorm/壓縮，保留 build→爆點→屏息 −77dB 低谷→高潮 的動態，E2 同步靠這條動態）→ 尾段
  8.6–9.0s fade-out 防 click → mp3 128k/44.1k/stereo。成品 9.04s、142KB、peak −1.4dB（無破音）、mean −24.9dB。

### F1 改版：上半段 2–5s 改用夥伴 accent layer（2026-07-09）

第三輪目檢回饋：E2 bed 的 2–5s 有高頻細碎聲，與翻牌儀式感不搭。F1 僅替換上半段問題區間：

- 保留原 bed 的 0–2s 鋪陳，以及 5s 後下半段（6.5s 爆點、8.5s settle 不改）。
- 2.0–5.0s 以夥伴提供的 `preview_accent_layer.wav` 作為主體，對齊 `_reveal` 3.0s 第一張卡翻開。
- 原 bed 在 2–5s 僅保留低頻底（FFT low-pass 後 18% 音量）並以 0.22s crossfade 進出，移除高頻「西西素素」感但避免接縫突然變乾。
- 輸出 `practice_draw_reveal_bed.mp3`（約 10.06s、192kbps/44.1kHz/mono、242KB），peak 約 0.79，無 clipping。

### F2 改版：移除 2–5s 細碎高頻（2026-07-16）

F1 真機回饋仍可聽見 2–5s「西西簌簌」聲。播放路徑確認揭曉時 waiting loop 已停止、舊 chime
也未疊放；頻譜量測進一步確認噪聲已烘焙在 F1 master 的 2–5s accent layer，而非重複播放：

- F1 2–5s 頻譜重心約 2782Hz、頻譜平坦度 0.056804、6kHz 以上能量占 13.91%。
- F2 保留同一段低頻與 C／G 揭牌音色；以 2100Hz、8th-order crossover 分離高頻，1.8–2.2s
  平滑降到 0%，4.8–5.2s 平滑恢復，避免硬切或時間軸漂移。
- F2 2–5s 頻譜重心降至約 747Hz、頻譜平坦度 0.000018、6kHz 以上能量降至 0.043%；
  10 秒時間軸、3.0s 第一張卡翻開與 5.0s 屏息節點全部不變。
- 輸出仍為 `practice_draw_reveal_bed.mp3`（約 10.06s、192kbps/44.1kHz/mono、242KB），
  SHA-256 `20a516649bc6ac59b32ed73520b473e4ded6e1f7d091b45d7f69ae7fdfda92e2`，無 clipping／接縫 click。

### F3 改版：退役等待 shimmer loop（2026-07-16）

Build 326 已確認包含 F2，但使用者在按下翻牌後約 2–5 秒仍聽到「西西簌簌」。該時段其實是 server drawing
等待期：F2 reveal bed 尚未開始，App 會以 0.22 音量重播 1.75 秒的 `practice_draw_waiting_loop.wav`。

- 正式儀式不再啟動 waiting loop；等待期間只保留視覺微動與起始 whoosh。
- `playWaitingLoop()`／`stopWaitingLoop()` 為相容舊呼叫點暫留，但 production 固定 no-op。
- `practice_draw_waiting_loop.wav` 僅留作歷史 provenance，不再由 App 播放。
- 揭曉成功後仍只播放 F2 `practice_draw_reveal_bed.mp3`，檔案與 SHA-256 不變。

### v4 改版：bed v4 與咻聲 v2（2026-10-01）

Bruce 的要求：SR／R／N 聲音一致、飽滿有質感、從按下抽牌到定音連貫不斷層；看過對照影片後選定
「翻牌之後回到原本的音樂」（v4）。設計與驗收依《每日翻牌音效飽滿化：實作規格（v4）》（2026-10-01，
Claude Code 起草，已交付 Bruce）。產生程式（Python：numpy／scipy／ffmpeg）`build_b4.py`、
`mock_build.py` 與規格一起交付；要重做時照下列步驟即可重現。

**bed v4（`practice_draw_reveal_bed.mp3`）**：由 F2 衍生（素材性質同 E2／F2：夥伴以 Gemini 生成的
VibeSync 專用內容），加上 Claude Code 程式合成的長音。沒有使用任何第三方 sample。

- 從 F2（SHA-256 `20a51664…92e2`）解碼、重取樣到 48 kHz，剪掉開頭 0.370 s：三個全頻段重音落在
  3.32／6.48／8.52 s，對齊畫面的 3.3／6.5／8.5 s（F2 晚 0.35–0.39 s）。
- 35 Hz 高通；50–150 Hz 飽和出 2–4 次諧波、以 −10 dB 混回；80 Hz 以下 −4 dB。開頭樂句（0.9–1.5 s）
  退 1.5 dB，其餘照原曲，翻牌後不動。
- 補洞：F2 自己的三個洞（1.9–2.5 s、屏息 4.4–5.2 s、落定前 7.9–8.1 s）用 C3｜C4–G4–C5 長音
  （程式合成，只出現在 5.6 s 以前）與 F2 自己的殘響（2 kHz 以下送入 RT60 2.4 s／4.5 s 殘響）補上。
  翻牌後不加任何新的音。
- 翻牌後（3.3–9.6 s）的響度與舊版（F2 × 0.75）相同。檔案正規化到 −18 LUFS、true peak −2.9 dBTP，
  程式播放音量 0.74。
- 輸出 MP3 192 kbps／48 kHz／stereo、10.0 s、241KB，
  SHA-256 `f211ee0f1755b072ca3b0c27f665bc53b035e5602c13682c6d70630e71b11c07`。
- 量測（解碼後的檔，手機近似響度）：揭曉最低點 −15.0 dB（F2 −64.8 dB）、0.5 秒內最大跌幅 10.1 dB
  （F2 57.9 dB）；翻牌後 500–3000 Hz 與 F2 原曲相關 0.96、時差 0 ms；40 Hz 以下能量 1.4%、
  100 Hz 以下 22.8%（F2 7.7%／53.4%）。

**咻聲 v2（`practice_draw_whoosh.m4a`，取代 `practice_draw_whoosh.wav`）**：Claude Code 原創程式化合成，
沒有使用任何第三方 sample。

- 層次：拿起卡片的喀聲（1–3 kHz）、帶通咻聲（400 Hz → 2.5 kHz → 1 kHz，7 kHz 以上低通）、
  150–400 Hz whoomp、C6 小亮點，加一段 C3｜C4–G4–C5 暖尾巴：比主體低 8 dB，撐到 1.8 s 後每秒
  −3 dB，5.5 s 收完，4 kHz 以上能量 0%。
- 一次性播完，不是循環音效，F3「等待期不跑 loop」不變；但尾巴改變了「等待期全靜音」的聽感，待 Eric 確認。
- 母帶 true peak −1.2 dBTP；AAC 160 kbps／48 kHz／stereo、5.5 s、110KB，
  SHA-256 `15e973f3620efa4f8eaf4f008a809a4d4d9e60d7d9e7bfdd79e585db3064e3aa`。
- 程式播放音量 0.22：手機上比揭曉高潮小 8 dB（舊咻聲比高潮大 8.5 dB）。

**播放**：進入抽牌等待時 `preloadReveal()` 先把 bed 載入 player（`ReleaseMode.stop`），揭曉時從頭 resume，
降低起播延遲；v4 的三個重音都在 bed 裡，bed 晚播重音就一起晚。

## 授權鐵則（放音檔進來前必過）

- **僅可用**：本專案原創生成、CC0、自製、買斷、或授權條款明確允許「商用 app bundling」的素材。
- **禁用**：NonCommercial / 授權不明 / 從遊戲或影片擷取 / 可辨識到第三方原聲（如神魔之塔、寶可夢等）的素材。
- 授權文字只存在本 repo 文件，**不**塞進 app UI。
- 目標：優先小檔案；v4 後整組翻牌音效資產約 **601KB**（bed mp3 約 241KB、咻聲 m4a 約 110KB；已退役的
  chime 與 waiting loop 共約 250KB 仍留在資料夾）。

## 音檔清單

| 用途（呼叫點） | bundled 檔名 | 原始候選檔 | 來源／作者 | 授權 | 生成日期 | 需署名 |
|---|---|---|---|---|---|---|
| `playWhoosh()` 抽牌咻聲（一次性：主體 ~0.5s＋暖尾巴，最長 5.5s） | `practice_draw_whoosh.m4a`（v2，110KB） | —（v1 為 `A_romantic_magic_01_whoosh.wav`） | Claude Code 原創程式化合成（for VibeSync） | 專案原創（非 CC0） | 2026-10-01 | 否 |
| `playWaitingLoop()` 等待 shimmer loop（F3 已退役，不播放） | `practice_draw_waiting_loop.wav`（僅留歷史 provenance） | `A_romantic_magic_02_waiting_loop.wav` | Codex 原創程式化 synthesis（for VibeSync） | 專案原創（非 CC0） | 2026-06-26 | 否 |
| `playRevealChime()` 揭曉 chime/sparkle（一次性，~0.6–1s） | `practice_draw_reveal_chime.wav` | `B_gacha_sss_03_reveal_chime.wav` | Codex 原創程式化 synthesis（for VibeSync） | 專案原創（非 CC0） | 2026-06-26 | 否 |
| `playRevealBed()` 揭曉配樂 bed（一次性，10.0s，與 `_reveal` 同步） | `practice_draw_reveal_bed.mp3`（v4，241KB） | F2 master 衍生：提前 0.37s＋低頻整理＋補洞 | 夥伴提供素材（F2）＋Claude Code 程式合成長音與後製 | 專案原創（AI/自製後製，非第三方 sample） | 2026-10-01 | 否 |

> ~~`playRiser()`／`playSettle()`（D4，`practice_draw_riser.wav`／`practice_draw_settle.wav`）已於 E2 退役並移除。~~

> 歷史選定組合：whoosh＋waiting loop 原取 A_romantic_magic；waiting loop 已於 F3 退役。
> reveal chime 原取 B_gacha_sss，但 E2 起揭曉由單一 master bed 接管，production 不疊放舊 chime。

## 實裝重點（Batch 4.7B）

1. 播放套件：`audioplayers`（短音效與 reveal bed，iOS 支援成熟）。
2. 實作：`AudioPlayersPracticeDrawSfx`（`lib/features/practice_chat/presentation/widgets/practice_draw_audio_sfx.dart`）。
   - whoosh／reveal chime：一次性（`ReleaseMode.release`），各自獨立 player 避免互相截斷。
   - waiting loop：F3 已退役；相容 API 固定 no-op，不建立 player。
   - iOS AudioContext：`respectSilence: true`（尊重靜音鍵，ambient）＋`mixWithOthers`（不中斷使用者背景音樂）。
   - 全程 guarded：headless／測試環境無 platform channel 時所有播放／停止靜默吞例外，不丟。
3. 音量常數集中在實作檔內（whoosh 0.22／reveal chime 0.8／reveal bed 0.74），方便真機調整。
4. drawing 等待期不播放任何循環音效，只有咻聲 v2 自帶的一次性暖尾巴；同時 `preloadReveal()` 預載 bed，
   成功後從頭 resume。
5. 測試：`practiceDrawSfxProvider` 可 override 注入 spy，鎖定 normal-motion 也不得啟動 waiting loop。

## 待辦（TODO）

- [x] **E2 抽取 bed mp3**：已抽 `音檔.mp4` 0–9s、peak-normalize、mp3 128k 落地（142KB）＋asset-exists 測試綠。
- [x] **F1 上半段替換**：2–5s 改用夥伴 accent layer，3.0s 對齊第一張卡翻開；5s 後沿用 E2 下半段。
- [x] **F2 去細碎高頻**：保留揭牌音色與節點，只平滑壓掉 2–5s 的寬頻顆粒噪聲；音檔 hash 已鎖測試。
- [ ] Eric 出新 TestFlight build 後真機目檢音效（等待期靜音＋reveal bed 是否到位）。
- [x] **F1 真機目檢未通過**：三爆點仍對齊，但 2–5s 細碎高頻需移除；production 未疊放 reveal chime，
      問題確認來自 bed 本身，後續由 F2 收斂。
- [x] **F2／F3 根因拆分**：build 326 已確認包含 F2；殘留聲來自 reveal 前的 waiting loop，F3 已退役。
- [ ] **v4 真機目檢**：咻聲尾巴接住等待、翻牌後的音樂與舊版同一首同樣大聲、三個重音對齊畫面
      （240 fps 慢動作看 3.3／6.5／8.5s；bed 若整體偏晚，多剪前導補）。
- [ ] reduce-motion 目前保留 haptic 與一次性音效；未來若加「使用者
      靜音偏好」，再決定是否連一次性音效一併靜音。
