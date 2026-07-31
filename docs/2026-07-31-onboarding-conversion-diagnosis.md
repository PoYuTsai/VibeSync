# VibeSync 上手體驗轉化診斷

> 2026-07-31 診斷報告。狀態：**僅診斷，未改動任何 runtime code / config**。
> 訪客模式（延後註冊）與分析埋點為策略選項／前置債，本次未實作。
> 對照框架：高轉化使用者上手體驗（Onboarding）策略架構，1,460 個產品案例分析。
> 所有 `file:line` 引用於 2026-07-31 於 `claude/vibesync-onboarding-optimization-6b44wy`
> （base `b85aa55`）實測驗證。

---

## 0. 一頁結論

三句話：

1. **VibeSync 的 onboarding 問題不是太長，是太空。** 五頁畫面沒有一頁讓使用者感受到產品能做什麼，
   全部是「用講的」。框架的核心洞見正是「流程長度並非轉化的敵人，缺乏價值的空洞流程才是」。
2. **能製造阿哈時刻的素材已經寫好，但是死碼。** `demo_conversation.dart` 有一份零 API 呼叫的
   完整示範分析（投入度 72、五種風格、最終推薦），`onboarding_page.dart` 也留好了 `customContent`
   插槽——插座與插頭都做好了，從來沒插上。
3. **個人化引擎接好了、能用、但沒人餵資料。** `effective_style_prompt_builder.dart` 真的會把
   「關於我」注入四個 AI 面的 prompt；但唯一入口埋在報告分頁頂端，而報告分頁對免費用戶整頁上鎖。
   結果是**新用戶看到的每一則 AI 輸出都是完全 generic 的**。

貫穿性問題：**專案沒有任何分析埋點**，因此以上每一項都無法量測、改完也無法證明有效。

---

## 1. 實測動線

新用戶從點開 App 到看到第一個 AI 產出的真實路徑：

```
Splash（硬寫死 3.5 秒，每次啟動都跑）
    app.dart:111-139、splash_screen.dart:136-161
  ↓
/login 硬牆——未登入時除了 /login 什麼都進不去
    routes.dart:52-54、initialLocation:'/login' (routes.dart:83)
    Email 註冊還要跳出 App 收驗證信才拿得到 session
    login_screen.dart:642-656
  ↓
/onboarding 第 1~4 頁：純 Material icon + 文案
    onboarding_screen.dart:33-59
  ↓
第 5 頁分流：「你現在有正在聊的對象嗎？」
    onboarding_screen.dart:198-269
  ↓
落 `/` → 自動被 push 到鍵盤設定 4 頁（按「略過」的用戶立刻中）
    app.dart:75-96
  ↓
建對象卡 → 建對話 → 貼文字 → AiDataSharingConsent 勾選同意框 → 分析
  ↓
第一個 AI 產出
```

### 代價

| 路徑 | 點擊數 | 其他成本 |
|---|---|---|
| 分析路徑（onboarding 主打的核心價值） | 約 11–13 次 | 2 次文字輸入 + 一趟 App 外信箱驗證，跨約 8 個畫面 |
| 練習路徑（最短） | 約 8 次 | 10 秒強制抽卡動畫，且**使用者必須自己寫第一句** |

練習室的 10 秒儀式是 `practice_draw_ceremony.dart:35`
（`kPracticeRevealDuration = Duration(milliseconds: 10000)`）；
無 AI 主動開場，空 `messages` 只渲染角色 hero（`practice_chat_screen.dart:221-228`）。

值得注意的錯位：**onboarding 花了 5 頁裡的 3 頁在賣「分析」，但分析是全 App 最長的路徑**；
最短的路徑（練習室抽卡）反而是側翼功能。

---

## 2. 七項對照診斷

### 2.1 阿哈時刻被鎖在註冊牆後面

