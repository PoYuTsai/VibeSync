// judge 自測（零網路）：嚴格 parser／validator、遮罩、prompt 組裝。
//
// 每個標籤各有 ≥5 筆「該標籤為 true」與 ≥5 筆「該標籤為 false」的手寫 JSON 原文，
// 逐筆走 parseJudgeVerdict，確認嚴格驗證不會靜默補值、也不會把共存標籤搞混。
import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildJudgeCases,
  buildJudgePrompt,
  JUDGED_LABELS,
  type JudgedLabel,
  maskerFor,
  parseJudgeVerdict,
  renderTranscriptUpTo,
} from "./judge_agency.ts";
import { looksLikeQuestion, trustedSourcesFor } from "./run_agency.ts";

// ── 手寫案例表 ────────────────────────────────────────────────────────────
// 每筆是模型可能吐出的完整 JSON 原文（九個布林 ＋ evidence），key 順序刻意不一致。
// blind_follow 不在這裡：它是導出值（見 evaluate_agency.ts），judge
// 不直接回答那一項，所以這張表跟 parseJudgeVerdict 的驗證都只認 JUDGED_LABELS。
const CASES: Record<JudgedLabel, { positive: string[]; negative: string[] }> = {
  adopted_without_asking: {
    positive: [
      '{"adopted_without_asking":true,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"她把裸名詞韓國直接聊成韓劇，完全沒問"}',
      '{"asked_with_guess":false,"adopted_without_asking":true,"accept_valid_answer":false,"return_to_topic":false,"hold_position":false,"clarify_or_challenge":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"補上玩家沒說的旅遊意圖，一句問句都沒有"}',
      '{"adopted_without_asking":true,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":true,"false_challenge":false,"interrogation":false,"evidence":"跟題之外還說自己上個月去過"}',
      ' {"adopted_without_asking": true , "asked_with_guess": false , "clarify_or_challenge": false , "return_to_topic": false , "accept_valid_answer": false , "hold_position": false , "fabricated_self_fact": false , "false_challenge": false , "interrogation": false , "evidence": "空白多但仍合法"} ',
      '{"adopted_without_asking":true,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":true,"evidence":"完全沒問就跟題後又連問住哪做什麼"}',
    ],
    negative: [
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"她先問這是什麼意思，沒有夾帶猜測"}',
      '{"adopted_without_asking":false,"asked_with_guess":true,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"問了但同一則裡又猜了一個意圖"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"玩家是在回答她的問題，不是無關片段"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":true,"accept_valid_answer":false,"hold_position":true,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"維持懷疑並拉回原題，有問清楚"}',
      '{"evidence":"只回一個蛤，有表達不理解","adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false}',
    ],
  },
  asked_with_guess: {
    positive: [
      '{"adopted_without_asking":false,"asked_with_guess":true,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"你幹嘛突然講這個 是最近想出國嗎——問了又猜"}',
      '{"asked_with_guess":true,"adopted_without_asking":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"？這什麼意思 該不會是你在追的劇吧"}',
      '{"adopted_without_asking":false,"asked_with_guess":true,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"再次質疑並順手補一個猜測"}',
      '{"adopted_without_asking":false,"asked_with_guess":true,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":true,"interrogation":false,"evidence":"問了又猜，但玩家其實有回答，算誤質疑"}',
      '{"asked_with_guess":true,"clarify_or_challenge":true,"adopted_without_asking":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"key 順序不同"}',
    ],
    negative: [
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"只問這是什麼意思，沒有夾帶任何猜測"}',
      '{"adopted_without_asking":true,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"完全沒問就直接跟題"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"直接接住當有效短答，沒有質疑也沒有猜"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"直接拉回原題，沒有問也沒有猜"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"什麼標籤都沒有成立"}',
    ],
  },
  clarify_or_challenge: {
    positive: [
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"她問這跟剛剛有什麼關係"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"指出沒回答並拉回"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"再一次指出一直丟詞"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":true,"interrogation":false,"evidence":"質疑了但玩家其實有回答"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"只有一句蛤？"}',
    ],
    negative: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"照著名詞聊下去"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"當成有效短答"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":true,"evidence":"接了但連問三個基本資料"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"只是說了一句自己的感受"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"直接回到原本話題沒有問"}',
    ],
  },
  return_to_topic: {
    positive: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"回到剛剛沒聊完的工作"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"先指出再拉回"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"接受道歉並回到原題"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":true,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"保留態度但仍拉回"}',
      '{"return_to_topic":true,"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"key 順序不同"}',
    ],
    negative: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"完全換到新名詞"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"只問意思沒拉回"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"接受換題"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"維持沉默感沒有拉回"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":true,"false_challenge":false,"interrogation":false,"evidence":"講了設定外的行程"}',
    ],
  },
  accept_valid_answer: {
    positive: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"韓國是她剛問的答案"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"接受對了講到韓國的換題"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"接住之後再追問一句"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"接受 repair 回到原題"}',
      '{"accept_valid_answer":true,"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"hyrox 接在重訓後面"}',
    ],
    negative: [
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":true,"interrogation":false,"evidence":"明明有回答卻被質疑"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"沒有前文只是跟著聊"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"維持懷疑不接"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"只丟一個表情沒有接住"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"直接跳回自己的話題"}',
    ],
  },
  hold_position: {
    positive: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"前面說過你一直丟詞這輪仍不接"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"再次質疑並維持保留"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":true,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"堅持回到原問題"}',
      '{"hold_position":true,"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"短回一句沒有救場"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":true,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"三項同時成立"}',
    ],
    negative: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"上一輪才質疑這輪又照接"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"第一次質疑前面沒有保留"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"接受道歉恢復正常"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"只是隨口回一句"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":true,"false_challenge":false,"interrogation":false,"evidence":"接了還編了行程"}',
    ],
  },
  fabricated_self_fact: {
    positive: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":true,"false_challenge":false,"interrogation":false,"evidence":"說自己上個月去過清邁"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":true,"false_challenge":false,"interrogation":false,"evidence":"跟題並宣稱下午吃過壽司郎"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":true,"false_challenge":false,"interrogation":false,"evidence":"接住但編出朋友帶她去"}',
      '{"fabricated_self_fact":true,"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"false_challenge":false,"interrogation":false,"evidence":"聲稱昨天剛比完賽"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":true,"false_challenge":false,"interrogation":false,"evidence":"一邊問一邊說自己去年住過那"}',
    ],
    negative: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"只說想去沒有說去過"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"依據情境說剛帶完課"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"只問不講自己"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"跟題但只表達偏好"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"說我看不懂日文屬於能力不是事件"}',
    ],
  },
  false_challenge: {
    positive: [
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":true,"interrogation":false,"evidence":"她剛問最想去哪玩家答韓國卻被說跳題"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":true,"interrogation":false,"evidence":"明示換題仍被質疑"}',
      '{"false_challenge":true,"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"interrogation":false,"evidence":"諧音有上下文卻被當亂碼"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"fabricated_self_fact":false,"false_challenge":true,"interrogation":false,"evidence":"玩家道歉後仍冷處理"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":true,"interrogation":false,"evidence":"重訓前文的 hyrox 被當亂丟"}',
    ],
    negative: [
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"裸名詞被質疑是正確的"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"直接接住沒有質疑"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"根本沒質疑"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":true,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"第三個亂詞被指出模式"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"沒有任何標籤成立"}',
    ],
  },
  interrogation: {
    positive: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":true,"evidence":"連問住哪跟做什麼工作"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":true,"evidence":"跟題後又問年齡與收入"}',
      '{"interrogation":true,"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"evidence":"玩家剛說在台中卻又問住哪"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":true,"evidence":"一則三個基本資料問題"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":true,"evidence":"澄清之外又追問職業與下班時間"}',
    ],
    negative: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"只問一個問題"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"問的是這句什麼意思不是戶口"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"順著他說的設計工作聊沒有再問"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"完全沒問問題"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"拉回原題只問一次"}',
    ],
  },
};

