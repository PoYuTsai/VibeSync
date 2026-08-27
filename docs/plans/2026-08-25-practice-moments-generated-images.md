# 練習室動態：配圖改為 fal.ai 即時生成（含過期自動刪除）設計

2026-08-25。實作前設計文件。**本文件不含任何 runtime 變更**；實作依 §14 分期。

**決策鏈**：撞圖研究（`2026-08-25-practice-moments-image-duplication.md`）確認 20 張 bundled 素材的撞圖是結構性必然 → Eric 提出改用生圖 API → 比較各家 CP 值後 **Eric 拍板供應商用 fal.ai**。模型於 2026-08-26 由 FLUX.1 [schnell] 換成 **Seedream 4.5**（見 §3）：schnell 出的圖普遍是塑膠感／CG 感，Eric 在真機上看過首批圖後拍板換模型。

---

## 1. 一句話架構

**文字貼文照現有同步路徑一字不動落地；文字 commit 成功後由 `EdgeRuntime.waitUntil` 背景「以文生圖」（貼文文字＋題材 → 英文場景 prompt → fal.ai → 下載轉存 Supabase Storage public bucket），token-fenced 寫回同列的獨立 image 欄位組；feed handler 順路做有界的接手與過期清理（機會式，零新排程基礎設施）；env kill switch 關閉時退回現行 20 張 bundled 素材路徑。**

```
feed 請求（現行路徑不動，8 秒總死線不變）
 └ fillOneSlot: reserve → DeepSeek 文字 → validate → commit（wantsImage 時標 image_status='pending'）
 └ commit 成功後 waitUntil(生圖 job)          ← 新增，不佔 8 秒死線
      claim_practice_moment_image（token + 180s 租約 + 同交易 per-user 限流）
      → DeepSeek 一次便宜呼叫：body＋brief → 英文場景句（失敗退題材級模板句）
      → fal.ai 同步端點（timeout 涵蓋完整 body）→ 邊界驗證下載 → Storage 上傳（token 隔離 key、永不覆寫）
      → commit_practice_moment_image（token-fenced → image_status='ready'）
      失敗 → release_practice_moment_image（attempts 到頂轉 'failed'＝該則永久純文字）
 └ waitUntil(清理 job)：出窗圖 → 孤兒帳本清算 → 最舊出窗 prefix 對帳（三段都 LIMIT 有界）
接手自癒：之後任何 feed 請求看到 pending 且租約逾時的列，取最多 2 則丟進 waitUntil
```

Client 動態：貼文先以純文字出現；生圖 10 秒內完成，**下次進頁**（D7：每次進畫面重抓）看到圖。不推播、不輪詢。

---

## 2. 與既有設計決策的關係（正式翻案清單）

| 既有決策 | 本案處置 |
| --- | --- |
| 設計報告 §3 決策 D3「P1 不做 Storage/CDN」 | **反轉**：引入 Supabase Storage public bucket。反轉依據＝撞圖研究量化結論（一屏撞圖率最高 88%）＋bundled 池結構性撐不住 |
| 設計報告決策 6「排程預熱不做（需 pg_net／新 CI 憑證）」 | **不重開**：本案不需要任何排程——生成掛在請求生命週期的 waitUntil，清理走機會式 |
| 「零新憑證」 | **反轉**：新增 `FAL_API_KEY` 一把（Eric 手動 `supabase secrets set`，流程照 `DEEPSEEK_API_KEY` 前例、不進 preflight 必檢清單＝缺 key 降級不擋 deploy） |
| D6「feed 14 天、DB 永久保留」 | **不變**：只刪 Storage 物件與標記欄位，**永不刪列**（release RPC 三鐵則之一照舊） |
| no-canned 鐵則 | **不變且延伸**：生圖失敗絕不塞替代圖，終態＝純文字 |
| 隱私鐵則（生成輸入零使用者資料） | **不變**：生圖 prompt 輸入＝committed body（本身由 server 事實生成）＋themeId＋常數模板 |
| 撞圖研究 S1–S3 方案 | S3（bundled 變體素材）**作廢**；S1/S2 降為 fallback 路徑的可選小修；census 工具保留 |
| `moments_memory.ts`（1:1 記憶注入） | **零影響**：記憶只用文字，已實測無 image 引用 |

---

## 3. 供應商定案：fal.ai／模型 Seedream 4.5（2026-08-26 換）

**已由 Eric 拍板（2026-08-25）。** 選型理由與規格：

