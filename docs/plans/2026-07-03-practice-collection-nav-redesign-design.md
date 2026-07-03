# 練習室導覽重構＋圖鑑 gacha 化 設計定稿（2026-07-03）

> 來源：Bruce dogfood 回饋＋Eric 拍板 intake；brainstorming 五題全數 Eric 定案。
> 範圍鐵則：**純 client UI 案**。migration／Edge／quota／RPC／翻牌 requestId 扣費鏈路零改動；翻牌儀式動畫本體不改，只搬掛載點。

## 新導覽鏈路

```
學習 tab 首頁 → 角色圖鑑（gacha hub）→ 練習室對話
```

## 定案清單

| # | 議題 | 定案 |
|---|------|------|
| 1 | 點已抽卡行為 | 有未完成對話 → `resumeSession` 續玩；沒有 → 新縫 `startSessionWithProfile(profileId)` 純 client 免費開新局（不算翻牌、不扣翻牌額度；聊天照常計費） |
| 2 | 換一位收法 | 只刪「為你抽了一位＋換一位」，難度 chips＋標準/新手切換原位留 |
| 3 | 每日 CTA 動線 | 全收斂圖鑑翻牌鈕；`_PracticeLockedEntry` 留兜底但翻牌 CTA 改「去圖鑑翻牌」導引 |
| 4 | 鎖卡剪影 | 近全黑保輪廓（亮度 5–8%）＋中央大「？」取代鎖頭；名字「？？？」／「每日翻牌解鎖」／無星等維持 |
| 5 | 翻完去向 | 留在圖鑑，新卡點亮＋捲動定位＋短暫高亮，使用者自己點卡進對話 |

## 各面改動

### 首頁（learning）

- hero 卡（`practice_room_entry_card.dart`）整卡含「每日登入就送新女孩」eyebrow 改 `push('/practice-collection')`。
- 移除右下 `PracticeCollectionEntryChip`。

### 圖鑑頁（`practice_collection_screen.dart`）

- 「Collection」標題右側加質感翻牌鈕（品牌漸層＋微光，配現有金橘 gacha 視覺）；今日未翻時脈動微光吸睛。
- 觸發同一個 `practiceChatControllerProvider.drawNewPracticeGirl()`；402/429 分流沿用現有文案行為。
- `PracticeDrawCeremony` overlay 從練習室 Stack **搬**到圖鑑頁 Stack（搬家非複製，避免雙播）。
- 點已抽卡＝進對話（定案 #1）；原「看大圖」由對話頁 profile sheet 承擔，圖鑑點卡單一心智。
- 鎖卡剪影照定案 #4；鎖卡 snackbar 提示維持。

### 練習室（`practice_chat_screen.dart`）

- 開場前控制列照定案 #2 收。
- `_PracticeLockedEntry` 照定案 #3 改導引。
- **Debrief 動作列**（`:1867` 附近）「換一位」也是翻牌觸發點 → 改「去圖鑑換人」導引，翻牌全收斂圖鑑。

### Controller 新縫（`practice_chat_providers.dart`）

- `startSessionWithProfile(profileId)`：查該角色最新可見 thread → 有就 `resumeSession`；沒有就純 client 設 state（girl 從 catalog 解析、`isRevealed=true`、messages 空、難度沿用偏好），不打 server。

## 邊界防護

1. **翻牌 draft 不被點卡開局覆寫**：draft（翻好未聊持久化）只由翻牌鏈路寫；`startSessionWithProfile` 不碰 draft 儲存。今日翻 A 未聊、跑去聊 B，A 仍是已解鎖卡可隨時點進。
2. **聊 A 中點卡 B**：controller state 替換；A 進度已由既有 session 持久化保住，之後點 A 卡續玩。不做離開確認彈窗。

## 測試計畫

- Controller unit：`startSessionWithProfile` 續玩/開新局分流、不寫 draft、不打 draw API。
- Widget：圖鑑翻牌鈕（含 402/429 分流）、鎖卡剪影 key、點卡路由、hero 卡新去向、兜底導引、控制列收法。
- 既有測試預期改行為：collection card tap（原 `showPracticeGirlFullPhoto`）、locked entry CTA。

## 備註

- SR/R/N 為 display-only 稀有度（`practice_girl_rarity.dart`），不影響機率/扣費/難度——已答 Bruce，本案不動。
- 需新 TF build 才能 dogfood。
