# 簡易搭訕流程詳解｜夜市製作定稿 v2

使用者已核准主劇本；反應分支為本次製作細化。素材尚未生成、聲線尚未選定，未接進 App。

內部來源：第 11 集研究與 Eric 的逐項修訂。本稿為夜市改編。以相鄰 JSON 為逐句製作來源，不沿用舊版台詞或音軌。

## 固定要求

- Chris alone says 有點突然。 No 對吧 added to this line; pause 1000–2000ms then continueintro withoutwaitingconfirmation.
- Exact intro is locked, polite RIGHT handextendsduringname; handshakebranches preservefaceandwardrobe.
- Strong eyecontact, weightback, fallingintonation throughout; nofixedstare/noartificialdrone.
- Pottery is past life sample; do not materialize pottery cup at tea stall.
- Leah beverage starts as orderticket and arrivesonlywithpickupaction; cups/hands/phones cannot teleport.
- Allspokenlines nonlooping, ambience separate and no intelligible recurringdialogue.
- Review based actualvisitedbeats/choices; no universalpositivefeedback or attraction score.
- No legacy audio assigned to new text, no subtitle timing estimates treated as final.

## 逐鏡與分支

### stroll

Native9:16 first-person walking. Sydney right/front, real Taiwan night-market crowd; stop at craftgiftstall. Leah not yet introduced.

**Sydney：**等我一下，我看一下這個。

接續：notice。

### notice

Gaze turns to tea counter. Adult Leah holds orderticket, looks at menu. Sydney notices player's pause, leans nearer withoutgrabbing.

**Sydney：**想認識她？（表演：quiet friend aside; halfbeat）

**Sydney：**先吐口氣。三、二、一，走過去。

> **接近**
> 別在腦中排演整段對話。走到她看得到的側前方，停穩，再開口。

玩家選擇：

- 走到她看得到的側前方 → approach
- 先繼續逛夜市 → walk_ending


### approach

Voluntary walk sidefront, do notblockpickup lane. Stopconversationaldistance,stableeyelevel,weightback.

接續：opening。

### opening

Leah raisesheadafterhi, slightlysurprised. Creamtopandearringsmustmatchreference. Normalblinks, directeyecontact; noforcedlaugh.

**Chris：**嗨。

**Chris：**剛剛看到妳，覺得妳這件米白色上衣配這個耳環，蠻好看的。

**Leah：**喔，謝謝。（表演：slightlysurprised, processing; notflirty）

> **淺溝通**
> 重心往後、尾音下沉、強眼神溝通。清楚說出你的觀察，不急著索取反應。

接續：empathy_intro。

### empathy_intro

Chris says empathy statement, pause1–2s thencontinueswithoutwaitingconfirmation. Extend relaxedrighthand DURING name, darklongsleeve identityreference; handnotreachtowardSydney. No added 對吧.

**Chris：**有點突然。（表演：statement; fallingtail; 1500ms pause thencontinue）

**Chris：**我跟朋友來買東西，剛在那邊等她。看到妳，想過來打個招呼。你好，我叫 Chris。

> **同理心陳述｜處理安全感**
> 突然被陌生人搭話，會有戒心很正常。說出她可能的感受，停一拍，再接著說。

> **背景介紹**
> 交代你為什麼在這裡，讓她對你的出現有脈絡。

反應分支：default → handshake_accept；handshake_declined → handshake_nohand；hands_full → handshake_full。

### handshake_accept

Leahacceptsrighthand; briefgentlehandshakeandrelease, nointerlockedfingers.

**Leah：**我叫 Leah。

**Chris：**Leah。

接續：transition。

### handshake_nohand

Leahanswersnamewithouttakinghand. Chrisnaturallywithdraws,maintainseyecontact, doesnotexplainorrequestagain.

**Leah：**我叫 Leah。

**Chris：**Leah。

接續：transition。

### handshake_full

Leahhandsoccupiedwithorderandbag; Chrisnoticesandretractswithoutmakingherjuggle. No handshake.

**Leah：**我叫 Leah。

**Chris：**Leah。

接續：transition。

### transition

Normalconversation, mildsmile; frienddirectionconsistent. Nojokepunchlinedelivery.

**Chris：**妳今天自己來逛？

**Leah：**跟朋友，她還在那邊買吃的。

**Chris：**那我們現在都在等人。

接續：cold_read。

### cold_read

