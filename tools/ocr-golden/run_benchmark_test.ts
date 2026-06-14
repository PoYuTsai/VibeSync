// run_benchmark.ts 核心比對邏輯單元測試
// 跑法：deno test tools/ocr-golden/run_benchmark_test.ts

import {
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  aggregate,
  aggregatePhase1,
  alignMessages,
  canonicalizeMedia,
  isActivityCardNoise,
  levenshtein,
  normalizeText,
  scorePhase1,
  scoreUnit,
  similarity,
  stripEmoji,
  wilsonLowerBound,
} from "./run_benchmark.ts";

// 計分層測試共用：最小 unit / body 構造器
function unitOf() {
  return {
    id: "t",
    source: "real" as const,
    images: [] as string[],
    label: "x",
    scenarios: [] as string[],
  };
}
function labelOf(messages: Array<{
  side: "left" | "right";
  text: string;
  quotedReplyPreview?: string;
  quotedReplyPreviewIsFromMe?: boolean;
}>) {
  return {
    id: "t",
    contactName: null,
    classification: "valid_chat",
    importPolicy: "allow",
    messages,
  };
}
function bodyOf(messages: Array<{
  side?: string;
  content?: string;
  quotedReplyPreview?: string;
  quotedReplyPreviewIsFromMe?: boolean;
}>) {
  return {
    recognizedConversation: {
      classification: "valid_chat",
      importPolicy: "allow",
      messages,
    },
  };
}

Deno.test("normalizeText：全形轉半形、去空白、轉小寫", () => {
  assertEquals(normalizeText("Ｈｅｌｌｏ　ｗｏｒｌｄ！"), "helloworld!");
  assertEquals(normalizeText("你 好  嗎"), "你好嗎");
});

Deno.test("levenshtein：基本距離", () => {
  assertEquals(levenshtein("abc", "abc"), 0);
  assertEquals(levenshtein("abc", "abd"), 1);
  assertEquals(levenshtein("", "abc"), 3);
  assertEquals(levenshtein("在嗎", "再嗎"), 1); // 錯字被修正會產生距離
});

Deno.test("similarity：相同文字 = 1，差一字的短句仍高相似", () => {
  assertEquals(similarity("哈囉你好嗎", "哈囉你好嗎"), 1);
  const s = similarity("今天天氣真的很好耶", "今天天氣真的很好捏");
  if (s < 0.8) throw new Error(`預期 ≥0.8，得到 ${s}`);
});

Deno.test("alignMessages：順序保持的一對一對齊", () => {
  const expected = [
    { side: "left" as const, text: "今天吃什麼" },
    { side: "right" as const, text: "想吃拉麵" },
    { side: "left" as const, text: "好啊走" },
  ];
  const actual = [
    { side: "left", content: "今天吃什麼" },
    { side: "right", content: "想吃拉麵" },
    { side: "left", content: "好啊走" },
  ];
  assertEquals(alignMessages(expected, actual), [[0, 0], [1, 1], [2, 2]]);
});

Deno.test("alignMessages：漏抓（actual 缺一則）不錯位", () => {
  const expected = [
    { side: "left" as const, text: "第一句話內容" },
    { side: "right" as const, text: "第二句話內容" },
    { side: "left" as const, text: "第三句話內容" },
  ];
  const actual = [
    { side: "left", content: "第一句話內容" },
    { side: "left", content: "第三句話內容" },
  ];
  // 第二句漏抓；第三句必須對到 actual[1]，不能硬塞給第二句
  assertEquals(alignMessages(expected, actual), [[0, 0], [2, 1]]);
});

Deno.test("alignMessages：幻覺訊息（actual 多一則）被排除", () => {
  const expected = [
    { side: "left" as const, text: "真實訊息一號" },
    { side: "right" as const, text: "真實訊息二號" },
  ];
  const actual = [
    { side: "left", content: "真實訊息一號" },
    { side: "left", content: "憑空多出來的內容" },
    { side: "right", content: "真實訊息二號" },
  ];
  assertEquals(alignMessages(expected, actual), [[0, 0], [1, 2]]);
});

Deno.test("alignMessages：輕微 OCR 誤差（≥0.8 相似）仍可對齊", () => {
  const expected = [
    { side: "left" as const, text: "明天下午三點老地方見面喔" },
  ];
  const actual = [
    { side: "left", content: "明天下午三點老地方見面唷" },
  ];
  assertEquals(alignMessages(expected, actual), [[0, 0]]);
});

Deno.test("alignMessages：完全不同的短訊息不對齊", () => {
  const expected = [{ side: "left" as const, text: "晚安" }];
  const actual = [{ side: "left", content: "早安你好" }];
  assertEquals(alignMessages(expected, actual), []);
});

