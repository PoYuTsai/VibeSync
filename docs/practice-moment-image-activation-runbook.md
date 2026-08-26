# 練習室動態生成配圖：啟用與回退 runbook

一句話：**PR #34 已合併、三支 migration 已套用 production；2026-08-26 已由 Eric-AI 啟用 kill switch。這份 runbook 保存目前狀態、重新啟用／回退方式，以及生圖健康檢查。**

- 對應設計文件：`docs/plans/2026-08-25-practice-moments-generated-images.md`
- 合併 commit：`318ef43`（PR #34，2026-08-26）
- 最近一次執行：Eric-AI（Eric 授權，2026-08-26）

---

## 1. Production 目前狀態（全部已完成，不需重做）

| 項目 | 狀態 |
| --- | --- |
| PR #34 Squash Merge 進 `main` | ✅ `318ef43` |
| 三支 migration 依序套用 production 並驗證 | ✅ `20260825120000` → `20260825150000` → `20260826024500`（Eric 於 2026-08-26 執行，remote ledger 與 schema/RPC 契約通過） |
| `FAL_API_KEY` 已設於 Supabase Secret | ✅（**任何情況下都不得輸出這把 key 的值**到 log、PR、留言或終端） |
| `DEEPSEEK_API_KEY` 已設於 Supabase Secret | ✅（只驗名稱存在，不輸出值） |
| fal.ai Dashboard spend cap | ✅ Eric 於 2026-08-26 設定完成 |
| `MOMENT_IMAGE_GEN_ENABLED` | ✅ 2026-08-26 已設為全小寫 `true`，三個必要 Secret 名稱均已確認存在 |

---

## 2. 首次啟用或回退後重新啟用

Kill switch 是 `practice-chat` Edge Function 讀的環境變數。值**必須是全小寫字串 `true`**；`TRUE`／`1`／`yes` 一律視為關閉（程式是 `=== "true"` 嚴格比對，見 `supabase/functions/practice-chat/handler.ts`）。

目前 production 已啟用；以下指令保留給日後回退後重新開啟，不需重複執行。

```
npx.cmd --yes supabase secrets set MOMENT_IMAGE_GEN_ENABLED=true --project-ref fcmwrmwdoqiqdnbisdpg
```

確認（只列名稱與雜湊，不印值）：

```
npx.cmd --yes supabase secrets list --project-ref fcmwrmwdoqiqdnbisdpg
```

清單裡必須同時看到 `MOMENT_IMAGE_GEN_ENABLED`、`FAL_API_KEY`、`DEEPSEEK_API_KEY` 三個名字——三者缺一，生圖路徑就不會被組起來（fail-safe，不是錯誤）。

**不需要重新部署 Edge Function**：secret 由新的執行實例讀取，而貼文本來就是在 slot 時間才生成。合併時 push-triggered 的 `Deploy Edge Function` workflow 已涵蓋部署，**不得重複部署**。

---

## 3. 驗證它真的活了

### 3.1 觀測（Supabase Edge Function logs）

開啟後，等到有人開「她們的動態」且該次請求補了一則要配圖的貼文，log 會依序出現：

| 事件 | 意義 |
| --- | --- |
| `practice_moment_image_jobs` | 有生圖 job 被排進背景（`scheduled` 為本次排入數） |
| `practice_moment_image_committed` | **成功**：圖已存進 Storage 並寫回 ready（帶 `bytes`） |
| `practice_moment_image_failed` | 失敗一次，看 `failureClass` 分辨原因（見下表） |
| `practice_moment_image_scene_degraded` | 場景句 DeepSeek 失敗、退用題材模板句（**不是**錯誤，圖照生） |
| `practice_moment_image_expired_swept` / `practice_moment_image_orphan_ledger_swept` / `practice_moment_image_orphans_swept` | 三段清理各自的成果數 |

