# 每日翻牌音效 — 素材授權清單（practice_draw audio）

> **狀態：已 bundle（Batch 4.7B 實裝）。** `practiceDrawSfxProvider` 預設已換成會真的播放的
> `AudioPlayersPracticeDrawSfx`（audioplayers），三組音檔已放進 `assets/audio/practice_draw/`
> 並於 `pubspec.yaml` 註冊為 asset。授權／來源見下表，僅存於本 repo 文件，**不**塞進 app UI。

## 來源與授權（provenance）

這三個音檔是 **Codex 於 2026-06-26 為 VibeSync 以原創程式化 synthesis（procedural synthesis）生成**。
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

## 授權鐵則（放音檔進來前必過）

- **僅可用**：本專案原創生成、CC0、自製、買斷、或授權條款明確允許「商用 app bundling」的素材。
- **禁用**：NonCommercial / 授權不明 / 從遊戲或影片擷取 / 可辨識到第三方原聲（如神魔之塔、寶可夢等）的素材。
- 授權文字只存在本 repo 文件，**不**塞進 app UI。
- 目標：優先小檔案，整組翻牌音效資產 **< 500KB**（E2 退役 riser/settle −192KB＋加 bed mp3 142KB → 實測整個 dir ≈ 448KB）。

## 音檔清單

| 用途（呼叫點） | bundled 檔名 | 原始候選檔 | 來源／作者 | 授權 | 生成日期 | 需署名 |
|---|---|---|---|---|---|---|
| `playWhoosh()` 抽牌咻聲（一次性，~0.3–0.6s） | `practice_draw_whoosh.wav` | `A_romantic_magic_01_whoosh.wav` | Codex 原創程式化 synthesis（for VibeSync） | 專案原創（非 CC0） | 2026-06-26 | 否 |
| `playWaitingLoop()` 等待 shimmer loop（循環、極小聲） | `practice_draw_waiting_loop.wav` | `A_romantic_magic_02_waiting_loop.wav` | Codex 原創程式化 synthesis（for VibeSync） | 專案原創（非 CC0） | 2026-06-26 | 否 |
| `playRevealChime()` 揭曉 chime/sparkle（一次性，~0.6–1s） | `practice_draw_reveal_chime.wav` | `B_gacha_sss_03_reveal_chime.wav` | Codex 原創程式化 synthesis（for VibeSync） | 專案原創（非 CC0） | 2026-06-26 | 否 |
| `playRevealBed()` 揭曉配樂 bed（一次性，9.04s，與 `_reveal` 同長） | `practice_draw_reveal_bed.mp3`（142KB，已 bundle） | `音檔.mp4` 音軌 0–9s 全段（Gemini 生成參考影片）+ ffmpeg peak-normalize | 夥伴用 Google Gemini 生成（for VibeSync）+ ffmpeg 後製 | 專案原創（AI 生成，非第三方 sample） | 2026-06-27 | 否 |

> ~~`playRiser()`／`playSettle()`（D4，`practice_draw_riser.wav`／`practice_draw_settle.wav`）已於 E2 退役並移除。~~

> 選定組合（strategy）：whoosh＋waiting loop 取 A_romantic_magic（高級浪漫基調），reveal chime
> 取 B_gacha_sss（SSS 抽中的獎勵 hit）。若真機上 B 在手機喇叭顯得太「遊戲感」，可改回
> `A_romantic_magic_03_reveal_chime.wav`。

## 實裝重點（Batch 4.7B）

1. 播放套件：`audioplayers`（短音效＋loop 的輕量標準選擇，iOS 支援成熟）。
2. 實作：`AudioPlayersPracticeDrawSfx`（`lib/features/practice_chat/presentation/widgets/practice_draw_audio_sfx.dart`）。
   - whoosh／reveal chime：一次性（`ReleaseMode.release`），各自獨立 player 避免互相截斷。
   - waiting loop：`ReleaseMode.loop`、極小聲；`stopWaitingLoop()` idempotent，未播放時呼叫為 no-op。
   - iOS AudioContext：`respectSilence: true`（尊重靜音鍵，ambient）＋`mixWithOthers`（不中斷使用者背景音樂）。
   - 全程 guarded：headless／測試環境無 platform channel 時所有播放／停止靜默吞例外，不丟、不殘留 loop。
3. 音量常數集中在實作檔內（whoosh 0.7／waiting loop 0.22／reveal chime 0.8／reveal bed 0.75），方便真機調整。
4. error／402／429／hidden／dispose／reduce-motion 一律不殘留等待 loop（呼叫端 ceremony 已備妥對應 `stopWaitingLoop`）。
5. 測試：`practiceDrawSfxProvider` 可 override 注入 spy；真實 impl 在測試環境可建立、可呼叫四方法皆不丟例外（不真的發聲）。

## 待辦（TODO）

- [x] **E2 抽取 bed mp3**：已抽 `音檔.mp4` 0–9s、peak-normalize、mp3 128k 落地（142KB）＋asset-exists 測試綠。
- [ ] Eric 出新 TestFlight build 後真機目檢音效（romantic 基調＋reveal hit 是否到位、loop 是否夠小聲）。
- [ ] **E2 真機目檢**：揭曉配樂 bed 是否與 `_reveal` 三爆點對齊（預覽~3s／屏息~5s／高潮~8.5s）；
      bed 與保留的 reveal chime 疊放是否好聽（不合可拿掉 chime 或調 `_kRevealBedVolume`）。
- [ ] reduce-motion 目前保留 haptic 與一次性音效、但不啟動 waiting loop；未來若加「使用者
      靜音偏好」，再決定是否連一次性音效一併靜音。
