以下結論僅依 packet；未執行程式或檢查未提供的檔案。

## 九項判定

| # | 判定 | 結論 |
|---|---|---|
| 1 | ISSUE | 已確認為 Free 時 deep link 會被擋；但「尚未確認且殘留 premium tier」會直接放行 Books 2–4。P1 |
| 2 | ISSUE | 閘門判斷順序可能閃出內容；書架更會把 loading/error 直接呈現成「訂閱解鎖」並導 paywall。P1 |
| 3 | PASS | 提供的電子書路徑只使用 settings box，沒有呼叫 `ArticleReadService` 或文章額度 key。 |
| 4 | ISSUE | 非同步寫入跨帳號完成時沒有 owner/generation 驗證，存在 A snapshot 發布到 B 畫面的競態。P1 |
| 5 | ISSUE | Quiz revision 有處理，但 `contentVersionSeen` 只寫不比較，內容改版後舊完成、checklist、答案可能繼續有效。P2 |
| 6 | ISSUE | block/schema/必填欄位大致 fail closed，但 catalog 未驗證「總共二十章」，部分不可信進度也會被寬容接受。P2 |
| 7 | PASS | 三燈及 Quiz 均同時使用文字、圖示、語意標籤，不只靠顏色。 |
| 8 | UNCERTAIN | 提供的 Book 3 樣本明確反操弄，但無法用一章代表四本書全部內容。 |
| 9 | UNCERTAIN | 路由看起來互不衝突、article/Coach 檔案也未列為修改，但 packet 沒有 24 個 ID 與 Coach deep-link 的回歸證據。 |

## Critical

沒有從 packet 證明的 P0 問題。

## Important

### 1. 未確認的 premium 狀態會被當成已授權

嚴重度：P1

精確證據：

```dart
if (subscription.isPremium) return EbookAccessDecision.allowed;
if (subscription.isResolving) return EbookAccessDecision.resolving;
if (subscription.hasError) return EbookAccessDecision.unavailable;
```

`isPremium` 的優先序高於 `isResolving` 與 `hasError`。而 `EbookSubscriptionAccess.fromState` 允許三者同時為真，`SubscriptionState` 也沒有禁止 `tier=starter` 搭配 `isLoading=true` 或 `error != null`。

可重現情境：

1. 帳號原本是 Starter，或本機仍保留 Starter tier。
2. App 正在刷新訂閱，或刷新失敗；實際 entitlement 尚未確認，甚至已經降為 Free。
3. 直接開啟 Book 2 deep link。
4. `EbookAccessGate` 呼叫 premium builder，付費內容立即建立。

這同時推翻 focus 1 與 focus 2 的絕對保證。

驗證步驟：

- 對 `ebookAccessFor` 加矩陣測試：
  - premium + resolving
  - premium + error
  - premium + resolving + error
- 三者都應不得回傳 `allowed`。
- Widget test 需確認 premium child 從未被 build。

### 2. 書架把技術錯誤包裝成 Free upsell

嚴重度：P1

精確證據：

```dart
bool ebookLockedFor(...) =>
    ebookAccessFor(...) != EbookAccessDecision.allowed;
```

因此 `resolving` 和 `unavailable` 都變成 `locked=true`。接著書架顯示：

```dart
label: '訂閱解鎖'
```

點擊行為則是：

```dart
if (locked) {
  context.push('/paywall');
}
```

可重現情境：

- 訂閱 provider 回傳 `isLoading=true`，或 `error != null`。
- Books 2–4 顯示為「訂閱解鎖」。
- 使用者點擊後直接進 paywall，而不是 loading 或可重試錯誤。

這與 packet 所述「無法確認時不把技術錯誤包裝成 Free upsell」直接矛盾。

驗證步驟：

- 分別以 resolving、unavailable 建立 `EbookShelfSection`。
- 斷言不出現「訂閱解鎖」、不導航 paywall，且 error 狀態提供重試。

