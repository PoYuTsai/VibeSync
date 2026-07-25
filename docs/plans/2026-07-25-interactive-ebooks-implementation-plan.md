# 學習專區四本互動式電子書 — 詳細實作計畫

> - 日期：2026-07-25
> - 狀態：READY FOR CC IMPLEMENTATION
> - 產品決策者：Eric
> - 預定執行者：Claude Code（CC）
> - 風險等級：R2
> - 高風險邊界：訂閱／paywall、帳號切換、本機進度隔離、公開教材內容與 App Review 調性
> - 授權邊界：本文只授權未來收到 Eric 明確開工指示後的本機實作、測試與繁中 commits；不授權 push、deploy、TestFlight、production mutation 或外部訊息

## 0. 這份文件的用途

這份文件是「四本互動式電子書」的施工規格、內容契約與驗收標準，不是單純構想筆記。

配套的 CC 開工摘要：

- `docs/plans/2026-07-25-interactive-ebooks-cc-handoff.md`

兩份來源教材：

- Windows：`C:\Users\eric1\OneDrive\Desktop\Vibesync重要文件\交友軟體實戰手冊.md`
- Windows：`C:\Users\eric1\OneDrive\Desktop\Vibesync重要文件\交友軟體實戰五階段課程.md`
- WSL：`/mnt/c/Users/eric1/OneDrive/Desktop/Vibesync重要文件/交友軟體實戰手冊.md`
- WSL：`/mnt/c/Users/eric1/OneDrive/Desktop/Vibesync重要文件/交友軟體實戰五階段課程.md`

若本文與目前程式碼衝突：

1. 先以實際程式、測試、`AGENTS.md` 與最新相關 commit 為準。
2. symbol 或檔案落點可以依現況微調，但不能自行改動本文的產品不變量。
3. 若差異涉及 Free／Paid 分界、文章額度、帳號資料隔離、內容安全立場或四冊內容範圍，停止並請 Eric 決定。
4. 不得用舊夥伴分析中的「四變數／投資曲線／賦格」內容覆蓋兩份新版教材。

---

## 1. 已鎖定的產品方向

### 1.1 內容真源

兩份新版教材是 canonical source：

- 《交友軟體實戰：五階段進階課程》回答「先學什麼、為什麼、怎麼診斷」。
- 《交友軟體實戰手冊》回答「實際長什麼樣、死在哪一句、下一句怎麼修」。

舊夥伴分析只保留下列產品外殼：

- 四本書。
- 章節式閱讀器。
- 翻卡。
- 情境測驗與即時回饋。
- 章節完成與續讀。
- Book 1 免費，Books 2–4 訂閱。
- Hive 本機進度。
- 電子書不消耗既有文章每日免費額度。

舊分析中的以下內容不再是教材真源：

- 四大變數。
- 投資曲線作為主架構。
- 賦格／失格。
- 間歇性強化作為正向核心引擎。
- 讓對方證明自己。
- 得寸進尺。
- 以焦慮、不確定感或退出困難推進關係。

### 1.2 五個標記

全套教材使用：

|標記|名稱|白話定義|
|---|---|---|
|V|價值|你自然露出的生活、能力、判斷與真實特質|
|F|框架／方向|互動現在由誰定方向，以及雙方界線是否清楚|
|E|情緒|對話中的幽默、共鳴、張力與感受起伏|
|I|投資|對方投入的時間、資訊、自我揭露與主動程度|
|R|互惠|你是否清楚、具體又不施壓地表達興趣|

Quiz 不得把一句同時包含 `V + E` 的訊息硬說成只有一個正確變數。

### 1.3 三燈

|燈號|意思|下一步|
|---|---|---|
|綠燈|對方主動加碼、追問、引用、回覆變長或開新話題|可以自然推進|
|黃燈|有回應但不加碼、接得住但沒有往前|維持或換軌，不加壓|
|紅燈|回覆明顯收短、話題被關閉、玩笑不接或明確拉開距離|退回或停止|

三燈在任何 UI 中都要同時顯示文字與圖示，不能只用紅黃綠顏色。

### 1.4 學習方式

- 先診斷第一個漏斗瓶頸。
- 只練目前瓶頸，不強迫從 Book 1 依序讀到 Book 4。
- Books 2–4 對付費使用者一次全部開放，不做前一本完成才解鎖下一本。
- Book 1 的診斷結果要明確告訴使用者應跳去哪一本／哪一章。
- 互動目標是辨識與判斷，不是背話術。

### 1.5 權限

|內容|Free|Starter|Essential|
|---|---:|---:|---:|
|Book 1|可讀|可讀|可讀|
|Books 2–4|鎖定|可讀|可讀|
|既有 24 篇文章|維持現況|維持現況|維持現況|
|電子書是否消耗文章每日額度|否|否|否|

權限判斷以目前 `SubscriptionState.isPremium` 為準；它涵蓋 Starter 與 Essential。

### 1.6 Quiz 行為

預設政策：

- 支援單選與複選。
- 提交後立即回饋。
- 每個選項可有自己的白話 feedback。
- 答錯可以再試。
- 答對後標示已理解並保存。
- 章節完成不以「必須答對」為硬門檻。

資料模型保留 `retryPolicy`，至少支援：

- `untilCorrect`：預設。
- `lockedAfterSubmit`：只有 Eric／夥伴明確指定的題目才使用。

不得把「首答永久鎖定」硬寫死在 progress service。

---

## 2. 來源教材校正契約

實作內容前先完成以下校正，不能把原稿矛盾直接編進 App。

### 2.1 必修正的不一致

