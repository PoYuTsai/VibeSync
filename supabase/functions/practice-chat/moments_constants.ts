// 練習室模擬社群動態的共用常數（零依賴，生成端與資料層契約的單一真相源）。
//
// 這裡的每一個數字都有對應的守門：
// - 與 migration SQL 對得起來的（attempts / slot / body / lease / allowlist 大小）
//   由 moments_constants_test.ts 做**雙向**比對，任何一邊漂移都會紅。
// - 純 Edge 側的（死線、每次補幾則、feed 天數、模型參數）由該測試的內部
//   一致性斷言與 moments_handler_test.ts 釘住。
//
// 為什麼獨立成一支而不是放在 moments_handler.ts：migration source test 要
// import 它做雙向比對，而那支測試不該把整個 handler（連帶 supabase client
// 型別、DeepSeek）拉進來。

// ── 與 migration SQL 對齊（雙向比對）─────────────────────────────────

/** 每個 (profile_id, post_date, slot) 最多幾次模型呼叫。SQL: CHECK (attempts BETWEEN 0 AND 3)。 */
export const MAX_MOMENT_ATTEMPTS = 3;

/** 一天最多幾則。SQL: CHECK (slot BETWEEN 0 AND 1)，即 MOMENT_SLOT_COUNT - 1。 */
export const MOMENT_SLOT_COUNT = 2;

/** reserve 租約長度。SQL: p_lease_seconds INTEGER DEFAULT 120。 */
export const MOMENT_RESERVE_LEASE_MS = 120_000;

/** DB 的 body 長度上界（縱深防禦，不是產品規格）。SQL: char_length(body) BETWEEN 1 AND 220。 */
export const MOMENT_BODY_DB_MAX_CHARS = 220;

/**
 * 角色 allowlist 大小，同時是 list RPC 的 p_profile_ids 上限。
 *
 * 「全站每日最多 600 次模型呼叫」＝ 100 位角色 × 2 slot × 3 attempts。
 * DB 只保證後面兩項；前面那個 100 是 Edge 的責任（profile_id 只能來自
 * GIRL_PROFILES），所以這個數字必須同時等於 SQL 內的 100 與 Edge 名冊大小。
 */
export const MOMENT_PROFILE_ALLOWLIST_MAX = 100;

// ── 產品長度守門（三層的中間那層）───────────────────────────────────

/** prompt 給模型的字數指示下界。 */
export const MOMENT_PROMPT_MIN_CHARS = 20;
/** prompt 給模型的字數指示上界。 */
export const MOMENT_PROMPT_MAX_CHARS = 60;

/**
 * 真正的產品守門：18-66 字（prompt 指示 20-60 的 ±10% 容差）。
 *
 * 留容差是因為打回一則就吃掉一次 attempts，為了 61 字丟掉一則好貼文不划算。
 * 若上線後打回率偏高，要調的是 prompt 的引導方式，不是偷偷放寬這裡。
 */
export const MOMENT_BODY_MIN_CHARS = 18;
export const MOMENT_BODY_MAX_CHARS = 66;

// ── Edge 側的補生成預算 ─────────────────────────────────────────────

/** 進 handler 起算的總死線；到點就不等，未完成的列留給租約與下次請求。 */
export const MOMENT_FILL_DEADLINE_MS = 8_000;

/** 單一請求最多補幾則（K）。 */
export const MOMENT_FILL_MAX_PER_REQUEST = 3;

/** feed 往回看幾天（D6：feed 14 天、DB 永久保留）。 */
export const FEED_WINDOW_DAYS = 14;

/**
 * 已抽卡帳號的 feed 最新可見貼文最長可沉寂多久。
 *
 * 每位角色仍保留安靜日；這是整個 feed 的懶生成保底，不是把 100 位角色
 * 全改成每天發文。保底仍走既有每日兩格、每格三次 attempts 與每請求 K 則上限。
 */
export const MOMENT_FEED_FRESHNESS_MAX_AGE_MS = 24 * 60 * 60 * 1000;

// ── DeepSeek 呼叫參數（設計報告 §5）─────────────────────────────────

