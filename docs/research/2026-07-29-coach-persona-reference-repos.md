# Coach 1:1 擬人化：可參考的開源專案研究

> Status: research only（不含實作計畫，不改 runtime）
> Date: 2026-07-29
> Scope: 「問教練一句」升級成擬人形象 AI assistant 的外部參考來源盤點
> Related: `docs/plans/2026-05-07-spec6-coach-1on1-design.md`、`docs/plans/2026-04-30-vibesync-memory-coach-roadmap.md`

---

## 0. 結論先講

這題的重點不是「找一個 AI girlfriend repo 抄過來」。原因有兩個：

1. **VibeSync 已經有一套完整的擬人引擎，在 Practice 裡。** `supabase/functions/practice-chat/`
   底下的 `practice_persona.ts`（1189 行）、`life_schedule.ts`、`relationship_thread.ts`、
   `consistency_prompt.ts`、`time_context.ts` 已經做到多數 AI girlfriend 專案在做的事：
   人格 allowlist、作息與場景、關係溫度與熟悉度、主動小測試、時間感。
   Coach 要擬人化，第一順位是**內部復用**，不是外部移植。

2. **Coach 的擬人化和 Practice 的擬人化，是兩個不同的問題。**
   Practice 要的是「像一個真實的陌生女生」。Coach 要的是「像一個記得你的人、有判斷、有立場、
   會追蹤你上次有沒有去做」。前者靠人格模擬，後者靠**記憶連續性與敘事一致性**。
   所以最該讀的參考不是 AI girlfriend 類，是 **agent memory 類**。

因此下面把參考專案分成四類，並標出各自對應 VibeSync 的哪一個缺口。

---

## 1. 現況盤點（code evidence）

### 1.1 Coach 現在長什麼樣

`supabase/functions/coach-chat/prompts.ts:53` 的 `SYSTEM_PROMPT_BASE` 開頭是：

> 你是 VibeSync Coach 1:1：有記憶、有邊界、有真實社交經驗的 AI 約會教練。

觀察到的特徵：

| 面向 | 現況 |
| --- | --- |
| 身分 | **沒有名字、沒有性別、沒有形象**。是一個 role，不是一個人 |
| 輸出 | 結構化 JSON（`headline` / `answer` / `userTruth` / `nextStep` / `suggestedLine` / `boundaryReminder`）→ 前端渲染成卡片 |
| 互動 | 單輪 Q&A + 最多 3 次免費釐清（`clarification_policy.ts`），本質是**表單式問答**，不是對話 |
| 記憶 | 有 context 注入（`recentMessages` / `conversationSummary` / `analysisSnapshot` / `effectiveStyleContext` / `partnerHint` / `outcomeInsightLines`），但**沒有跨 session 的教練自我狀態** |
| 進入點 | `coach_surface.dart:230` 的「問教練一句」卡片，掛在分析頁裡 |
| 計價 | `coachAnswer` 扣 1 則，`clarifyingQuestion` 不扣 |

**擬人化的四個缺口**：
1. 沒有 identity（叫什麼、什麼口吻、什麼立場）
2. 沒有跨 session 連續性（教練不記得「上次我叫你去做什麼」）
3. 沒有主動性（永遠等使用者發問）
4. 輸出是卡片不是人話（`answer` 360 字上限 + 6 個欄位，讀起來像報告）

### 1.2 內部已有、可直接復用的資產

| 檔案 | 做了什麼 | 對 Coach 擬人化的用途 |
| --- | --- | --- |
| `practice-chat/practice_persona.ts` | persona / difficulty / profile 的 server-side allowlist，client 只送 id | **人格定義的安全模式**，Coach 形象應照抄這個邊界設計 |
| `practice-chat/life_schedule.ts` | 由伺服器時間 + profile 推導場景，無 DB state | 教練的「此刻狀態」可用同樣的 deterministic 手法 |
| `practice-chat/relationship_thread.ts` | 記憶摘要 + 溫度 + 熟悉度 + 階段 | 教練與使用者的關係階段（新手 / 熟客 / 老朋友） |
| `practice-chat/consistency_prompt.ts` | 主動小測試的類型與傾向 | 教練的主動追問 / 回訪機制 |
| `coach_follow_up/` + `follow_up_notification/` | 已有追蹤與通知骨架 | 主動關心的既有管道，不用重造 |
| `coaching_memory/` | `coaching_outcome_digest` / `outcome_event` | 已經在記「建議有沒有被採用、結果如何」，這是擬人化最貴的一塊，已經有了 |

