# 翻牌儀式「完美復刻」— ms-level Storyboard（Gate 1 deliverable）

> 方法重置後第 4 輪。目標＝**逐幀復刻 `音檔.mp4`**，fidelity 第一、code purity 次要。
> 本檔取代舊 design doc 的 storyboard 段（`2026-06-27-card-draw-replication-design.md`）。
> Gate 序：**storyboard approval → local Flutter preview video approval → 才進 build/TF**。

## 來源真相（ffprobe 量測，非記憶）

- 檔案：`/mnt/c/Users/eric1/OneDrive/Desktop/音檔.mp4`（夥伴 Gemini 生成的概念片，模擬 VibeSync UI）
- 影像：**720×1280 直式（9:16）、24fps、10.000s、240 frames**
- 音訊：AAC 44.1k stereo、9.999s

## 音訊封包（0.5s 視窗 RMS，量測值）

| t | RMS dB | 意義 |
|---|--------|------|
| 0.0 | −94（靜音） | 開場無聲 |
| 0.5 | −34 | **聲音進場** |
| 1.0 | −33 | 蓄力 |
| 2.0 | −51 | 過渡低點 |
| **3.0** | **−26** | **PEAK #1**（蓄力完成 / 第一翻牌沖擊） |
| 4.5 | −60 | 漸弱 |
| **5.0** | **−77** | **屏息（near-silent）最深谷** |
| 6.0 | −30 | 再蓄力 |
| **6.5** | **−26** | **PEAK #2**（爆裂高潮 / 光束climax） |
| 8.0 | −51 | 過渡低點 |
| **8.5** | **−29** | **PEAK #3**（落定入 UI 沖擊） |
| 9.5→10 | −59→−126 | 淡出至靜音 |

修正 handoff：**三個 peak（3.0/6.5/8.5）非兩個**；屏息谷在 5.0s。

## 結構＝兩段升階（two-stage 升階，驗證 Batch A/C 骨架方向對）

charge → **stage-1 preview reveal** → 屏息 recede → **flip-explosion** → **grand reveal** → settle。
被否決的是 fidelity / timing / audio，**不是結構**。

## Beat 表（每 beat：時刻｜畫面｜卡尺寸/位置｜光效｜音對齊｜render 歸屬）

卡寬 = 佔螢幕寬 %（以 390 logical 估）。render：**CP**=CustomPaint live／**PR**=pre-render asset。

| # | t (s) | 畫面狀態 | 卡尺寸 / 位置 | 光效 | 音對齊 | render |
|---|-------|----------|--------------|------|--------|--------|
| 0 | 0.0–0.5 | 卡背（紫六角水晶）靜置於**正常亮色 UI**（header/chips/聊天列全在） | 白外框 ~82%，內卡 ~74%，置中偏上 | 邊緣金色細光點綴 | 靜音 | CP |
| 1 | 0.5–1.0 | 螢幕**轉暗→星空**，卡升起進 3D，UI 淡出 | ~76%→70%，輕 3D tilt（±10–15°） | 星空浮現＋金色 rim light | 0.5s 聲音進場 | CP |
| 2 | 1.0–3.0 | 卡背浮空蓄力，**neon 軌道邊框循環變色（cyan↔gold↔blue）**，星塵漸密 | ~70%，置中，持續微 3D 擺動 | `_OrbitalHaloPainter`＋`_EnergyBorderPainter`（色循環）＋`_StarfieldPainter` 加密＋sparkles | 漸強 → | CP |
| 3 | 3.0 | 卡背 3D 立直、金框、蓄力完成 | ~68%（tilt 透視前縮） | 金 rim 最亮、星塵收束 | **PEAK #1** | CP |
| 4 | 3.5–4.75 | **Stage-1 preview reveal**：正面卡（真實抽到的女生照）滑入、浮空懸停 | ~52%，y-center ~38% | 卡落位柔光、底部微 glow | 漸弱 | CP |
| 5 | 5.0 | 正面卡**回縮變小**至最靜點（屏息） | ~48%，y-center ~40%，透明度微降 | 幾乎無光、星空轉暗 | **屏息 −77dB** | CP |
| 6 | 5.25–6.0 | 卡**翻回卡背**、金框、3D tilt、光在頂部聚集 | ~60%→edge-on 起手 | 金框＋頂部聚光、star 重新點亮 | 再蓄力漸強 | CP |
| 7 | 6.0–7.25 | **Flip-explosion（wow）**：卡 edge-on rotateY 穿過**軌道光環＋垂直光束＋鏡頭光斑＋星爆**，光中浮現照片→收束 | edge-on 旋轉（寬度被光蓋過） | **PR：光環/光束/flare/sparkle additive 疊在 live card 之上**；live card 底層做 rotateY | **PEAK #2 @6.5** | **PR**＋CP底 |
| 8 | 7.25–8.0 | **Grand reveal**：正面卡定格、**金色雕花框＋cyan 底部 neon**、典藏感 | ~70%，置中 y~46% | 金框描邊光＋cyan glow＋稀疏星塵 | 7.25 resolve | CP |
| 9 | 8.25–8.75 | grand 卡縮小、UI 淡回（practice room 重現） | ~70%→~74% 過渡 | neon 漸隱、UI 淡入 | **PEAK #3 @8.5 落定** | CP |
| 10 | 8.75–10.0 | 正面卡**落定於正常亮色 UI**（photo-first，「點照片看全屏」），= 抽到後穩態 | ~74%，y-center ~40%，亮色 theme | UI 正常、儀式光全退 | 淡出 9.5→10 | CP |

