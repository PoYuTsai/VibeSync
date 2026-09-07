# 夜市互動練習 MVP（簡易搭訕流程詳解）

> 2026-09-08 起 App 內是 v2 版：三段直式影片、兩個選擇點、復盤頁。第一批 Sydney 陪逛 14 支橫式版本已移除，內容在 git 歷史。

- 劇本與素材依據：`docs/learning/night-market-research/course11-v2/`；產品敘事摘要見 `course-synthesis.md`「現行 MVP source 對齊」。
- 單一真實來源：`lib/features/night_market/data/night_market_story.dart`（三段、字幕、選項、講評卡、復盤卡）。
- 資產：`assets/videos/night_market/s1_notice.mp4`、`s2_opening_to_craft.mp4`、`s3_lifehook_to_end.mp4`（1080x1920，共約 36MB，聲音在影片內）與 `assets/images/night_market/cover.jpg`。
- 入口：Learning 頁 Hero 下方卡片「簡易搭訕流程詳解」→ `/practice-night-market`；本頁不建 session、不耗額度。
- 守門：`test/unit/features/night_market/`（圖閉合、字幕順序、復盤層數、資產在 bundle）與 `test/widget/features/night_market/`（開始、暫停、停點→講評→續播→復盤→再練、字幕開關、失敗重試）。
- 未做：分支影片（忙碌／拒絕）、麥克風接話、復盤「回看這段」；等真機驗收後決定。
