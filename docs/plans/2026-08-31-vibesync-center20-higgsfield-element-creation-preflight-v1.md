# VibeSync Part 2 B｜中央 20 位 Higgsfield Element 建立預檢 v1

日期：2026-08-31  
狀態：**已執行完成。20／20 Character Elements 均為 exact name、`completed`，provider IDs 已回填；credits 由 654.25 維持 654.25。該次建立授權已用完，未執行 rebuild、reroll 或影片生成。**

## 本次外部動作邊界

- 動作：在 Higgsfield `Elements → New Element` 逐一建立 20 個 Character Element。
- Model：不適用；這是資產 Element 建立，不是影像生成。
- Mode：`Elements → New Element`，Category 固定選 `Character`，不用 `Auto`。
- 秒數／比例／解析度／音效：不適用。
- 來源：20 張 JPEG，每個 Element 僅上傳對應的一張身份圖。
- 畫面張數：共 20 張；每次建立 1 張。UI 未提供批次建立入口。
- Higgsfield 帳戶：Plus Plan。
- 2026-08-31T13:35:11+08:00 即時 credits：`654 left`。
- 建立表單在尚未上傳時沒有顯示任何 numeric cost；官方說明也沒有列出手動建立 Element 的固定費用。因此本次**不能宣稱已知為 0 credits**。若上傳後或按下 Create 前出現任何扣點數字，立即停止並重新向 Eric 預檢。
- Reroll／retry／rebuild／自動重送：全部 OFF。任何失敗、重名、身份錯誤或重建都是另一個外部動作，不自動再送。
- 本次不建立 Part 2 B 影片 Job，不調整影片生成參數，也不購買 credits。

Higgsfield 即時 UI 實查：建立表單包含 `Category`（Auto／Character／Location／Prop）、Workspace、Enter name、Add description、單一 Upload media、Cancel、Create。現有 My Elements 只有 `VibeSync_ENV0_ScreenWell`、`VibeSync_Male_M1`、`Sydney_V3_WhiteOnepiece`；20 位女孩均尚未存在。

官方參考：Higgsfield 說明可從 Assets 手動 `Create Element`，並在生成時從 My Elements 引用；其 credits 說明只明確列影像／影片 generation、reroll 與 upscale 為扣點動作。建立 Element 的實際 UI 未顯示固定價格，故仍以按 Create 前的即時畫面為準。

## 執行結果

- 執行時間：2026-08-31T05:51:42Z–2026-08-31T05:55:35Z。
- 20 張來源均上傳至 Eric 的 Higgsfield private workspace。
- 20／20 exact Element name、`character`、`completed`。
- 20／20 Element 的來源 media ID 與對應上傳圖一致。
- 重複名稱：0；數字尾碼漂移：0；失敗：0；自動重試：0。
- credits：建立前 654.25，逐筆建立後與最終均為 654.25。
- 真正 provider IDs：`../handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/TANK100_center20_element_provider_ids_v1.json`。
- 本次沒有建立 Part 2 B 影片 Job；影片仍需另一份完整 26-input live preflight 與 Eric 新的一次「跑」。

## 每次建立的固定欄位

- Name：使用下表 `Element name`，不加 `@`。
- Category：`Character`。
- Description：`Adult woman from the VibeSync roster. Identity reference only: preserve the uploaded face, hairstyle, age impression and body impression. Do not lock the source background, clothing, pose, hands, camera or lighting.`
- Source image：只使用同列 JPEG；禁止使用中央 20 人控制板、群像圖、Stella 重複圖或其他女孩圖片。
- Element 只鎖身份；座位、晚禮服、手勢、號碼牌、玻璃、燈光與鏡頭仍由母幀、prompt 與後製控制。

## 20 個建立項目與檔案快照

共同目錄：`docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/`