> 框架對照：Alma 採取「延後註冊」，允許使用者在建立帳號前體驗核心功能。
> 「價值預支」降低進入門檻，讓使用者在支付註冊成本前就與產品建立連結。

VibeSync 目前是完全相反的設計：

- `initialLocation: '/login'`（`routes.dart:83`）
- `resolveAppRedirect` 第一條規則就是 `if (!isLoggedIn) return isLoginRoute ? null : '/login';`
  （`routes.dart:52-54`）——未登入時**除了登入頁什麼都進不去**
- Email 註冊需要離開 App 收驗證信才會產生 session（`login_screen.dart:642-656`）
- 全 codebase 搜尋 `signInAnonymously` / `isGuest` / `guestMode` / `trialMode`：**零命中**

也就是說，在使用者付出「註冊成本」——甚至是「跳出 App 收信」這種高流失動作——之前，
產品一句話都還沒證明自己。

登入頁本身也沒有承擔說服工作：只有 App 名、一句 tagline「截圖就能分析，五種風格教你回」、
社群登入按鈕與 Email 表單（`login_screen.dart:747-761`）。框架舉的 Superhuman 把註冊頁
設計成專業「推銷」、側邊放知名企業標誌作社會證明——VibeSync 的登入頁是純閘門，零社會證明。

### 2.2 現成的阿哈時刻 demo 是死碼——最便宜的修法

`lib/features/onboarding/data/demo_conversation.dart` 已經寫好一份**完全不用呼叫 API** 的示範：

- 3 則真實感對話（`欸你週末都在幹嘛` / `看情況欸 有時候爬山有時候耍廢` / `哇塞你也爬山！我最近去了抹茶山超美`）
- 投入度 72 分、`EnthusiasmLevel.hot`
- 五種風格回覆（延展／共鳴／調情／幽默／冷讀）全部寫好
- 最終推薦 + 推薦理由 + 心理解讀 + 策略 + 提醒

驗證：`grep -rn "DemoConversation" lib/` 扣除檔案自身後**零命中**。
它只被 `test/unit/onboarding_test.dart` 引用。

更明顯的是，`onboarding_page.dart:16` 定義了 `final Widget? customContent;`，
`:92-95` 的渲染分支註解寫著：

```dart
// Custom content (e.g., demo conversation)
if (customContent != null) ...[
```

**插座做好了、插頭做好了，從來沒插上。** 這個 widget 從未被傳入非 null 的 `customContent`。

這是整份診斷裡投入產出比最高的一項：**零 API 成本、零計費風險、零 Edge 改動、純 client**，
就能把 onboarding 從「用講的」變成「用演的」，並把阿哈時刻從第 11–13 步提前到第 3 步。

### 2.3 功能敘事而非成果敘事，且視覺是佔位級

> 框架對照：Timo 在歡迎畫面直接展示產品實際運作；Butts 透過精緻動畫讓使用者在讀文字前就直覺理解價值。
> 「當使用者看到成果而非功能時，他們是在為一個更好的自己買單。」

VibeSync onboarding 五頁**全部是 200×200 漸層圓盤 + Material 內建 icon**
（`onboarding_page.dart:47-67`、`:101-113`）：

| 頁 | 標題 | icon |
|---|---|---|
| 1 | 不知道怎麼回她？ | `Icons.favorite_border` |
| 2 | 即時看懂她的訊號 | `Icons.psychology_outlined` |
| 3 | 五種風格，選最對的那句 | `Icons.chat_bubble_outline` |
| 4 | AI 與你的隱私 | `Icons.privacy_tip_outlined` |
| 5 | 你現在有正在聊的對象嗎？ | `Icons.forum_outlined` |

`imagePath` 是誤導性欄位名——它只是 icon key，repo 內**沒有任何 onboarding 圖檔**。

文案其實寫得不差（「不知道怎麼回她？」是痛點導向、「對方這次的投入度 0-100 一目瞭然」是成果導向），
**問題純粹出在視覺沒有跟上文案**。說了「投入度 0-100 一目瞭然」，畫面上卻是一個愛心 icon。

