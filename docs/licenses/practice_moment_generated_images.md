# 練習室動態：runtime 生成配圖的來源與授權

適用對象：「她們的動態」在 runtime 生成、存放於 Supabase Storage public bucket
`practice-moment-images` 的圖片。與 `practice_moment_scene_assets.md`（20 張手動
產生的 bundled 素材）分開記錄——那批是隨 App 打包的靜態資產，這裡是每則貼文
即時生成的動態資產。

## 生成方式

| 項目 | 內容 |
| --- | --- |
| 供應商 | fal.ai（`https://fal.run`，同步端點） |
| 模型 | **ByteDance Seedream 4.5**（`fal-ai/bytedance/seedream/v4.5/text-to-image`）。2026-08-26 從 FLUX.1 [schnell] 換過來 |
| 輸入 | 英文場景句（由 DeepSeek 依貼文內文與題材產生，失敗時退用 40 條題材模板句其一）＋ 常數 STYLE 前綴。**零使用者資料**（隱私鐵則，source test 強制） |
| 尺寸／格式 | `image_size: "landscape_4_3"` preset；輸出固定 PNG（該模型無 `output_format` 參數） |
| 內容約束 | prompt 明文禁人物（無臉、無手、無身體、無剪影）、禁可讀文字（無招牌／標籤／logo／UI）、禁品牌；請求固定帶 `enable_safety_checker: true` |
| 儲存 | Supabase Storage public bucket，物件 key 以 image_token 隔離；出 14 天 feed 窗即刪除物件（DB 列保留供審計） |

## 授權

- 圖片由 fal.ai 託管的 Seedream 4.5 依我方 prompt 即時生成，用於 App 內的 AI 模擬
  練習內容展示。
- 商用可行性依 **fal.ai 的服務條款**與 **ByteDance Seedream 模型條款**為準；換模型
  或換供應商時**必須一併重新覆核這一段**，不可假設沿用。
- 這批圖不含真實人物肖像：prompt 層硬性排除人物，且自拍題材的貼文**不走生成路徑**
  （續用圖鑑照片），以避免肖像與人臉一致性的風險。

## App Review 相關

- feed 畫面頂部常駐「AI 模擬練習內容，不是真人動態」的說明。
- 生成失敗的終態是**純文字貼文**，不會落任何替代圖或罐頭內容。

## 變更紀錄

| 日期 | 變更 |
| --- | --- |
| 2026-08-26 | 建立。模型自 FLUX.1 [schnell] 換為 Seedream 4.5；輸出格式自 JPEG 變為 PNG |