- **端點**：同步 `https://fal.run/fal-ai/bytedance/seedream/v4.5/text-to-image`（另有 `queue.fal.run` 佇列制備用）。**同步 HTTP 即可**——生圖跑在 waitUntil 背景，使用者從不等它，所以模型變慢（schnell 的 1–2 秒 → Seedream 的十幾秒量級）對體感零影響，只需把 fal timeout 從 30s 放寬到 60s。
- **認證**：header `Authorization: Key ${FAL_API_KEY}`。
- **關鍵參數**：`image_size: "landscape_4_3"`（**官方 enum preset**）。custom size 的規則是「兩軸皆在 1920–4096」**或**「總像素落在 2560×1440 到 4096×4096」——第一版自訂的 1920×1440 兩條都不滿足（高度低於 1920、總像素 2.76MP 低於 3.69MP 下限），會被供應商打回，這是複審抓到的 P1。改用 enum 讓 fal 自己映射到合法尺寸，構造上不可能違規；代價是實際像素數未公開，檔案大小改由 12MB 上限與 production log 的實測值把關、`num_images: 1`＋`max_images: 1`、`seed`（**傳入 fnv1a slot 種子**）、`enable_safety_checker: true`（**安全鐵則，見 §9**）。**沒有 `output_format` 參數：輸出格式由供應商決定，我們指定不了。** 官方 schema 的 example 給的是 `.png`／`image/png`，但 2026-08-27 的 canary 實測回的是 **JPEG**（`v3b.fal.media/....jpg`，2.1MB）——**example 不是契約**，這是第二輪複審後的實測修正（見 §5、§7）。
- **輸出**：JSON 內 `images[].url` 指向 fal 的 CDN（暫時 URL）→ **Edge 下載後轉存 Supabase Storage**，client 永遠只拿我們自己的 URL。
- **價格**：**$0.04/張**（fal 官方定價，與張數大小無關）→ 實測量（~11 張/天、~370 張/月含重試）約 **$13–15/月**。換模型前的 schnell 是 $0.0024/張、月費 < $1，也就是這次換模型讓成本上升約 16 倍——絕對金額仍小，但**算術上界**同步放大（見 §11）。
- **換模型的彈性**：fal.ai 同站託管 FLUX 全系與 Qwen-Image 等開源模型——質感不滿意時**只換 model id 字串**，金流、金鑰、client 模組全部不動。這是選託管平台而非單一模型官方 API 的核心理由。
- **落選備註**：Qwen Image 3.0 Pro（阿里官方 ~$0.075/張、非同步任務制＋輪詢）為本清單最貴且整合最複雜；gpt-image-1-mini（$0.005 起）為大廠備選。2026-08-26 的換模型只換了 model id 與該模型的 schema 接點，供應商仍是 fal，架構未動——這正是當初把整合層寫成供應商無關的目的。

**正式接線前的試打**（Eric 手動、不寫程式、花費 < $1）：在 fal.ai playground 用 `2026-08-24-practice-moments-scene-image-prompts.md` 的 STYLE/NEGATIVE 模板生 10–20 張，打同文件 §6 驗收清單。

---

## 4. 時序架構：為什麼是「背景兩段式」

| 方案 | 判定 | 理由 |
| --- | --- | --- |
| **(a) waitUntil 背景生圖** | **採用** | 文字路徑（已上線）一行不動；`handler.ts:478-590` 已有 waitUntil 的可注入 dep 範式與測試 collector 可照抄；Edge wall clock（免費 150s／付費 400s）對「生圖 2s＋下載轉存 3s」綽綽有餘；零新基礎設施 |
| (b) 每日預生成 | 否 | 需 pg_net 或新 CI 憑證（決策 6 否決過）；且 lazy 模型只為有人看的角色花錢，預生成為全名冊無條件燒 |
| (c) 塞進 8 秒同步死線 | 否 | 死線是「最多 3 則文字補生成」共用的總預算，再塞「生圖＋下載＋上傳」等於把 feed 延遲耦合到兩個外部服務；背景化只差「下次進頁才看到圖」，產品上可接受 |

**waitUntil 蒸發風險**（Edge 實例回收）由接手機制自癒：租約 180s 逾時後，任何觀看者的請求把 pending 列重新認領（單請求上限 2 則）。與現行文字補生成「租約逾時或下次請求接手」同一哲學。

---

## 5. 文圖一致性：文先圖後

- **方向**：文字照現行 prompt 先生成（`moments_prompt.ts` 的 wantsImage 分支僅微調措辭：告知「會配一張你拍的照片」但**不再給 imageId 候選清單**，`imageId` 一律回 null）；圖從 committed body 長出來。撞圖截圖的違和感（三段不同文字共用同一張鍋子照）由構造消滅：她寫弄了碗麵，圖就是那碗麵。
- **英文場景句**：一次便宜 DeepSeek 呼叫（~300 tokens）把「繁中 body＋themeId brief」轉成 1–2 句英文場景描述。輸出驗證：純 ASCII、長度上限、禁 person/face/text/logo 詞面。**該呼叫失敗退回題材級英文模板句**（每個 themeId 各一句，純資料表；撰寫當下 42 個，#36 擴充觀點與興趣題材後為 62 個）——內部 prompt 的模板退路不違反 no-canned（該鐵則管可見文字），但新模組命名避開 "fallback" 字面（`moments_generated_only_source_test.ts` 逐字串掃描），用 `themeSceneLine` 之類。
- **完整 prompt** ＝ STYLE 前綴 ＋ 場景句。Seedream 4.5 在 fal 上**沒有 `negative_prompt` 參數**，素材規格書 NEGATIVE 清單的語義改折進 STYLE 前綴（no people／no readable text 兩條硬規則明寫）與每條場景句的措辭；黑圖保險與試打驗收再兜底一層。模板精神沿用 `2026-08-24-practice-moments-scene-image-prompts.md`。
- **隱私**：輸入鏈全程零使用者資料；新模組加 source test 禁 import 任何 turns/thread/memory 型別（比照 `moments_generated_only_source_test.ts`）。

