# 新單元《成為獎賞：魅力進階課》施工圖

> 2026-07-30 立案。狀態：**容器 SHIPPED，內容未開工**。
> Eric 已拍板：3 冊、Essential 專屬、不試讀、語氣重無所謂。
> 接手先讀這一份，**不要重新盤點 5.7MB 逐字稿**。

## 這是什麼

夥伴（Bruce）要把 Chris 的課程全集做成互動式課程，與既有《終極指引》並列，
合稱 Dating Knowledge Library。產品定位是「Game Coach」而不是市面上的「回話 AI」：
analyze-chat 與 Coach 說完結論之後，使用者能一步進到同一套語言的原理章節。

淺水區給結論，深水區給原理。

## 已完成（兩個 commit，都已 push 且 Build & Distribute success）

### `5655fdde` 教練解說接上 Dating Knowledge Library

三處入口深連電子書章節，全 client、server 一行未動：

| 入口 | 檔案 | 行為 |
|---|---|---|
| 本回合怎麼接 | `learning_link_resolver.dart` | 9 種 CoachActionType 各對一章 |
| 教練跟進三情境 | `coach_follow_up_section.dart` | 選了 chip 才出現 |
| 問教練一句五問句 | `coach_surface.dart` | 點了才出現，改掉問句就收起來 |

對照表在 `lib/features/learning/domain/dating_knowledge_links.dart`。
**目前全部指向終極指引 1–4 冊**；新單元上線後，內功層的題目（框架、需求感、
獎賞）要改指新單元。

**刻意不做**逐段深連（AI 推薦回覆的理由灰字）——Bruce 同意先不做。那行是模型
當場寫的，要連就得讓 Edge 多吐 `conceptKey`，代價是把 39 個概念的 taxonomy 寫進
system prompt、每次分析都付輸入成本，還多一個分類子任務跟寫回覆搶注意力。
**等術語表穩定再評估**，反過來做會邊做邊改。

### `29ecfc13` 書架單元 + Essential 權限容器

擋路的兩個硬規則已解掉：

1. 權限判斷照抄了 `isPremium`，而它是 `isStarter || isEssential`。Essential 專屬
   單元沿用會讓 **Starter 讀到整個單元**，而且沒有任何錯誤訊息。
2. catalog 用「全域位置」決定權限（`index == 0 ? free : premium`）。第二個單元一
   出現，它的第一本會被要求是免費書——破洞破在內容檔而不是程式碼裡。

一併加入 `EbookAccess.essential`、`Ebook.unit`、單元內書號從 1 起算、
`freePreviewChapterCount` 對 essential 恆為 0、付費牆文案分流、書架單元分隔列
（只有兩個單元以上才顯示）。

守門在 `test/unit/features/learning/ebook_essential_unit_test.dart`。

## 3 冊架構（Eric 已認可）

```
【流程線 · 照著做，把人約出來】   終極指引 1–4 冊，不動
【內功線 · 懂原理，不用照著做】   成為獎賞 1–3 冊，全新

  第1冊  內核 · 吸引到底是怎麼發生的   (~7章)
  第2冊  框架 · 這段關係誰在主導       (~6章)
  第3冊  進階聊天 · 結構模型與樣本     (~6章)
```

每冊維持 20–25 分鐘，跟終極指引同尺寸，書架看起來才是一套。

**交付節奏**：先做完第 1 冊給 Eric 與 Bruce 驗文風與互動密度，再用同一把尺做
第 2、3 冊。第一冊會定下整個單元的寫法骨架，定調錯了後兩冊會跟著歪。

## 第 1 冊章節骨架

| 章 | 標題方向 | 主要來源 | 狀態 |
|---|---|---|---|
| 1 | 你以為的原因，大概都不是原因 | 轉變2.0 吸引篇01、30天計劃 基礎篇01 | **已萃取** |
| 2 | 需求感不是要消除 | 轉變2.0 吸引篇02 | **已萃取** |
| 3 | 裝出來的價值撐不過見面 | 轉變2.0 吸引篇03/04、高階技術 學前引導1 | 待讀 |
| 4 | 情人與供養者 | 轉變2.0 關係篇02 | **已萃取** |
| 5 | 價值、能量、屬性 | 魅力原理 第三/四/七集 | 待讀 |
| 6 | 她要的是哪幾種感覺 | 魅力原理 第八/九集 | 待讀 |
| 7 | 雄性極性 | 曼森方法 內核篇02/05/06/07 | 待讀 |

### 章 1：限制性信念

**核心機制——大腦替錯誤信念找藉口的三段退守**：拿真實影片給人看，他會依序退守
「那是找演員演的」→（證明不是）「那是因為你長得帥」→（給他看不修邊幅也成功的）
「那是因為你那個城市比較開放」。面對無法解釋的事實，人寧可相信自己臨時編出來、
彼此矛盾的藉口——因為承認事實等於承認自己可以改變卻沒改變。
→ 適合做 `dialogue` 或三段 `comparison`。