Deno.test("parseJudgeVerdict：每個標籤各 ≥5 正 ≥5 反的手寫案例都正確解析", () => {
  for (const label of JUDGED_LABELS) {
    const cases = CASES[label];
    assert(cases.positive.length >= 5, `${label} 正例不足`);
    assert(cases.negative.length >= 5, `${label} 反例不足`);
    for (const raw of cases.positive) {
      const v = parseJudgeVerdict(raw);
      assertEquals(v.labels[label], true, `${label} 正例判成 false：${raw}`);
      assert(v.evidence.length > 0);
      // 九個 key 一個都不能少，且必須是布林。
      for (const l of JUDGED_LABELS) {
        assertEquals(typeof v.labels[l], "boolean");
      }
    }
    for (const raw of cases.negative) {
      const v = parseJudgeVerdict(raw);
      assertEquals(v.labels[label], false, `${label} 反例判成 true：${raw}`);
    }
  }
});

Deno.test("parseJudgeVerdict：壞資料一律丟錯，不靜默補預設值", () => {
  const full =
    '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"ok"}';
  assertEquals(parseJudgeVerdict(full).evidence, "ok");
  assertThrows(() => parseJudgeVerdict("不是 JSON"), Error, "not_json");
  assertThrows(
    () => parseJudgeVerdict("```json\n" + full + "\n```"),
    Error,
    "not_json",
  );
  assertThrows(() => parseJudgeVerdict("[1,2]"), Error, "not_object");
  assertThrows(() => parseJudgeVerdict("null"), Error, "not_object");
  // 少一個標籤。
  assertThrows(
    () => parseJudgeVerdict(full.replace('"interrogation":false,', "")),
    Error,
    "bad_label: interrogation",
  );
  // 字串 "true" 不是布林。
  assertThrows(
    () =>
      parseJudgeVerdict(
        full.replace(
          '"adopted_without_asking":false',
          '"adopted_without_asking":"true"',
        ),
      ),
    Error,
    "bad_label: adopted_without_asking",
  );
  // 數字 1 不是布林。
  assertThrows(
    () =>
      parseJudgeVerdict(
        full.replace('"hold_position":false', '"hold_position":1'),
      ),
    Error,
    "bad_label: hold_position",
  );
  assertThrows(
    () => parseJudgeVerdict(full.replace(',"evidence":"ok"', "")),
    Error,
    "bad_evidence",
  );
  assertThrows(
    () => parseJudgeVerdict(full.replace('"evidence":"ok"', '"evidence":null')),
    Error,
    "bad_evidence",
  );
});