// ---------- ① 計分層容差：媒體 token 歸一 ----------

Deno.test("canonicalizeMedia：描述型媒體標記歸一為裸 token", () => {
  assertEquals(canonicalizeMedia("[sticker: dog with hat]"), "[sticker]");
  assertEquals(canonicalizeMedia("[photo of a sunset]"), "[photo]");
  assertEquals(canonicalizeMedia("[image: 一張自拍]"), "[photo]");
  assertEquals(canonicalizeMedia("[貼圖]"), "[sticker]");
  assertEquals(canonicalizeMedia("sent a photo"), "[photo]");
  assertEquals(canonicalizeMedia("今天天氣真好"), "今天天氣真好"); // 非媒體不動
});

Deno.test("stripEmoji：去 emoji／膚色修飾／variation selector，保留文字", () => {
  assertEquals(stripEmoji("好🫶🏻🫶🏻🫶🏻"), "好");
  assertEquals(stripEmoji("教小孩真不容易😯😯"), "教小孩真不容易");
  assertEquals(stripEmoji("❤️🐩"), "");
  assertEquals(stripEmoji("剛剛先去發北鼻給大家的🎁❤️❤️‍🔥"), "剛剛先去發北鼻給大家的");
  assertEquals(stripEmoji("沒有表情符號"), "沒有表情符號");
});

Deno.test("similarity：媒體描述差異與 emoji 變體仍高相似（容差）", () => {
  if (similarity("[sticker]", "[sticker: 一隻戴帽子的狗]") < 0.8) {
    throw new Error("媒體 token 應容差對齊");
  }
  if (similarity("教小孩真不容易😯😯", "教小孩真不容易😲😲") < 0.8) {
    throw new Error("emoji 變體不該打斷對齊");
  }
  if (similarity("好🫶🏻🫶🏻🫶🏻", "好🙌🙌🙌") < 0.8) {
    throw new Error("emoji 不同但文字相同應對齊");
  }
});

Deno.test("isActivityCardNoise：日期/時段/預約鈕碎片判為活動卡雜訊", () => {
  assertEquals(isActivityCardNoise("06/10 (三)"), true);
  assertEquals(isActivityCardNoise("19:00 ~ 20:00"), true);
  assertEquals(isActivityCardNoise("預約"), true);
  // 卡片標題本身 = 正當訊息，不可誤判
  assertEquals(isActivityCardNoise("【中和】空中瑜伽 新手寶寶班（4好幣）＊糖糖代課"), false);
  assertEquals(isActivityCardNoise("剛吃飽準備回健身房"), false);
});

// ---------- ① 計分層：scoreUnit 容差與分類 ----------

Deno.test("scoreUnit：媒體描述歸一後對齊，不再雙重扣分", () => {
  const label = labelOf([{ side: "left", text: "[sticker]" }]);
  const body = bodyOf([{ side: "left", content: "[sticker: 一隻戴帽子的狗]" }]);
  const r = scoreUnit(unitOf(), label, 200, body, 10);
  assertEquals(r.alignedCount, 1); // 對齊
  assertEquals(r.missed?.length, 0); // 不算漏
  assertEquals(r.hallucinated?.length, 0); // 不算幻覺
  assertEquals(r.exactTextMatches, 1); // 歸一後逐字算對
});

Deno.test("scoreUnit：引用預覽被當訊息吐 → quotedPreviewLeak 而非一般幻覺", () => {
  const label = labelOf([
    { side: "left", text: "[sticker]", quotedReplyPreview: "辛苦北鼻了" },
    { side: "left", text: "好喜歡～～" },
  ]);
  const body = bodyOf([
    { side: "left", content: "辛苦北鼻了" }, // 洩漏的引用卡（鬼訊息）
    { side: "left", content: "[sticker]" },
    { side: "left", content: "好喜歡～～" },
  ]);
  const r = scoreUnit(unitOf(), label, 200, body, 10);
  assertEquals(r.quotedPreviewLeaks?.length, 1);
  assertEquals(r.quotedPreviewLeaks?.[0].text, "辛苦北鼻了");
  // 不應再列入一般 hallucinated
  assertEquals(
    r.hallucinated?.some((h) => h.text.includes("辛苦北鼻了")),
    false,
  );
});