### 3. 帳號切換期間可能發布錯誤 owner 的 snapshot

嚴重度：P1

精確證據：

```dart
final owner = await _ownerOrNull();
...
_publish(await repository.markChapterCompleted(ownerUserId: owner, ...));
```

而 `_publish` 只檢查：

```dart
if (_disposed) return;
state = AsyncData(snapshot);
```

snapshot 本身不帶 owner，也沒有比較「完成寫入時的 owner」和目前 Supabase account id。`ebookProgressOwnerProvider` 又明確支援在同一 provider 生命週期中接收 auth stream 變化。

可重現情境：

1. A 開始一筆延遲的 Hive 寫入。
2. 寫入完成前 auth stream 切換至 B，controller 開始載入 B。
3. A 的 Future 隨後完成。
4. `_publish(A snapshot)` 無法辨認 owner，可能將 A 的完成度發布到目前 B 的 UI，至少造成短暫閃現。

此外，`EbookQuizCard.didUpdateWidget` 只在 quiz id/revision 改變時 restore，並不處理同一題的 `savedState` 因帳號切換而改變，也增加保留 A 答案的風險。

驗證步驟：

- 使用可控制完成時機的 fake Box。
- A 啟動寫入後發出 B auth event，再完成 A 寫入。
- 每個 pump 都斷言 B 畫面從未出現 A 的章節、Quiz 或 checklist 狀態。
- 另測同一 quiz/revision 的 `savedState` 從 A 狀態改成 null 時，卡片必須清空。

### 4. `contentVersion` 沒有實際失效語意

嚴重度：P2

精確證據：

- `contentVersionSeen` 會由 `setLastChapter`、`markChapterCompleted` 寫入。
- `load`、`ebookBookProgressProvider`、`isChapterCompleted`、`checkedItemsFor`、`quizStateFor` 都沒有比較目前 book 的 `contentVersion`。
- 新版本第一次閱讀時，`setLastChapter` 只是覆寫版本號，舊的 completed、quiz、checklist 全部保留。

可重現情境：

1. 儲存 Book v1 已完成章節及 checklist。
2. 同一 chapter/block id 的內容在 v2 被實質改寫。
3. App 載入 v2。
4. 舊章仍顯示「已完成」，舊 checklist 仍勾選；若 quiz revision 漏升，舊答案也繼續呈現。
5. 使用者換章後，`contentVersionSeen` 被更新為 2，舊狀態的來源資訊也失去。

Quiz revision 本身處理正確，但 book-level content version 沒有處理策略。

驗證步驟：

- 建立 `contentVersionSeen=1` 的完整進度，再以同 ID、`contentVersion=2` 的書渲染。
- 明確斷言預期的遷移／失效行為。
- 再確認只有 quiz revision 改變時，舊答案確實不被 restore。

### 5. 寫入失敗會留下假成功或卡死 UI

嚴重度：P2

精確證據：

`_completeChapter` 沒有 `try/finally`：

```dart
setState(() => _saving = true);
await ...markChapterCompleted(...);
setState(() => _saving = false);
```

Hive 寫入若拋錯，按鈕會維持 saving，錯誤也未轉成可重試狀態。

Quiz 則先更新本機 UI，再呼叫未 await 的保存 callback：

```dart
setState(() {
  _submitted = true;
  _solved = solved;
});
widget.onSubmit(...);
```

閱讀器中的 callback 呼叫 async controller，但沒有等待或錯誤處理。使用者可能看到「答對了／已理解」，實際上答案沒有保存。

驗證步驟：

- 讓 fake Box 的 `put` 拋例外。
- 完成章節後應解除 loading 並顯示重試。
- Quiz/checklist 不得在保存失敗後永久呈現已保存狀態。
- 測試中不得留下 unhandled asynchronous error。

### 6. Catalog 沒有執行二十章不變量

嚴重度：P2

精確證據：

`_validateCatalog` 驗證非空、book number/access、重複 ID，但沒有檢查：

