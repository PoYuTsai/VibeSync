# 練習室動態：配圖重複問題的成因與解法研究

2026-08-25。研究文件，**不含程式變更**；落地方案待 Eric 拍板。

**現象**：`她們的動態` feed 裡，不同角色的貼文反覆出現**同一張**配圖。真機截圖可見同一張炒鍋照出現在 Vivian（「下班隨便弄了碗麵」）、Roxy（「傍晚隨便弄了點吃的」）、Monica（「吃到一盤對味的家常菜」）三則；同一張咖啡杯照出現在 Ariel、Talia 兩則。十幾則貼文裡就撞了兩組。

---

## 1. 一張圖是怎麼被決定的

```
moments_schedule.momentPlanFor()
  └─ 依 theme.imageTags 取候選 → momentImagesForTags()      ← 候選清單（宣告序）
  └─ 擲 IMAGE_PROBABILITY = 0.2 決定 wantsImage
moments_handler
  └─ resolveAvailableMomentImages()                          ← 濾成真的有素材的 id
  └─ buildMomentMessages() 把整包候選丟進 prompt
       「從 momentImageOptions 裡挑一個最貼題材的 id 填進 imageId」
DeepSeek                                                     ← ★ 真正挑圖的是模型
  └─ validateMomentDraft() 只驗「有沒有在候選內」，不管挑了哪張
  └─ 寫進 practice_moment_posts.image_id（全域共用，一次寫定）
client resolveMomentImage(id) → assets/images/practice_moments/<id>.webp
```

關鍵在 **★**：**挑哪一張圖，全鏈路唯一的決定者是模型，而且沒有任何一段程式知道別則貼文用了什麼。**

---

## 2. 四個獨立成因

### A. 素材池只有 20 張，而且一個 id 只有一個檔案

`AVAILABLE_MOMENT_IMAGE_IDS` = 20 張場景圖 + 1 個自拍 sentinel。自拍會因角色而異，場景圖不會——**兩則貼文只要落到同一個 id，畫面就是像素級一模一樣的同一張照片**。

feed 窗是 14 天（`FEED_WINDOW_DAYS`），配圖率約 17%（實測 1975 slot / 334 有圖）。解鎖 50 位角色時，14 天窗內約有 69 則圖文貼文要分配到 21 個 id——**就算完全均勻分配，平均每張圖也要被用 3.3 次**。生日悖論下，同屏撞圖是必然，不是機率問題。

### B. 候選清單本身高度集中

主題池 42 個題材的 `imageTags` 分佈極不平均。30 天全站模擬，各 id 出現在候選清單的次數：

| 次數 | id | | 次數 | id |
| --- | --- | --- | --- | --- |
| 164 | `moment_dessert_plate` | | 39 | `moment_live_stage` |
| 113 | `moment_late_night_snack` | | 39 | `moment_dog_walk` |
| 113 | `moment_home_cooking` | | 38 | `moment_cat_nap` |
| 96 | `moment_coffee_cup` | | 38 | `moment_flower_bunch` |
| 94 | `moment_sunset_sky` | | 36 | `moment_exhibition_wall` |
| 73 | `moment_street_night` | | 19 | `moment_desk_work` |
| 68 | `moment_rainy_window` | | 15 | `moment_self_portrait` |
| 63 | `moment_cafe_corner` | | 11 | `moment_mountain_trail` |
| 43 | `moment_yoga_mat` | | 9 | `moment_train_window` |
| 42 | `moment_bookshelf` | | 8 | `moment_gym_corner` |
| | | | 5 | `moment_sea_view` |

`moment_dessert_plate` 在 **49%** 的圖文 slot 裡是候選之一；`moment_sea_view` 只有 1.5%。吃的（food / dessert / cooking）與咖啡的標籤幾乎黏在每一個生活題材上，海景與健身房則幾乎進不了池。

### C. 挑圖交給模型，而且沒有種子——語意最明顯的那張被反覆挑中

這是把 A 與 B 從「偶爾撞」放大成「一直撞」的主因。模型被要求「挑一個**最貼題材**的 id」，於是每一次都收斂到最典型的那個對應：

- 講煮飯／弄麵／家常菜 → 一律 `moment_home_cooking`
- 講咖啡 → 一律 `moment_coffee_cup`

三個不同角色寫三段不同的文字，只要題材同屬「吃的」，就會拿到同一張照片。**截圖裡的兩組重複正是這個機制的直接產物。**

值得記一筆的是，`moments_image_catalog.ts` 對 `momentImagesForTags` 的註解寫著：

> 回傳順序固定（依 MOMENT_IMAGES 宣告序），**呼叫端再用種子挑**，才能保證「同一天同一角色永遠得到同一張圖」。