1. 舊分析寫四變數；新版手冊是五標記 `V/F/E/I/R`。採五標記。
2. 手冊文字說「十二個案例」，實際為 A–N 共十四個。成品寫十四個。
3. 課程標題寫「照片五個位置」，表格實際列六個功能位。成品稱「六個功能位」。
4. 五階段是階段 0–4，不是五本書；四本書是產品分冊，不是階段數。
5. 「很少、偏低、明顯上升、穩定」沒有共同數值門檻。診斷以個人趨勢與第一個明顯瓶頸為主，不假裝有精準產業基準。

### 2.2 需要柔化或補證據的主張

下列說法若沒有可靠來源，不可用絕對語氣：

- 少於二十次完全無法診斷。
- 同時聊五到八人是固定上限。
- 體脂是最大的單一變數。
- 某種做法幾乎完全可控到場率。
- 某技巧一定在三到五天／第五輪前有效。
- 特定吸引力研究的結論。

處理方式：

- 改成「樣本太少容易被偶然波動影響」。
- 改成「超出你能記住細節的數量，回應品質通常會下降」。
- 改成「健康、儀容、合身穿著與生活內容會影響整體呈現」。
- 將時間窗寫成啟發式建議，不寫成保證。
- 若保留研究主張，需在 JSON 的 `sourceRefs` 留下可驗證出處。

### 2.3 調性與安全

- 敘述以「對方」為主，對話案例可保留不同角色。
- 技巧是幫使用者表達真實自己並讀懂雙向意願，不是操控。
- 「假定同意」改稱「清楚提出具體方案」。
- 「框架」第一次出現要解釋成「互動方向與界線」。
- 「價值」第一次出現要解釋成「自然露出的生活與特質」，不是人的高低。
- 「DHV」只可在術語卡作補充，不作主要標題。
- 「賦格／失格／得寸進尺／常春藤名校效應」不作正向核心術語。
- 忽冷忽熱、貶低、讓對方焦慮、壓縮退出空間、升級棘輪只能放在「為何不要這樣做」。

### 2.4 必補安全內容

至少在 Book 4 加入：

- 第一次見面優先公開場所。
- 保有自己的交通與返家安排。
- 可告知可信任朋友行程。
- 不因對方答應見面就推定其他親密行為。
- 明確拒絕立即停止。
- 模糊回應不視為同意。
- 轉 IG／Line 前注意詐騙、個資與不必要的即時位置資訊。

不得保存使用者貼入的真實私密聊天或長篇反思；MVP 只保存課程進度與題目答案 ID。

---

## 3. 四本書與二十章

### Book 1 —《先找到真正卡點》

> 權限：免費  
> 目標：找到第一個漏斗瓶頸，解決檔案與開場問題。  
> 建議閱讀時間：約 35–45 分鐘。

#### 1.1 六個數字，找出你卡在哪

- A 配對數。
- B 開場後有回覆。
- C 撐過五輪。
- D 實際提出見面。
- E 對方答應。
- F 真的到場。
- 第一個明顯掉下來的地方就是目前階段。
- 強調失敗基準率高，不把每次失敗都解讀成個人缺陷。

互動：

- 漏斗情境單選題。
- 翻卡：表面問題 vs 真正瓶頸。
- 結尾提供「應讀哪一本」導覽。

#### 1.2 六張照片，各有一個工作

- 主照。
- 全身。
- 社交。
- 興趣／活動。
- 生活感。
- 彈性／故事感。
- 真實、不過度修圖、不造成見面落差。

互動：

- 六種照片用途配對題。
- 弱／強照片組合翻卡。
- 不做照片上傳或 AI 評分。

#### 1.3 Bio 不是履歷，是一個好接的鉤子

- 具體生活細節。
- 一句幽默或自嘲。
- 一個低成本開口。
- 不列抽象優點，不列負面要求。

互動：

- 比較泛用 Bio 與具體 Bio。
- 找出哪一句提供了回應入口。

#### 1.4 She／Me／Us：開場不要像查戶口

- 具體引用對方檔案。
- 露出自己的一小塊。
- 有共同點才談「我們」。
- 狀態＋感受勝過單純事實。

互動：

- 單選／複選 V/F/E/I/R。
- 對話翻卡揭示「為什麼這句好接」。

#### 1.5 八種檔案的開場實驗室

- 旅行、寵物、美食、運動、音樂藝文、職業感、資訊少、Bio 有笑點。
- 三個禁區：純外貌稱讚、純問句無自我、過長。
- 批量測試與回覆率概念。

互動：

- 每種檔案至少一組弱／強比較。
- 情境選句 Quiz。
- 不提供一鍵複製「萬用話術」。

### Book 2 —《看懂一段對話》

> 權限：訂閱  
> 目標：看懂每句話在移動什麼，以及何時該推進、維持或停止。  
> 建議閱讀時間：約 40–50 分鐘。

#### 2.1 V／F／E／I／R 五個標記

- 五標記定義。
- 一句可同時動多個標記。
- 標記是觀察工具，不是人物評分。

互動：

- 複選變數題。
- 逐句揭示標記的翻卡。

#### 2.2 對話為什麼死：三個最常見原因

- 查戶口。
- 只回事實，不回情緒。
- 自己沒有出現在對話裡。

互動：

- 找死亡點。
- 選替代回覆。

#### 2.3 回應性：理解、認可、在乎

- 引用對方之前說過的內容。
- 往情緒走。
- 先回應，再給自己的東西，最後才開新口。

互動：

- 情緒 vs 事實分類題。
- 黃燈換軌案例翻卡。

#### 2.4 側面價值與互惠

- 生活細節自然出現。
- 不直接自誇。
- 具體表達興趣，不用泛用奉承。
- R 是互惠，不是需求感遊戲。

互動：

- 自誇／側面展示比較。
- 泛用稱讚／具體觀察比較。