諷刺的是素材其實有：`assets/images/coach/` 已經有品牌教練 **Sydney 的四種姿勢**
（greeting / thinking / tip / encouragement），而且**已經上線在首頁**
（近期 commit `1bf83f2`「固定首頁教練四姿勢顯示尺寸」、`4072f3d`「調整首頁教練隨對象數自適應定位」）。
第一印象用罐頭 icon，自家品牌角色反而只出現在使用者已經進來之後。

### 2.4 個人化引擎空轉——最可惜的一項

> 框架對照：Headspace 允許選多個目標，免費試用轉化率提升 10%。
> Speak 讓使用者先練口說，再用圖表證明「口說比閱讀更快達成目標」，並預測「兩個月後你能在法國流利對話」。
> 「個人化是數據蒐集與感知價值的平衡。」

**好消息：VibeSync 真的有個人化引擎，而且是好的。**

`lib/features/user_profile/domain/services/effective_style_prompt_builder.dart` 會把「關於我」的
互動風格、練習目標、話題種子、備註轉成 prompt 片段，並且針對四個 AI 面各自裁切：

- `buildForAnalysis`（900 字上限）
- `buildForOpener`（900）
- `buildForNewTopic`（900）
- `buildForCoachFollowUp`（500，刻意捨棄 notes/topics）

這不是裝飾，是真的進 prompt（server 端 `analyze-chat/index.ts:7457` 的 `styleContextInfo`、
`coach-chat/prompts.ts` 的「使用者風格設定」段落）。

**壞消息：沒有人餵它資料。**

1. **入口埋錯地方。** `AboutMeCard` 在全 codebase 只出現一次：
   `lib/features/report/presentation/screens/my_report_screen.dart:79`——報告分頁頂端。
   而報告分頁**對免費用戶整頁上鎖**（`:81-82` `if (subscription.isFreeUser) _lockedReportCard(context)`，
   鎖定文案 `:215`「我的報告會在 Starter 解鎖」）。
   驅動所有 AI 個人化的資料，被放在新免費用戶幾乎不會抵達、抵達了也是看到付費牆的地方。

2. **onboarding 收集零個人化資料。** 前四頁是靜態文案。第 5 頁問了
   「你現在有正在聊的對象嗎？」——這是全流程**唯一**一個個人化訊號——
   但答案**只拿來決定跳哪一頁，沒有存進任何地方**（`onboarding_screen.dart:89-95`
   只呼叫 `markCompleted()` 然後導頁）。問出口的訊號被丟掉了。

3. **空 profile 直接短路。** profile 為空時四個 builder 一律 `return null`
   （`effective_style_prompt_builder.dart:62, 112, 164, 198`），
   server 端 `styleContextInfo` 變空字串，coach 的「使用者風格設定」段落被整段濾掉。

**結論：新用戶看到的每一則 AI 輸出都是完全 generic 的**，
儘管 About Me 卡片對使用者承諾「AI 會參考這些設定調整建議語氣」。

4. **練習室永遠不個人化。** `supabase/functions/practice-chat/prompt.ts` 搜尋
   `userProfile` / `effectiveStyle` / `interactionStyle` / `practiceGoal`：**零命中**。
   練習室只注入陪練角色的 persona，完全不看使用者是誰。

5. **無「預見價值」機制。** 框架裡 Speak 的圖表證明、Endel/BitePal 的「解鎖後個人化計畫」預覽、
   Grammarly 依測驗結果推薦定製方案——VibeSync 目前完全沒有對應物。
   使用者填了「關於我」之後，沒有任何畫面告訴他「因為你選了 X，所以建議會變成 Y」。

### 2.5 摩擦的位置放錯：牆在價值之前，不是之後

> 框架對照：House 拆分表單使轉化率提升 15%；Focus Flight 把付費牆設計成飛機票，
> 配合震動與列印音效；Grammarly 依測驗回答推薦定製定價，升級率提升近 20%。