---

## 6. DB schema 變更草案

基準：`supabase/migrations/20260822120000_practice_moment_posts.sql` 與 `20260824063344_practice_moment_reserve_usage_gate.sql`。**純加法**，一個 targeted migration：

```sql
ALTER TABLE practice_moment_posts
  ADD COLUMN image_status      TEXT NOT NULL DEFAULT 'none'
    CHECK (image_status IN ('none','pending','ready','failed','expired')),
  ADD COLUMN image_path        TEXT,
  ADD COLUMN image_attempts    SMALLINT NOT NULL DEFAULT 0 CHECK (image_attempts BETWEEN 0 AND 2),
  ADD COLUMN image_token       TEXT,
  ADD COLUMN image_reserved_at TIMESTAMPTZ,
  ADD CONSTRAINT practice_moment_image_ready_has_path
    CHECK (image_status <> 'ready' OR image_path IS NOT NULL);
CREATE INDEX practice_moment_posts_image_expiry_idx
  ON practice_moment_posts (post_date) WHERE image_status = 'ready';
```

**RPC 變更**：
- `reserve_practice_moment_slot` **不動**。
- `commit_practice_moment_post` 加 `p_wants_image BOOLEAN DEFAULT FALSE`（TRUE 時原子寫 `image_status='pending'`）。簽名變更沿用 `20260824063344` 的 overload 衛生範式（fail-closed 稽核 → DROP 舊版 → CREATE）；舊 Edge 以 named params 呼叫吃 DEFAULT，部署窗內雙向相容。
- `list_practice_moment_posts` 回傳表加 `image_status, image_path`（DROP+CREATE；舊 Edge 只讀已知欄位，多欄無害）。
- **新增三支 image RPC**，逐格鏡像 reserve/commit/release 的六態轉移表與 token fencing（含「attempts 明寫 +1 不靠 DEFAULT」「絕不 DELETE 列、絕不動 body、絕不回收 attempts」三鐵則）：
  - `claim_practice_moment_image(..., p_image_path)`：僅 `status='ready' AND image_status='pending'` 且（token IS NULL 或租約逾時）可認領；認領即 `image_attempts+1`、把即將寫入的 token 路徑**記進孤兒帳本**（`image_orphan_paths`），並**同交易** `increment_model_usage(user,'practice_moment_image',...)`（超限 RAISE → 整筆 rollback，帳本也一起回滾）；回傳含 `body, theme_id` 免二次讀。max_attempts DEFAULT 2、lease 固定 180s（`p_lease_seconds` 只接受這個值，見下方租約邊界）。`p_image_path` 由 `20260826024500` 加入（第四輪複審 P2-2）。
  - `commit_practice_moment_image(..., p_image_path)`：token 與**租約**雙重 fenced，寫 `image_status='ready'`，**同交易**把該路徑從孤兒帳本抹掉（被引用的物件永不可能被清算刪到）。
  - `release_practice_moment_image(...)`：attempts 到頂轉 `'failed'`（終態＝永久純文字），否則清 token 留 pending。
- **清理兩小支**：`list_expired_practice_moment_images(p_before DATE, p_limit INT)`（回 ready＋出窗的 path）與 `mark_practice_moment_images_expired(p_paths TEXT[])`。
- **孤兒帳本兩小支（`20260826024500`）**：`list_practice_moment_image_orphans(p_limit INT, p_grace_seconds INT)`（回寬限期之外、且不被自己列引用的路徑）與 `clear_practice_moment_image_orphans(p_paths TEXT[])`（只清帳本、不動任何生命週期欄位）。欄位是純加法的 `image_orphan_paths TEXT[] NOT NULL DEFAULT '{}'`（CHECK cardinality ≤ 4）。
- 權限照現行：REVOKE ALL → GRANT service_role only；檔尾 `NOTIFY pgrst, 'reload schema'`。

**重試語義**：文字 `attempts`（≤3）與 `image_attempts`（≤2）完全獨立——文字重試不燒圖額度，圖失敗不碰文字。圖上限 2 次：失敗多為內容政策或供應商故障，重試邊際價值低。

---

## 7. 儲存與傳遞

