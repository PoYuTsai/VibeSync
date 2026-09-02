// Analyze v2 黑箱語料（Phase 3a）。每案帶可確定性判定的期望值；stage／action／
// balls／atoms 等期望等 3c／3e 再加。改這裡不動 runtime。
export type Msg = { isFromMe: boolean; content: string };
export type MessageDecision =
  | "send"
  | "do_not_send"
  | "acknowledge_and_stop"
  | "need_context";
export interface CorpusCase {
  readonly id: string;
  readonly family: string;
  readonly messages: readonly Msg[];
  readonly expect: {
    /// 可接受的決策集合（邊界案允許兩種）。
    readonly messageDecision: readonly MessageDecision[];
  };
}

export const CORPUS: readonly CorpusCase[] = [
  {
    id: "thin_opening",
    family: "opening",
    messages: [
      { isFromMe: true, content: "嗨" },
      { isFromMe: false, content: "哈囉" },
    ],
    expect: { messageDecision: ["send"] },
  },
  {
    id: "first_message_after_match",
    family: "opening",
    messages: [
      { isFromMe: false, content: "嗨 你的照片是在哪拍的呀 好美" },
    ],
    expect: { messageDecision: ["send"] },
  },
  {
    id: "warm_question_back",
    family: "direct_question",
    messages: [
      { isFromMe: false, content: "剛看完你說的那部片 真的有被嚇到" },
      { isFromMe: true, content: "哈哈我就說吧 第二幕那段我看兩次還是會抖" },
      { isFromMe: false, content: "你平常都看這種的嗎？還是有別的推薦" },
      { isFromMe: false, content: "我最近有點片荒" },
    ],
    expect: { messageDecision: ["send"] },
  },
  {
    id: "soft_reject_after_invite",
    family: "boundary",
    messages: [
      { isFromMe: false, content: "你週末都在幹嘛啊" },
      { isFromMe: true, content: "通常會去爬山或找朋友吃飯，你呢" },
      { isFromMe: false, content: "我都在家耍廢哈哈" },
      { isFromMe: true, content: "那這週六要不要一起去吃那家新開的義大利麵" },
      { isFromMe: false, content: "這週有點忙耶" },
      { isFromMe: false, content: "下次再看看" },
    ],
    expect: { messageDecision: ["acknowledge_and_stop"] },
  },
  {
    id: "defer_vague_busy",
    family: "boundary",
    messages: [
      { isFromMe: true, content: "禮拜五晚上有空嗎 想約妳吃飯" },
      { isFromMe: false, content: "最近有點忙欸" },
      { isFromMe: false, content: "再說吧" },
    ],
    expect: { messageDecision: ["acknowledge_and_stop"] },
  },
  {
    id: "defer_with_alternative",
    family: "invite_window",
    messages: [
      { isFromMe: true, content: "禮拜五晚上有空嗎 想約妳吃飯" },
      { isFromMe: false, content: "禮拜五要加班耶" },
      { isFromMe: false, content: "禮拜天可以嗎" },
    ],
    expect: { messageDecision: ["send"] },
  },
  {
    id: "defer_polite_reason",
    family: "boundary",
    messages: [
      { isFromMe: true, content: "這週末要不要一起去看那個展" },
      { isFromMe: false, content: "好像不錯" },
      { isFromMe: false, content: "不過我這週末已經約了朋友 之後再看看好了" },
    ],
    expect: { messageDecision: ["acknowledge_and_stop"] },
  },
  {
    id: "cold_one_word_replies",
    family: "cold",
    messages: [
      { isFromMe: true, content: "今天天氣超好 有出門嗎" },
      { isFromMe: false, content: "沒" },
      { isFromMe: true, content: "那在家做什麼" },
      { isFromMe: false, content: "躺著" },
      { isFromMe: true, content: "哈哈 週末就是要耍廢 你平常有什麼興趣嗎" },
      { isFromMe: false, content: "還好" },
    ],
    expect: { messageDecision: ["send", "do_not_send"] },
  },
  {
    id: "she_invites_first",
    family: "invite_window",
    messages: [
      { isFromMe: false, content: "我朋友給了我兩張週五的演唱會票" },
      { isFromMe: false, content: "你有興趣嗎" },
      { isFromMe: false, content: "是那個你之前說喜歡的樂團" },
    ],
    expect: { messageDecision: ["send"] },
  },
  {
    id: "after_meetup_followup",
    family: "invite_window",
    messages: [
      { isFromMe: true, content: "到家了嗎" },
      { isFromMe: false, content: "到了 今天謝謝你" },
      { isFromMe: false, content: "那家店真的很好吃 下次換我請" },
    ],
    expect: { messageDecision: ["send"] },
  },
  {
    id: "she_shares_bad_day",
    family: "disclosure",
    messages: [
      { isFromMe: false, content: "今天被主管當眾罵 超級丟臉" },
      { isFromMe: false, content: "明明不是我的錯" },
      { isFromMe: false, content: "覺得好累" },
    ],
    expect: { messageDecision: ["send"] },
  },
  {
    id: "she_asks_personal_question",
    family: "direct_question",
    messages: [
      { isFromMe: true, content: "你的貓超可愛" },
      { isFromMe: false, content: "哈哈牠很黏人" },
      { isFromMe: false, content: "對了 你是做什麼工作的啊" },
      { isFromMe: false, content: "感覺你很常出差" },
    ],
    expect: { messageDecision: ["send"] },
  },
  {
    id: "long_conversation_35",
    family: "insufficient",
    messages: [
      { isFromMe: false, content: "嗨 你也喜歡爬山喔" },
      { isFromMe: true, content: "對啊 你最近有去哪" },
      { isFromMe: false, content: "上個月去了合歡山" },
      { isFromMe: true, content: "哇 那邊日出很讚" },
      { isFromMe: true, content: "你平常都幾點起床" },
      { isFromMe: false, content: "我都七點多" },
      { isFromMe: false, content: "你呢" },
      { isFromMe: true, content: "我也差不多哈哈" },
      { isFromMe: true, content: "週末通常在幹嘛" },
      { isFromMe: false, content: "看書或跑步" },
      { isFromMe: false, content: "你呢" },
      { isFromMe: true, content: "我也差不多哈哈" },
      { isFromMe: true, content: "你喜歡吃辣嗎" },
      { isFromMe: false, content: "超愛 越辣越好" },
      { isFromMe: false, content: "你呢" },
      { isFromMe: true, content: "我也差不多哈哈" },
      { isFromMe: true, content: "有養寵物嗎" },
      { isFromMe: false, content: "有一隻貓 叫布丁" },
      { isFromMe: false, content: "你呢" },
      { isFromMe: true, content: "我也差不多哈哈" },
      { isFromMe: true, content: "你是台北人嗎" },
      { isFromMe: false, content: "對 但老家在台中" },
      { isFromMe: false, content: "你呢" },
      { isFromMe: true, content: "我也差不多哈哈" },
      { isFromMe: true, content: "最近在追什麼劇" },
      { isFromMe: false, content: "在看一部日劇" },
      { isFromMe: false, content: "你呢" },
      { isFromMe: true, content: "我也差不多哈哈" },
      { isFromMe: true, content: "你會煮飯嗎" },
      { isFromMe: false, content: "會一點 蛋炒飯專家" },
      { isFromMe: false, content: "你呢" },
      { isFromMe: true, content: "我也差不多哈哈" },
      { isFromMe: true, content: "喜歡海邊還是山上" },
      { isFromMe: false, content: "山上 海邊太曬" },
      { isFromMe: false, content: "你呢" },
      { isFromMe: true, content: "我也差不多哈哈" },
      { isFromMe: false, content: "欸 對了" },
      { isFromMe: false, content: "你上次說的那家咖啡廳在哪" },
      { isFromMe: false, content: "我這週末想去" },
    ],
    expect: { messageDecision: ["need_context", "send"] },
  },
  {
    id: "user_over_investing",
    family: "cold",
    messages: [
      { isFromMe: true, content: "早安 今天要加油喔" },
      { isFromMe: true, content: "你昨天說的簡報還順利嗎" },
      { isFromMe: true, content: "如果需要幫忙可以跟我說" },
      { isFromMe: false, content: "嗯 還可以 謝謝" },
    ],
    expect: { messageDecision: ["do_not_send", "send"] },
  },
  {
    id: "she_double_texts",
    family: "multi_ball",
    messages: [
      { isFromMe: true, content: "我先去洗澡 等等聊" },
      { isFromMe: false, content: "好～" },
      {
        isFromMe: false,
        content: "欸 我剛想到 你上次說的那家拉麵我今天去吃了",
      },
      { isFromMe: false, content: "真的超好吃 你品味不錯欸" },
    ],
    expect: { messageDecision: ["send"] },
  },
  {
    id: "logistics_confirm",
    family: "invite_window",
    messages: [
      { isFromMe: true, content: "那週六下午三點 捷運忠孝敦化站三號出口見？" },
      { isFromMe: false, content: "好啊" },
      { isFromMe: false, content: "我可能會晚十分鐘 要先去拿東西" },
    ],
    expect: { messageDecision: ["send"] },
  },
  {
    id: "she_teases_him",
    family: "play",
    messages: [
      { isFromMe: true, content: "我週末跑了十公里" },
      { isFromMe: false, content: "哇 這麼厲害" },
      { isFromMe: false, content: "該不會是跑去便利商店然後回來吧 哈哈" },
    ],
    expect: { messageDecision: ["send"] },
  },
  {
    id: "she_returns_after_silence",
    family: "short_reply",
    messages: [
      { isFromMe: true, content: "最近好嗎" },
      { isFromMe: false, content: "抱歉之前太忙沒回" },
      { isFromMe: false, content: "這陣子在趕案子 現在終於結束了" },
      { isFromMe: false, content: "你最近怎樣" },
    ],
    expect: { messageDecision: ["send"] },
  },
  {
    id: "boundary_friend_hint",
    family: "boundary",
    messages: [
      { isFromMe: true, content: "我覺得跟你聊天很開心 想多認識你" },
      { isFromMe: false, content: "我也覺得你人很好" },
      {
        isFromMe: false,
        content: "不過我現在還不太想談感情 我們先當朋友可以嗎",
      },
    ],
    expect: { messageDecision: ["acknowledge_and_stop"] },
  },
  {
    id: "she_asks_his_opinion",
    family: "ask_advice",
    messages: [
      { isFromMe: false, content: "我在考慮要不要換工作" },
      { isFromMe: false, content: "新的薪水高很多 但要搬去新竹" },
      { isFromMe: false, content: "你覺得呢" },
    ],
    expect: { messageDecision: ["send"] },
  },
  {
    id: "hobby_common_ground",
    family: "multi_ball",
    messages: [
      { isFromMe: false, content: "你也有在玩攝影喔 我看你照片" },
      { isFromMe: true, content: "對啊 但都是隨手拍" },
      { isFromMe: false, content: "我最近在學底片 沖出來都糊掉哈哈" },
      { isFromMe: false, content: "你有推薦的入門機嗎" },
    ],
    expect: { messageDecision: ["send"] },
  },
];

export function corpusMessages(): Record<string, Msg[]> {
  return Object.fromEntries(CORPUS.map((c) => [c.id, [...c.messages]]));
}