**先講對的地方：付費牆沒有在 onboarding 出現。** 全流程沒有任何 onboarding → paywall 的推送，
唯一的自動 push 是 iOS 鍵盤擴充回傳 quota 超限訊號時（`app.dart:66-70`）。這點是正確的。

**但功能性上鎖（feature lock）繞過了 `docs/snapshot.md` 自己訂的 Free 鐵則。**
鐵則寫的是「Free users must be able to try core features until quota is exhausted」，
而額度本身其實很寬鬆（30/月、15/日，`supabase/functions/_shared/quota.ts:18-28`）。
問題是有些牆不是額度用完才出現的：

| 上鎖點 | 位置 | 問題 |
|---|---|---|
| 報告分頁對免費用戶整頁上鎖 | `my_report_screen.dart:81-82, 215` | 3 個 tab 之一，**用 0 次就撞牆** |
| 練習室免費每日僅第一抽免費，第二抽直接 paywall | `practice_collection_screen.dart:229-263` | 最短價值路徑，第二次就撞牆 |
| Opener 免費永遠只見 5 種風格中的 3 種 | `opener_access.dart:20-25` | 且固定扣 3 則額度（`opening_rescue_screen.dart:255`） |

尤其報告分頁：它同時是「關於我」的唯一入口（見 2.4），所以這道牆不只擋住報告，
還連帶擋住了個人化資料的收集入口。

**額度本身在首頁完全不露出。** 使用者要進到特定功能內部才知道自己有 30 則。
框架講的「戰略性摩擦能篩選高價值用戶」的前提是使用者知道自己在花什麼——目前不知道。

**感官設計只用在一個地方。** 全 App `HapticFeedback` 僅出現在**練習抽卡儀式**
（`practice_draw_ceremony.dart`，全 codebase 共 3 處呼叫，集中在這一個檔案），
那裡還另外配了 whoosh / chime / reveal bed 音效（`assets/audio/practice_draw/`）。

**團隊明顯做得出 Focus Flight 等級的感官設計，只是沒有用在兩個最該用的地方：**
付費牆（`paywall_screen.dart` 1,398 行，零 haptic、零音效），
以及**分析結果落地的那一刻——也就是真正的阿哈時刻**。

### 2.6 情感連動素材齊全，但沒用在流程裡

> 框架對照：BitePal 讓使用者為虛擬寵物浣熊命名建立情感連結；One year 加入創始人手寫信；
> Mural 放棄彈出式橫幅改用「六步驟清單」，使一週留存率相對提升 10%。

VibeSync 的情感素材是足的：

- Sydney 教練四種姿勢（`assets/images/coach/`）
- 練習室 100 張角色圖鑑 + 稀有度 + `0/100 收藏完成度` 進度條
- 抽卡儀式音效與震動

但 **onboarding 流程本身**沒有任何：創始人訊息、進度清單、角色陪伴、心理投資機制。
Sydney 不出現在 onboarding；沒有「你已完成 X/Y」；沒有 Mural 式的六步驟清單。

首頁空狀態在案 3（`docs/plans/2026-07-06-case3-cold-start-branching-design.md`）之後
有兩顆 CTA（`partner_list_screen.dart`），但那是**分岔路口，不是清單**——
它讓使用者選一條路，而不是讓使用者看見「還有幾步就完成設定」。

### 2.7 權限與平台：一好、兩壞

> 框架對照：iOS 上手流程平均比網頁長 21%，主因是權限請求。
> Brilliant 與 Center 採取「權限預熱」策略，Center 甚至預告使用者將收到的通知內容。

**好的一項：通知權限預熱做得對，而且是教科書等級。**

第一次對象分析完成後才出現軟性徵詢卡（`soft_opt_in_card.dart`，
由 `analysis_screen.dart` 在首次對象綁定分析完成時觸發）：