**但沒有任何呼叫端用種子挑。** `momentPlanFor` 把整包候選原封不動傳給 handler，handler 原封不動塞進 prompt。設計意圖與實作在這裡是斷的——排程層每一個決策（發不發、幾點發、什麼題材、要不要配圖）都用 `fnv1a` 種子，唯獨「挑哪張圖」漏掉了。

以「模型挑候選第一個」近似此行為模擬（解鎖 50 位・14 天）：

```
有圖貼文 69 則，只用到 10 張不同的圖
  25 則（36%）moment_dessert_plate
  18 則（26%）moment_coffee_cup
   8 則（12%）moment_street_night
   ...其餘 7 張合計 18 則
同一天內同一張圖出現 ≥2 次：16 組；單日最高重複 4 次
```

> 註：「挑第一個」是行為近似，模型實際是依語意挑，所以榜首是哪一張會不同（真機上是 `home_cooking` 而非 `dessert_plate`）。但**分佈塌縮成少數幾張**這件事，模擬與截圖一致。

### D. 全鏈路沒有任何跨貼文的去重意識

每個 slot 是獨立生成的（這是刻意的：純函式、可重試、不產生第二則不同內容）。代價是**生成時看不到別人**：沒有「今天已經有人用過這張了」這個概念。Client 的 feed 渲染同樣不做任何去重。所以 feed 是把 N 位角色的貼文按時間合流成一條——**撞圖不但會發生，還會被時間排序推到彼此隔壁**。

---

## 3. 量化：各解法在 feed 上的實際效果

模擬 14 天 feed，計算「相鄰 4 則有圖貼文內出現同一張圖」的對數（≈ 一屏可見的撞圖）：

| 策略 | 解鎖 20 位 | 解鎖 50 位 | 解鎖 100 位 |
| --- | --- | --- | --- |
| **現況**（模型挑最貼題材） | 9 張圖／撞圖率 61% | 10 張圖／88% | 11 張圖／89% |
| 現況樂觀上界（模型均勻亂挑） | 17 張／23% | 17 張／32% | 18 張／41% |
| **S2 種子挑** | 14 張／23% | 17 張／41% | 19 張／34% |
| **S2＋S3 種子挑 + 每 id 3 變體** | 27 張／**0%** | 36 張／**10%** | 45 張／**11%** |
| S2＋S3 種子挑 + 每 id 5 變體 | 25 張／10% | 46 張／4% | 62 張／**6%** |

讀法：**只做 S2 大約砍掉一半的撞圖，但撞圖率仍在三到四成**——因為 21 張圖的池子撐不住 69～148 則貼文。**要真的解決必須把池子做大（S3）**。

---

## 4. 解法選項

### S1（必要前提）修正候選集中 — 調 `imageTags`
把「吃的」相關標籤從泛用題材上拔掉一部分，讓冷門素材（`sea_view`、`gym_corner`、`train_window`、`desk_work`）進得了池。純資料修改、零風險，但**單獨做效果有限**——它改善的是候選分佈，不改變模型收斂到同一張的行為。

### S2（推薦，低成本高效益）挑圖改由 server 種子決定
把「挑哪張」從模型手上收回排程層，補上 catalog 註解本來就宣稱的那一步：

```ts
const candidates = momentImagesForTags(theme.imageTags);
const chosen = candidates.length && rollUnit(`${seed}|image`) < IMAGE_PROBABILITY
  ? [pickFrom(candidates, `${seed}|image_pick`)]   // ← 缺的就是這一行
  : [];
```

`imageCandidates` 收斂成單一元素後：

- prompt 走**現成的**「圖決定文」分支——目前 `onlySelfPortrait` 已經是這個寫法（「這一則會配上你自己的照片……把文字寫成配得上一張自拍的樣子」），照抄即可，不是新機制。
- `validateMomentDraft` **一行都不用改**（allowlist 剛好只剩一個元素）。
- DB schema、feed API、client 對照表全部不動。

**需要補的東西**：每個 id 一句給模型看的中文描述（例如 `moment_home_cooking` →「瓦斯爐上的炒鍋，旁邊砧板有切好的蔥花與蒜末」），否則模型不知道自己在配什麼圖、文字會對不上畫面。這是 `MOMENT_IMAGES` 加一個 `brief` 欄位的事。

**副作用（正面）**：挑圖回到決定論，重試不會換圖；並且**因為圖在生成前就已知**，未來要做任何跨貼文去重才有著力點。

### S3（推薦，效果最大）每個 id 多做 2–4 個變體，client 端種子選一

**這件事幾乎是免費的**——`docs/plans/2026-08-24-practice-moments-scene-image-prompts.md` 的管線本來就規定**每個 id 先生 3 張候選**（`raw/${id}_a.png`），最後只留一張。另外兩張多半還在。