/** 貼文 20-60 字，比照 CHAT_MAX_TOKENS。 */
export const MOMENT_MODEL_MAX_TOKENS = 200;
/** 略高於聊天的 0.9：100 位角色要看得出差異。 */
export const MOMENT_MODEL_TEMPERATURE = 0.95;
/** 低於 chat 的 30s：背景補位不該拖住 feed。 */
export const MOMENT_MODEL_TIMEOUT_MS = 20_000;

// ── 生成配圖（與 20260825120000_practice_moment_images.sql 對齊，雙向比對）──
//
// 圖與文字的計數完全獨立：MAX_MOMENT_ATTEMPTS 管文字、這裡管圖。
// 雙向契約在 moments_images_migration_source_test.ts（照 moments_constants_test.ts
// 的做法讀 migration 原文剖數字）。

/** 每個圖文 slot 最多幾次生圖呼叫。SQL: CHECK (image_attempts BETWEEN 0 AND 2)。 */
export const MAX_MOMENT_IMAGE_ATTEMPTS = 2;

/**
 * 生圖 job 租約。SQL: p_lease_seconds INTEGER DEFAULT 180。
 * 必須遠大於「fal 呼叫 60s＋下載＋上傳」的總預算，stale worker 與新 worker
 * 同時上傳的競態才幾乎不可達（設計文件 §9）。
 */
export const MOMENT_IMAGE_RESERVE_LEASE_MS = 180_000;

/** Storage 物件 key 的 DB 長度上界（縱深防禦）。SQL: char_length(image_path) ≤ 200。 */
export const MOMENT_IMAGE_PATH_DB_MAX_CHARS = 200;

/**
 * 機會式清掃單次上限（Edge 端傳給 list_expired 的 p_limit）。
 * 必須 ≤ SQL 側的 p_limit 硬上界 100；20 足以在一天內消化 ~11 張/天的積壓。
 */
export const MOMENT_IMAGE_SWEEP_LIMIT = 20;

// ── 生圖呼叫參數（PR-3 Edge 端；與 DB 無對應，釘在 moments_image_gen_test）──

/** 單一請求最多排幾個生圖背景 job（新 commit 與 pending 接手合計）。 */
export const MOMENT_IMAGE_FILL_MAX_PER_REQUEST = 2;

/**
 * fal.ai 同步端點的 HTTP timeout。
 *
 * Seedream 4.5 是完整模型（非 FLUX schnell 那種 4 步蒸餾），單張耗時是
 * 十幾秒量級而不是一兩秒，30s 會偶爾誤判成 timeout 並燒掉一次 attempt。
 * 60s 之下最壞預算鏈是 場景句 10s＋fal 60s＋下載 15s＋上傳 15s ＝ 100s，
 * 仍遠低於 180s 租約與 DB 端在 180s 的 commit 硬擋。
 */
export const MOMENT_IMAGE_MODEL_TIMEOUT_MS = 60_000;

/** 生成結果（provider CDN URL）的下載 timeout。 */
export const MOMENT_IMAGE_DOWNLOAD_TIMEOUT_MS = 15_000;

/** 場景句 DeepSeek 呼叫的 timeout；失敗退題材模板句，不重試。 */
export const MOMENT_IMAGE_SCENE_TIMEOUT_MS = 10_000;

/**
 * 黑圖保險：不安全或崩掉的生成常是一張近乎單色的圖，無損 PNG 壓縮後
 * 遠小於正常場景圖。低於此值視為生成失敗（fal_image_too_small）。
 */
export const MOMENT_IMAGE_MIN_BYTES = 10_000;

/**
 * 異常大檔上界。Seedream 4.5 只出 **PNG（無損）**，官方範例的
 * file_size 就是 4.4MB，1920×1440 的實景圖落在 4-8MB 很正常，
 * 舊的 4MB 上限會把正常的圖當成異常擋掉。12MB 留足餘裕，同時仍能擋住
 * 「回了一個完全不該是圖」的異常回應（整張都要進記憶體，不能無上限）。
 */
export const MOMENT_IMAGE_MAX_BYTES = 12_000_000;