#### 2.5 情緒起伏、玩笑與三燈

- 張力型起伏 vs 焦慮型起伏。
- 玩笑是降低對方表態成本，不是施壓掩護。
- 綠／黃／紅三燈。
- 成功弧線 J–L。

互動：

- 三燈單選題。
- 下一步行動題。
- 成功弧線逐句翻卡。

### Book 3 —《對話急救室：該救，還是該停》

> 權限：訂閱  
> 目標：找出死亡點、選擇救援／換軌／停止，避免把紅燈當挑戰。  
> 建議閱讀時間：約 45–55 分鐘。

#### 3.1 死亡案例 A–C

- 查戶口。
- 泛用稱讚。
- 升級棘輪。

互動：

- 找死亡句。
- 判斷是 V/F/E/I/R 哪裡失衡。
- 選低壓替代句。

#### 3.2 死亡案例 D–F

- 回覆時間操作。
- 只回事實。
- 自己消失在對話裡。

互動：

- 判斷真正死因。
- 對話動能翻卡。

#### 3.3 救援案例 G–I

- 黃燈換軌。
- 已讀不回只重啟一次。
- 「最近比較忙」通常需要退回。

互動：

- 救援／停止二選一。
- 下一步與一週後分支題。

#### 3.4 診斷樹：第一個答案可以是「對方沒興趣」

- 先判斷是否仍有意願。
- 再看階段定位。
- 再看樣本與趨勢。
- 再看底層與市場錯配。
- 疑難情境：回覆短、轉 Line、聊得好但不見面、見面前變冷。

互動：

- 診斷步驟排序。
- 「救、維持、停」情境題。

#### 3.5 六個反效果技巧

- 回覆時間操作。
- Negging。
- 間歇性否定／強化。
- 假裝的篩選標準。
- 預先消除退出理由。
- 升級棘輪。

互動：

- 反技巧辨識。
- 判斷其短期效果與長期代價。
- 每個案例必須有尊重與退出提醒。

### Book 4 —《從聊天走到見面》

> 權限：訂閱  
> 目標：把雙方意願轉成小而具體的見面安排，並安全地處理拒絕、取消與到場。  
> 建議閱讀時間：約 45–55 分鐘。

#### 4.1 時間窗與兩種卡關

- 根本沒開口。
- 有開口但提案模糊或時機不對。
- 在對話仍有動能時提出，不把輪數當保證公式。

互動：

- 心理阻力／技術問題分類。
- 何時適合提出下一步。

#### 4.2 種子：模糊的是時間，不是對象

- 種子需要具體對象。
- 讀綠／黃／紅反應。
- 綠燈後不繼續種。
- 種子田的風險。

互動：

- 種子／空話分類。
- M 成功與 N 失敗對照。

#### 4.3 小而具體的提案

- 具體時間。
- 具體地點或活動。
- 具體理由。
- 低承諾門檻。
- 「清楚提出具體方案」取代「假定同意」字面。
- 對方始終保有容易拒絕與改時間的空間。

互動：

- 提案組件辨識。
- 大而模糊／小而具體比較。

#### 4.4 拒絕、取消、到場與安全

- 明確拒絕立即停止。
- 模糊延後最多再試一次不同方向。
- 一次取消且主動提替代時間 vs 沒有替代。
- 兩次取消停止投入。
- 降低交通、時間與正式程度摩擦。
- 公開場所、自主交通、告知朋友、個資與同意。

互動：

- 取消情境分支題。
- 安全行為多選題。

#### 4.5 十二週練習與每週自評

- 一次只練一個階段。
- 每週記錄自己的漏斗趨勢。
- 開場、續航、轉線下自評。
- 長期主線：健康、儀容、生活內容、社交圈。

互動：

- 自評 checklist。
- 本週唯一練習目標。
- MVP 不儲存私密文字，只保存 checklist／完成狀態。

---

## 4. 每章固定內容模板

每章 JSON 順序應遵守：

1. `storyIntro`：生活化情境。
2. `learningGoal`：本章只回答一個問題。
3. `principle`：白話原理。
4. `dialogue`：至少一段對話泡泡。
5. `flipCard`：至少一張「情境 → 背後機制」。
6. `quiz`：至少一題。
7. `safetyCallout`：涉及推進、拒絕、界線時必填。
8. `takeaway`：今天只帶走一個動作。
9. 完成本章按鈕。

資料不變量測試必須確認：

- 每章至少一個 `flipCard`。
- 每章至少一個 `quiz`。
- 涉及邀約、拒絕或升級的章節至少一個 `safety` callout。
- 每個互動 ID 全域唯一。

---

## 5. 現有程式掛載點

### 5.1 學習首頁

目前：

- `lib/features/learning/presentation/screens/learning_screen.dart`
- 首屏是 `PracticeRoomEntryCard` Hero。
- Hero 下方是文章導向文案與每日免費文章提示。
- 最後是 24 篇文章雙欄 grid。

目標順序：

1. AI 實戰練習室 Hero。
2. 「互動電子書」區塊。
3. 「短篇實戰文章」區塊。
4. 既有 24 篇文章 grid。

現有文章每日剩餘提示必須移到「短篇實戰文章」標題附近，不得放在電子書書架上方造成錯誤聯想。

### 5.2 文章與 Coach 深連

既有 numeric article id 已被：

- `lib/features/analysis/domain/coach/learning_link_resolver.dart`
- Coach「看教學」

精準引用。

不得：

- 把電子書塞進 `articles`。
- 重用 numeric article id。
- 改動既有 24 篇 id。
- 讓電子書內容導入造成 Coach 教學連結回歸。

### 5.3 可重用元件