**六條最常見的限制性信念**：
1. 我不帥所以女生不喜歡我（把長相當唯一變數）
2. 漂亮女生本來就該跟有錢人在一起（先幫對方做完決定）
3. 那麼快發生關係的女生比較隨便（用道德判斷迴避能力問題）
4. 我相信緣分，現在單身是緣分沒到（把被動包裝成信仰）
5. 我不需要有魅力，反正要找老實結婚的（放棄成長的藉口）
6. 年輕該拚事業，有錢自然有女人（反例：收入很高卻長期單身）

**共同結構**：每一條都把「我沒有行動」翻譯成「我不需要行動／行動也沒用」。
→ `checklist` 六條逐條勾「這條我有沒有」。

### 章 2：需求感（立場最鮮明，建議當樣板章）

**反主流主張**：市面上都說「不能暴露需求感」，這是錯的且有害。需求感是本能，
消不掉，你按下傳送鍵那刻它就在了。照著「完全不表達喜歡」做的人結果是**依然
得不到**，然後被歸咎到別的問題上。要控制的不是慾望，是**慾望有沒有奪走判斷力**。

**五種被需求感綁架的聊天行為**（★ 對聊天 App 直接可用，做 `entryList`）：

| 內在 | 在對話裡長什麼樣 |
|---|---|
| 貪 | 一天連發好幾則、她沒回又補一則、訊息越來越長 |
| 瞋 | 她慢回就冷處理／陰陽怪氣「看來你很忙」 |
| 癡 | 她說在忙還繼續發、把已讀當拒絕 |
| 慢 | 硬塞車錶餐廳出國照，把展示面當籌碼 |
| 疑 | 反覆問「你是不是不想理我」「我是不是很煩」 |

**判準**（做 `callout(principle)`）：說完之後，主導權還在不在你手上？
- ✅「我蠻想見你的，你這週有空再說」——表達了慾望，沒交出主導權
- ❌「你到底想不想見我」——把慾望變成對方要處理的情緒

### 章 4：情人與供養者（材料最厚，30KB）

**先破誤區**：把對象分類（拜金女／綠茶婊／好女人／我的真命天女不一樣）會讓你把
結果歸因到「對方是什麼人」，而不是「你們之間發生了什麼互動」。分類讓你停止學習。

**兩種擇偶策略**：供養者路線以生存資源為優先，先讓對方大量投資才推進；情人路線
以特質為優先，從眾多對象裡挑一個。

**被放在供養者位置的八個訊號**：肢體始終高度抗拒／關係推進被無限延長／坦然收下
付出且引導你投資更多／時間地點內容都由她安排／出現不合理要求／追很久發現是備選／
你始終被動／交往後莫名被劈腿。

**為什麼「對她好」會失效（機制，不是抱怨）**：社會、父母、朋友教的追求法——多關心、
送禮物、請客——**就是供養者策略本身**。用它等於跟她身邊所有供養者比拚物質，而規則
是出價最高者得，**結構上不可能贏**；就算暫時贏了，她選的是資源不是你。
這叫**邏輯選擇，不是吸引**。

**對聊天 App 的翻譯**（產品最需要的部分）：供養者行為在還沒見面時就看得出來——
秒回而她慢回你焦慮／有求必應／情緒勞動全你承擔／用資源開場而不是用互動／
一直問她要什麼卻從沒說過自己要什麼。

## 寫作規範（非常重要，接手不要放寬）

1. **一句原文都不能引用。** 來源是語音逐字稿，錯字極密：皮配率＝匹配率、
   EARO Scores＝Elo Score、自于自乐＝自娛自樂、况下＝框架、搭扇＝搭訕、
   共扬者＝供養者、一支性＝一致性、米南／迷難＝迷男。全部理解後重寫。
2. **拿掉所有素材出處的名字**（Bruce 要求）。`sourceRefs` 是 JSON metadata，
   grep 過整個 presentation 層**從來不渲染給使用者**，所以天然成立，只要保持
   欄位合法即可。
3. **不寫考試型內容**（Bruce 要求）。`quiz` block 目前用量為 0，維持。
   但 `flipCard`（先問後翻）、`dialogue`（逐句拆）、`comparison`（好壞對照）、
   `checklist` 不是考試，正好補互動感——終極指引 20 章 134 個 block 裡
   paragraph 佔 70 個，互動性其實不成立，新單元不要重蹈。
4. **不寫怨懟**。原始材料在關係篇帶明顯情緒（劈腿故事、名人例子、對女性的評價）。
   排除的理由不是道德，是**怨懟會讓讀者變差**：帶著「女人很現實」的框架去聊天，
   只會更防衛、更計較、更不吸引人，剛好違背這本書要做的事。保留結構洞察即可。