Deno.test("scoreUnit：活動卡碎片列 → activityCardNoise 而非一般幻覺", () => {
  const label = labelOf([
    { side: "left", text: "【中和】空中瑜伽 新手寶寶班（4好幣）＊糖糖代課" },
    { side: "left", text: "要去教寶寶囉" },
  ]);
  const body = bodyOf([
    { side: "left", content: "【中和】空中瑜伽 新手寶寶班（4好幣）＊糖糖代課" },
    { side: "left", content: "06/10 (三)" },
    { side: "left", content: "19:00 ~ 20:00" },
    { side: "left", content: "預約" },
    { side: "left", content: "要去教寶寶囉" },
  ]);
  const r = scoreUnit(unitOf(), label, 200, body, 10);
  assertEquals(r.activityCardNoise?.length, 3);
  assertEquals(r.hallucinated?.length, 0);
});

Deno.test("scoreUnit：引用預覽欄文字比對（dim 讀錯計入 quotePreview）", () => {
  const label = labelOf([
    { side: "left", text: "等等見", quotedReplyPreview: "北鼻我睏睏想躺一下" },
    { side: "left", text: "剛到永春", quotedReplyPreview: "在幹嘛" },
  ]);
  const body = bodyOf([
    { side: "left", content: "等等見", quotedReplyPreview: "北鼻我眯眯想躺一下" }, // dim 讀錯
    { side: "left", content: "剛到永春", quotedReplyPreview: "在幹嘛" }, // 對
  ]);
  const r = scoreUnit(unitOf(), label, 200, body, 10);
  assertEquals(r.quotePreviewTotal, 2);
  assertEquals(r.quotePreviewCorrect, 1); // 一對一錯
});

Deno.test("aggregate：彙總引用預覽準確率與洩漏/活動卡雜訊總數", () => {
  const leakLabel = labelOf([
    { side: "left", text: "[sticker]", quotedReplyPreview: "辛苦北鼻了" },
    { side: "left", text: "好喜歡～～" },
  ]);
  const leakBody = bodyOf([
    { side: "left", content: "辛苦北鼻了" }, // 洩漏
    { side: "left", content: "[sticker]" },
    { side: "left", content: "好喜歡～～" },
  ]);
  const previewLabel = labelOf([
    { side: "left", text: "等等見", quotedReplyPreview: "北鼻我睏睏想躺一下" },
    { side: "left", text: "剛到永春", quotedReplyPreview: "在幹嘛" },
  ]);
  const previewBody = bodyOf([
    { side: "left", content: "等等見", quotedReplyPreview: "北鼻我眯眯想躺一下" },
    { side: "left", content: "剛到永春", quotedReplyPreview: "在幹嘛" },
  ]);
  const results = [
    scoreUnit(unitOf(), leakLabel, 200, leakBody, 10),
    scoreUnit(unitOf(), previewLabel, 200, previewBody, 10),
  ];
  const agg = aggregate(results);
  // 引用預覽計分：preview 單元 2 則（1 對 1 錯）+ leak 單元 1 則（label 標了卻被洩漏成
  // 獨立列 → aligned 的 [sticker] 無 quotedReplyPreview ⟹ 判錯）= 共 3 則、對 1 則。
  assertEquals(agg.quotePreviewTotal, 3);
  assertEquals(agg.quotePreviewAccuracy, 1 / 3);
  assertEquals(agg.quotedPreviewLeakTotal, 1);
  assertEquals(agg.activityCardNoiseTotal, 0);
});

// ── 第③軌 Phase 1 量測測試 ──────────────────────────────────────────────

Deno.test("wilsonLowerBound：小樣本下界明顯低於點估、零樣本回 null", () => {
  assertEquals(wilsonLowerBound(0, 0), null);
  const lb3 = wilsonLowerBound(3, 3)!; // 3/3=100% 但樣本小
  if (!(lb3 > 0.3 && lb3 < 0.95)) throw new Error(`3/3 LB 預期落 (0.3,0.95)，得 ${lb3}`);
  const lb100 = wilsonLowerBound(100, 100)!; // 大樣本逼近 1
  if (!(lb100 > 0.96)) throw new Error(`100/100 LB 預期 >0.96，得 ${lb100}`);
});

function p1BodyOf(
  myBubbleColor: string | null,
  evidence: string | null,
  messages: Array<{
    content: string;
    side?: string | null;
    bubbleFillColor?: string | null;
    senderNameRaw?: string | null;
    quotedName?: string | null;
  }>,
) {
  return {
    recognizedConversation: { classification: "valid_chat", importPolicy: "allow", messages: [] },
    phase1Vision: {
      myBubbleColor,
      myBubbleColorEvidence: evidence,
      screenSpeakerPattern: null,
      messages: messages.map((m) => ({
        content: m.content,
        side: m.side ?? null,
        outerColumn: null,
        horizontalPosition: null,
        blockType: null,
        isFromMe: m.side === "right",
        bubbleFillColor: m.bubbleFillColor ?? null,
        senderNameRaw: m.senderNameRaw ?? null,
        senderNameX: null,
        quotedName: m.quotedName ?? null,
        quotedNamePresent: m.quotedName != null,
      })),
    },
  };
}