- **Bucket**：`practice-moment-images`，**public**。內容是無人物 AI 場景圖、全域共用、零使用者資料；signed URL 會讓 URL 每次變動打爆 client 磁碟快取、且過期時間要另外對齊 14 天窗，得不償失。bucket 與 `storage.objects` policy（anon 唯讀、寫入 service_role only）進同一支 migration（`INSERT INTO storage.buckets ... ON CONFLICT DO NOTHING`）。
- **物件 key（token 隔離，2026-08-25 第二輪複審 P1-1）**：`<post_date>/<profile_id>_<slot>_<image_token>.img`（副檔名**格式中性**：key 必須在 claim 的同一筆交易寫進孤兒帳本，早於下載，拿不到實際格式；格式的唯一真相放在 Storage 的 `content_type` metadata，public URL 照它出 header，瀏覽器與 `cached_network_image` 都以此解碼、不看副檔名）。每次認領寫**自己的**路徑、永不覆寫（upsert:false）——底層上傳收不到取消訊號，timeout 晚到的舊上傳在物理上碰不到 winner 的物件，也不可能在清理後重建 committed 物件；輸家（timeout 晚到完成、commit 被打回）**自刪**自己的物件——但自刪只是快路徑，**持久保證在孤兒帳本**（路徑在 claim 的同一筆交易就記下，見 §8），日期前綴對帳再兜一層。
- **Edge 不做影像處理**：fal 直出（尺寸由 `landscape_4_3` preset 決定），下載後**原格式**上傳。黑圖保險見 §9。**格式契約**：Seedream 4.5 沒有 `output_format`，格式是供應商的選擇而不是我們的參數，所以受理集合的定義是「我們能原樣存、client 能原樣解」而不是「文件 example 給的那一種」——**JPEG 與 PNG 皆收**，寫入 Storage 的 `contentType` 一律由 **magic bytes 推導**（header 是 CDN 說了算的字串，位元組才是我們真的存下去的東西；兩者不一致時以位元組為準，才能保證 public URL 出的 header 與物件內容相符）。2026-08-27 canary 實測：JPEG、2.1MB，比 schnell 時期的 jpeg 大但遠低於先前依 example 推估的 PNG 4–8MB。
- **API 回傳**：`MomentFeedPost` 加 `imageUrl: string | null`——僅 `image_status='ready'` 時由 `SUPABASE_URL`＋path 組出。`imageId` 欄位語義不變（自拍 sentinel 與 bundled fallback 續用）。
- **向前相容（已驗證）**：`practice_moment_post.dart` 的 fromJson 只讀已知鍵，未知鍵直接忽略；生成圖貼文的 `imageId` 為 null → 舊 client 走「null＝純文字」主路徑。零風險。

---

## 8. 過期刪除：機會式清理（lazy purge）

| 方案 | 判定 | 理由 |
| --- | --- | --- |
| pg_cron | 否 | 只能跑純 SQL；直接 DELETE `storage.objects` 會留 S3 實體孤兒；打 Storage API 需 pg_net（未啟用＝憑證面） |
| GitHub Actions schedule | 否 | repo 零先例；且 CI 無 service-role key，得為每日 job 新開憑證 |
| **feed handler 機會式** | **採用** | repo 已有同型先例（`20260703120000_opener_charge_idempotency.sql`「lazy purge：每次呼叫順手刪」）；量極小（~11 物件/天） |

做法：feed 回應送出後 waitUntil 內串三段，各自負責一種「物件不該再存在」，**三段共用同一條順序鐵則：先刪物件、後改 DB**（反過來會製造「DB 已忘記、物件還在」的孤兒；改 DB 失敗下輪重掃，Storage 刪除冪等）。列永不刪（D6），`image_path` 保留供審計與冪等重刪。

| 段 | 清什麼 | 流程 |
| --- | --- | --- |
| 主清掃 | **被引用但出窗**的圖 | `list_expired_practice_moment_images(今天-13, LIMIT 20)` → `storage.remove` → `mark_practice_moment_images_expired` |
| 帳本清算 | **寫過但沒人引用**的圖 | `list_practice_moment_image_orphans(LIMIT 20, 寬限 600s；DB 端夾住下限 ≥180s)` → `storage.remove` → `clear_practice_moment_image_orphans` |
| prefix 對帳 | 連帳本都沒有的殘留（帳本上線前的物件、人工上傳） | 找**最舊的出窗日期資料夾** → 分頁列出並刪除 |

穩態儲存 ≈ 14 天 × 11 張 × ~2.1MB ≈ **320MB**（依 2026-08-27 canary 實測的單張大小；換 Seedream 前的 schnell 時期是 ~23MB。先前依官方 example 推估的 ~900MB 是把 PNG example 當契約算出來的，實測後作廢）。零流量期的積壓有界，下次有人開 feed 分批消化。

**待辦（換模型後新增，實測後降級為「觀察」）**：單張 2.1MB 在手機端仍偏重（一屏數張就是十幾 MB），但已不是先前推估 4–8MB 那種必須立刻處理的量級。建議之後改用 Supabase Storage 的影像轉換端點（`/storage/v1/render/image/public/...?width=&quality=`）出圖——只需改 `storagePublicUrlBase` 一個地方，client 不用動；但那是付費方案功能，啟用前要先確認方案支援，否則圖會 400 變成純文字降級。先看 production 的 `practice_moment_image_committed` log 裡的實際 `bytes` 再決定。

**清理競態圍籬（2026-08-25 複審 blocking item 3，migration `20260825150000`；第三輪修訂）**：出窗判定的 cutoff **由 DB 自己以當下 `now()` 計算**（`(now() AT TIME ZONE INTERVAL '8 hours')::date - 13`，13 = `FEED_WINDOW_DAYS - 1`），claim／commit／release 三支各自內建，**不吃呼叫端傳入的日期**——早期版本的 `p_expiry_before` 參數已移除，因為 request 開始時算的日期跨過台北午夜就失效。於是：出窗的列在資料層永遠不可再認領（殘留的出窗 pending 順手收成 failed 終態）；慢 worker 的晚到 commit 即使 token 有效也被拒並收屍；跨午夜的失敗 release 直接收成 failed 而不是放回 pending。「list → 刪物件 → mark」窗口內，出窗列的 image 欄位組只有 mark 自己能動，「列被新生成取代、清理誤刪新圖」在構造上不可達；競態測試在 `moments_images_migration_postgres_test.ts` 逐向驗證。