> 要我提醒你跟進嗎？👀
> 跟{name}的對話剛分析完。想要的話，我可以在 48 小時後提醒你回來看看下一步、主動出擊。
> 〔幫我提醒〕〔不用〕

這正是框架講的 Center 式預熱——**先預告使用者會收到什麼內容，再請求授權**，
而且時機挑在使用者剛感受到價值之後。這一項不需要改。

**壞的第一項：主線 OCR 的相片權限沒有預熱。**
點「截圖開始」直接跳系統框（`image_picker_widget.dart` 內的 `ImagePicker`）。
諷刺的是鍵盤那條支線反而做了雙重預熱（先 AI 資料同意、再相片權限，
`keyboard_setup_screen.dart:322-348`）。**主線比支線草率。**

**壞的第二項：鍵盤設定 4 頁的觸發時機與平台判斷都有問題。**

- 觸發：使用者第一次停在 `/` 時自動 push（`app.dart:75-96`）。
  按「略過」想快點進 App 的使用者，反而**立刻被丟進 4 頁鍵盤設定**——
  想要更少畫面，得到更多畫面。
- 平台：`_scheduleKeyboardOnboarding` 的條件式**沒有任何 `Platform.isIOS` 判斷**
  （已驗證 `app.dart` 未 import `dart:io`、無任何 `Platform.` 呼叫），
  但頁面文案與 deep link 是 iOS 專屬的（`keyboard_setup_screen.dart:30` `app-settings:`、
  `:425`「到 iPhone 設定開啟『VibeSync 鍵盤』」）。
  Android 用戶會看到一個對他們無效的流程。
  （實務衝擊有限——目前發布主線是 TestFlight/iOS——但這是潛在缺陷，不是設計決策。）

**文化面補充**：框架提到東方市場偏好資訊高密度、西方偏好極簡。
VibeSync 的 TA 是繁體中文使用者，但 onboarding 五頁每頁只有一句標題 + 兩行說明，
資訊密度偏低。這不必然是錯的，但值得對照 TA 重新評估——
尤其框架指出金融/健康/教育這類需要高信任度的產品，**適度的複雜能轉化為信任**，
而「AI 約會教練」在信任門檻上更接近這一類，而非 AI 工具類的「快速讓位」。

---

## 3. 貫穿性前置債：零埋點

`pubspec.yaml` 內**沒有 firebase_analytics、PostHog、Mixpanel、Amplitude、Segment——一個都沒有**
（已驗證，零命中）。全 codebase 只有兩個檔案出現 analytics 字樣，且都不是漏斗埋點。

意思是：**上面每一項診斷目前都無法用數據驗證，改完也無法證明有效。**

這不是新發現，`docs/plans/2026-07-06-post-review-optimization-roadmap.md` 案 6 自己就寫了：
耗時 telemetry「只存記憶體、debug 才看得到」「正式版完全看不到用戶真實等多久」，
並建議「先把現成 telemetry 落地上報，拿到真實分佈再決定攻哪段」。

**建議定位：這是做任何轉化優化之前的前置條件，不是可有可無的加分項。**
沒有它，Tier 1/2 的每一項都只能靠直覺與 dogfood 體感判斷成效。

實作路徑上有一個避開隱私清單問題的選項：不引入第三方 SDK，
沿用現有的 `submit-feedback` / `ai_logs` 通道自建漏斗事件——
這也是案 1 已經在用的模式，可避免動 `PrivacyInfo.xcprivacy` 與隱私政策揭露。

---

## 4. 建議優先序（僅建議，本次未實作）

### Tier 1｜零風險、純 client、可立刻進下個 build