Chrisobservesstylewithoutscanningbody. Leahcanagreeorcorrect.

**Chris：**妳看起來蠻會挑這種小東西的，應該不太喜歡跟大家買一樣的。

> **冷讀**
> 給出你的觀察與猜測，不只是問資料。看看她怎麼認同、修正或補充。

反應分支：default → craft_entry；cold_read_wrong → cold_read_repair。

### cold_read_repair

Leahcorrects;Chrisacceptscorrection, noautomaticrejectionexit.

**Leah：**沒有欸，我買東西蠻隨便的。

**Chris：**喔，那我猜錯了。我剛看妳搭配，還以為妳會很挑。

**Leah：**我比較喜歡看人家做東西，自己也有去上陶藝。

接續：craft_expand。

### craft_entry

Leahwarmingthroughowninterest, nophysicalpotterypropsat teastall.

**Leah：**也沒有啦，我只是蠻喜歡逛手作的。

**Chris：**妳是喜歡逛，還是自己也會做？

**Leah：**我有去上陶藝課，但做得不怎麼樣。

接續：craft_expand。

### craft_expand

Listen,norapidquestions. Leahnaturallyaddsfriendcontext.

**Chris：**妳還真的自己下去做。

**Leah：**朋友找我去的，後來覺得蠻好玩。

> **展開話題**
> 問問題可以，但不要一直問。接住她的生活片段，也透露一點你自己的東西。

玩家選擇：

- 分享一小段自己的經歷，留個鉤子 → life_hook
- 繼續問上课時間和地點 → question_repair


### question_repair

Notmoralpunishment; briefanswerthenplayergetsrepairchoice.

**Chris：**妳在哪裡上？上多久了？

**Leah：**附近一間工作室，才幾堂。

> **問答修復**
> 她回答完了。現在讓她也看到你一點，不必再接下一份資料。

玩家選擇：

- 接回自己的相關經歷 → life_hook
- 自然道別 → early_bye


### life_hook

Ordinarypersonalstory; stopafterhook, calmeyecontact, notexpectantgrin.

**Chris：**我之前也去過一次。原本只是陪朋友，結果最後是我不肯走。

> **生活／個性樣本＋留白**
> 每次透露一點自己的經歷與特質，留下可追問的鉤子。勾起她的好奇，讓她逐步了解你、猜測你的生活與價值。

反應分支：default → hook_followup；no_hook_question → hook_no_question。

### hook_followup

Leahcurious, selfinitiatedquestion; slightchangefrominitialpoliteness.

**Leah：**為什麼？

接續：personality。

### hook_no_question

Leahnodding, doesn'taskwhy. Chrisdoesnotdemandcuriosityorendautomatically.

**Leah：**喔。

**Chris：**做那個真的比看起來難。

**Leah：**對啊，我那個把手重做了三次。

接續：ordinary_chat。

### personality

Answerjusthook. Owntrait notCVorstatusboast.

**Chris：**杯口一直歪。我平常很多事情都隨便，但自己想做好的東西，就會突然很龜毛。

**Leah：**我也是，我那個把手重做了三次。

接續：ordinary_chat。

### ordinary_chat

Sustainedeyecontact,naturalblinks;ordinarycontent,Leahsmilesandasks. Noforcedjokeorcontinuousgiggles.

**Chris：**那妳有把它拿回家用嗎？

**Leah：**有啊，不然很浪費。

**Chris：**我那個也還留著，但我朋友每次看到都要講一下。

> **強眼神溝通**
> 接住她的目光。不急著想下一句，也不因為她看回來就把視線移開。

接續：second_hook。

### second_hook

Lightbanter, not seductivewhisper.

**Leah：**到底是多醜？

**Chris：**下次給妳看。

> **觀察情緒**
> 內容不必多幽默。留意她有沒有笑、怎麼笑，以及是否繼續參與。

接續：qualify。

### qualify

Groundedappreciationafterher3attempts.Noextraunrelatedcompliments.

**Chris：**不過妳那個把手願意重做三次，蠻有耐心的。

**Leah：**我就是不喜歡做一半。

**Chris：**這點我蠻欣賞的。

> **賦格**
> 肯定她已經展現的特質。她先讓你看到一點自己，你再給出真實、具體的欣賞。

反應分支：default → highpoint_wrap；busy → busy_notice；available → available_notice；decline → decline。

### highpoint_wrap

SharedtopicendswhileLeahstillengaged. Chrisrelaxedturnslightlytowardfriendnotwalkawaystunt.