**孤兒帳本：可持久重試的閉環（2026-08-26 第四輪複審 P2-2，migration `20260826024500`）**：上傳 timeout 的晚到自刪、commit 不確定態的保留物件，原本都只是 Edge 記憶體裡的 best effort——實例一被回收，那個 public 物件就沒有人記得它存在。現在把「我可能會寫這個物件」記進**同一筆 claim 交易**：

```
claim  → image_orphan_paths += <token 路徑>   （租約成立的同一交易）
commit → image_orphan_paths -= <token 路徑>   （成功的同一交易）
其餘一切結局（失敗、release、不確定態、實例被回收）→ 紀錄留著
```

於是「有物件但沒人引用」是**可查詢的資料狀態**，不再依賴任何 Edge 實例活著；清算每次 feed 請求跑一批，直到清乾淨為止。兩道守門讓它永遠安全：寬限期（Edge 傳 600s）之內的紀錄不列，列自己 `image_path` 指著的物件不列。這條閉環同時讓 commit 的不確定態有了正確歸宿——**不刪物件**（DB 可能其實已 commit，刪了會讓 ready 列指向 404 一整個窗期），帳本會在確認沒人引用之後才清掉它。

**租約與清算的邊界由資料層自己閉合（`807ebef`）**：只靠 Edge 常數「job 不可能活過 600s」是推論，不是保證。三個地方一起把它變成資料層不變式——claim 只接受 `p_lease_seconds = 180`（其他值一律 RAISE，不准有人偷偷延長租約）、commit 除了 token fencing 再加一道**租約 fencing**（`image_reserved_at <= now() - 180s` 一律回 FALSE，即使 token 還沒被輪替）、清算的寬限期以 `GREATEST(p_grace_seconds, 180)` 夾住下限。兩個邊界剛好互斥：**t = 180s 時 commit 已被拒、清算還沒開始列**（commit 用 `<=`、清算用 `<`），因此不存在「worker 仍可 commit、清算卻已可刪圖」的窗口，也就不可能出現 ready 列指向已被回收的物件。commit 內的順序也被釘住：**出窗收屍必須早於租約 RETURN**，否則同時出窗又逾期的列會提早返回、永遠留在 pending。

**prefix 對帳兜底改成不遺漏（同上）**：舊版依 UTC 小時在固定 3 天帶內輪替一個 prefix，有兩個漏法——feed 零流量超過該帶，殘留就永遠滑出掃描範圍；單一 prefix 超過 Storage list 的 100 筆上限也永遠掃不完。現在改成**掃描目標由 bucket 自己說了算**：list 根目錄拿到還存在的日期資料夾，取其中最舊的出窗日期，分頁排空（每次請求上限 4 頁 × 100 筆，沒清完下次接著清；已刪的不會再出現在列表裡）。資料夾清空即從列表消失，所以停機一個月回來仍掃得到。窗內日期永不觸碰（`name < 窗起點` 才是候選），這是刪錯圖的最後一道守門。

---

## 9. 安全與品質邊界

- **無人物／無文字／無品牌**：STYLE＋NEGATIVE 模板硬約束（沿用已驗收字面）＋fal `enable_safety_checker: true`。FLUX 無 Imagen 的 `person_generation` 硬參數——殘餘風險由 prompt 約束與試打驗收吸收。
- **內容安全：2026-08-26 換 Seedream 4.5 時的明確降級**。舊版（FLUX schnell）回應帶 `has_nsfw_concepts` 逐張布林，做得到「只有明確回報 `false` 才繼續，其餘一律不下載、不上傳、不 commit」的 fail-closed。**Seedream 4.5 的 output schema 只有 `images` 與 `seed`，沒有任何 NSFW 欄位**（fal 官方 OpenAPI 查證），那道逐張判定在這個模型上不存在。現行三層是：
  1. **平台端 safety checker**：請求固定帶 `enable_safety_checker: true`（schema 預設即 true，關閉需帳號授權）。**保證邊界要說清楚**：官方只保證這個檢查可以被啟用，**未規定命中時的回應形狀**（HTTP error／空 images／其他皆有可能），因此程式不依賴任何特定失敗形狀——各種回應分別由既有路徑收斂（`fal_image_http_*`／`fal_image_empty`／格式與大小守門）。**不可宣稱「不合格的圖絕不會到我們手上」。**
  2. **輸入端硬約束**：STYLE 前綴明文禁人物／禁可讀文字／禁品牌，場景句另經 `validateSceneLine`（禁詞、ASCII、長度）。
  3. **黑圖保險**：bytes < 10KB 視為失敗。
  代價：少了逐張的供應商判定訊號，也少了 `fal_image_nsfw`／`fal_image_safety_unverified` 兩個觀測點，且剩下三層都不是逐張的內容判定。換回有逐張判定的模型時，把 fail-closed 那段加回來即可。