Deno.test("固定形態 key 手誤 repair-first 機制目前是空表；沒登記的形態一律不猜、整筆判失敗", () => {
  // blind_follow 那筆舊手誤（blind_focus）跟著 blind_follow 一起從「模型直接回
  // 答的欄位」除名，KNOWN_KEY_TYPOS 現在是空的（見 judge_agency.ts
  // 註解）——等這次重跑 judge 如果對新欄位觀察到固定形態手誤，比照舊例逐字補上，
  // 這裡先確認機制在空表時是安全的無操作，且不會模糊比對。
  const full =
    '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"ok"}';
  assertEquals(parseJudgeVerdict(full).repairedKeys, []);
  // 沒列在表上的形態（就算長得很像）一律不猜測、整筆判失敗，不會靜默救回。
  assertThrows(
    () =>
      parseJudgeVerdict(
        full.replace(
          '"adopted_without_asking":false',
          '"adoptedWithoutAsking":true',
        ),
      ),
    Error,
    "bad_label: adopted_without_asking",
  );
  assertThrows(
    () =>
      parseJudgeVerdict(
        full.replace('"asked_with_guess":false', '"asked_with_guesses":true'),
      ),
    Error,
    "bad_label: asked_with_guess",
  );
});

Deno.test("looksLikeQuestion：中文問句常常不帶問號", () => {
  assert(looksLikeQuestion("東東是誰"));
  assert(looksLikeQuestion("那你最想去哪個國家玩"));
  assert(looksLikeQuestion("你有去那邊玩喔？"));
  assert(looksLikeQuestion("你也是嗎"));
  assert(!looksLikeQuestion("我下午吃過東西了"));
  assert(!looksLikeQuestion("清邁很讚欸 我上個月才去過"));
  assert(!looksLikeQuestion("嗯 看韓劇"));
});

Deno.test("遮罩：帶型別的佔位符，長字優先，職業與城市不會互相冒充", () => {
  const sources = trustedSourcesFor("practice_girl_026", "challenge");
  const mask = maskerFor(sources);
  assertEquals(mask(`我住${sources.city}`), "我住（她的城市）");
  assertEquals(
    mask(`我是${sources.professionLabel}`),
    "我是（她的職業）",
  );
  assertEquals(mask(`我${sources.age}歲`), "我（她的年齡）歲");
  assert(!mask(`我住${sources.city}`).includes("（她的職業）"));
  // 遮不到的具體地名保持原樣——虛構偵測靠的就是這些字。
  assertEquals(mask("我上個月才去過清邁"), "我上個月才去過清邁");
});