5. **App Review 紅線**：寫「怎麼判讀訊號、怎麼建立框架、怎麼推進」可以；
   寫「怎麼繞過對方明確拒絕」不行。這是 Guideline 1.1，是整個 App 下架等級的
   風險，不是改一篇文章的等級。原始材料有幾篇踩線（例如紅丸會員那篇談 MeToo 的），
   整篇排除。
6. **半形逗號**：終極指引現有內容把逗號寫成半形 `,`，是排版瑕疵。新單元用全形，
   順手的話也可以修舊的（另案）。

## JSON 契約（`ebook_catalog_repository.dart` 會直接丟例外）

新檔：`assets/learning/ebooks/book_5_core.json`，並加進
`EbookCatalogRepository.productionAssetPaths`（順序即書架順序）。

必要欄位：`schemaVersion`(=1) / `id` / `contentVersion` / `number` / `unit` /
`title` / `subtitle` / `goal` / `access` / `theme` / `estimatedMinutes` /
`sourceRefs`(不得為空) / `chapters`(不得為空)。

硬規則：
- `unit: "becomeThePrize"`、`access: "essential"`、`number` 在單元內從 1 起算
- 同一單元必須在 `productionAssetPaths` 裡**連續出現**
- **block id 與 entry id 全域唯一**（跨所有書），不能撞到既有 20 章。
  建議前綴 `ebook-5-*`
- `theme` 目前只有 `compass/lens/firstAid/bridge` 四個 key，新書要新主題就得
  同步 `_themeByName` 與 presentation 的查表
- `crossRef` / `stageFunnel` 的跳轉目標會被驗證，指到不存在的章節直接爆

block 型別：`heading` `paragraph` `bulletList` `callout` `comparison` `dialogue`
`flipCard` `quiz` `stageFunnel` `entryList` `crossRef` `checklist`。
各自必填欄位見 `_parseBlock`（約 `ebook_catalog_repository.dart:321`）。

## 材料範圍（256 檔，實際會用到約 90–100 檔）

| 領域 | 檔數 | 用途 |
|---|---|---|
| 內核／認知（紅丸法則、限制性信念、魅力原理、曼森內核） | ~37 | 第 1 冊 |
| 框架（軟硬框架、推拉、碰撞、防護罩、信念管理） | ~20 | 第 2 冊 |
| 高階聊天（軟體演算法、結構模型、四種樣本、升級、收尾） | ~15 | 第 3 冊 |
| 訊號解讀（窗口識別、女性分類、情緒雷達） | ~10 | 併入第 3 冊 |
| 線下搭訕（30天計劃、搭訕達人、現場實戰） | ~76 | **排除**，使用者不上街 |
| 約會現場／進挪／私密空間／速約 | ~10 | **排除**，超出範疇且踩線 |
| 冥想／覺醒者／世俗矩陣 | ~8 | **排除**，離定位太遠 |
| 案例逐字稿（實戰／私教／答疑） | ~80 | 當素材，不獨立成章 |

## 重建工作環境

```bash
# clone 課程 repo（scratchpad 是 session 專屬，換 session 要重來）
git clone --depth 1 -b claude/organize-courses-by-name-kh4z3h \
  https://github.com/chiang53610-droid/chris.git chris-courses

# 產生 256 檔的主題摘要（避免整份讀）
python3 - <<'PY'
import os,re
root='chris-courses'; lines=[]; cur=None
for dirpath,dirs,files in sorted(os.walk(root)):
    if '.git' in dirpath: continue
    for fn in sorted(files):
        if not fn.endswith('.md') or fn=='SUMMARY.md': continue
        d=os.path.relpath(dirpath,root)
        if d!=cur: cur=d; lines.append(f"\n### {d}")
        txt=open(os.path.join(dirpath,fn),encoding='utf-8',errors='replace').read()
        body=re.sub(r'\s+','',re.sub(r'^#.*\n','',txt).strip())
        lines.append(f"- {fn[:-3]} [{len(txt)//1000}k] :: {body[:110]}")
open('digest.txt','w',encoding='utf-8').write('\n'.join(lines))
PY
```

## 待決事項

- **免費使用者深連撞付費牆**：`EbookReaderScreen` 沒有 `lockedBuilder`，所以深連到
  全鎖章節會**自動 `push('/paywall')`**。`EbookDetailScreen` 有，程式碼註解寫明
  那是刻意的「不自動導 paywall，讓人先看得到內容目錄」。Eric 2026-07-30 決定
  **暫時維持現狀，等 Bruce 決策**。若要改，補 `lockedBuilder` 一處修改即可讓
  所有深連受惠。
- **第 2、3 冊的章節切法**尚未細化，等第 1 冊驗過再定。
- **Dating Knowledge Library 第二層（解說用語）**：讓 analyze-chat 與 Coach 在寫
  解說時就使用電子書的術語（框架、推拉、樣本、窗口、獎賞），這樣連結才形成
  library 而不是孤立按鈕。**必須等新單元內容定稿**，術語表要從書裡長出來。