```text
books.length == 4
sum(book.chapters.length) == 20
```

預設 `productionAssetPaths` 確實固定四個檔案，因此四本較有保障；但把任一 JSON 刪成較少章，只要仍非空，runtime parser 就會接受。

驗證步驟：

- 建立四本結構合法、總共十九章的 catalog。
- `load()` 目前應會成功；依產品不變量應 fail closed。
- 同樣測試二十一章及缺少預期 book id 的情況。

## Minor

### Retry 重設沒有保存

嚴重度：P3

精確證據：

```dart
void _reset() {
  setState(() {
    _selected = <String>{};
    _submitted = false;
    _solved = false;
  });
}
```

沒有通知 controller 清除先前保存的錯誤答案。

可重現情境：

1. 答錯並保存。
2. 點「再試一次」。
3. 尚未重新提交便離開、讓 widget 被回收，再回到題目。
4. 舊的錯誤 submission 又被 restore。

驗證步驟：

- 執行上述導覽流程，斷言重試狀態不會回彈；或明確定義 retry 只是暫時 UI 狀態並加入對應測試。

## Uncertain

### 教材調性只能驗證所附樣本

Book 3 第 3.5 章的證據是正面的：反覆明示「提高對方表達真實意願的成本」不可接受，並要求明確拒絕立即停止、模糊回應不算同意。Book 4 安全 callout 也清楚區分見面與其他親密同意。

但 packet 沒有提供其餘十九章全文，無法排除其他章把相同技巧改名後當成正向策略。

需要的證據：

- 四份 JSON 的完整人工調性審查。
- 搜尋「突破阻力、消除拒絕理由、撤退再升級、讓對方證明自己」等操作性指示，再逐段判讀上下文。

### 24 篇文章與 Coach deep link 缺少回歸證據

正面證據是：

- 變更清單沒有 `articles_data.dart` 或 Coach 實作檔。
- 電子書使用獨立 `/learning/books/...` 路徑。
- 既有 `/learning/articles/:id` 路徑沒有在 diff 中被修改。

但列出的測試沒有明確的 article-ID snapshot、24 篇數量或 Coach「看教學」路由測試，也沒有實際測試輸出。

需要的證據：

- 斷言文章數仍為 24。
- 對既有 article id 做固定 snapshot。
- 逐一觸發 Coach「看教學」入口，確認解析至相同文章。
- 提供測試命令、exit code 與結果，而不只是測試檔名。

### settings box 是否真的加密

程式只證明使用 `StorageService.settingsBox`；實際 box 建立及 cipher 設定未提供。註解不能證明 at-rest encryption。

需要檢查 `StorageService` 初始化程式及一個確認 raw Hive 檔案不含明文進度的測試。

## 看起來正確的部分

- 在狀態明確為 Free、沒有 stale premium 的情況下，detail 與 reader deep link 都經過 `EbookAccessGate`，premium builder 不會建立。
- 電子書進度 key 使用 Supabase user id，拒絕空 owner，沒有使用 email 或 anonymous 共用 key。
- repository 將 read-modify-write 序列化，可防同一 repository 內的快速操作互相覆蓋。
- Resume 保存及解析均使用 chapter id，而不是 index；未知 chapter 也有安全 fallback。
- Quiz 使用 stable choice id 和 quiz revision，revision 不符時正常視為未作答；預設 retry policy 是 `untilCorrect`，並非寫死首答鎖定。
- 提供的電子書流程沒有碰文章額度 service 或 usage-box key。
- Content parser 對未知 block type、未知 enum、缺少必填欄位、重複 ID、非法 quiz 正解數及未知 schema version均會拒絕載入。
- 三燈、死亡點、Quiz 正誤及章節完成狀態都有文字與圖示；不是只靠紅黃綠。
- 所附反操弄與安全教材樣本立場清楚，沒有把降低拒絕能力重新包裝成正向技巧。