- `BrandSurfaceCard`
- `BrandIconBadge`
- `BrandSectionHeader`
- `BrandPrimaryButton`
- `BrandSecondaryButton`
- `BrandInfoNote`
- `GradientBackground`
- `AppColors`
- `AppTypography`

MVP 不必先抽取 `ArticleDetailScreen` 的 private markdown-ish renderer。電子書使用 typed blocks，避免不必要地改動 24 篇文章。

---

## 6. 資料與資產架構

### 6.1 為什麼使用 bundled JSON

既有文章已全部硬編在單一大型 Dart 檔。四本書約二十章、四十個以上互動元素，若再用 const Dart：

- 文案 review 會被大量 Dart 語法干擾。
- 編輯容易誤改括號、引號或 Flutter 型別。
- 內容與 UI 耦合。
- 未來轉 CMS 困難。

MVP 使用 bundled JSON：

- 不新增第三方 dependency。
- 仍需發版才更新，不假裝是 CMS。
- 用 typed parser 及 schema tests 保住資料安全。
- 一書一檔，便於夥伴 review。

### 6.2 新增 assets

```text
assets/learning/ebooks/book_1_bottleneck.json
assets/learning/ebooks/book_2_conversation.json
assets/learning/ebooks/book_3_rescue.json
assets/learning/ebooks/book_4_meeting.json
```

`pubspec.yaml` 新增：

```yaml
flutter:
  assets:
    - assets/learning/ebooks/
```

不新增封面圖片。書封使用 theme key、品牌色、icon 與編號排版。

### 6.3 Book JSON 概念結構

```json
{
  "schemaVersion": 1,
  "id": "ebook-1-bottleneck",
  "contentVersion": 1,
  "title": "先找到真正卡點",
  "subtitle": "先修第一個瓶頸，不再亂補話術",
  "access": "free",
  "theme": "compass",
  "estimatedMinutes": 40,
  "sourceRefs": [
    {
      "document": "five-stage-course",
      "sections": ["第一節", "階段 0", "階段 1"]
    }
  ],
  "chapters": []
}
```

內容 JSON 只能放 semantic keys，不得放：

- Flutter `Color`。
- `IconData` code point。
- Widget name。
- route callback。
- Hive key。

### 6.4 Domain models

建議落點：

```text
lib/features/learning/domain/models/ebook.dart
lib/features/learning/domain/models/ebook_block.dart
lib/features/learning/domain/models/ebook_progress.dart
```

核心模型：

```text
Ebook
EbookChapter
sealed EbookBlock
EbookQuizChoice
EbookQuizState
EbookProgressSnapshot
EbookBookProgress
```

Block types：

```text
heading
paragraph
bulletList
callout
comparison
dialogue
flipCard
quiz
checklist
```

Quiz：

```text
mode: single | multiple
retryPolicy: untilCorrect | lockedAfterSubmit
revision: int
choices:
  id
  text
  isCorrect
  feedback
takeaway
```

每個 choice 使用 stable string id，不以陣列 index 當永久儲存值。

### 6.5 Catalog

建議：

```text
lib/features/learning/data/repositories/ebook_catalog_repository.dart
lib/features/learning/data/providers/ebook_providers.dart
```

`EbookCatalogRepository`：

- 從 `AssetBundle` 載入四個 JSON。
- parser 遇到未知 block type 時 fail closed，顯示可讀錯誤，不跳過互動造成假完整。
- production catalog 必須恰好四本。
- 提供 `findBook(bookId)`、`findChapter(bookId, chapterId)`。
- parser 可注入 `AssetBundle`，方便 unit／widget test。

不使用 remote fetch。

---

## 7. 進度儲存與帳號隔離

### 7.1 Box

使用現有加密：

```text
StorageService.settingsBox
```

不使用：

- `ArticleReadService`。
- article daily quota keys。
- 新 Hive adapter／typeId。
- 未分帳號的 global key。

### 7.2 Storage key

```text
learning_progress_v1:<ownerUserId>
```

`ownerUserId` 必須是目前 Supabase account id，trim 後不可為空。

不得使用 email 作 key。

### 7.3 Snapshot

建議以 JSON string 儲存：

```json
{
  "schemaVersion": 1,
  "updatedAt": "2026-07-25T00:00:00.000Z",
  "books": {
    "ebook-1-bottleneck": {
      "contentVersionSeen": 1,
      "lastChapterId": "ebook-1-chapter-2",
      "completedChapterIds": ["ebook-1-chapter-1"],
      "quizStates": {
        "ebook-1-quiz-1": {
          "quizRevision": 1,
          "selectedChoiceIds": ["choice-v", "choice-e"],
          "solved": true
        }
      },
      "checklistStates": {}
    }
  }
}
```

### 7.4 規則

- `lastChapterId` 不存 index。
- chapter reorder 不影響 resume。
- Quiz `revision` 改變時，舊選項視為未作答。
- 純文案修改且 ID／revision 未變時保留進度。
- 大改一章時應更換 chapter id 或提供明確 migration。
- 完成章節冪等。
- book progress = 完成章節數 ÷ 總章節數。
- 不以 scroll pixel 百分比當完成度。
- 不每日重置。
- 不儲存真實聊天文字。

### 7.5 寫入語意

Repository API 全部回傳 `Future`：

```text
load(ownerUserId)
markChapterCompleted(ownerUserId, bookId, chapterId)
setLastChapter(ownerUserId, bookId, chapterId)
recordQuizSubmission(ownerUserId, bookId, quizId, quizRevision, choiceIds, solved)
setChecklistItem(ownerUserId, bookId, blockId, itemId, checked)
```