- **下載／上傳完整邊界（blocking item 2；第三輪同步）**：結果 URL 必須是 https，且 host 屬 `fal.media`／其子網域，**或**精確等於 `storage.googleapis.com` 且路徑以 `/falserverless/` 開頭（fal 官方 output 範例就是後者；只放行「精確 host ＋ 該 bucket 路徑前綴」，不是任意 GCS 物件、更不是任意外部 URL）；兩個 fetch 均 `redirect: "error"`＋response.url 最終 host 縱深驗證；timeout 計時器涵蓋**完整 response body**（懸掛的 JSON 與圖片串流都會被 abort）；Content-Type 必須落在**受理集合**（`image/jpeg`／`image/png`）——這道 header 守門擋的是「根本不是圖」的回應（HTML 錯誤頁、JSON），在讀 body 之前就早退、省掉最多 12MB 流量；**真正決定寫入格式的是 magic bytes**（JPEG `FF D8 FF`／PNG `89 50 4E 47 0D 0A 1A 0A`），認不得就 `fal_image_bad_magic` 拒收，認得就以位元組推導出來的型別作為上傳 `contentType`；大小硬上限兩層——Content-Length 預檢＋流式累計硬擋（上限 12MB，對實測 2.1MB 有 ~5.7 倍餘裕）；上傳獨立 timeout（底層不可取消，安全性由 token 隔離路徑＋輸家自刪＋出窗 prefix 孤兒對帳保證）。任何異常回應都不落入記憶體、不拖 Edge。
- **自拍貼文維持圖鑑照片，不生成**：人臉一致性做不到＋原設計 §7.4「不得生成像真實人物的新圖」（App Review 肖像風險）。候選收斂後只剩 `moment_self_portrait` 的 slot 不進生圖分支。
- **Kill switch**：`MOMENT_IMAGE_GEN_ENABLED`（getEnv 閘門，照 `PRACTICE_HINT_PREFETCH_ENABLED` 範式，handler.ts:2142）。**關閉或缺 `FAL_API_KEY` 時退回現行 20 張 bundled 素材路徑**——bundled 路徑已上線已驗收，保住「兩種貼文型態」；因此 20 張素材長期保留，`test/lint/moments_scene_asset_parity_test.dart` 三方對帳一行不用改。
- **timeout < lease**：fal 呼叫 60s＋下載 15s＋上傳 15s＋場景句 10s ＝ 最壞 100s ≪ image lease 180s；而且這不只是「算得剛好」——超過 180s 的 commit 在資料層直接被拒（§8 租約邊界）。上傳競態不再倚賴機率——token 隔離路徑讓「同時上傳」寫的是不同物件，晚到者自刪（§7）。
- **provenance**：`docs/licenses/` 補一條 runtime 生成聲明（模型 Seedream 4.5（ByteDance，經 fal 託管）、prompt 來源文件、無人物無品牌約束；商用授權依 fal 託管條款與 ByteDance 模型條款，換模型時需一併覆核）。

---

## 10. Client 變更

- **套件**：`cached_network_image`（磁碟快取必要——D7 每次進頁重抓 feed，無快取＝每次重載全部圖）。
- **entity**：`PracticeMomentPost` 加可選 `imageUrl`；`MomentImageSource` sealed class 加第三個 variant：

```dart
class MomentRemoteImage extends MomentImageSource {
  const MomentRemoteImage(this.url);
  final String url;
}
```

  解析優先序：`imageUrl` 非空 → `MomentRemoteImage`；否則現行 `resolveMomentImage(imageId)`。防禦性檢查 URL host 必須是本 app 的 Supabase host。
- **tile**：`_buildImage` switch 加 case——`CachedNetworkImage(fit: cover, placeholder: 4:3 圓角素色塊, errorWidget: SizedBox.shrink())`。占位只在 imageUrl 存在時保留 4:3 空間（防 layout shift）；API 只在 ready 時給 URL，**client 永遠不會等一張可能不來的圖**。errorWidget 降級純文字＝現行鐵則照抄。
- 舊版 App（無此欄位解析）自動純文字，四象限（新舊 client × 新舊 Edge）全相容。

---

## 11. 成本模型與觀測

