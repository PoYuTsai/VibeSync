# 每日翻牌儀式「復刻 音檔.mp4」設計（2026-06-27）

> 目標：把翻牌揭曉儀式做成 `音檔.mp4`（桌面參考片，夥伴 Gemini 生成）的高還原復刻。
> 分支：`feature/card-draw-replication`。單一檔：`lib/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart`（1299 行）。

## 為什麼要重做（診斷結論）

- 第 2 輪 dogfood：Eric 實機（1.0.0 **286**、Essential、reduce-motion off、完整重裝）覺得儀式「還是 4.5/4.7、連音效都沒變」。
- 逐幀拆錄影＋對標 `音檔.mp4`＋讀 code 證實：**286 確實在跑 Batch A–D**（卡背金幣＝`_CeremonyCardBack` 的 `Icons.auto_awesome`、軌道點＋金框卡都在），但 **A–D 從頭只在「舊小卡」地基做細修，從沒照參考片的尺度與語彙重做**。所以 Eric 的感覺是準的。
- 第 1 輪「等待幀截圖證明新 code 在跑」是誤判：等待幀在 4.5 與 B/C/D 長一樣，分辨點全在高潮段。

## 五條 gap（對照圖：scratchpad/compare.png，左＝參考、右＝286）

| # | 痛點 | app 現況 | 參考目標 | 根因（code） |
|---|---|---|---|---|
| 1 | 卡太小 | 寫死 `_cardW=214/_cardH=292`、約半螢幕寬 | 近滿版大卡 | 尺寸是常數、無 responsive |
| 2 | 像舊版 | 紫底＋金幣星芒 | 黑金浮雕大框＋紫色立體六角水晶 logo＋密星空 | 卡背語彙不同 |
| 3 | 高潮弱 | 淡軌道點 | 大條彗星光環橫掃＋拖尾 | `_OrbitalHaloPainter` 太小太暗 |
| 4 | — | 小金框＋小資訊條 | 照片滿版＋底部漸層資訊＋青金能量光邊 | grand 版型不同 |
| 5 | 音效廢 | 5 顆離散 SFX（含難聽合成 riser/settle） | 一條連續音樂 bed | 之前從參考抽段＋暴力增益 |

決策（Eric 拍板）：
- **卡背＝完整復刻參考的紫水晶六角**（CustomPaint 重畫，無現成 asset；app icon 是愛心泡泡）。
- **音效＝直接用 `音檔.mp4` 的音軌**（授權 Eric 已確認 Gemini 原創 OK），抽出 master 後與時間軸同步播。

## 關鍵洞察：時間軸要對齊音樂

參考音軌 0.5s 視窗能量（mean/max dB）量出天然結構：
- `0–0.5s` 靜默 → 卡背登場
- `~3.0s` 第一爆點（max −9.9dB，全片最大）→ 預覽卡翻出
- `~5.0s` 近靜音低谷（−77dB）→ 翻回卡背蓄力／屏息
- `~6.5→8.5s` 第二段 build＋第二爆點 8.5s（−13.9dB）→ 高潮翻面→典藏卡落定

現況 `_reveal` 只有 7.5s、預覽翻面 0.7s、高潮 5.0s＝**完全沒對到音樂**。
兩段升階骨架本來就對（卡背→預覽→蓄力→高潮典藏卡），**不打掉狀態機**，只重定時＋換皮＋放大。

## 實作順序（每顆 TDD、跑 practice scope、高風險上 Codex、合併前 Eric iOS/TF 目檢）

- **E1（A＋B）重定時＋放大卡**：`_reveal` 7.5s→~9s；beat 常數重映射（預覽≈0.33、低谷≈0.55、高潮翻面落定≈0.94）；`_cardW/_cardH`→responsive ≈0.84×螢幕寬、直式 3:4、設上限。低風險、一跑就「卡變大、節奏對了」。
- **E2（F）音軌同步**：抽參考 0–~9s bed、normalize/master（現 −33dB 太小）；揭曉起播**一條與 `_reveal` 同步的配樂**；退役離散 riser/settle；保留抽牌咻聲；尊重靜音鍵、不重疊、每個離開出口都 stop。
- **E3（C）紫水晶卡背**：`_CeremonyCardBack`＋`_MysticBackPainter` 重畫＝3D 紫六角水晶＋密星空＋黑金浮雕厚框。
- **E4（D）彗星高潮**：`_OrbitalHaloPainter` 加大加亮成大彗星光環橫掃＋拖尾；調 `_StarfieldPainter` beam。
- **E5（E）滿版典藏卡**：grand 版型→照片滿版＋底部漸層資訊＋青金能量光邊。

## 鐵則（沿用 Batch A–D，絕不破）

- 只靠 `drawStatus` 狀態機驅動，**零新增計費／網路行為**。
- **零 `Timer`／零 `Future.delayed`**：時間軸全由 `_intro`/`_reveal` 有限 controller 推導；唯一 `repeat()` 是 `_waiting`，嚴格 gate（只 drawing＆非 reduce-motion，reveal/error/hidden/dispose 全 stop）→ `pumpAndSettle` 必收斂。
- reduce-motion：跳過 3D 翻面與強動畫；一次性 haptic／音效仍觸發但不啟動等待 loop。
- 只有「真進過 drawing 又成功 reveal」才慶祝；換一位失敗只兜底淡出。
- 公開 `@visibleForTesting` beat 常數＝widget 與 test 單一真相。
- 坑：分支用主 checkout 切（**別開 fresh worktree**＝缺 .g.dart codegen＋pub get 漂 lock）；**絕不 `git add pubspec.lock`**；WSL `dart format` 壞→交給 Windows 側。

## 驗收

對標 `音檔.mp4` 逐節點：卡尺度、卡背紫水晶六角、彗星高潮、滿版典藏卡、音樂同步。Eric iOS/TF 真機目檢為準。