體積也不是問題：

| | 現況 | 3 變體 | 5 變體 |
| --- | --- | --- | --- |
| 總體積 | **896 KB** | ~2.7 MB | ~4.5 MB |
| 已核准預算 | 2.6 MB（設計報告 2–3 MB） | **仍在預算內** | 超出 |

當初「刻意控制在 20 張」的理由是「100 張角色照已佔 13 MB」，但實測 20 張場景圖只花掉 0.9 MB——**預算其實還有兩倍以上的餘裕沒用。**

建議做法是**變體只存在於 client**：

- Edge / DB / API 契約完全不動，`image_id` 仍是 20 個語意 id。
- Client `resolveMomentImage()` 改成吃 `(imageId, profileId, postDate, slot)`，用 `fnv1a` 種子在 `moment_coffee_cup_1/2/3.webp` 之間挑。`PracticeMomentPost` 這四個欄位都現成。
- 變體檔缺席時退回 base id——沿用既有的向前相容鐵則。
- `test/lint/moments_scene_asset_parity_test.dart` 的三方對帳要跟著改成「每個 Edge id 對應 1..K 個檔案」。

### S4（可選，零素材成本的部分緩解）同一張圖做構圖變化
用種子決定 `alignment` 與縮放，讓同一個 webp 在不同貼文長得不完全一樣。程式碼裡已有先例——自拍分支就是這樣處理的（「用 4:3 框＋略高於中線的 alignment，讀起來是同一個人的另一個構圖」）。

**這是緩解不是解決**：仔細看還是同一口炒鍋。適合當 S3 素材補齊前的過渡，或與 S3 疊加。

### S5（不建議單獨使用）Client 端撞圖就降級成純文字
渲染時發現近 N 則出現過同一張圖就不畫圖。實測代價：

| | 抑制視窗 6 則 | 抑制視窗 12 則 |
| --- | --- | --- |
| 現況挑圖法（解鎖 50 位） | **75% 的圖沒了** | 86% 沒了 |
| S2 種子挑 | 45% 沒了 | 71% 沒了 |
| S2＋S3 三變體 | 12% 沒了 | 28% 沒了 |

配圖率本來就只有 17%，再砍掉四分之三等於**把圖文貼文這個型態實質關掉**，直接違反真機驗收「兩種貼文型態都要有」。只有在 S3 之後，S5 才是划算的收尾保險。

---

## 5. 建議

**S1 + S2 + S3 一起做，S5 當收尾保險。**

理由：S2 便宜、修的是一個實作與自身註解不符的缺口、並且是任何後續去重的前提；但 S2 單做仍留三到四成撞圖率，**只有 S3 把池子從 21 撐到 60+ 才真的把撞圖壓到個位數百分比**，而 S3 的素材成本已經預付過了（每個 id 本來就生了 3 張）。

建議切成三個 PR，各自可獨立測試與回退：

1. **PR-1（Edge，純函式）** S1 標籤再平衡 + S2 種子挑 + `MOMENT_IMAGES` 補 `brief`；prompt 改走既有的「圖決定文」分支。deno 測試涵蓋分佈均勻度與決定論。
2. **PR-2（素材 + client）** S3 變體檔入庫、`resolveMomentImage` 改簽章、三方對帳測試改成 1..K。
3. **PR-3（client，可選）** S5 近 N 則抑制 + S4 構圖變化。

---

## 6. 驗收方式

- **模擬（可 CI 化）**：`tools/moments-image-census/census.ts`（`deno run --allow-read` 或 `node --experimental-strip-types`）直接 import 正式排程與圖庫模組跑 14 天 feed，本文所有數字都出自它。改完策略重跑即可比較；轉成 deno 測試時斷言（a）相異圖 ≥ 40 張、（b）相鄰 4 則撞圖率 ≤ 15%、（c）沒有任何一張圖佔比 > 10%。斷言值目前只是建議門檻，實作 PR 時再依實測收斂。
- **真機**：Eric 在 iPhone 上把 `她們的動態` 從頭滑到 14 天底，任一屏內不應出現兩張相同配圖。

---

## 7. 待 Eric 拍板

1. **變體張數**：3（~2.7 MB，在既有預算內）還是 5（~4.5 MB，需要放寬預算）？
2. **配圖率**：池子變大之後，`IMAGE_PROBABILITY = 0.2` 要不要回調？（0.45 → 0.15 → 0.2 是為了素材少而壓的；D5b「文字優先」的版面決定則是另一回事，兩者不必綁在一起。）
3. **S4 構圖變化**要不要做——它會讓同一張素材更耐重複，但也讓配圖的構圖不再是美術上鎖死的那一版。