- **量**：census 實測（`tools/moments-image-census/census.ts`）全名冊 100 位、配圖率 0.2 → **~11 張/天、~330 張/月**；含 10% 重試 ~370 張/月。與使用者數無關（貼文全域共用）。
- **錢（第三輪複審修正：期望量、真硬上限、成長軸分開寫）**：
  - **期望平均量（估算，非任何保證）**：`IMAGE_PROBABILITY = 0.2` 的機率擲骰下，排程模擬 ~11 張/天 → Seedream 4.5 $0.04/張 ≈ **~$13/月**（schnell 時期是 ~$0.9/月）。機率值只是 scheduler 參數，**不是 DB constraint，不構成任何硬上限**。
  - **系統真正強制的（第四輪複審修正：固定契約其實有上界）**：每個 post_date 的 provider attempts 上界是 **100 角色 × 每日 2 slots × 每 slot 2 attempts ＝ 400 次**（100 來自 Edge 角色 allowlist，2 slots 與 2 attempts 各由 SQL CHECK 保證）≈ **$16／post_date**（$0.04 × 400；schnell 時期是 $0.96）。`IMAGE_PROBABILITY = 0.2` 只影響期望量，**不影響這個上界**。此外有 per-user scope 3/min、20/day（單帳號放大面 backstop）。
  - **wall-clock 的但書**：文字補生成只會補**今天**的 slot，所以「新產生的列」每個 wall-clock 日同樣受 400 次上界；但**先前 post_date 沒生成完的 pending 列，會在之後的請求被接手**（backlog 可能集中在某一天執行），因此單一 wall-clock 日的實際花費可以是數個 post_date 的殘量相加，最壞界是窗內 14 個 post_date 的剩餘 attempts 總和（$0.04 單價下是 $200 量級的絕對天花板，非預期值——**fal spend cap 因此從「建議」升格為必要**）。
  - **沒有全站原子 daily cap**：上面的 400 是「固定參數下的算術上界」，不是資料層的原子計數器——沒有任何機制在達到它時停止呼叫。會改變這個上界的只有 allowlist 大小、每日 slots 與 attempts 上限三者；`IMAGE_PROBABILITY` 只影響平均產生幾張，**不動上界**。
  - **成長軸**：貼文與圖全域共用，全站量**不隨使用者數成長**。放大**上界**的只有角色 allowlist 大小（現 100）；放大**期望量**的是 `IMAGE_PROBABILITY`（現 0.2）。兩者的改動都屬 Eric 拍板項。
  - **需要真正的「達標即停」時**：加全站原子 daily cap RPC（新 migration），或在 fal.ai Dashboard 設 **spend cap** 當供應商側絕對托底——**建議啟用時順手設**，它是唯一與程式錯誤、參數誤調都無關的托底。
  - 另每張一次 DeepSeek 場景句（~300 tokens，可忽略）；Storage 穩態 ~320MB（實測單張 2.1MB）＋egress 按觀看數（client 磁碟快取壓低；見 §8 的影像轉換待辦）。
- **四層防護（皆為風險緩解，非全站配額）**：DB CHECK（image_attempts ≤2，per-slot）× Edge 100 角色 allowlist × per-user scope `practice_moment_image: { perMinute: 3, perDay: 20 }` × kill switch。與文字路徑的差別在**種類而非有無**：文字的「全站 ≤600 次/日」與生圖的「每 post_date ≤400 次」都是同一種算術上界（allowlist × slots × attempts），兩者都不是資料層的原子每日配額；生圖側多一層機率擲骰，只讓期望值遠低於上界。真正的「達標即停」只有 fal Dashboard 的 spend cap。
- **觀測**（logInfo/logWarn）：`practice_moment_image_claimed / committed / released / failed`（帶 failureClass: provider_timeout / safety_black / upload / describe / http_${status}）、`practice_moment_image_expired_swept`（deleted/marked 數）；`practice_moments_filled` 加 `imageJobsScheduled`。健康線：`failed` 佔圖文 slot > 10% 告警（比照文字路徑 exhausted > 5% 慣例）。
- **錯誤分類命名**：照 `deepseek.ts` 模板——`fal_image_http_${status}` / `fal_image_timeout` / `fal_image_empty` / `fal_image_download_failed` / `fal_image_too_small`（黑圖保險）；provider response body 不進錯誤訊息。

---

## 12. 分期交付（一 PR 一目的，全部可獨立測試回退）

| PR | 內容 | migration | 回退面 |
| --- | --- | --- | --- |
| **PR-1** | 本設計文件 | 否 | — |
| **PR-2** | migration：image 欄位組＋bucket＋5 支新 RPC＋commit/list 改簽名；PGlite 契約測試（照 `moments_migration_postgres_test.ts` 逐格驗轉移表）＋`moments_constants.ts` 新常數雙向比對 | **是**（targeted migration；**production 套用先於 PR-3 部署**；套用後在 `docs/migrations-ledger.md` 只登記**本次**這幾支——不順修其他未登記條目，那屬另一個目的） | Edge 未寫 pending，行為零變化 |
| **PR-3** | Edge 生成路徑（旗標預設關）：`moments_image_gen.ts`（fal client＋prompt 組裝＋場景句呼叫＋黑圖保險）、Storage 上傳、waitUntil 接線＋接手、rate-limit scope、kill switch、logs；deno 測試（mock fetch）＋新 source test（隱私 import 禁令） | 否 | 關旗標＝現行行為 |
| **PR-4** | Edge 機會式過期清理＋測試 | 否 | 不做只是物件多留幾天 |
| **PR-5** | Client：`cached_network_image`、`imageUrl` 解析、`MomentRemoteImage`、tile 渲染＋占位＋降級、widget 測試 | 否 | imageUrl 恆 null 時畫面零變化 |
| **PR-6** | 第四輪複審修正：孤兒帳本 migration `20260826024500`（claim 改簽名記帳、commit 抹帳、清算兩支新 RPC）＋commit 三態收嚴（只在明確 `false` 才刪物件）＋清掃改三段、prefix 對帳改最舊資料夾分頁掃＋`shiftIsoDate` 抽成 `moments_date.ts` 解循環依賴 | **是**（**新增**的後續 migration；既有 0825 兩支一旦套用過即不可變，因此改簽名走新檔案的 DROP + CREATE 並前後各稽核一次 overload） | 旗標關閉時零行為變化；帳本欄位純加法 |
| **啟用** | Eric：fal.ai 開帳號綁卡 → `supabase secrets set FAL_API_KEY=...` → `MOMENT_IMAGE_GEN_ENABLED=true`（ops 動作，非 PR） | — | 隨時關回 |

