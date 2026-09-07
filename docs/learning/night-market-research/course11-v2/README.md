# 夜市第 11 集改編｜製作包 v2

Eric 已核准主劇本，2026-09-07 開始製作細化。此資料夾是製作輸入，不是已完成的 App 版本。

- `night-market-approved-production-v2.md`：完整逐鏡、對白、Sydney hint、分支與復盤。
- `night-market-course11-v2.json`：唯一逐句來源；39 個段落、10 組情境條件、15 張条件式復盤卡。
- `night-market-voice-cues-v2.json`：71 句配音；聲音、時間碼均尚未生成／對齊。
- `night-market-voice-audition-v2.json`：Chris、Leah、Sydney 試音內容與驗收要求。
- `night-market-production-validation-v2.json`：圖連線與定稿鎖定檢查；不代表聲音、動態或真機驗收通過。

## 製作狀態

2026-09-08 更新：主線 13 支影片已生成並串成三段接進 App（見 `docs/learning/night-market-mvp.md`）；下方為 09-07 的原始狀態，保留供對照。

已完成：主劇本拆分、反應條件、配音清單、Sydney 提示、條件式復盤資料、來源與關鍵句核對。

尚未完成：三角色聲音選角與試演、原生 9:16 影片、台詞嘴型／時間碼核對、Flutter 新情境接線、獨立最終審查與 iPhone 驗收。未生成付費素材、未 build、未 commit 或 push。舊版 App 仍使用舊資產。

## 先處理聲音

已否決的舊男聲不再沿用。必須取得新角色的正式 voice_id/voice_type，先以試音稿確認台灣華語口音、角色自然度與情緒變化，再批次生成完整對話。不能用調低音高假裝換了適合的男聲，也不能把角色照片的 element 當成已核准聲音。

影音製作與接線只能引用 `status` 已通過的產物；現在沒有這種產物。不要把估計時長填成字幕時間碼，或把舊台詞音軌掛到新句子。
