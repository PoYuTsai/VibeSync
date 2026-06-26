# 每日翻牌音效 — 素材授權清單（practice_draw audio）

> **狀態：尚未 bundle 任何音檔。** 目前 `PracticeDrawSfx` 為 no-op（不打包音檔、不發聲），
> 此目錄只存放未來音檔與其授權紀錄的 scaffold。授權未逐一確認前，一律不得把音檔放進
> app、不得在 `pubspec.yaml` 註冊為 asset。

## 授權鐵則（放音檔進來前必過）

- **僅可用**：CC0、自製、買斷、或授權條款明確允許「商用 app bundling」的素材。
- **禁用**：NonCommercial / 授權不明 / 從遊戲或影片擷取 / 可辨識到第三方原聲（如神魔之塔等）的素材。
- 若某素材授權**不是 CC0**，先**不要**放進 app，回報 Eric 決定後再處理。
- 授權文字只存在本 repo 文件，**不**塞進 app UI。
- 目標：優先小檔案，整組翻牌音效資產 **< 500KB**。

## 音檔清單

| 用途（呼叫點） | 檔名 | 來源 URL / 作者 | 授權 | 下載日期 | 需署名 (attribution) |
|---|---|---|---|---|---|
| `playWhoosh()` 抽牌咻聲（~0.3–0.6s） | _（待補）_ | _（待補）_ | _（待補）_ | _（待補）_ | _（待補）_ |
| `playWaitingLoop()` 等待 shimmer/ambient loop（極小聲） | _（待補）_ | _（待補）_ | _（待補）_ | _（待補）_ | _（待補）_ |
| `playRevealChime()` 揭曉 chime/sparkle（~0.6–1s） | _（待補）_ | _（待補）_ | _（待補）_ | _（待補）_ | _（待補）_ |

## 接上真音檔的步驟（未來）

1. 取得符合上述鐵則的音檔，逐一填好本表（含來源、授權、下載日期、是否需署名）。
2. 把音檔放進本目錄上層（`assets/audio/practice_draw/`），於 `pubspec.yaml` 註冊 asset。
3. 評估並（經 Eric 同意後）新增音訊播放套件（如 `audioplayers`），實作一個會真的播放的
   `PracticeDrawSfx`，並在 `practiceDrawSfxProvider` 換掉預設的 `NoopPracticeDrawSfx`。
4. 確保 iOS 尊重 app lifecycle、不殘留 player；waiting loop 必在 reveal／error／hidden／
   dispose 停止（呼叫端已備妥對應的 `stopWaitingLoop`）。
5. 測試環境不得真的播放聲音（維持可 mock / no-op）。

## 待辦（TODO）

- [ ] reduce-motion 目前保留 haptic 與一次性音效、但不啟動 waiting loop；未來若加「使用者
      靜音偏好」，再決定是否連一次性音效一併靜音。