| # | 項目 | 說明 |
|---|---|---|
| 1 | **把 `DemoConversation` 接進 `customContent` 插槽** | 零 API 成本、零計費風險。把 onboarding 從「用講的」變「用演的」。投入產出比最高。 |
| 2 | **Material icon 換成 Sydney 四姿勢 / 真實產品畫面** | 素材已在 repo 且已上線首頁，等於零素材成本。 |
| 3 | **第 5 頁分流答案存成 profile 種子** | 目前唯一的個人化訊號被丟掉。存下來就能讓第一次 AI 呼叫不是完全 generic。 |
| 4 | **鍵盤 onboarding 補 `Platform.isIOS` 判斷 + 延後觸發** | 兼修 Android 潛在缺陷，並移除「按略過反而看更多畫面」的反效果。 |

四項都不碰 auth gate、不碰計費、不碰 Edge、不碰 migration。

### Tier 2｜中低風險，需要設計取捨

| # | 項目 | 說明 |
|---|---|---|
| 5 | **「關於我」搬進／串進 onboarding** | 個人化引擎目前完全空轉。注意：這不改 prompt 邏輯，只是把已接好的資料管線餵飽。 |
| 6 | **首頁露出額度與 Coach/Opener 入口** | 目前首頁是 CRM 清單；Coach 1:1 沒有自己的 route，Opener 沒有首頁入口。 |
| 7 | **主線 OCR 相片權限預熱** | 對齊已經做得很好的通知預熱模式。 |
| 8 | **Mural 式進度清單取代／補強首頁空狀態** | 框架實證：一週留存相對 +10%。 |

### Tier 3｜需 Eric 產品決策

| # | 項目 | 說明 |
|---|---|---|
| 9 | **報告分頁對免費用戶的上鎖策略** | 這道牆同時擋住了個人化資料入口，且與 snapshot 的 Free 鐵則精神有張力。屬定價/商業模式決策。 |
| 10 | **付費牆感官設計 + 依 onboarding 回答的個人化定價** | 團隊已有抽卡儀式的技術能力，只是沒用在這裡。框架實證 Grammarly +20%。 |
| 11 | **Splash 3.5 秒** | 每次啟動都跑、不 await 任何工作、純裝飾。屬品牌決策。 |

---

## 5. 策略選項：延後註冊／訪客模式（本次不實作）

框架裡槓桿最高的一項，也是 VibeSync 最貴的一項。

**收益**：讓使用者在建立帳號前先體驗核心功能，把「註冊成本」推遲到價值已被感知之後。
以 VibeSync 的情況，這能一次解決 2.1（阿哈時刻被鎖在牆後）與 2.2（demo 死碼）背後的同一個病根。

**代價清單**（動它必須全部處理）：

- `resolveAppRedirect` 的 auth gate 與 `test/unit/app/redirect_matrix_test.dart` 的完整矩陣
- Supabase anonymous auth 啟用與 session 生命週期
- RevenueCat `appUserId` 從匿名到具名的遷移（誤處理會影響訂閱歸屬）
- Hive owner-scoping：目前多處以 `ownerUserId` 分區（如 `profile:<uid>`），匿名帳號的資料歸屬
- 帳號合併：匿名期間產生的對象卡、分析紀錄、額度使用如何併入正式帳號
- 額度歸屬與濫用防護：匿名帳號可否消耗 Free 額度、重裝是否重置

**風險定位**：`docs/snapshot.md` 的 Active Risk Areas 明列 auth 為高風險區，
且專案正處於 App Review readiness stabilization。**建議排在過審之後獨立成案並走雙審**，
不建議與其他 onboarding 優化混在同一批改動裡。

**低成本替代方案**：在不動 auth gate 的前提下，Tier 1 的第 1 項
（把 demo 接進 onboarding）其實已經捕捉了「價值預支」的大部分心理效果——
使用者仍需註冊，但**在註冊之後、投入真實資料之前**就先看到產品能做什麼。
建議先做這個，量測效果，再決定要不要付訪客模式的全額代價。

---

## 6. 順手發現的技術債

