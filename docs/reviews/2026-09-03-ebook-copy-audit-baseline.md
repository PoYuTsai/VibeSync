# 電子書內容稽核基準

來源：`assets/learning/ebooks`　產生：2026-09-03 01:59 UTC

## 內容規模

| 冊 | 章 | 可見字串 | 可見字元 | ≥80 | ≥100 | ≥120 |
|---|---:|---:|---:|---:|---:|---:|
| ebook-1-bottleneck | 5 | 188 | 4123 | 11 | 4 | 0 |
| ebook-2-conversation | 5 | 299 | 6844 | 12 | 9 | 6 |
| ebook-3-rescue | 5 | 174 | 4761 | 10 | 7 | 6 |
| ebook-4-meeting | 5 | 187 | 4893 | 10 | 6 | 3 |
| ebook-5-core | 7 | 302 | 11852 | 51 | 32 | 16 |
| ebook-6-frames | 6 | 199 | 8942 | 42 | 30 | 22 |
| ebook-7-chat | 6 | 220 | 8259 | 32 | 19 | 12 |
| **合計** | **39** | **1569** | **49674** | **168** | **107** | **65** |

區塊 558、條目 130、前往按鈕 17。字元數含標點與空白；不含空白為 48810。

## 發現

| 規則 | 說明 | 筆數 | 分佈 |
|---|---|---:|---|
| R01 | 半形標點 | 431 | ebook-1-bottleneck 80、ebook-2-conversation 151、ebook-3-rescue 93、ebook-4-meeting 107 |
| R02 | 半形符號 | 57 | ebook-1-bottleneck 15、ebook-2-conversation 19、ebook-3-rescue 8、ebook-4-meeting 13、ebook-7-chat 2 |
| R03 | 行首行尾空白／連續換行 | 5 | ebook-2-conversation 2、ebook-4-meeting 3 |
| R04 | 單段欄位含雙換行 | 15 | ebook-4-meeting 1、ebook-5-core 4、ebook-6-frames 10 |
| R05 | 表格殘留「｜」 | 58 | ebook-1-bottleneck 12、ebook-2-conversation 6、ebook-3-rescue 9、ebook-4-meeting 31 |
| R06 | 欄位過長 | 64 | ebook-2-conversation 3、ebook-3-rescue 6、ebook-4-meeting 5、ebook-5-core 15、ebook-6-frames 21、ebook-7-chat 14 |
| R07 | summary 與內文重複 | 4 | ebook-1-bottleneck 1、ebook-3-rescue 1、ebook-4-meeting 2 |
| R08 | 簡體字／用字不一致 | 7 | ebook-3-rescue 3、ebook-7-chat 4 |
| R09 | 第 1 冊未定義代碼 | 8 | ebook-1-bottleneck 8 |
| R10 | 五變數 glossary 缺漏 | 5 | ebook-2-conversation 5 |
| R11 | 原課本指涉 | 35 | ebook-2-conversation 5、ebook-3-rescue 20、ebook-4-meeting 10 |
| R12 | 禁用詞 | 17 | ebook-2-conversation 1、ebook-4-meeting 1、ebook-5-core 2、ebook-6-frames 4、ebook-7-chat 9 |
| R13 | P0 定稿句缺漏 | 10 | — 10 |
| R14 | 結構契約 | 0 | — |

### R01 半形標點（431）

- `ebook-1-c1-b1` text：半形標點 ,×5　「如果你兩週只配對到 3 個人,就算對話技巧完美,天花板也」
- `ebook-1-c1-b2` text：半形標點 ,×5 :×1　「第二個觀念:失敗的基準率很高,這是結構」
- `ebook-1-c1-b3` text：半形標點 ,×1　「不用算數字。看下面五句話,點選最像你現況的那一層——」
- `ebook-1-c1-b5` text：半形標點 (×1 )×1 ,×3 :×1　「不改變任何做法,只記錄:A 配對數 / B」
- `ebook-1-c1-b7` items[1]：半形標點 ,×1　「黃燈維持,不加壓。最常見的失誤是把猶」
- `ebook-1-c1-b7` items[2]：半形標點 ,×1 ;×1　「模糊的是時間,不是對象。約會試探必須有具」
- `ebook-1-c1-b7` items[3]：半形標點 ,×1　「趣」。無法回傳這個答案的系統,會讓你在錯的地方越挖越深。」
- `ebook-1-c1-b8` text：半形標點 ,×2　「階段 0 的照片決定配對數,階段 1 的開場決定回覆率」
- …另 423 筆，見 JSON

### R02 半形符號（57）