| 順序 | Element name | Repo-relative source path | px | bytes | SHA-256 |
|---:|---|---|---:|---:|---|
| 1 | `VibeSync_Girl_078_Leah` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_078_Leah.jpg` | 720×1080 | 159285 | `a9cba8f20c50ec27b37559a369c302a17e633cd5ce4ceaf5da4b9dd9cc9a7807` |
| 2 | `VibeSync_Girl_024_Celine` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_024_Celine.jpg` | 511×1080 | 167979 | `b775efc959865db53e76663d1a73b1bf7265534ae5e66c69f45a0d50f60c2f70` |
| 3 | `VibeSync_Girl_032_Peggy` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_032_Peggy.jpg` | 504×1080 | 91300 | `71c5b1050d53bfc1630ec2180f14559fcbe1878e7f4a175df3ad8cc4e205b131` |
| 4 | `VibeSync_Girl_016_Ruby` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_016_Ruby.jpg` | 608×1080 | 125073 | `6f455f2da3fc5f2dc2c582e56f47271b0b52cacf0f8db3927674d7b5911f9d5c` |
| 5 | `VibeSync_Girl_051_Jessie` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_051_Jessie.jpg` | 500×1080 | 94117 | `e4f305321b30fbff8590c0a35130531125ba7d732926cbe9cbafbd388cae33fe` |
| 6 | `VibeSync_Girl_083_Tara` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_083_Tara.jpg` | 719×1080 | 105289 | `06bb9bcb74eb011f6e1b85f47704aa2d5832dfc16f5ab0b7bbb1e4000a668b67` |
| 7 | `VibeSync_Girl_011_Ella` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_011_Ella.jpg` | 512×1080 | 108862 | `e1ccbaa9e113d604622ed4a6f7da3218e1163014e27bbbdd2b4de5eab6f58405` |
| 8 | `VibeSync_Girl_019_Vivian` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_019_Vivian.jpg` | 608×1080 | 95244 | `05ff0f9a72b6483b6d70044d76464befa77352a4f6ef18a88a1ebf05664d06dd` |
| 9 | `VibeSync_Girl_070_Yuki` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_070_Yuki.jpg` | 510×1080 | 99073 | `064c2f7ed5bd94a11dc3cc27573b55830c2cd2a17fc0610814c0909f06d79f9c` |
| 10 | `VibeSync_Girl_082_June` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_082_June.jpg` | 523×1080 | 104410 | `58e8252364d7868125c32e013655e257baf214be107f8a279de6f9dfee2c684f` |
| 11 | `VibeSync_Girl_017_Grace` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_017_Grace.jpg` | 608×1080 | 111973 | `2e2794e6130e1d804cecaf8c8fa282a8e52f9a613ae5cb87867631a9ed4c0afc` |
| 12 | `VibeSync_Girl_023_Fiona` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_023_Fiona.jpg` | 720×1080 | 171739 | `6e2ba5393a076833359179363b42f3f5d51b870a2cbc620d3180ee9d95c72243` |
| 13 | `VibeSync_Girl_026_Joyce` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_026_Joyce.jpg` | 720×1080 | 136183 | `9ce1d368a6700a4027ad1de329cfee4ae134f70ea6b69e02cc91135d309efaf9` |
| 14 | `VibeSync_Girl_068_Flora` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_068_Flora.jpg` | 720×1080 | 174680 | `a52cb416447ace7f93d941e0d2bbbb5984708629908919ee2ad2c00158ab7c3b` |
| 15 | `VibeSync_Girl_038_Stella` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_038_Stella.jpg` | 608×1080 | 106337 | `800b1bdabdffcc45617f211948e0b397e74d9fd105355146349104b5ce1a29c7` |
| 16 | `VibeSync_Girl_099_Audrey` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_099_Audrey.jpg` | 1080×1080 | 124214 | `776f08739346859c166b239fefc1a7b95e2d3618a8df2da5125776d43e87e923` |
| 17 | `VibeSync_Girl_086_Demi` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_086_Demi.jpg` | 720×1080 | 152718 | `8b63a9ba02a3529b207fd4477c756e6ae1c4b5f3b0927ad579b0abf11b16be0f` |
| 18 | `VibeSync_Girl_088_Joan` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_088_Joan.jpg` | 720×1080 | 143263 | `0a90a83a997f67774ae5598b60da356304a04f201dccbf5f4fe8ee165be369ce` |
| 19 | `VibeSync_Girl_090_Talia` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_090_Talia.jpg` | 720×1080 | 127260 | `051fbeb1d09c01575959f10076ec37643db8b7b28d90b8f3fe0868d162065a9b` |
| 20 | `VibeSync_Girl_096_Willa` | `docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_096_Willa.jpg` | 720×1080 | 136438 | `94ca77e2751fa2ebd64569ef0c65f1cf8b586a1bad4f1ac7fb8f3a08577b5366` |

## 完整性與重算證據

- 快照時間：`2026-08-31T05:30:54Z`。
- 精確快照：上表 20 個 repo-relative paths、每檔 bytes 與 SHA-256；不以單一 aggregate digest 取代逐檔證據。
- 第一套重算：Windows PowerShell `Get-FileHash -Algorithm SHA256`。
- 第二套獨立重算：Ubuntu WSL `sha256sum`。
- 結果：20／20 檔名與 SHA-256 完全相符；20 張均可解析為 baseline 8-bit JPEG，尺寸如表。
- PowerShell 重現方式：`Get-ChildItem <pack> -File -Filter 'VibeSync_Girl_*.jpg' | Sort-Object Name | ForEach-Object { $_.Name; $_.Length; (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }`
- WSL 重現方式：`sha256sum /home/eric1/work/VibeSync/docs/handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/element-upload-pack-v1/VibeSync_Girl_*.jpg`

## 授權後的執行順序與停損

1. 依 1→20 順序逐一開 `New Element`，選 `Character`，填 exact name／固定 description，僅上傳同列 JPEG。
2. 每次 Create 前再次檢查是否出現 numeric credit cost；若出現，未按 Create 即停止。
3. 成功後立刻確認 My Elements 只新增該 exact name，沒有覆蓋或混入上一位角色。
4. 若 UI 可讀取 provider ID，才回填 `TANK100_center20_element_provider_ids_v1.json`；讀不到就保持 `null`，不得猜造。
5. 每次建立後重讀 credits；若 credits 從 654 下降或出現非預期費用，立即停止，回報已完成項目與剩餘額度。
6. 任一失敗不自動 retry；任一肉眼身份錯誤不自動 rebuild。
7. 20 個均成功後才另做 Part 2 B 影片 Job 的 26-input live preflight；本次「跑」不授權影片生成。

## Eric 授權語意

Eric 在看到本清單後回覆「跑」，只代表授權：上傳這 20 張指定 JPEG，依序嘗試建立這 20 個 Character Elements，並遵守上述遇到價格／扣點／失敗即停止的規則；不包含影片生成、reroll、重建、購買 credits 或其他素材上傳。