- `Box.put` 必須 `await`。
- 完成章節後要等寫入成功才翻到下一章或返回目錄。
- `setLastChapter` 可由 controller 序列化寫入，避免快速 swipe 的舊寫入覆蓋新寫入。
- Provider dispose 不得取消或遺失已開始的 Hive write。

### 7.6 Corruption 與 migration

- JSON decode、型別轉換、未知 schema version 都在 repository 捕捉。
- UI 不直接處理 Hive dynamic map。
- 損壞時回空 snapshot 與可測試的 recoverable state，不 crash reader。
- 不把損壞 raw payload 寫進 log。
- 不默默 delete 原 key；若需清除，先另行決策。

### 7.7 登出／刪帳

- key 已按 account id 分區，帳號 B 不得讀到帳號 A。
- 登出時 invalidate ebook progress provider。
- 一般登出可保留該帳號本機進度，重新登入同帳號可恢復。
- 刪除帳號既有 `StorageService.clearAll()` 會清 settings box。

---

## 8. Riverpod state

建議新增：

```text
ebookCatalogProvider
ebookProgressRepositoryProvider
ebookProgressControllerProvider
ebookBookProgressProvider(bookId)
```

責任：

- Catalog provider：載入四本書與 parser 錯誤。
- Repository：只管讀寫。
- Controller：持有目前帳號 snapshot，先 await repository，再更新 state。
- Derived provider：輸出單本完成度與 lastChapterId。

規則：

- owner id 不可從 content 或 route 傳入。
- 測試可 override owner provider／repository。
- 未登入時 fail closed，不建立 `anonymous` 共用進度 key。
- 登出後 provider 不得保留舊帳號 snapshot。

Quiz 當下選擇可以先在 widget local state；提交後由 controller 保存。不要每點一個尚未提交的選項就重建整個 reader。

---

## 9. 路由與導航

新增：

```text
/learning/books/:bookId
/learning/books/:bookId/chapters/:chapterId
```

### 9.1 書籍目錄

`EbookDetailScreen`：

- 封面卡。
- 書籍說明。
- 總完成度。
- 「開始閱讀／繼續閱讀」。
- 章節清單。
- 完成章節使用 icon＋文字，不只顏色。
- unknown book 顯示「找不到這本書」與返回學習頁 CTA。

### 9.2 閱讀器

`EbookReaderScreen`：

- route chapter id 只決定初始章節。
- `PageView.builder` 一頁一章。
- 每章內部獨立垂直 scroll。
- AppBar 下顯示「第 X／Y 章」與位置進度。
- 位置進度和完成度要有不同 label，不混為一談。
- swipe 章節更新 lastChapterId。
- 章末按鈕：
  - 中間章：「完成本章，下一章」。
  - 最末章：「完成本書」並回目錄。
- unknown chapter fallback 到：
  1. 保存的 lastChapterId（若合法）。
  2. 第一章。
- 直接 deep link 進 reader 也必須做 access gate。

### 9.3 Back behavior

- 正常流程：書架 → 目錄 → 閱讀器，使用 `push` 保留 back stack。
- 直接 deep link 沒有可 pop route 時：
  - Reader back → 對應書籍目錄。
  - Detail back → `/?tab=learning`。

不得用 back 退出整個 App。

---

## 10. 付費閘門

### 10.1 Pure access policy

```text
ebookLockedFor(book, subscription)
```

規則：

- `access == free` 永不鎖。
- `access == premium` 且 `subscription.isPremium == false` 才鎖。
- Starter／Essential 都解鎖。
- 不讀文章 daily quota。

### 10.2 Shared guard

建立共用 `EbookAccessGate`：

- Catalog unknown 先顯示 not found，不導航 paywall。
- Book 1 可直接 render。
- Premium book：
  - subscription loading → 只顯示 loading scaffold。
  - subscription error／狀態無法確認 → 顯示可重試錯誤，不洩漏內容，也不把技術錯誤假裝成 Free upsell。
  - resolved Free → post-frame 導向 `/paywall`。
  - resolved Premium → 才建立 child。
- `_gateChecked` 或等價狀態防止重複導航。

即使使用 post-frame redirect，Premium child 在 gate 完成前也不能 build，避免付費內容閃現。

### 10.3 書架

- Locked card 顯示鎖頭＋「訂閱解鎖」。
- Book 1 對 Free 顯示「免費」。
- 已讀過但後來降級的 Books 2–4：
  - 可顯示完成百分比。
  - 仍不可開啟內容。
- 點 locked card 用 `push('/paywall')`。

### 10.4 明確不做

- 不修改 RevenueCat。
- 不修改 tier 定義。
- 不修改 quota。
- 不用文章每日三篇額度包裝 chapter。
- 不在 client 下載付費內容後只靠 opacity 隱藏。

注意：四本 JSON 都隨 App bundle 發布，這不是 server-side DRM。付費閘門保護正常 App UX，不應宣稱能防止解包資產。若未來需要強 DRM，另做 server content delivery，不納入 MVP。

---

## 11. UI 與互動元件

### 11.1 書架

建議：

```text
lib/features/learning/presentation/widgets/ebook_shelf_section.dart
lib/features/learning/presentation/widgets/ebook_shelf_card.dart
```

每本使用 compact full-width `BrandSurfaceCard`：

- 書號與 icon。
- 標題／副標。
- 章節數／估計時間。
- 完成度。
- 免費／鎖定 pill。

四張卡教材優先、文章在後。

### 11.2 Block renderer

```text
lib/features/learning/presentation/widgets/ebook_block_renderer.dart
```

對 sealed block exhaustive switch：

- 新增 block type 時編譯器迫使補 renderer。
- 未知 JSON type 在 parser fail closed，不到 renderer 才爆。

### 11.3 Dialogue

```text
ebook_dialogue_block.dart
```