**Rollout 順序（Eric 2026-08-25 拍板：migration 先行）**：正式啟用的順序是——(1) 依 `docs/shared-agent-rules.md` 的 targeted migration 流程**先**依序精準套用並驗證 `20260825120000` → `20260825150000` → `20260826024500`（用分支上的檔案即可，不需等合併；三支有先後相依，最後一支會 DROP 掉舊的 10-arg claim 並建立 11-arg 版本）→ (2) 再合併 PR 讓相依 Edge 進 main 自動部署 → (3) 最後設 `MOMENT_IMAGE_GEN_ENABLED=true`。Edge 端的部署窗相容（省略 `p_wants_image` 鍵）只是防呆保險，不是亂序的授權。`practice-chat` 部署照現行 push-triggered workflow，無 `--no-verify-jwt` 需求變化。

---

## 13. 風險清單

1. **waitUntil 任務蒸發**（實例回收）→ pending 卡住。緩解：180s 租約接手自癒；觀測 pending 列齡。
2. **fal 故障／safety 拒絕** → attempts 燒完轉 `'failed'` 純文字，無半成品落盤；failed 比例告警。
3. **成本失控** → 四層緩解（§11）；固定參數下每 post_date ≤400 次 provider attempts，但**沒有達標即停的機制**，絕對托底建議用 fal Dashboard spend cap。
4. **上傳競態** → token 隔離路徑（`<post_date>/<profile>_<slot>_<token>.img`）＋`upsert: false` **永不覆寫**＋輸家自刪：晚到上傳構造上碰不到 winner 物件。
5. **孤兒物件** → 路徑在 claim 的同一筆交易記進帳本，清算是可持久重試的閉環（§8）；帳本之外的殘留由「最舊出窗資料夾分頁排空」兜底，兩者都不依賴任何 Edge 實例活著。
6. **質感不過驗收** → fal 同站換 model id 即可，架構不動（2026-08-26 已實際走過一次：schnell → Seedream 4.5）。但**不是只換一個字串**：safety 欄位、尺寸參數、輸出格式三個 schema 接點都要跟著改，漏一個的失敗樣態是「一張圖都生不出來」。成本表與儲存估算一併重算。
7. **隱私回歸** → source test 禁 import 使用者資料型別，防後人把聊天內容餵進場景句。
8. **弱網** → remote 圖載不出走 errorWidget 純文字；kill switch 下 bundled 路徑離線可用。

---

## 14. 已定案與尚待拍板

**已定案**：供應商 fal.ai（Eric，2026-08-25）；模型 **Seedream 4.5**（Eric，2026-08-26，看過首批真機圖後從 FLUX schnell 換出）；架構照本文件。

**尚待 Eric 拍板（實作前確認即可）**：
1. 生圖徹底失敗（attempts 燒完）那則：純文字終態【本文件推薦】vs 退用 bundled 圖
2. kill switch 退回 bundled（=20 張長期保留、0.9MB 不回收）【本文件推薦】的確認
3. `IMAGE_PROBABILITY` 維持 0.2 或上調（**期望**成本線性，算術上界不變）
4. fal.ai 帳號開通與 `FAL_API_KEY` 設定時點（PR-3 合併前不需要）
5. 試打驗收：playground 生 10–20 張打 2026-08-24 規格書 §6 清單，過了才開旗標

## 15. 驗收方式

- **PR-2**：PGlite 測試逐格驗 image RPC 六態轉移；constants 雙向比對綠。
- **PR-3**：deno 測試 mock fal（成功／timeout／黑圖／下載失敗／fencing 打回）；關旗標時零行為變化的回歸測試。
- **PR-5**：widget 測試三態（remote 成功／載入中占位／錯誤降級純文字）。
- **端到端（Eric 真機）**：開旗標後進「她們的動態」→ 新圖文貼文首次純文字、重進頁面出圖；圖與文字內容相符；14 天前的舊貼文無圖；關旗標回 bundled 素材。

## 16. 參考來源

- fal.ai Seedream 4.5 text-to-image API 文件（端點、`image_size`、safety checker、輸出 schema）：https://fal.ai/models/fal-ai/bytedance/seedream/v4.5/text-to-image/api
- fal.ai FLUX schnell API 文件（2026-08-26 前的模型）：https://fal.ai/models/fal-ai/flux/schnell/api
- fal.ai 定價（$0.003/MP）：https://fal.ai/pricing 、聚合站交叉比對 https://pricepertoken.com/fal-ai-pricing
- Supabase Edge 背景任務（waitUntil、wall clock 150s/400s）：https://supabase.com/docs/guides/functions/background-tasks
- 供應商比較過程（gpt-image-1-mini $0.005、Imagen 4 Fast $0.02、Qwen 3.0 Pro ~$0.075）：本 session 網查，聚合站數字，正式採用前以官方頁為準
- 既有素材規格書（STYLE/NEGATIVE 模板與驗收清單）：`docs/plans/2026-08-24-practice-moments-scene-image-prompts.md`
- 撞圖研究（本案起點）：`docs/plans/2026-08-25-practice-moments-image-duplication.md`