| 項目 | 位置 | 說明 |
|---|---|---|
| `DemoConversation` 死碼 | `lib/features/onboarding/data/demo_conversation.dart` | 僅 `test/unit/onboarding_test.dart` 引用 |
| `OnboardingPage.customContent` 從未使用 | `onboarding_page.dart:16, 92-95` | 上者的插座 |
| onboarding 旗標是**裝置層**而非帳號層 | `onboarding_service.dart:5` | 對比 `AiDataSharingConsent` 有 `::userId` 後綴、`UserProfileRepository` 用 `profile:<uid>`。同一台裝置的第二個帳號會完全跳過 onboarding |
| 鍵盤 onboarding 無平台判斷 | `app.dart:75-96` | 無 `dart:io` import、無 `Platform.` 呼叫；頁面文案為 iOS 專屬 |
| `AppConstants.freeConversationLimit` 等 3 個常數定義後無人讀取 | `app_constants.dart:28-30` | `starterConversationLimit`、`essentialConversationLimit` 同 |
| `OnboardingService.reset()` / `resetKeyboard()` / `isCompleted()` 無 production 呼叫者 | `onboarding_service.dart:33-38, 48-52, 60-64` | 測試用 affordance |

---

## 7. 框架 Diagnostic Checklist 逐題作答

**Q1. 你的產品前十個畫面中，使用者感受到「阿哈時刻」了嗎？**

**沒有。** 前十個畫面是：Splash、登入、onboarding ×5、鍵盤設定 ×4（或建對象卡流程）。
第一個 AI 產出出現在第 11–13 次點擊之後。
最諷刺的是，**能在第 3 個畫面就交付阿哈時刻的素材已經寫好了，但是死碼**。

**Q2. 嘗試拆分長表單，並在關鍵節點注入感官愉悅。**

VibeSync 沒有長表單問題（「關於我」已經是分段選擇式）。
真正的問題是**感官愉悅只用在一個地方**——練習抽卡儀式。
付費牆 1,398 行零 haptic 零音效；分析結果落地——真正的阿哈時刻——也沒有任何感官標記。
**團隊有這個能力，只是用錯地方。**

**Q3. 不要只蒐集數據，要用圖表向用戶證明這些數據如何為他們服務。**

VibeSync **連蒐集都還沒做到**。onboarding 收集零個人化資料；
唯一問出口的訊號（有沒有對象）被丟棄；「關於我」的入口埋在對免費用戶上鎖的分頁裡。
在能談「用圖表證明」之前，得先讓資料真的被收到。
引擎（`effective_style_prompt_builder.dart`）已經是好的，缺的是輸入端。

**Q4. 在流程中加入「人類觸感」或遊戲化元素。**

**素材齊全，但沒用在 onboarding。** Sydney 四姿勢、100 張角色圖鑑、
`0/100 收藏完成度`、抽卡儀式——這些都在，但都在使用者已經進來之後。
onboarding 本身零情感連結、零進度感、零角色陪伴。

**Q5. 動態調整深度：高專業度工具強化教育流程；AI 工具考慮快速讓位。**

VibeSync 目前**兩邊都不是**：它有 AI 工具的極簡畫面數（5 頁），
卻沒有 AI 工具「快速讓位、直達功能」的短路徑（需 11–13 步才有產出）。

按框架的分類邏輯，「AI 約會教練」的信任門檻更接近金融/健康/教育類——
**使用者要交出私密對話，這需要信任，而信任來自有價值的引導深度**，
不是來自把畫面數壓到最少。目前的 5 頁靜態文案既沒有短路徑的爽快，
也沒有深度引導的信任建立。這是最需要 Eric 拍板的方向性選擇。

---

## 附錄：本報告未涵蓋的範圍

- 未做任何 runtime code / config 改動
- 未跑 `flutter analyze` 或測試（零改動，不適用）
- 未部署 Edge Function、未執行 migration
- 未觸發 `Build & Distribute`
- 未新增分析套件
- 訪客模式僅列策略選項與代價清單，未產出實作設計檔