- 只做教材用 display-only bubbles。
- 不直接重用 production conversation bubble，避免帶入時間、狀態、互動依賴。
- speaker 使用 `you / other / coach` semantic enum。
- 可顯示 annotation、死亡點、燈號，但不能只用顏色。

### 11.4 Flip card

```text
ebook_flip_card.dart
```

- 點擊或 keyboard activate 翻面。
- 正面是情境／對話。
- 背面是機制／修正。
- 預設約 300–350ms。
- `MediaQuery.disableAnimations` 時立即切換或使用極短淡入。
- Semantics label 清楚說「顯示解析／返回情境」。
- 不使用固定高度造成大字體 overflow。
- 翻面狀態不持久化。

### 11.5 Quiz

```text
ebook_quiz_card.dart
```

- 單選用 radio-like control。
- 複選用 checkbox-like control。
- 提交前不揭示正解。
- 提交後顯示：
  - 選項圖示。
  - 正確／再想想文字。
  - 每個選項 feedback。
  - 全題 takeaway。
- 不能只用綠／紅。
- `untilCorrect` 答錯後可重設並再試。
- restore 時依 quiz revision 驗證。

### 11.6 Checklist

- 只保存 item id／bool。
- 不接受自由文字。
- 適用 Book 1 profile check 與 Book 4 每週自評。

---

## 12. 無障礙與韌性

必驗證：

- 320px 寬度。
- text scale 1.0、1.3、2.0。
- light／dark 不需另做；沿用目前品牌 dark system。
- reduced motion。
- VoiceOver／TalkBack semantics。
- quiz 與三燈不只靠顏色。
- 長繁中文字串不 overflow。
- PageView 橫滑不阻斷章節垂直 scroll。
- Loading、錯誤、unknown id 都有可返回路徑。

Flip card 背面若比正面長，容器必須能隨內容調整或內部安全捲動；不能裁字。

---

## 13. Workstreams

### Workstream A — 內容 manifest 與校正

產物：

- 四本／二十章 content manifest。
- 每章 source refs。
- 五標記 glossary。
- 安全與調性規則。
- 矛盾修正紀錄。

完成條件：

- 不再出現四變數主架構。
- 不再宣稱十二案例。
- 不再稱照片五功能位。
- 反操弄立場與新版教材一致。

### Workstream B — Typed models 與 JSON catalog

1. 新增 domain models。
2. 新增 JSON parser。
3. 新增 catalog repository。
4. `pubspec.yaml` 註冊 assets。
5. 建立最小 Book 1 Chapter 1 fixture。
6. 資料 invariant tests。

### Workstream C — Progress repository

1. account-scoped key。
2. snapshot encode／decode。
3. schema version。
4. chapter completion。
5. last chapter ID。
6. quiz revision／choice IDs。
7. checklist state。
8. corrupt data fallback。
9. account isolation tests。

### Workstream D — Interaction widgets

1. Dialogue。
2. Flip card。
3. Single／multi Quiz。
4. Checklist。
5. Block renderer。
6. Semantics／reduced motion／text scale tests。

### Workstream E — Navigation vertical slice

先只用 Book 1 Chapter 1 打通：

```text
學習首頁
→ 書架
→ Book 1 目錄
→ Chapter 1
→ 翻卡
→ Quiz
→ 完成本章
→ 返回目錄
→ 返回書架
→ 重開續讀
```

同時驗證：

- unknown book。
- unknown chapter。
- direct deep link。
- back behavior。

### Workstream F — Paywall

1. Pure policy。
2. Shared guard。
3. Shelf lock state。
4. Free／Starter／Essential tests。
5. loading／error no-flash tests。
6. 確認電子書未呼叫 `ArticleReadService`。

### Workstream G — 四本內容

一本一批：

1. Book 1。
2. Book 2。
3. Book 3。
4. Book 4。

每本完成後：

- schema test。
- 每章互動 invariant。
- 內容 safety scan。
- 人工閱讀。
- 夥伴／Eric 文案驗收。

### Workstream H — Regression 與 review

- 既有文章。
- MainShell。
- Coach learning links。
- subscription access。
- full analyze／tests。
- opposite-frontier review。
- GLM falsification。
- 主執行者 reconcile。

---

## 14. 測試計畫

### 14.1 Baseline

2026-07-25 已執行：

```powershell
flutter test test/unit/features/learning `
  test/unit/app/main_shell_test.dart `
  test/unit/features/analysis/domain/coach/learning_link_resolver_test.dart
```

結果：22／22 PASS。

CC 開工前要重跑並記錄當下結果。

### 14.2 Catalog／data tests

建議：

```text
test/unit/features/learning/ebook_catalog_test.dart
test/unit/features/learning/ebook_content_invariants_test.dart
```

涵蓋：

- 恰好四本。
- ID 全域唯一。
- Book 1 free，Books 2–4 premium。
- 恰好二十章。
- chapter order／id 穩定。
- 每章至少一個 flip card 與 quiz。
- 涉及推進的章有 safety callout。
- Quiz choice id 唯一。
- single 恰好一個正解。
- multiple 至少一個正解。
- feedback 非空。
- correct choice／revision 合法。
- source refs 存在。
- unknown type fail closed。
- JSON 實際 assets 可載入。

### 14.3 Progress tests

```text
test/unit/features/learning/ebook_progress_repository_test.dart
test/unit/features/learning/ebook_progress_controller_test.dart
```

涵蓋：

- 空 snapshot。
- 完成章節冪等。
- 完成度。
- lastChapterId round-trip。
- chapter reorder 不影響 resume。
- Book A／B 不互漏。
- Account A／B 不互漏。
- quiz choice string ids。
- wrong answer 可 retry。
- solved restore。
- revision 變更使舊答案失效。
- checklist restore。
- malformed JSON。
- dynamic list 型別污染。
- unknown schema version。
- awaited write。
- rapid lastChapter writes 最後一筆勝出。