**Chris：**好，那妳先忙吧，我也回去找我朋友。

**Leah：**好啊。

> **無興趣指標｜主動收尾**
> 聊得好的時候，也能結束這一輪。不用一直留在她身邊，聊到沒話才走。

接續：offer_ig。

### busy_notice

Leahchecksfriendmessage,reorientsbutfinishessentence.

**Leah：**我朋友在等我了。

> **忙碌收尾**
> 她有自己的行程。收短一點，把下一步說清楚。

玩家選擇：

- 簡短交換聯絡，讓她去忙 → busy_wrap
- 直接道別 → early_bye


### busy_wrap

Noobstructingpath.

**Chris：**好，那妳先去找她。

接續：offer_ig。

### available_notice

Leahfinishesmessageandvoluntarilyreengages.

**Leah：**她還要一陣子。你們等一下還要去哪？

> **即約**
> 有時間、互動也在延續，就提出具體邀請，讓她回應。

玩家選擇：

- 邀她一起去前面喝咖啡 → coffee_invite
- 先交換聯絡，改天再約 → highpoint_wrap


### coffee_invite

Cafeestablishedinopeninggeography. Chriswaitsanswerbeforemoving.

**Chris：**我等一下想去前面那間喝個咖啡，妳要不要一起？

反應分支：default → coffee_accept；invite_declined → coffee_unavailable。

### coffee_accept

Leahagrees; tellSydneybeforeleaving; herfriendmeetingplanretained.

**Leah：**好啊，我跟我朋友說一下。

**Chris：**好，我也跟朋友講一聲。

接續：coffee_walk。

### coffee_walk

Walktosydneycraftstallvisiblecontinuously; noinstantteleport;Leahkeepsphoneaftermessage. Sydneyacknowledges.

**Chris：**我們去前面喝個咖啡，等一下再會合。

**Sydney：**好啊，等一下見。

接續：date_ending。

### coffee_unavailable

Timeconstraintnotinsult.

**Leah：**今天可能不行，我等一下還有事。

**Chris：**好，那改天。

接續：offer_ig。

### offer_ig

SayofferwhileopeningOWNphoneQR; screenmocknoactualcontact; holdneutralnotpush. Leahfreechoicetoscan.

**Chris：**欸，加個朋友吧，妳有 IG 嗎？

> **收號｜狀態不要變**
> 眼神、聲音和前面一樣穩。簡單提出，不突然加快語速或解釋一大串理由。

反應分支：default → scan_ig；contact_declined → decline_contact。

### scan_ig

Leahconsents,takesOWNphone,scans; maintainhand/phonecontinuity. Chrislooksbackupspeaking.

**Leah：**有啊，我掃你。

**Chris：**妳是這個對吧？我發妳個貼圖。

**Leah：**有了。

接續：future_coffee。

### future_coffee

Naturalpostexchangeconversationandgoodbye notimmediatevictory.

**Chris：**改天空了，約個咖啡。

**Leah：**好啊。

**Chris：**那先這樣，掰。

**Leah：**掰。

接續：return_sydney。

### decline_contact

Noinsistence.

**Leah：**不好意思，我不太加不認識的人。

**Chris：**好，沒問題。祝妳逛得開心。

接續：return_sydney。

### decline

Canexitanyappropriateboundarywhenunwillingexplicit.

**Leah：**不好意思，我沒有想認識人。

**Chris：**好，沒問題。祝妳逛得開心。

接續：return_sydney。

### early_bye

Calmdeparturewithoutcontact.

**Chris：**好，那妳先忙，掰。

**Leah：**掰。

接續：return_sydney。

### return_sydney

Returntosamecraftstall,Sydneyfinishedgift, walktogethermarketcontinues.

**Sydney：**走吧。

接續：review。

### review

Conditionalreviewonly;retainpreviousscene; do notloopdialogue. Displayonlyexperiencedtechniques and matching replayentry.


### walk_ending

SydneyandChriscontinuewalking; do notreplayintroline.

**Sydney：**走吧，我們往前逛。


### date_ending

WalkbesideLeahtocafewithvisiblejourney;offerlatercoachreviewwithoutinterruptingher.


## 製作順序與放行条件