/**
 * 生成尺寸：官方 enum preset。
 *
 * Seedream 4.5 的 custom size 規則是「兩軸皆在 1920-4096」**或**「總像素
 * 落在 2560×1440 到 4096×4096」。先前自訂的 1920×1440 兩條都不滿足
 * （高度低於 1920、總像素 2.76MP 低於 3.69MP 下限），會被供應商打回
 * ——這是第一輪複審抓到的 P1。改用 enum：由 fal 自己映射到該模型的合法
 * 尺寸，構造上不可能違規；代價是實際像素數未公開，所以檔案大小要靠
 * MOMENT_IMAGE_MAX_BYTES 與 production log 的實測值來把關。
 */
export const MOMENT_IMAGE_SIZE_PRESET = "landscape_4_3";

/**
 * 可接受的生成圖格式表：content type → magic bytes。
 *
 * FLUX 時代我們送 `output_format: "jpeg"`，格式是**我們指定的**，單一格式
 * 的守門因此是正確的。Seedream 4.5 沒有 output_format 參數——格式由供應商
 * 決定，而官方 schema 只給了一張 `.png` 的 example。把 example 當契約寫死
 * 是這裡踩過的坑：canary 實測回的是 `.jpg`（2026-08-27，v3b.fal.media，
 * 2.1MB），只收 PNG 會讓每一張真圖都被自己的守門擋掉。
 *
 * 所以受理集合的定義是「我們能原樣存、client 能原樣解的格式」，而不是
 * 「文件說會回的格式」——供應商換編碼器不該讓功能整個停擺。寫入 Storage
 * 的 contentType 一律由 magic bytes 推導（見 sniffImageContentType）：
 * header 可謊，位元組不會。
 */
export const MOMENT_IMAGE_ACCEPTED_FORMATS = [
  { contentType: "image/jpeg", magic: [0xFF, 0xD8, 0xFF] },
  {
    contentType: "image/png",
    magic: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
  },
] as const;

/**
 * 物件 key 的副檔名：**刻意保持格式中性**。
 *
 * key 必須在 claim 的同一個交易就寫進 orphan 帳本（早於下載），所以副檔名
 * 在「知道實際格式」之前就已經固定，物理上不可能跟著回應變。與其寫死
 * `.png` 讓 JPEG 物件掛著騙人的副檔名，不如中性到底：格式的唯一真相放在
 * Storage 的 content_type metadata，public URL 照它出 header，瀏覽器與
 * cached_network_image 都以此解碼，不看副檔名。
 */
export const MOMENT_IMAGE_EXTENSION = "img";

/** Storage bucket 名，與 migration 的 storage.buckets 列一致。 */
export const MOMENT_IMAGE_BUCKET = "practice-moment-images";

/** Storage 上傳 timeout；與下載、fal 呼叫合計必須遠小於 180s 租約。 */
export const MOMENT_IMAGE_UPLOAD_TIMEOUT_MS = 15_000;

/**
 * 孤兒帳本單次清算上限（Edge 端傳給 list_practice_moment_image_orphans）。
 * 與主清掃同量級：~11 張/天的失敗殘留，一輪 20 筆綽綽有餘。
 */
export const MOMENT_IMAGE_ORPHAN_LEDGER_LIMIT = 20;

/**
 * 孤兒帳本的寬限秒數（SQL: p_grace_seconds DEFAULT 600）。
 *
 * 帳本在 claim 的同一筆交易裡記下「這個 token 路徑可能會有物件」，commit
 * 成功的同一筆交易再把它抹掉。清算只處理**寬限期之外**的紀錄——寬限期
 * 必須遠大於一個 job 的最壞 wall clock（場景 10s＋fal 60s＋下載 15s＋
 * 上傳 15s ＝ 100s，且租約只有 180s），在跑的 job 才不可能被自己的清算刪掉。
 */
export const MOMENT_IMAGE_ORPHAN_GRACE_SECONDS = 600;

/** Storage list 單頁筆數（Supabase 端上限 100）。 */
export const MOMENT_IMAGE_LIST_PAGE_SIZE = 100;

/** 單次請求最多排掉幾頁孤兒物件（100 × 4 = 400 個／請求，足夠追上積壓）。 */
export const MOMENT_IMAGE_ORPHAN_MAX_PAGES = 4;

/** 單次請求最多翻幾頁 bucket 根目錄找最舊的出窗日期 prefix。 */
export const MOMENT_IMAGE_PREFIX_MAX_PAGES = 2;