### 14.4 Widget tests

```text
test/widget/features/learning/ebook_shelf_section_test.dart
test/widget/features/learning/ebook_detail_screen_test.dart
test/widget/features/learning/ebook_reader_screen_test.dart
test/widget/features/learning/ebook_flip_card_test.dart
test/widget/features/learning/ebook_quiz_card_test.dart
test/widget/features/learning/ebook_access_gate_test.dart
```

涵蓋：

- 書架四本。
- Free／locked badges。
- quota 提示只在文章區。
- detail start／continue。
- chapter completion。
- single／multi quiz。
- retry／restore。
- reduced motion。
- semantics。
- text scale 2.0。
- unknown book／chapter。
- direct deep link。
- Free 不能看 Books 2–4。
- Starter／Essential 能看。
- loading 不 render premium child。
- subscription error 不誤進內容或假裝 quota。

### 14.5 Route／regression tests

- `/learning/books/:bookId`。
- `/learning/books/:bookId/chapters/:chapterId`。
- 既有 `/article/:id`。
- `LearningLinkResolver` 所有 article id 仍存在。
- MainShell `learning` tab。
- 24 篇文章仍顯示。
- article cover／practice guide tests。

### 14.6 Commands

Targeted：

```powershell
flutter test test/unit/features/learning
flutter test test/widget/features/learning
flutter test test/unit/app/main_shell_test.dart
flutter test test/unit/features/analysis/domain/coach/learning_link_resolver_test.dart
```

Full：

```powershell
flutter analyze
flutter test --concurrency=1
git diff --check
```

報告必須分開：

- Targeted tests。
- Full Flutter tests。
- Manual route smoke。
- 尚未執行項目。

不得把 targeted green 寫成完整 regression green。

---

## 15. 手動驗收路徑

### 15.1 Free

1. 進 `/?tab=learning`。
2. Practice Hero 正常。
3. 看見四本電子書。
4. Book 1 顯示免費。
5. Books 2–4 顯示鎖定。
6. Book 1 → 目錄 → 閱讀。
7. 翻卡。
8. 單選答錯 → feedback → retry → 答對。
9. 複選作答。
10. 完成本章。
11. 返回目錄與書架，進度更新。
12. 重啟 App，續讀正確。
13. 點 Book 2 → paywall。
14. 直接 deep link Book 2 chapter → paywall，沒有內容閃現。
15. 電子書閱讀前後，今日文章剩餘篇數不變。

### 15.2 Paid

1. Starter 可讀四本。
2. Essential 可讀四本。
3. 可從 Book 1 診斷後直接跳 Book 4。
4. 不需完成 Book 2／3。

### 15.3 Account switch

1. Account A 完成章節。
2. 登出。
3. Account B 登入。
4. B 看不到 A 進度。
5. A 再登入。
6. A 進度恢復。

### 15.4 Accessibility

- 320px 寬。
- 2.0 text scale。
- reduced motion。
- screen reader 可讀出翻卡狀態、Quiz 選取、正誤與三燈文字。

---

## 16. 建議 commit 切法

### Commit 1

`新增互動電子書模型與內容目錄`

- Models。
- JSON parser。
- Catalog。
- pubspec asset registration。
- catalog tests。

### Commit 2

`新增帳號隔離的電子書進度儲存`

- Repository。
- Snapshot。
- Controller。
- account／corruption／revision tests。

### Commit 3

`新增電子書互動區塊與無障礙測試`

- Dialogue。
- Flip。
- Quiz。
- Checklist。
- Block renderer。
- widget tests。

### Commit 4

`新增電子書目錄閱讀器與穩定路由`

- Detail。
- Reader。
- Routes。
- direct-link／unknown-id tests。

### Commit 5

`學習頁加入電子書書架與訂閱閘門`

- Learning hierarchy。
- Shelf。
- Shared access guard。
- Free／Paid／loading tests。

### Commit 6

`內容新增先找到真正卡點`

### Commit 7

`內容新增看懂一段對話`

### Commit 8

`內容新增對話急救室`

### Commit 9

`內容新增從聊天走到見面`

### Commit 10

`測試補齊電子書回歸與驗收證據`

每顆 commit：

- 一件事一 commit。
- 繁中訊息。
- 不混入 Eric 或其他工作的變更。
- commit 前檢查 staged files。

未經 Eric 另行授權：

- 不 push。
- 不 deploy。
- 不建立 TestFlight。
- 不修改 production。

---

## 17. Review gate

本功能觸及 paywall、帳號資料隔離與公開教材，完成實作與本地驗證後必須做三方 challenge：

1. Claude Code 是 primary implementer／integrator。
2. Codex 做唯讀 opposite-frontier review。
3. GLM 做獨立 falsification pass。

Reviewer 不得：

- 修改 worktree。
- 部署。
- push。
-讀取 secrets。
- 收到 `.env`、客戶資料、真實聊天或無關程式。

Review focus：

1. Free 是否可能看到 Books 2–4。
2. Loading／deep link 是否閃出 premium content。
3. 電子書是否誤扣文章額度。
4. Account A／B 是否串進度。
5. content／quiz revision 是否處理舊答案。
6. JSON parser 是否 fail closed。
7. 三燈與 quiz 是否只靠顏色。
8. 反操弄內容是否被重新包裝成正向技巧。
9. 既有 24 篇與 Coach learning links 是否回歸。

Primary 逐項回 source／code 驗證，不以多數票決定。最多兩輪。

---