開/收對稱：**開場=卡背靜置亮 UI（紫六角）／收場=正面卡靜置亮 UI（女生）**；儀式中段=暗色星空。

## 實作架構（Eric 拍板 Option 1：explosion pre-render，assets 允許）

1. **單一時間軸控制器**（沿用既有 drawStatus 狀態機驅動、零計費/網路、零 Timer、唯一 repeat=`_waiting` 嚴格 gate），總長對齊 master audio 10.0s，**具名子區間錨在三 peak（3.0/6.5/8.5）＋屏息（5.0）**。
2. **CP（CustomPaint live）** 負責：beat 0–6、8–10（charge / 雙色 neon 循環 / stage-1 preview / 屏息 recede / 翻回 / grand 金框 cyan / settle / reduce-motion fallback）。多數 painter 已存在（`_MysticBackPainter`/`_OrbitalHaloPainter`/`_EnergyBorderPainter`/`_StarfieldPainter`）。
3. **PR（pre-render asset）** 負責：beat 7 explosion（6.0–7.25s，~1.25s）。**light-only additive sprite**（光環＋光束＋flare＋star，**不含卡/照片**），疊在 live card（底層自己做 edge-on rotateY 顯示真實女生照）之上 → 真機主體仍是真實抽到的人。
4. **fallback**：reduce-motion 時整條特效不 render，PR 不播，直接 drawSucceeded 穩態（守既有鐵則）。

### Explosion asset 來源（待 Gate-1 通過後定）
- 選項 A（最高保真、最省工）：對 `音檔.mp4` 6.0–7.25s 段做 **luma-key／screen-blend**（光在暗底，暗底自然被 additive 丟掉）→ 抽出 light-only 序列直接用。風險：~0.4s 內有極淡 Emily 照片殘影。
- 選項 B（最正確）：自製 generic 光爆 sprite（Rive/Lottie/透明序列），完全不含照片。工多。
- 建議：先做 A 看 preview，殘影若擾眼再升 B。

## 音訊計畫（Eric req）
- **直接用 `音檔.mp4` 完整原音軌做 master loudnorm**（two-pass `loudnorm`，正常響度）。
- **不**再切柔和 riser/settle；**不**疊舊 `reveal_chime`（`playRevealChime` 全拿掉）。
- 真機主聲音 = 這條 master track。asset 落在 `assets/audio/practice_draw/`，授權＝夥伴 Gemini 原創（沿用 licenses 記錄）。

## 驗收 Gate（本輪改制）
1. **Gate-1 storyboard approval**（本檔＋8-beat 證明圖）← 現在等 Eric。
2. **Gate-2 local preview video approval**：Flutter render 出整段儀式（含 master audio、iPhone 直式 ≥390×844、卡背→reveal 完成全長），**左 reference／右 app side-by-side**，Eric 逐秒看。
3. 才進 iOS/TF build 真機。
- 測試綠 = 只代表安全，**不代表復刻完成**。

## Gate-2 preview 產法（技術路徑，待 Gate-1 後執行）
ceremony 為確定性時間軸（無真 Timer），可用 widget-test harness：固定步長 `pump(1/30s)` → `RepaintBoundary.toImage` 逐幀截圖 → ffmpeg 組 mp4 → mux master audio → 與 reference `hstack` side-by-side。**離線、可重現、不需真機**。