常見 `failureClass`：`fal_image_http_<狀態碼>`（供應商回錯，402/403 多半是額度或 key；平台端 safety checker 命中通常也走這裡）、`fal_image_too_small`（黑圖保險）、`fal_image_too_large`（超過 12MB 上限）、`fal_image_bad_content_type`／`fal_image_bad_magic`（不是 PNG）、`fal_image_download_failed`、`fal_image_timeout`（fal 呼叫超過 60s）、`fal_image_upload_timeout`。

> 2026-08-26 換 Seedream 4.5 之後，`fal_image_nsfw` 與 `fal_image_safety_unverified` **不會再出現**——該模型的 output 沒有逐張 NSFW 判定，守門改由請求端的 `enable_safety_checker: true` 在平台側完成（設計文件 §9）。

### 3.2 資料層（Supabase SQL Editor，唯讀查詢）

```sql
-- 今天與昨天的圖片狀態分佈；開啟後應開始出現 pending → ready
SELECT post_date, image_status, count(*)
FROM public.practice_moment_posts
WHERE post_date >= current_date - 1
GROUP BY 1, 2
ORDER BY 1 DESC, 2;

-- 孤兒帳本應該長期接近空；持續累積代表清算沒在跑
SELECT count(*) AS rows_with_orphans
FROM public.practice_moment_posts
WHERE cardinality(image_orphan_paths) > 0;
```

`image_status` 的意義：`none`＝純文字或圖鑑照片、`pending`＝排隊或生成中、`ready`＝有圖、`failed`＝重試燒完的終態純文字、`expired`＝出窗已刪圖（列保留供審計）。

**開啟前就已存在的貼文永遠是 `none`，不會回頭補圖**——這是預期行為，不是 bug。要等新的 slot 時間到（每個角色每天 2 則）才會看到 `pending`／`ready`。

### 3.3 健康線

`failed` 佔圖文 slot 超過 **10%** 就要看 `failureClass` 分佈並回報；這比照文字路徑 `exhausted > 5%` 的慣例。

---

## 4. 回退（隨時可做，不需改碼、不需重部署）

```
npx.cmd --yes supabase secrets set MOMENT_IMAGE_GEN_ENABLED=false --project-ref fcmwrmwdoqiqdnbisdpg
```

關掉之後：新貼文回到 20 張 bundled 素材路徑（行為與合併前完全相同），**已經生成的圖仍會正常顯示**（`storagePublicUrlBase` 刻意獨立於開關），出窗清理也照常運作。

---

## 5. 本 runbook **不做**的事

- 不重新部署 Edge Function（push-triggered workflow 已涵蓋）
- 不動任何 migration（三支已套用完成）
- 不觸發 `Release to App Stores`／TestFlight 送審——那是 Eric 的手動動作
- 不輸出、不回報任何 secret 的值
- 不調整 `IMAGE_PROBABILITY`、角色 allowlist 或 attempts 上限（改動屬 Eric 拍板項）

---

## 6. 啟用／回退後回報格式

1. `secrets list` 是否看到三個必要名稱（**只回報名稱有無，不回報值**）
2. 首次觀測到 `practice_moment_image_committed` 的時間；若尚未出現，說明是還沒到 slot 時間還是有 `failed`
3. §3.2 兩段 SQL 的結果
4. 有無 `failed`／`failureClass` 分佈，是否超過 10% 健康線
5. 若判斷需要回退，說明理由並執行 §4

---

## 7. 之後才輪到的事（不在本 runbook 範圍）

真機驗收需要一個**含 PR #34 client 變更的新 build**：解析 `imageUrl` 與渲染網路圖是 PR #34 的 Flutter 端改動，舊 TestFlight build 會忽略未知欄位、繼續顯示純文字。目前 Eric 已回報新 build 已出，可直接進行真機驗收：

- 新的圖文貼文**首次進頁是純文字**，重進頁面才出圖（文先圖後是設計）
- 圖與該則文字相符，且**無人臉、無文字、無品牌**
- 自拍題材仍用圖鑑照片，不生成人臉
- 14 天前的舊貼文無圖屬正常（清理生效）