1. 三角色聲音試演：自然台灣華語、同一句不同情緒、Chris 英文名字、IG、貼圖、句尾與停頓。
2. 鎖定聲線後生成完整對話，逐句核對文字與角色；同理心與自介中間固定留 1–2 秒。
3. 以聲音實際時長安排原生 9:16 表演，沿用角色 identity，重新建立夜市場景構圖；握手需完整連續性。
4. 環境與對話分軌；片尾不循環人聲；聲音審查未通過不得大量生成影片。
5. 實測聲音後才填入 startMs/durationMs；檢查字幕、嘴型與演員動作，而非只看 ASR。
6. 全部分支素材齊全並通過審查後才替換 App 預設情境；目前新稿沒有 production-ready 的影片或配音。

## 手機驗收

- 原生直式滿屏，臉部、手和攤位不被裁切，對白/選項覆蓋在場景內且不遮臉。
- 全流程除了玩家選擇之外連續動態；對話無重複播放。
- 背景、靜音、返回和重練不觸發舊聲音或跨分支。
- 強眼神、重心、尾音實際可見可聽，不只写提示。
- 同理心為陳述，不等待確認；握手不接也自然繼續。
- 冷讀錯誤、鉤子沒追問有接續；忙/有空/婉拒各自合乎情境。
- Sydney 只復盤實際經歷的片段，邀約與聯絡不以必定成功呈現。
- 390×844、大字級、iPhone 外放與耳機均需驗收。

## 情境條件與復盤

- 基本流程（main）
- 她有行程（busy）
- 有空再聊（available）
- 沒有接握手（handshake_nohand）
- 手上拿著東西（hands_full）
- 猜測被修正（coldread_repair）
- 她沒有追問（quiet_hook）
- 她不加陌生人（no_contact）
- 今天不方便一起走（no_invite）
- 她不想繼續認識（not_interested）

### 同理心陳述

「有點突然。」是陳述。停一拍後接背景，先處理突然被接觸的安全感。

顯示條件：經歷 empathy_intro；重練入口：opening。

### 背景介紹

跟朋友來買東西、剛在哪裡等，讓自己的出現有脈絡。

顯示條件：經歷 empathy_intro；重練入口：opening。

### 淺溝通｜強眼神・重心往後・尾音下沉

回看示範的眼神、姿態與尾音。內容很普通，也能透過穩定的淺溝通形成交流。

顯示條件：經歷 opening；重練入口：opening。

### 冷讀

給出觀察與猜測，再留意她怎麼補充自己。

顯示條件：經歷 cold_read，且未經歷 cold_read_repair；重練入口：transition。

### 冷讀修復

她修正猜測後，承認猜錯並接她的實際資訊，不用堅持自己的判斷。

顯示條件：經歷 cold_read_repair；重練入口：transition。

### 生活個性樣本＋留白

「最後是我不肯走」留下鉤子。她追問後，再透露自己的個性；不一次介紹完。

顯示條件：經歷 personality；重練入口：craft_expand。

### 留白後沒有追問

她沒有追問，就接回共同話題。不要求她好奇，也不因此直接結束互動。

顯示條件：經歷 hook_no_question；重練入口：craft_expand。

### 賦格

她說把手重做三次後，再肯定她的耐心。欣賞有前文。

顯示條件：經歷 qualify；重練入口：ordinary_chat。

### 無興趣指標｜主動收尾

這段在仍有往返時先收一輪，再提出交換聯絡，沒有一直聊到沒話。

顯示條件：經歷 highpoint_wrap；重練入口：ordinary_chat。

### 忙碌收尾

她有自己的行程。縮短收尾，接下來依你選擇交換聯絡或直接道別。

顯示條件：經歷 busy_notice；重練入口：busy_notice。

### 收號

提出加朋友、展示自己的 QR，對方接著掃碼；聲音與態度維持前面的穩定。

顯示條件：經歷 scan_ig；重練入口：offer_ig。

### 沒有交換聯絡

她表達不加陌生人，這段以自然道別收尾。

顯示條件：經歷 decline_contact；重練入口：offer_ig。

### 即約

把去處說具體，她回應願意之後，才交代朋友並一起走。

顯示條件：經歷 coffee_accept；重練入口：available_notice。

### 即約不方便

她今天不方便，接回改天聯絡，沒有繼續要求當下同行。

顯示條件：經歷 coffee_unavailable；重練入口：available_notice。

### 這次先繼續逛

這次尚未進入搭話。可以重練從注意到她、到決定接近的那一段。

顯示條件：經歷 walk_ending；重練入口：notice。