## 18. Definition of Done

### Content

- [ ] 四本、二十章完整。
- [ ] 每章至少一張翻卡與一題 Quiz。
- [ ] 五標記一致。
- [ ] 三燈一致。
- [ ] 14 案例與 6 照片功能位已校正。
- [ ] 絕對化主張已柔化或有 source。
- [ ] 安全、同意、個資與撤退內容已加入。
- [ ] Eric／夥伴完成文案驗收。

### Product

- [ ] Book 1 Free。
- [ ] Books 2–4 Starter／Essential。
- [ ] 非線性閱讀。
- [ ] 電子書不吃文章 quota。
- [ ] 書架、目錄、Reader、Flip、Quiz、Checklist、續讀完整。

### Persistence

- [ ] Account scoped。
- [ ] lastChapterId。
- [ ] quiz string choice ids。
- [ ] revision invalidation。
- [ ] corruption fallback。
- [ ] 刪帳清除。
- [ ] 登出切帳不互漏。

### Accessibility

- [ ] Color＋icon＋text。
- [ ] text scale 2.0。
- [ ] reduced motion。
- [ ] Semantics。
- [ ] 320px 無 overflow。

### Regression

- [ ] 24 篇文章不變。
- [ ] Article quota 不變。
- [ ] Coach learning links 不變。
- [ ] MainShell learning tab 不變。
- [ ] `flutter analyze` green。
- [ ] Targeted tests green。
- [ ] Full tests green。
- [ ] `git diff --check` green。

### Workflow

- [ ] 一 concern 一 commit。
- [ ] 繁中 commit。
- [ ] Review Packet 有 exact range。
- [ ] Codex＋GLM review 已 reconcile。
- [ ] 未經授權沒有 push／deploy／TestFlight。

---

## 19. 預期 changed-file manifest

### Assets

```text
assets/learning/ebooks/book_1_bottleneck.json
assets/learning/ebooks/book_2_conversation.json
assets/learning/ebooks/book_3_rescue.json
assets/learning/ebooks/book_4_meeting.json
pubspec.yaml
```

### Domain／data

```text
lib/features/learning/domain/models/ebook.dart
lib/features/learning/domain/models/ebook_block.dart
lib/features/learning/domain/models/ebook_progress.dart
lib/features/learning/data/repositories/ebook_catalog_repository.dart
lib/features/learning/data/repositories/ebook_progress_repository.dart
lib/features/learning/data/providers/ebook_providers.dart
lib/features/learning/data/providers/learning_providers.dart
```

### Presentation

```text
lib/features/learning/presentation/screens/ebook_detail_screen.dart
lib/features/learning/presentation/screens/ebook_reader_screen.dart
lib/features/learning/presentation/widgets/ebook_access_gate.dart
lib/features/learning/presentation/widgets/ebook_shelf_section.dart
lib/features/learning/presentation/widgets/ebook_shelf_card.dart
lib/features/learning/presentation/widgets/ebook_block_renderer.dart
lib/features/learning/presentation/widgets/ebook_dialogue_block.dart
lib/features/learning/presentation/widgets/ebook_flip_card.dart
lib/features/learning/presentation/widgets/ebook_quiz_card.dart
lib/features/learning/presentation/widgets/ebook_checklist_block.dart
lib/features/learning/presentation/screens/learning_screen.dart
lib/app/routes.dart
```

### Tests

```text
test/unit/features/learning/ebook_catalog_test.dart
test/unit/features/learning/ebook_content_invariants_test.dart
test/unit/features/learning/ebook_progress_repository_test.dart
test/unit/features/learning/ebook_progress_controller_test.dart
test/widget/features/learning/ebook_shelf_section_test.dart
test/widget/features/learning/ebook_detail_screen_test.dart
test/widget/features/learning/ebook_reader_screen_test.dart
test/widget/features/learning/ebook_flip_card_test.dart
test/widget/features/learning/ebook_quiz_card_test.dart
test/widget/features/learning/ebook_access_gate_test.dart
```

實際檔名可依現況微調，但超出 learning feature、routes、subscription read-only access helper、logout provider invalidation、pubspec 與測試的變動，都必須在 Review Packet 說明。

---

## 20. 明確不做

- 不新增 AI 生成。
- 不上傳真實聊天。
- 不新增 Supabase table。
- 不新增 Edge Function。
- 不做跨裝置同步。
- 不做 CMS。
- 不做 analytics／A/B test。
- 不做書籤、筆記、全文搜尋。
- 不做漏斗數字長期追蹤。
- 不做照片上傳健檢。
- 不做 drag／drop。
- 不做提案句產生器。
- 不改 RevenueCat。
- 不改文章額度。
- 不改既有 article id。
- 不重構整個 learning feature。
- 不新增封面圖片。
- 不 push／deploy／TestFlight，除非 Eric 另行明確授權。

---

## 21. 已關閉決策

- 來源真源：兩份新版教材。
- 變數：五標記 `V/F/E/I/R`。
- 產品：四本書、約二十章。
- 權限：Book 1 Free；Books 2–4 Starter／Essential。
- 額度：電子書不吃文章 quota。
- 閱讀：非線性。
- 儲存：加密 Hive、account scoped。
- Resume：chapter id，不是 index。
- Quiz：single＋multiple；retry policy 可配置，預設答錯可重試。
- Content：bundled JSON＋typed parser。
- UI：現有 Practice Hero 保留，電子書在文章前。
- 封面：品牌元件，不新增圖檔。
- 安全：尊重、互惠、同意與撤退是硬規則。
- Release：四本內容及夥伴審稿完成前，不宣稱公開 MVP 完成。

CC 不需要重新設計上述決策；若有實證衝突，帶證據回報 Eric。
