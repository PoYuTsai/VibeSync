export type SocialKnowledgeSignal =
  | "always"
  | "evidence_sparse"
  | "interpretation"
  | "reply"
  | "invite"
  | "invite_no_alternative"
  | "alternative_time"
  | "repeated_non_uptake"
  | "clear_no"
  | "stalled"
  | "rejection"
  | "low_investment"
  | "high_investment"
  | "boundary"
  | "intimacy"
  | "health"
  | "offline"
  | "anxiety"
  | "repair"
  | "compatibility"
  | "humor"
  | "partnered"
  | "impaired"
  | "minor"
  | "conflict";

export type SocialKnowledgeDomain =
  | "decision"
  | "evidence"
  | "action"
  | "voice"
  | "safety";

export interface SocialKnowledgeAtom {
  readonly id: string;
  readonly domain: SocialKnowledgeDomain;
  readonly priority: number;
  readonly signals: readonly SocialKnowledgeSignal[];
  readonly guidance: string;
}

function atom(
  id: string,
  domain: SocialKnowledgeDomain,
  priority: number,
  signals: readonly SocialKnowledgeSignal[],
  guidance: string,
): SocialKnowledgeAtom {
  return { id, domain, priority, signals, guidance };
}

// Batch C：Analyze Chat 與 Coach 1:1 共用的 typed social-knowledge registry。
// 62 個 atom 是固定、可審查的規則，不做 embedding，也不連向量庫。Coach
// 每輪只由 deterministic selector 取出小片段；Analyze 的完整 prompt 仍由
// shared prompt sections 組裝，維持既有 byte-level contract。
export const SOCIAL_KNOWLEDGE_REGISTRY: readonly SocialKnowledgeAtom[] = Object
  .freeze([
    atom(
      "core.one_judgment",
      "decision",
      100,
      ["always"],
      "資訊足夠時只收斂成一個工作判斷，不把選項清單丟回使用者。",
    ),
    atom(
      "core.small_step",
      "action",
      99,
      ["always"],
      "下一步要小、可執行、可觀察，並且不需要對方承擔額外壓力。",
    ),
    atom(
      "core.mutuality",
      "decision",
      98,
      ["always"],
      "先看互惠與投入是否雙向，再決定回覆、推進或收手。",
    ),
    atom(
      "core.authenticity",
      "voice",
      97,
      ["always"],
      "幫使用者說得更好，不替他捏造經驗、身份、興趣或人格。",
    ),
    atom(
      "core.uncertainty",
      "evidence",
      96,
      ["always", "evidence_sparse"],
      "證據不足就明說信心有限，選即使判錯也不會造成壓力的做法。",
    ),
    atom(
      "core.time_cost",
      "decision",
      88,
      ["always", "compatibility"],
      "除了熱度，也要衡量時間、情緒、金錢成本與能否容易退出。",
    ),

    atom("evidence.pattern_over_single", "evidence", 93, [
      "interpretation",
      "stalled",
      "low_investment",
    ], "看連續模式，不把單次短回、晚回或已讀當成關係定論。"),
    atom("evidence.response_speed_low_weight", "evidence", 82, [
      "interpretation",
      "stalled",
    ], "回覆速度是低權重訊號；她回來後是否接話、反問、延伸更重要。"),
    atom("evidence.actions_over_labels", "evidence", 90, [
      "interpretation",
      "compatibility",
    ], "用具體行為與持續投入判斷，不用星座、人格標籤或單句印象代替證據。"),
    atom("evidence.no_motive_invention", "evidence", 95, [
      "interpretation",
      "reply",
      "low_investment",
    ], "不要替對方腦補冷淡、吊胃口、故意測試或其他負面動機。"),
    atom("evidence.prior_advice_not_outcome", "evidence", 91, [
      "interpretation",
      "reply",
    ], "教練先前說過的話不是對方反應，也不能當成進展或新事實。"),
    atom("evidence.freshness", "evidence", 86, [
      "interpretation",
      "invite",
      "stalled",
    ], "舊對話只能提供背景；推進前要用低壓方式確認現在的窗口。"),

    atom(
      "interpret.max_two",
      "decision",
      89,
      ["interpretation"],
      "最多承認兩個合理可能，接著選一個目前最可用的判讀。",
    ),
    atom(
      "interpret.low_pressure_test",
      "action",
      92,
      ["interpretation"],
      "用一個低壓小動作驗證判讀，不要求對方立刻解釋或表態。",
    ),
    atom("interpret.interest_signals", "evidence", 92, [
      "interpretation",
      "high_investment",
    ], "真正的興趣訊號是主動延伸、反問、分享細節、提供時間或製造下一個窗口。"),
    atom("interpret.curiosity_not_investment", "evidence", 84, [
      "interpretation",
    ], "一句人格觀察或稱讚只代表好奇，不等於對方已投入或承諾。"),
    atom("interpret.high_investment", "action", 87, [
      "high_investment",
      "reply",
    ], "對方有實質投入時可以順勢多接一點，但仍保留自然節奏與下一輪空間。"),
    atom(
      "interpret.low_investment",
      "action",
      94,
      ["low_investment", "reply"],
      "對方連續低投入時跟著降投入，不替對話續命，也不逼她解釋。",
    ),

    atom(
      "reply.select_one_ball",
      "action",
      94,
      ["reply"],
      "把整輪當成回覆空間，只接一到兩個最值得接的情緒、畫面、問句或窗口。",
    ),
    atom(
      "reply.balance",
      "action",
      93,
      ["reply", "low_investment"],
      "回覆量與情緒投入要大致對等；短是因為選球準，不是機械數字數。",
    ),
    atom(
      "reply.content_before_question",
      "voice",
      88,
      ["reply"],
      "先給內容、感受或立場，再留一個自然回口，避免只會盤問。",
    ),
    atom(
      "reply.one_question",
      "voice",
      91,
      ["reply"],
      "一則可貼句最多留一個真正需要的問題。",
    ),
    atom(
      "reply.grounded_facts",
      "evidence",
      96,
      ["reply"],
      "可貼句只能用來源已有的時間、人物、狀態與經歷，不得順手擴寫。",
    ),
    atom(
      "reply.no_placeholder",
      "safety",
      96,
      ["reply"],
      "沒有真實店名、時間或地點就改寫成不需要該細節，不輸出任何填空佔位符。",
    ),
    atom("reply.hold_is_valid", "decision", 89, [
      "reply",
      "low_investment",
      "stalled",
    ], "不值得回或沒有可靠句子時，暫時不傳也是完整且可執行的決定。"),

    atom(
      "invite.window_first",
      "decision",
      97,
      ["invite"],
      "先確認有雙向窗口再邀約；沒有窗口時先升溫或等待，不用換句話硬約。",
    ),
    atom(
      "invite.specific_low_pressure",
      "action",
      92,
      ["invite"],
      "邀約要具體、低壓、容易答應也容易拒絕，避免模糊試探或情緒綁架。",
    ),
    atom(
      "invite.own_availability",
      "voice",
      94,
      ["invite"],
      "邀約要帶自己的偏好或可行時間，不自貶、不無限配合、不把節奏全讓出去。",
    ),
    atom(
      "invite.alternative_time",
      "evidence",
      98,
      ["alternative_time"],
      "對方忙但主動給替代時間是偏正向訊號，可順勢確認。",
    ),
    atom(
      "invite.no_alternative_once",
      "evidence",
      98,
      ["invite_no_alternative"],
      "單次說忙又沒給替代時間先視為中性，不急著判冷，也不要立即補第二個邀約。",
    ),
    atom(
      "invite.repeated_non_uptake",
      "decision",
      99,
      ["repeated_non_uptake"],
      "邀約反覆未被承接且沒有替代窗口時停止再邀，等對方帶新材料或主動給窗口。",
    ),
    atom(
      "invite.clear_no",
      "safety",
      100,
      ["clear_no"],
      "明確拒絕就是停止訊號：接受、不辯論、不換說法繼續推進。",
    ),
    atom(
      "invite.after_invite_stop",
      "action",
      90,
      ["invite"],
      "邀約送出後把球留給對方，不連續補訊息、補理由或催答案。",
    ),

    atom(
      "stalled.diagnose",
      "decision",
      92,
      ["stalled"],
      "先分辨話題耗盡、壓力過大、時機不對或興趣下降，再決定重啟或收手。",
    ),
    atom(
      "stalled.no_rescue_interview",
      "action",
      95,
      ["stalled", "reply"],
      "不要用連續查戶口問題救對話；救不起來的對話不該由使用者單方面扛。",
    ),
    atom(
      "stalled.reopen_with_value",
      "action",
      88,
      ["stalled"],
      "值得重啟時帶一個具體畫面、共同脈絡或新價值，避免空泛的『在幹嘛』。",
    ),
    atom(
      "stalled.space",
      "action",
      91,
      ["stalled", "low_investment"],
      "近期已補過訊息仍沒承接時先留白，讓是否繼續投入變成對方的選擇。",
    ),
    atom(
      "rejection.dont_argue",
      "safety",
      98,
      ["clear_no"],
      "被拒絕後不辯護、不說服、不要求對方證明理由。",
    ),
    atom(
      "rejection.repair_short",
      "voice",
      89,
      ["repair"],
      "若造成壓力，簡短承認影響、尊重界線並停止，不用長篇自我辯護。",
    ),
    atom(
      "rejection.stop_loss",
      "decision",
      96,
      ["repeated_non_uptake"],
      "反覆模糊拖延又沒有任何替代投入時，把止損說清楚，不硬製造希望。",
    ),

    atom(
      "boundary.consent",
      "safety",
      100,
      ["boundary", "intimacy"],
      "親密與推進只建立在清醒、明確、持續且可隨時撤回的同意上。",
    ),
    atom(
      "boundary.stop_signals",
      "safety",
      100,
      ["boundary", "intimacy"],
      "說不要、退開、僵住、沉默抗拒或需要反覆說服，全部視為停止訊號。",
    ),
    atom(
      "boundary.no_pressure",
      "safety",
      100,
      ["boundary", "intimacy"],
      "不得用羞辱、承諾、情緒勒索、隔離、灌酒或持續施壓換取回應與親密。",
    ),
    atom(
      "boundary.third_party",
      "decision",
      97,
      ["partnered", "boundary"],
      "涉及既有伴侶時先釐清角色、透明度與第三方成本，不替曖昧合理化。",
    ),
    atom(
      "boundary.power_money",
      "safety",
      98,
      ["boundary"],
      "權力、工作、金錢或服務關係明顯失衡時，服務與情緒勞動不等於戀愛或性窗口。",
    ),
    atom(
      "boundary.alcohol",
      "safety",
      100,
      ["impaired"],
      "酒精降低判斷能力時不推進親密；先確保清醒、交通與安全退路。",
    ),
    atom(
      "boundary.exit",
      "safety",
      96,
      ["boundary", "offline"],
      "任何邀約或轉場都要保留對方容易拒絕、停止與離開的路。",
    ),
    atom(
      "boundary.minor",
      "safety",
      100,
      ["minor"],
      "只要涉及未成年就停止性或親密推進建議，轉向安全與可信成人協助。",
    ),
    atom(
      "boundary.harassment",
      "safety",
      100,
      ["clear_no", "boundary"],
      "對方已拒絕或要求停止後，不再聯絡、換平台追問或借第三人施壓。",
    ),

    atom(
      "intimacy.window_consent",
      "decision",
      99,
      ["intimacy"],
      "先看雙向窗口與身體訊號，再用一句低壓確認，不把曖昧自動等同同意。",
    ),
    atom(
      "intimacy.transition",
      "action",
      91,
      ["intimacy", "offline"],
      "轉場要自然、可逆且明說下一站，讓對方有充分資訊與選擇。",
    ),
    atom(
      "intimacy.protection",
      "safety",
      99,
      ["intimacy", "health"],
      "親密建議必須涵蓋保護措施、潤滑、疼痛即停與事後照顧。",
    ),
    atom(
      "health.escalation",
      "safety",
      100,
      ["health", "intimacy"],
      "疼痛、出血、避孕失誤、性病症狀或非自願風險要轉向就醫、篩檢或緊急協助，不做診斷。",
    ),
    atom(
      "offline.logistics",
      "action",
      85,
      ["offline", "invite"],
      "線下邀約要考慮時間、地點、路線、交通與自然退路，不只設計一句話。",
    ),
    atom(
      "offline.group_safety",
      "safety",
      88,
      ["offline"],
      "多人或夜生活場景先建立群體安全感，保留同伴、手機、交通與離場能力。",
    ),

    atom(
      "state.regulate_first",
      "decision",
      95,
      ["anxiety", "conflict"],
      "焦慮、嫉妒、委屈或情緒上頭時先穩住狀態，再決定是否傳訊息。",
    ),
    atom(
      "state.no_self_worth",
      "voice",
      91,
      ["anxiety", "rejection"],
      "不要把對方單次反應綁成使用者的價值判決，也不要用訊息索取安撫。",
    ),
    atom(
      "style.primary_secondary",
      "voice",
      86,
      ["reply", "humor"],
      "語氣以主風格為骨架、副風格只做少量點綴；自然與可承擔永遠優先。",
    ),
    atom(
      "humor.not_oily",
      "voice",
      89,
      ["humor", "reply"],
      "幽默要建立在真實內容上，避免油膩、表演感與逼對方接梗。",
    ),
    atom(
      "compatibility.bidirectional",
      "decision",
      96,
      ["compatibility"],
      "找適合的對象是雙向篩選：既看聊不聊得來，也看對方是否尊重、投入且適合使用者。",
    ),
    atom(
      "repair.own_impact",
      "action",
      94,
      ["repair", "conflict"],
      "修復時承認具體影響、說清楚會怎麼調整，然後把是否繼續的選擇留給對方。",
    ),
    atom(
      "conflict.deescalate",
      "action",
      93,
      ["conflict", "boundary"],
      "衝突先降速、對齊事實與界線，不在高情緒時追著贏辯論或逼結論。",
    ),
  ]);