---

## 2. 參考專案分類

### A. 人格定義與可攜格式（persona definition）

解決的問題：**怎麼把一個角色寫下來、存起來、注入 prompt**。

| Repo | Stars | 值得看什麼 |
| --- | --- | --- |
| [SillyTavern/SillyTavern](https://github.com/SillyTavern/SillyTavern) | 31.3k | 這個領域的事實標準前端。重點看 **World Info / Lorebook 的關鍵字觸發注入**：不是把所有設定塞進 system prompt，而是依使用者訊息命中關鍵字才注入對應片段。對 VibeSync 直接可用 —— 社交知識庫依情境注入，而不是常駐 |
| [character-card-spec-v2](https://github.com/malfoyslastname/character-card-spec-v2) / v3 | — | 角色卡欄位設計：`description` / `personality` / `scenario` / `first_mes` / `mes_example` / `system_prompt` / `post_history_instructions` / `character_book`。**`post_history_instructions` 很關鍵**：放在對話歷史「之後」的指令，用來對抗長對話的人格漂移 |
| [kwaroran/Risuai](https://github.com/kwaroran/Risuai) | 1.6k | character card v3 的主要實作者，TypeScript，比 SillyTavern 好讀 |
| [elizaOS/eliza](https://github.com/elizaOS/eliza) | 18.8k | character file + plugin 架構，TypeScript。多 agent、多平台（Discord/Telegram）的人格一致性做法 |

> 對 VibeSync 的取捨：character card 格式**不要照搬**。那套是為「使用者自帶角色卡」設計的，
> VibeSync 的教練形象應該是產品資產、server-side 固定，走 `practice_persona.ts` 的 allowlist 模式。
> 要借的是**欄位切分方式**與 **lorebook 的條件式注入**。

---

### B. 記憶架構（agent memory）← 最該投資的一類

解決的問題：**怎麼讓 AI 真的記得你，而不是每次重新讀 context**。

| Repo | Stars | 值得看什麼 |
| --- | --- | --- |
| [letta-ai/letta](https://github.com/letta-ai/letta)（原 MemGPT） | 24.0k | **最直接對應 Coach 缺口**。三層記憶：core memory（常駐 prompt 的可編輯 block）/ archival memory（向量庫，agent 自己搜）/ recall memory（完整訊息history）。核心洞見是 **memory blocks 常駐、且 agent 用 `memory_replace`、`memory_rethink` 自己改寫**。Coach 的「這個使用者是誰、他反覆卡在哪、我上次派了什麼作業」就該是一個 core memory block |
| [mem0ai/mem0](https://github.com/mem0ai/mem0) | 62.0k | 這領域星數最高。抽取式記憶（從對話抽 fact 再存），API 簡單。適合當「怎麼設計 memory API」的參考 |
| [memodb-io/memobase](https://github.com/memodb-io/memobase) | 2.8k | **概念上最貼 VibeSync**。明確為 companion app 設計，用 **structured user profile（topic / sub_topic / content）取代純向量 RAG**，例如 `psychological.goals`、`interest.games`。加上 event timeline 與 buffer zone。VibeSync 的 About Me + Partner Style + coaching outcome 本質就是這個結構，可以拿它驗證自己的 schema 切法 |
| [getzep/graphiti](https://github.com/getzep/graphiti) | 29.3k | 時序知識圖譜，記憶帶時間邊（fact 何時成立、何時失效）。對「她三個月前說忙，現在還算不算數」這種判斷有用，但對 VibeSync 現階段偏重 |
| [MemMachine](https://github.com/MemMachine/MemMachine)、[oceanbase/powermem](https://github.com/oceanbase/powermem) | 3.3k / 0.8k | 後起的同類，可當 API 設計對照組 |

> **建議讀的順序：Letta 的 memory block 概念 → memobase 的 profile schema → mem0 的 API 形狀。**
> 三個看完就夠了，不需要引入任何一個當依賴（都是 Python，VibeSync 是 Deno Edge Function）。
> 要的是架構觀念，落地應該自己寫在 Supabase Postgres 上。

---

### C. 陪伴體驗與形象呈現（embodiment / companion UX）

解決的問題：**怎麼讓它看起來、感覺起來像一個「在的人」**。

| Repo | Stars | 值得看什麼 |
| --- | --- | --- |
| [moeru-ai/airi](https://github.com/moeru-ai/airi) | 45.2k | 目前最完整的 self-hosted companion，TypeScript。Live2D / VRM、即時語音、記憶、多平台。要看「一個完整的擬人系統有哪些模組」，看這個 |
| [Open-LLM-VTuber](https://github.com/Open-LLM-VTuber/Open-LLM-VTuber) | 12.9k | Live2D + 免手動語音互動 + 可打斷。跨平台本地執行 |
| [duixcom/Duix-Mobile](https://github.com/duixcom/Duix-Mobile) | 8.2k | **行動端** real-time digital human，宣稱 <1.5s 延遲、可地端部署。VibeSync 是 iOS App，這是這一類裡少數直接談行動端延遲的 |
| [uezo/ChatdollKit](https://github.com/uezo/ChatdollKit) | 1.2k | Unity / VRM，把 3D 模型變成 chatbot |
| [jofizcd/Soul-of-Waifu](https://github.com/jofizcd/Soul-of-Waifu) | 0.9k | Live2D/VRM + 語音 + 本地 LLM 的桌面 roleplay app |
| [Lynpoint/CyberVerse](https://github.com/Lynpoint/CyberVerse) | 1.5k | WebRTC voice-first agent + persona memory + RAG |
| [DasterProkio/awesome-ai-companion](https://github.com/DasterProkio/awesome-ai-companion) | 0.3k | **策展清單，先讀這個省時間**。分類完整：frontends / memory & identity / voice & embodiment / **proactive messaging & heartbeats** / shared activities。其中 proactive messaging 那一類（`astrbot_plugin_proactive_chat`、`dylan-heartbeat`、`revive-companion` 的 Poisson process 外聯時機引擎）對應 VibeSync 已有的 `coach_follow_up` / `follow_up_notification`，值得對照 |
| [proj-airi/awesome-ai-vtubers](https://github.com/proj-airi/awesome-ai-vtubers) | 0.5k | AI VTuber 策展清單 |

> **建議：這一類先不要動。** avatar / 語音 / Live2D 是擬人化裡**最貴、最容易做、也最不解決真問題**的一層。
> Coach 的問題不是「沒有臉」，是「不記得你、不追蹤你、講話像報告」。先做 B 類，C 類最後再說。

---

### D. 中文情感與角色扮演（語言與語感）

解決的問題：**中文語境下的共情表達與角色一致性**，這是英文 repo 幫不上忙的部分。

| Repo | 值得看什麼 |
| --- | --- |
| [thu-coai/CharacterGLM-6B](https://github.com/thu-coai/CharacterGLM-6B)（EMNLP'24） | 清華 COAI 的中文角色定制。**重點是它怎麼拆解 persona 維度**（屬性 attributes + 行為 behaviors），以及怎麼評 consistency / human-likeness / engagement。這三個評估維度可以直接拿來當 Coach 形象的驗收指標 |
| [scutcyr/SoulChat](https://github.com/scutcyr/soulchat) | 中文心理健康對話大模型，百萬級中文心理諮詢長文本 + 多輪共情對話。**共情表達的中文語料與句式**參考 |
| [SmartFlowAI/EmoLLM](https://github.com/SmartFlowAI/EmoLLM) | 心理健康大模型全流程開源（資料集、微調、評測、部署、RAG）。有角色扮演版與**男友心理諮詢師版**，與 VibeSync 的定位有重疊，值得看它的資料設計與邊界處理 |
| [CLUEbenchmark/SuperCLUE-Role](https://github.com/CLUEbenchmark/SuperCLUE-Role) | **中文原生角色扮演評測基準**。如果 Coach 要有形象，需要一套回歸測試防人格漂移，這是現成的評測維度來源 |
| [choosewhatulike/trainable-agents](https://github.com/choosewhatulike/trainable-agents)（Character-LLM） | 角色扮演 agent 的訓練方法論 |
| [OFA-Sys/Ditto](https://github.com/OFA-Sys/Ditto) | 角色扮演 self-alignment + benchmark |

> 注意：這些多半是**簡體中文**語料與繁體語感有落差，VibeSync 是繁中產品。
> 借的是方法（維度拆解、評測設計），不是語料。

---

## 3. 對應到 VibeSync 缺口的四個具體機制

| 缺口 | 參考來源 | 落地形狀（概念，非實作計畫） |
| --- | --- | --- |
| 沒有 identity | character-card-spec 的欄位切分 + `practice_persona.ts` 的 allowlist 模式 | 教練形象 server-side 固定，client 不送任何 prompt 文字。欄位至少切出：口吻、立場、不做什麼、開場白 |
| 沒有跨 session 連續性 | **Letta memory blocks** + memobase profile slots | 一個常駐的「使用者理解 block」，內容是教練對這個人的判斷（反覆卡點、風格、上次派的作業），每輪可被覆寫。這比再加 context 欄位更接近「記得」 |
| 沒有主動性 | awesome-ai-companion 的 proactive messaging 類 + 既有 `coach_follow_up` | 教練回訪：上次的 `nextStep` 有沒有做、結果如何。`coaching_memory/` 已經在收這個資料 |
| 輸出像報告 | SoulChat / CharacterGLM 的共情句式；character card 的 `post_history_instructions` | 保留結構化欄位供前端使用，但**新增一層對話化表層**；用 post-history 指令對抗長對話的語氣漂移 |

---

## 4. 風險（做這題之前必須先有答案）

1. **產品定位衝突（最大的一個）**
   VibeSync 已經有 Practice —— 一個模擬真實女生的擬人系統。
   如果 Coach 也擬人化到有形象、有性格、有陪伴感，兩者會在使用者心裡糊在一起。
   更糟的是，教練的價值來自**權威與距離**（他敢說「這局不值得，停手」），
   擬人化過頭會讓教練變成同溫層陪聊，直接損害 `SYSTEM_PROMPT_BASE` 裡辛苦建立的收斂能力。
   → **需要先定義：Coach 的擬人化上限在哪。** 建議是「有名字、有口吻、有記憶、有立場」，
   但**沒有私生活、沒有情緒需求、不談自己**。

2. **App Review 風險**
   VibeSync 目前正在 App Review readiness 階段。AI companion 類目的審核敏感度高於工具類，
   尤其涉及擬人形象 + 成人約會內容時。現在的 Coach 定位是「工具/教練」，改成「陪伴角色」
   可能改變審核類別的判定。→ 這是 Eric 的產品決策，不是技術決策。

3. **人格漂移（persona drift）**
   長對話中角色會慢慢偏離設定，這是已知且有論文在研究的問題（見 arXiv 上的
   persona drift detection 相關研究）。character card 的 `post_history_instructions`
   就是社群對這問題的土砲解法。→ 若要做，需要配一套回歸測試（SuperCLUE-Role 的維度可參考）。

4. **成本與計價模型衝突**
   現在是 `coachAnswer` 扣 1 則、`clarifyingQuestion` 免費。
   擬人化 = 鼓勵多輪閒聊 = token 成本上升，但閒聊在現行規則下**不扣費**。
   → 擬人化前必須先想清楚計價，否則直接炸 API 成本。這是 AGENTS.md 標的高風險區。

5. **依賴性（parasocial）**
   Dating coach 的成功指標是「使用者去跟真人互動了」，不是「使用者留在 App 裡跟教練聊天」。
   AI companion 的留存機制與這個目標**方向相反**。借鑑 companion repo 的互動設計時，
   要主動剔除那些為了拉高 session 時長而設計的機制。

---

## 5. 建議的最小切入順序

若要往下走，建議順序（**不從 avatar 開始**）：

1. **先定義擬人化上限**（產品決策，Eric）— 教練是誰、不是誰
2. **記憶連續性**（Letta memory block 概念）— 讓教練記得上次派的作業，`coaching_memory/` 已有資料
3. **對話化表層** — 保留現有 JSON 欄位，加一層人話輸出
4. **主動回訪** — 復用 `coach_follow_up` / `follow_up_notification`
5. **形象呈現（名字 / 頭像 / 語音）** — 最後，而且要先過 App Review 風險評估

前 4 步都不需要引入任何外部依賴，也不需要改 Practice。

---

## 6. 一句話版本

> 該讀的是 **Letta（記憶架構）+ memobase（profile schema）+ SillyTavern 的 lorebook（條件式注入）
> + CharacterGLM/SuperCLUE-Role（中文角色一致性評測）**；
> 該抄的是 **VibeSync 自己的 `practice-chat` persona 引擎**；
> 該避開的是 **AI girlfriend 那套為留存設計的陪伴機制，以及先做 avatar 的誘惑**。
