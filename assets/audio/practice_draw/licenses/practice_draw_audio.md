# 每日翻牌音效 — 素材授權清單（practice_draw audio）

> **狀態：已 bundle（Batch 4.7B 實裝）。** `practiceDrawSfxProvider` 預設已換成會真的播放的
> `AudioPlayersPracticeDrawSfx`（audioplayers），三組音檔已放進 `assets/audio/practice_draw/`
> 並於 `pubspec.yaml` 註冊為 asset。授權／來源見下表，僅存於本 repo 文件，**不**塞進 app UI。

## 來源與授權（provenance）

這三個音檔是 **Codex 於 2026-06-26 為 VibeSync 以原創程式化 synthesis（procedural synthesis）生成**。
**沒有使用任何第三方 sample、沒有抓取遊戲／影片音源、沒有外部 loop。**

> Original procedural synthesis generated for VibeSync; no third-party samples.

非 CC0、非第三方授權素材 —— 為 VibeSync 原創生成，著作權歸專案所有，可商用 app bundling。

## 授權鐵則（放音檔進來前必過）

- **僅可用**：本專案原創生成、CC0、自製、買斷、或授權條款明確允許「商用 app bundling」的素材。
- **禁用**：NonCommercial / 授權不明 / 從遊戲或影片擷取 / 可辨識到第三方原聲（如神魔之塔、寶可夢等）的素材。
- 授權文字只存在本 repo 文件，**不**塞進 app UI。
- 目標：優先小檔案，整組翻牌音效資產 **< 500KB**（目前 ≈ 296KB）。

## 音檔清單

| 用途（呼叫點） | bundled 檔名 | 原始候選檔 | 來源／作者 | 授權 | 生成日期 | 需署名 |
|---|---|---|---|---|---|---|
| `playWhoosh()` 抽牌咻聲（一次性，~0.3–0.6s） | `practice_draw_whoosh.wav` | `A_romantic_magic_01_whoosh.wav` | Codex 原創程式化 synthesis（for VibeSync） | 專案原創（非 CC0） | 2026-06-26 | 否 |
| `playWaitingLoop()` 等待 shimmer loop（循環、極小聲） | `practice_draw_waiting_loop.wav` | `A_romantic_magic_02_waiting_loop.wav` | Codex 原創程式化 synthesis（for VibeSync） | 專案原創（非 CC0） | 2026-06-26 | 否 |
| `playRevealChime()` 揭曉 chime/sparkle（一次性，~0.6–1s） | `practice_draw_reveal_chime.wav` | `B_gacha_sss_03_reveal_chime.wav` | Codex 原創程式化 synthesis（for VibeSync） | 專案原創（非 CC0） | 2026-06-26 | 否 |

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
3. 音量常數集中在實作檔內（whoosh 0.7／waiting loop 0.22／reveal chime 0.8），方便真機調整。
4. error／402／429／hidden／dispose／reduce-motion 一律不殘留等待 loop（呼叫端 ceremony 已備妥對應 `stopWaitingLoop`）。
5. 測試：`practiceDrawSfxProvider` 可 override 注入 spy；真實 impl 在測試環境可建立、可呼叫四方法皆不丟例外（不真的發聲）。

## 待辦（TODO）

- [ ] Eric 出新 TestFlight build 後真機目檢音效（romantic 基調＋reveal hit 是否到位、loop 是否夠小聲）。
- [ ] reduce-motion 目前保留 haptic 與一次性音效、但不啟動 waiting loop；未來若加「使用者
      靜音偏好」，再決定是否連一次性音效一併靜音。