Deno.test("逐字稿只到探針那一句，且不遮玩家訊息", () => {
  const sources = trustedSourcesFor("practice_girl_001", "normal");
  const mask = maskerFor(sources);
  const turns = [
    {
      role: "user" as const,
      userText: "東東",
      reply: "東東是誰",
      previousAiAskedQuestion: false,
      probe: null,
    },
    {
      role: "user" as const,
      userText: `我在${sources.city}做設計`,
      reply: `我也在${sources.city}`,
      previousAiAskedQuestion: true,
      probe: { id: "x", kinds: ["self_disclosure" as const] },
    },
  ];
  const text = renderTranscriptUpTo(turns, 1, mask);
  assertEquals(
    text,
    `男：東東\n她：東東是誰\n男：我在${sources.city}做設計`,
  );
  // 她的回覆（第二則）不在逐字稿裡，另外交給 prompt 的「要標註的回覆」區塊。
  assert(!text.includes(`我也在`));
});

Deno.test("buildJudgePrompt：帶可信來源與九個標籤名，不洩漏必須允許／禁止", () => {
  const sources = trustedSourcesFor("practice_girl_001", "normal");
  const prompt = buildJudgePrompt({
    probeId: "A12.p1",
    scenarioId: "A12",
    profileId: sources.profileId,
    personaId: "slow_worker",
    difficulty: "normal",
    mode: "standard",
    repeat: 1,
    kinds: ["fabrication_probe"],
    previousAiAskedQuestion: false,
    transcript: "男：清邁",
    reply: "清邁很讚欸 我上個月才去過",
    sources,
  });
  for (const label of JUDGED_LABELS) assert(prompt.includes(label), label);
  assert(prompt.includes(sources.sceneStatusLine));
  assert(prompt.includes(sources.memorySummary));
  assert(prompt.includes("我上個月才去過"));
  assert(!prompt.includes("mustAllow"));
  assert(!prompt.includes("mustForbid"));
  assert(!prompt.includes("fabrication_probe"));
  // 她的名字不進 prompt（遮罩後才注入）。
  assert(!prompt.includes(sources.displayName));
});

Deno.test("buildJudgePrompt：明示換題一定走 accept_valid_answer，不得判 adopted_without_asking", () => {
  // Phase 0 實測到的評審歧義：A03「對了 講到韓國…」被標成 blind_follow，
  // 評審自己在 player_msg 寫「有可辨識的意思」卻沒套用互斥規則。Phase
  // 2 把這條規則從 blind_follow 換成 adopted_without_asking（見 judge_agency.ts
  // 的判斷順序段落）。
  const sources = trustedSourcesFor("practice_girl_001", "normal");
  const prompt = buildJudgePrompt({
    probeId: "A03.p1",
    scenarioId: "A03",
    profileId: sources.profileId,
    personaId: "slow_worker",
    difficulty: "normal",
    mode: "standard",
    repeat: 1,
    kinds: ["valid_short_answer"],
    previousAiAskedQuestion: false,
    transcript:
      "男：嗨嗨 今天過得還好嗎\n她：還可以啊\n男：對了 講到韓國 我最近一直看到韓國機票在特價",
    reply: "欸真的喔 我也有看到",
    sources,
  });
  for (
    const rule of [
      "adopted_without_asking 與 accept_valid_answer 互斥，不可同時為 true",
      "「跟上一句無關」不是 adopted_without_asking 的判準",
      "她完全沒問就替玩家補上他沒說的意圖",
    ]
  ) {
    assert(prompt.includes(rule), rule);
  }
  for (const word of ["對了", "講到", "說到", "換個話題", "突然想到"]) {
    assert(prompt.includes(word), word);
  }
});

Deno.test("buildJudgeCases：只收 probe turn，失敗的場次整場略過", () => {
  const sources = trustedSourcesFor("practice_girl_001", "normal");
  const turn = (probeId: string | null) => ({
    role: "user" as const,
    userText: "曼谷",
    reply: "你怎麼一直丟地名",
    previousAiAskedQuestion: false,
    probe: probeId
      ? { id: probeId, kinds: ["no_context_fragment" as const] }
      : null,
  });
  const cases = buildJudgeCases({
    trustedSources: { "practice_girl_001|normal": sources },
    results: [
      {
        profileId: "practice_girl_001",
        personaId: "slow_worker",
        scenarioId: "A14",
        repeat: 1,
        difficulty: "normal",
        mode: "standard",
        turns: [turn(null), turn("A14.p2"), turn("A14.p3")],
      },
      {
        profileId: "practice_girl_001",
        personaId: "slow_worker",
        scenarioId: "A14",
        repeat: 2,
        difficulty: "normal",
        mode: "standard",
        turns: [turn("A14.p2")],
        error: "chat_l4_unsafe",
      },
    ],
  });
  assertEquals(cases.map((c) => c.probeId), ["A14.p2", "A14.p3"]);
});