Deno.test("scorePhase1：fill-only 救回模型自報 side 翻錯的暗色泡", () => {
  // ground truth 全 left（她說）；模型 raw side 把第 2 則翻成 right（暗色位置失準）。
  // 但泡色全灰、myColor=green ⇒ fill-only 全判 left＝全對。
  const label = labelOf([
    { side: "left", text: "到家了沒" },
    { side: "left", text: "記得吃飯喔" },
  ]);
  const body = p1BodyOf("green", "app_convention", [
    { content: "到家了沒", side: "left", bubbleFillColor: "gray" },
    { content: "記得吃飯喔", side: "right", bubbleFillColor: "gray" }, // raw 翻錯
  ]);
  const p1 = scorePhase1(label, body.phase1Vision)!;
  assertEquals(p1.alignedRows, 2);
  assertEquals(p1.fillKnown, 2);
  assertEquals(p1.fillCorrect, 2); // fill 全對
  assertEquals(p1.posKnown, 2);
  assertEquals(p1.posCorrect, 1); // position 翻錯 1 則
});

Deno.test("scorePhase1：myColor=unknown ⇒ fill 不可判（不亂猜）", () => {
  const label = labelOf([{ side: "left", text: "嗨嗨" }]);
  const body = p1BodyOf(null, "unknown", [
    { content: "嗨嗨", side: "left", bubbleFillColor: "gray" },
  ]);
  const p1 = scorePhase1(label, body.phase1Vision)!;
  assertEquals(p1.fillKnown, 0);
  assertEquals(p1.posKnown, 1);
});

Deno.test("scorePhase1：quotedName set-level 召回，senderNameRaw 不混入 quotedName", () => {
  const label = {
    ...labelOf([
      { side: "left", text: "吃了新口味" },
      { side: "right", text: "好吃嗎" },
    ]),
    messages: [
      { side: "left" as const, text: "吃了新口味", quotedName: "Candy 糖糖" },
      { side: "right" as const, text: "好吃嗎", quotedName: "Candy 糖糖" },
    ],
  };
  const body = p1BodyOf("green", "right_anchor", [
    { content: "吃了新口味", side: "left", bubbleFillColor: "gray", senderNameRaw: "Candy 糖糖", quotedName: "Candy 糖糖" },
    { content: "好吃嗎", side: "right", bubbleFillColor: "green", senderNameRaw: null, quotedName: "Candy 糖糖" },
  ]);
  const p1 = scorePhase1(label, body.phase1Vision)!;
  assertEquals(p1.quotedNameExpected, 2);
  assertEquals(p1.quotedNameRecalled, 2);
  // 逐列 audit：senderNameRaw 與 quotedName 各自獨立欄，未互相污染
  assertEquals(p1.rows[0].senderNameRaw, "Candy 糖糖");
  assertEquals(p1.rows[0].visionQuotedName, "Candy 糖糖");
  assertEquals(p1.rows[1].senderNameRaw, null);
});

Deno.test("aggregatePhase1：fill vs position Δpp、Wilson、evidence 分佈", () => {
  const mk = (id: string, body: ReturnType<typeof p1BodyOf>, label: ReturnType<typeof labelOf>) =>
    scoreUnit({ ...unitOf(), id, scenarios: ["dark_mode"] }, label, 200, body, 10);
  const r1 = mk(
    "a",
    p1BodyOf("green", "app_convention", [
      { content: "一", side: "left", bubbleFillColor: "gray" },
      { content: "二", side: "right", bubbleFillColor: "gray" }, // raw 翻錯
    ]),
    labelOf([{ side: "left", text: "一" }, { side: "left", text: "二" }]),
  );
  const agg = aggregatePhase1([r1])!;
  assertEquals(agg.fillCorrect, 2);
  assertEquals(agg.fillKnown, 2);
  assertEquals(agg.posCorrect, 1);
  assertEquals(agg.fillOnlyAccuracy, 1);
  assertEquals(agg.positionOnlyAccuracy, 0.5);
  assertEquals(agg.deltaPp, 50);
  assertEquals(agg.evidenceDist["app_convention"], 1);
});

Deno.test("scorePhase1：phase1Vision 缺席 ⇒ undefined（prod/舊 run 不受影響）", () => {
  const label = labelOf([{ side: "left", text: "嗨" }]);
  assertEquals(scorePhase1(label, undefined), undefined);
});
