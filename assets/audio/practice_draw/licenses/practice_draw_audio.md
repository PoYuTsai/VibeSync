# 每日翻牌音效 — 素材授權清單（practice_draw audio）

> **狀態：已 bundle（Batch 4.7B 實裝）。** `practiceDrawSfxProvider` 預設已換成會真的播放的
> `AudioPlayersPracticeDrawSfx`（audioplayers），三組音檔已放進 `assets/audio/practice_draw/`
> 並於 `pubspec.yaml` 註冊為 asset。授權／來源見下表，僅存於本 repo 文件，**不**塞進 app UI。

## 來源與授權（provenance）

這三個音檔是 **Codex 於 2026-06-26 為 VibeSync 以原創程式化 synthesis（procedural synthesis）生成**。
**沒有使用任何第三方 sample、沒有抓取遊戲／影片音源、沒有外部 loop。**

> Original procedural synthesis generated for VibeSync; no third-party samples.

非 CC0、非第三方授權素材 —— 為 VibeSync 原創生成，著作權歸專案所有，可商用 app bundling。

### Batch D4 追加：riser／settle（2026-06-27）

riser（蓄力）與 settle（落定）兩個 accent 音，**素材來自夥伴用 Google Gemini 生成的 10 秒參考影片
（`音檔.mp4`）音軌**——該影片本身是團隊為 VibeSync 翻牌儀式「完美復刻」對標而以 Gemini 生成的
**AI 原創內容，非從第三方遊戲／影片擷取、非可辨識第三方原聲**，故符合下方授權鐵則本意（與現有 3 音
同屬「為 VibeSync 生成、非第三方 sample」）。

- 從該音軌切出兩段並以 ffmpeg 後製：riser＝影片高潮 build-up（原片 5.95–7.10s）、settle＝高潮峰後落定
  （原片 6.95–8.00s）；皆 gain +16dB（原片 mean −34dB 偏小）＋fade in/out 防爆音＋對齊 44.1kHz mono。
- **殘留風險（誠實記錄）**：生成式 AI 理論上可能無意重現受版權音樂；此二段為泛用 ambient swell、無可辨識
  旋律，風險低。若日後判定需零風險，可改以程式化合成替換（介面與接線不變，僅換 wav）。
- Eric 已試聽 candidate（cand_riser_A／cand_settle_A）選定；bundled 檔即該試聽原檔，未再轉檔。

## 授權鐵則（放音檔進來前必過）

- **僅可用**：本專案原創生成、CC0、自製、買斷、或授權條款明確允許「商用 app bundling」的素材。
- **禁用**：NonCommercial / 授權不明 / 從遊戲或影片擷取 / 可辨識到第三方原聲（如神魔之塔、寶可夢等）的素材。
- 授權文字只存在本 repo 文件，**不**塞進 app UI。
- 目標：優先小檔案，整組翻牌音效資產 **< 500KB**（含 D4 riser/settle 後 ≈ 478KB）。

## 音檔清單

| 用途（呼叫點） | bundled 檔名 | 原始候選檔 | 來源／作者 | 授權 | 生成日期 | 需署名 |
|---|---|---|---|---|---|---|
| `playWhoosh()` 抽牌咻聲（一次性，~0.3–0.6s） | `practice_draw_whoosh.wav` | `A_romantic_magic_01_whoosh.wav` | Codex 原創程式化 synthesis（for VibeSync） | 專案原創（非 CC0） | 2026-06-26 | 否 |
| `playWaitingLoop()` 等待 shimmer loop（循環、極小聲） | `practice_draw_waiting_loop.wav` | `A_romantic_magic_02_waiting_loop.wav` | Codex 原創程式化 synthesis（for VibeSync） | 專案原創（非 CC0） | 2026-06-26 | 否 |
| `playRevealChime()` 揭曉 chime/sparkle（一次性，~0.6–1s） | `practice_draw_reveal_chime.wav` | `B_gacha_sss_03_reveal_chime.wav` | Codex 原創程式化 synthesis（for VibeSync） | 專案原創（非 CC0） | 2026-06-26 | 否 |
| `playRiser()` 蓄力 riser（一次性，~1.1s） | `practice_draw_riser.wav` | `音檔.mp4` 音軌 5.95–7.10s（Gemini 生成參考影片） | 夥伴用 Google Gemini 生成（for VibeSync）+ ffmpeg 後製 | 專案原創（AI 生成，非第三方 sample） | 2026-06-27 | 否 |
| `playSettle()` 落定 settle（一次性，~1.0s） | `practice_draw_settle.wav` | `音檔.mp4` 音軌 6.95–8.00s（Gemini 生成參考影片） | 夥伴用 Google Gemini 生成（for VibeSync）+ ffmpeg 後製 | 專案原創（AI 生成，非第三方 sample） | 2026-06-27 | 否 |

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
3. 音量常數集中在實作檔內（whoosh 0.7／waiting loop 0.22／reveal chime 0.8／riser 0.6／settle 0.7），方便真機調整。
4. error／402／429／hidden／dispose／reduce-motion 一律不殘留等待 loop（呼叫端 ceremony 已備妥對應 `stopWaitingLoop`）。
5. 測試：`practiceDrawSfxProvider` 可 override 注入 spy；真實 impl 在測試環境可建立、可呼叫四方法皆不丟例外（不真的發聲）。

## 待辦（TODO）

- [ ] Eric 出新 TestFlight build 後真機目檢音效（romantic 基調＋reveal hit 是否到位、loop 是否夠小聲）。
- [ ] Batch D4：真機目檢 riser（蓄力是否到位）＋settle（落定感是否足夠——此影片無乾淨衝擊，settle 偏柔，
      若不夠「落定」可改程式化合成替換 wav，介面不變）；音量常數 riser 0.6／settle 0.7 視真機微調。
- [ ] reduce-motion 目前保留 haptic 與一次性音效、但不啟動 waiting loop；未來若加「使用者
      靜音偏好」，再決定是否連一次性音效一併靜音。