- `ebook-1-c1-b5` text：半形符號 /　「何做法,只記錄:A 配對數 / B 開場後有回覆的 / 」
- `ebook-1-c2-tbl2-e4` entries[3].title：半形符號 /　「4. 興趣/活動」
- `ebook-1-c3-b1` text：半形符號 +　「有效結構:一句具體生活細節 + 一句幽默或自嘲 + 一個」
- `ebook-1-c4-b4` text：半形符號 +　「聊我:給狀態 + 感受。事實是零維的(只能」
- `ebook-1-c4-b7` text：半形符號 +　「【具體引用她的東西】+【你自己的一句狀態感受】+」
- `ebook-1-c4-cmp11-w` items[0].text：半形符號 /　「我這個人很複雜 / 你猜」
- `ebook-1-c4-cmp3-w` items[0].text：半形符號 /　「你好漂亮 / 你也喜歡爬山?」
- `ebook-1-c4-tbl5` title：半形符號 +　「事實版(死路)｜狀態+感受版(開口)」
- …另 49 筆，見 JSON

### R03 行首行尾空白／連續換行（5）

- `ebook-2-c5-lib-e3-fix3` text：行首或行尾有空白　「第 5 句的正確做法:接受她給的方向,換軌。⏎⏎ 男:好啦那就當你很無聊。無聊的」
- `ebook-2-c5-lib-e5-fix3` text：行首或行尾有空白　「修正:⏎⏎ 男:發生什麼事,是人的問題還是事的問題⏎⏎ 這個二選一同時做到三件事」
- `ebook-4-c2-warn8` text：行首或行尾有空白　「種子的唯一價值是通往具體提案。不會收成的種子田是浪費土地。種子對類型 A 有一個」
- `ebook-4-c3-grad9` text：行首或行尾有空白　「畢業標準(三項都要達到):⏎⏎ 你會在第二到三輪自然地種一個種子⏎ 你能正確讀出」
- `ebook-4-c4-lib-e5-warn2` text：行首或行尾有空白　「「改天約?」——改天不存在⏎ 「你什麼時候有空?」——把工作丟給她,還要她先承諾」

### R04 單段欄位含雙換行（15）

- `ebook-4-c4-lib-e3-b2` text：一個欄位塞了 3 段　「女:對啊我也一直想去欸⏎⏎男:那就這樣。週四晚上有空嗎,我先去排隊你直接來⏎⏎「」
- `ebook-5-c7-axis-1-p1` text：一個欄位塞了 2 段　「約束感不是別人給你的，是你自己給自己的。她問你「週末要不要出來？」，你腦袋先跑一」
- `ebook-5-c7-axis-1-p2` text：一個欄位塞了 3 段　「自在感是什麼？打字之前，你不會先跑一遍「她會怎麼評價我」。你先想的是「我想說什麼」
- `ebook-5-c7-axis-2-p1` text：一個欄位塞了 2 段　「負極長這樣：第一週就把工作、收入、感情史、你有多喜歡她，全部交代完畢。你變成透明」
- `ebook-5-c7-axis-2-p2` text：一個欄位塞了 3 段　「神秘感不是裝深沉、講話留一半吊人胃口。是三件事：留一部分不說，讓她想問；做決定不」
- `ebook-6-c2-p2` text：一個欄位塞了 4 段　「分法很直觀：意見不同的時候，你在維護誰？維護自己的立場、感受、底線，那是硬框架；」
- `ebook-6-c2-p3` text：一個欄位塞了 2 段　「兩種都重要，問題出在比例。很多人以為「對她好」是萬用解，什麼情況都配合、什麼要求」
- `ebook-6-c2-p4` text：一個欄位塞了 3 段　「這組概念還能解開一個困惑：條件明明很好的人，為什麼追誰誰不理？⏎⏎因為價值和價值」
- …另 7 筆，見 JSON

### R05 表格殘留「｜」（58）

- `ebook-1-c1-tbl6` items[0]：「｜」×1　「A. 配對數｜兩週內配對到幾個」
- `ebook-1-c1-tbl6` items[1]：「｜」×1　「B. 有回覆的｜你發第一則訊息,有回你的」
- `ebook-1-c1-tbl6` items[2]：「｜」×1　「C. 撐過五輪的｜一來一往五次以上還活著的」
- `ebook-1-c1-tbl6` items[3]：「｜」×1　「D. 你開口約的｜實際提出見面的」
- `ebook-1-c1-tbl6` items[4]：「｜」×1　「E. 答應的｜說好的」
- `ebook-1-c1-tbl6` items[5]：「｜」×1　「F. 真的到場的｜實際見到面的」
- `ebook-1-c1-tbl6` title：「｜」×1　「記錄項｜說明」
- `ebook-1-c2-tbl2` caption：「｜」×2　「位置｜功能｜常見錯誤」
- …另 50 筆，見 JSON

### R06 欄位過長（64）

- `ebook-2-c5-lib-e14-note2` text：calloutText 235 字，上限 160　「診斷:他在第 3 輪就拿到了綠燈,但沒有收。之後每一個種子的」
- `ebook-2-c5-lib-e3` entries[2].summary：entrySummary 43 字，上限 40　「關鍵判讀:當對方主動把自己描述得無趣、乖、無聊,那是在關閉這」
- `ebook-2-c5-lib-e8` entries[7].summary：entrySummary 43 字，上限 40　「為什麼有效:有具體理由(不是無來由的「在嗎」)、證明你記得她」
- `ebook-3-c1-warn2` text：calloutText 219 字，上限 160　「對照階段 2.6 的三燈訊號。如果是紅燈,結束。這是最常見也」
- `ebook-3-c2-lib-e1-b1` text：calloutText 194 字，上限 160　「流行說法:不要秒回,她隔多久你就隔多久,讓她覺得你很忙。⏎為」
- `ebook-3-c2-lib-e3-b1` text：calloutText 365 字，上限 160　「流行說法:不要在她表現之後就稱讚她,因為穩定的獎勵會消除她的」
- `ebook-3-c2-lib-e4` entries[3].summary：entrySummary 41 字，上限 40　「流行說法:提出你的標準(我喜歡有靈氣、會做飯的女生),讓她來」
- `ebook-3-c2-lib-e4-b1` text：calloutText 195 字，上限 160　「流行說法:提出你的標準(我喜歡有靈氣、會做飯的女生),讓她來」
- …另 56 筆，見 JSON

### R07 summary 與內文重複（4）

- `ebook-1-c5-lib-e8` summary：summary 與 ebook-1-c5-lib-e8-b1 內文相同　「她的 bio:「會做菜但只會做三道」」
- `ebook-3-c3-lib-e7` summary：summary 與 ebook-3-c3-lib-e7-b1 內文相同　「檢查三件事:」
- `ebook-4-c4-lib-e1` summary：summary 與 ebook-4-c4-lib-e1-b1 內文相同　「吃的」
- `ebook-4-c4-lib-e3` summary：summary 與 ebook-4-c4-lib-e3-b1 內文相同　「綠燈之後,直接把種子接完,不要重新開一個話題:」

### R08 簡體字／用字不一致（7）

- `ebook-3-c3-lib-e1` entries[0].title：「Line」應為「LINE」　「她很快就問你要 IG / Line」
- `ebook-3-c4-lib-e4` entries[3].title：「Line」應為「LINE」　「什麼時候轉到 Line / 通訊軟體?」
- `ebook-3-c4-lib-e4-b1` text：「Line」應為「LINE」　「軟體內的對話框衰減快。轉移可以降低衰減,但太早轉會失去情境。」
- `ebook-7-c1-p4` text：簡體字 温；「升温」應為「升溫」　「儀表板背後有一組更底層的東西：任何關係都由三個要素組成。第一」
- `ebook-7-c2-d1-l2` lines[1].annotation：「信號」應為「訊號」　「她開始追問了——好奇心啟動，這就是好的信號。」
- `ebook-7-c2-d1-l3` lines[2].annotation：「勾子」應為「鉤子」　「不急著約。留一個勾子，讓她記住你。」
- `ebook-7-c6-dlg1-2` lines[1].annotation：「信號」應為「訊號」　「她笑了、反駁了，但她沒有否認「見面」這件事——這就是你要的信」

### R09 第 1 冊未定義代碼（8）

- `ebook-1-c5-lib-e1-cmp1` caption：未定義代碼「V↑」　「V↑(有辨識力、有工作)E↑」
- `ebook-1-c5-lib-e2-cmp1` caption：未定義代碼「E↑」　「E↑(觀察 + 幽默),開口」
- `ebook-1-c5-lib-e3-cmp1` caption：未定義代碼「E↑」　「E↑(自嘲)、R↑(輕度的興」
- `ebook-1-c5-lib-e4-cmp1` caption：未定義代碼「V↑」　「V↑(有在動)、E↑(誇張化」
- `ebook-1-c5-lib-e5-cmp1` caption：未定義代碼「V↑」　「V↑(有夜生活、有文化消費)」
- `ebook-1-c5-lib-e6-cmp1` caption：未定義代碼「F↑」　「F↑(你在評估她,但是玩笑式」
- `ebook-1-c5-lib-e7-cmp2` caption：未定義代碼「E↑」　「的具體觀察(照片的共通性)、E↑(後半句的調侃)。開口:」
- `ebook-1-c5-lib-e8-cmp2` caption：未定義代碼「E↑」　「接住她的幽默並加碼(E↑),同時你也露了個性。這」

### R10 五變數 glossary 缺漏（5）

- `ebook-2-chapter-1` glossary#她投入多少（I）：缺少 glossary 名稱「她投入多少（I）」
- `ebook-2-chapter-1` glossary#聊天有沒有情緒（E）：缺少 glossary 名稱「聊天有沒有情緒（E）」
- `ebook-2-chapter-1` glossary#興趣回應（R）：缺少 glossary 名稱「興趣回應（R）」
- `ebook-2-chapter-1` glossary#誰在帶方向（F）：缺少 glossary 名稱「誰在帶方向（F）」
- `ebook-2-chapter-1` glossary#讓她認識你（V）：缺少 glossary 名稱「讓她認識你（V）」

### R11 原課本指涉（35）

- `ebook-2-c4-b3` items[1]：原課本指涉「見第六節」　「產生威脅反應 → 不用(理由見第六節)」
- `ebook-2-c5-lib-e10-note2` text：原課本指涉「階段 3.2」　「3. 在第 4 輪就約(課本階段 3.2:三到五輪)⏎4」
- `ebook-2-c5-lib-e2-note2` text：原課本指涉「階段 3.5」　「「表達興趣」的錯誤版本。課本階段 3.5 說要把興趣說出」
- `ebook-2-c5-lib-e4-fix3` text：原課本指涉「課本 6.1」　「為什麼那個建議是壞的(課本 6.1):⏎· 它想傳」
- `ebook-2-c5-lib-e4-xref1` label：原課本指涉「⚠ 6.1」　「⚠ 6.1 回覆時間操作」
- `ebook-3-c1-b3` text：原課本指涉「回到第一節」　「回到第一節重新算一次數字。你」
- `ebook-3-c1-b5` text：原課本指涉「階段 2.3」　「、生活內容是否足以支撐對話(階段 2.3)。這一層的問題」
- `ebook-3-c1-warn2` text：原課本指涉「階段 2.6」　「對照階段 2.6 的三燈訊號。如」
- …另 27 筆，見 JSON

### R12 禁用詞（17）

- `ebook-2-c5-lib-e13-dlg1-l5` lines[4].annotation#假定同意：禁用詞「假定同意」　「把她的建議當成已同意的前提(假定同意) · 「你下班幾點」
- `ebook-4-c4-lib-e3-b2` text#假定同意：禁用詞「假定同意」　「話當成已經同意的前提。這就是假定同意。」
- `ebook-5-c1-p2` text#聊什麼占 7 分：禁用詞「聊什麼占 7 分」　「你一個框架：你給別人的印象，聊什麼占 7 分，怎麼聊占 」
- `ebook-5-c6-bl1` items[2]#做流氓般的紳士：禁用詞「做流氓般的紳士」　「進的責任在你，不要等她主動。做流氓般的紳士，不要做紳士般」
- `ebook-6-c4-co1` text#代表她還在乎：禁用詞「代表她還在乎」　「是高能量的溝通。她在跟你吵，代表她還在乎、還願意跟你講。」
- `d1-l6` lines[5].text#跟你一樣短腿：禁用詞「跟你一樣短腿」　「嗯，我知道。柯基吧，跟你一樣短腿的那種。」
- `ebook-6-c6-p1` text#她冷的不是你：禁用詞「她冷的不是你」　「候，這層罩子根本不存在。所以她冷的不是你這個人，是「又一」
- `ebook-6-chapter-6` title#她冷的不是你：禁用詞「她冷的不是你」　「她冷的不是你，是「又一個追求」
- …另 9 筆，見 JSON

### R13 P0 定稿句缺漏（10）

- `catalog` canonical#一則訊息只能算線索：整套教材找不到定稿句「一則訊息只能算線索」
- `catalog` canonical#吵架不等於關係結束：整套教材找不到定稿句「吵架不等於關係結束」
- `catalog` canonical#問題不是穩定，而是整段互動只剩附和：整套教材找不到定稿句「問題不是穩定，而是整段互動只剩附和」
- `catalog` canonical#她明確答應後，再在一到兩輪內敲時間：整套教材找不到定稿句「她明確答應後，再在一到兩輪內敲時間」
- `catalog` canonical#她沒接，就換方向：整套教材找不到定稿句「她沒接，就換方向」
- `catalog` canonical#她說不行，就先接受：整套教材找不到定稿句「她說不行，就先接受」
- `catalog` canonical#妳可以的話，我就訂位：整套教材找不到定稿句「妳可以的話，我就訂位」
- `catalog` canonical#妳臨時有變再跟我說：整套教材找不到定稿句「妳臨時有變再跟我說」
- …另 2 筆，見 JSON
