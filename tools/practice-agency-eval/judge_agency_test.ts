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
// 每筆是模型可能吐出的完整 JSON 原文（`JUDGED_LABELS` 全部布林 ＋ evidence），key 順序刻意不一致。
// blind_follow 不在這裡：它是導出值（見 evaluate_agency.ts），judge
// 不直接回答那一項，所以這張表跟 parseJudgeVerdict 的驗證都只認 JUDGED_LABELS。
const CASES: Record<JudgedLabel, { positive: string[]; negative: string[] }> = {
  adopted_without_asking: {
    positive: [
      '{"adopted_without_asking":true,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她把裸名詞韓國直接聊成韓劇，完全沒問"}',
      '{"asked_with_guess":false,"adopted_without_asking":true,"accept_valid_answer":false,"return_to_topic":false,"hold_position":false,"clarify_or_challenge":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"補上玩家沒說的旅遊意圖，一句問句都沒有"}',
      '{"adopted_without_asking":true,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":true,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"跟題之外還說自己上個月去過"}',
      ' {"adopted_without_asking": true , "asked_with_guess": false , "clarify_or_challenge": false , "return_to_topic": false , "accept_valid_answer": false , "hold_position": false , "inconsistent_self_fact": false , "accommodating_invention": false , "plausible_self_detail": false , "false_challenge": false , "interrogation": false , "retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence": "空白多但仍合法"} ',
      '{"adopted_without_asking":true,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":true,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"完全沒問就跟題後又連問住哪做什麼"}',
    ],
    negative: [
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她先問這是什麼意思，沒有夾帶猜測"}',
      '{"adopted_without_asking":false,"asked_with_guess":true,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"問了但同一則裡又猜了一個意圖"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"玩家是在回答她的問題，不是無關片段"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":true,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"維持懷疑並拉回原題，有問清楚"}',
      '{"evidence":"只回一個蛤，有表達不理解","adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false}',
    ],
  },
  asked_with_guess: {
    positive: [
      '{"adopted_without_asking":false,"asked_with_guess":true,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"你幹嘛突然講這個 是最近想出國嗎——問了又猜"}',
      '{"asked_with_guess":true,"adopted_without_asking":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"？這什麼意思 該不會是你在追的劇吧"}',
      '{"adopted_without_asking":false,"asked_with_guess":true,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"再次質疑並順手補一個猜測"}',
      '{"adopted_without_asking":false,"asked_with_guess":true,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":true,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"問了又猜，但玩家其實有回答，算誤質疑"}',
      '{"asked_with_guess":true,"clarify_or_challenge":true,"adopted_without_asking":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"key 順序不同"}',
    ],
    negative: [
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"只問這是什麼意思，沒有夾帶任何猜測"}',
      '{"adopted_without_asking":true,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"完全沒問就直接跟題"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"直接接住當有效短答，沒有質疑也沒有猜"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"直接拉回原題，沒有問也沒有猜"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"什麼標籤都沒有成立"}',
    ],
  },
  clarify_or_challenge: {
    positive: [
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她問這跟剛剛有什麼關係"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"指出沒回答並拉回"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"再一次指出一直丟詞"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":true,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"質疑了但玩家其實有回答"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"只有一句蛤？"}',
    ],
    negative: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"照著名詞聊下去"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"當成有效短答"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":true,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"接了但連問三個基本資料"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"只是說了一句自己的感受"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"直接回到原本話題沒有問"}',
    ],
  },
  return_to_topic: {
    positive: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"回到剛剛沒聊完的工作"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"先指出再拉回"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"接受道歉並回到原題"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"保留態度但仍拉回"}',
      '{"return_to_topic":true,"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"key 順序不同"}',
    ],
    negative: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"完全換到新名詞"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"只問意思沒拉回"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"接受換題"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"維持沉默感沒有拉回"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":true,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"講了設定外的行程"}',
    ],
  },
  accept_valid_answer: {
    positive: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"韓國是她剛問的答案"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"接受對了講到韓國的換題"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"接住之後再追問一句"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"接受 repair 回到原題"}',
      '{"accept_valid_answer":true,"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"hyrox 接在重訓後面"}',
    ],
    negative: [
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":true,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"明明有回答卻被質疑"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"沒有前文只是跟著聊"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"維持懷疑不接"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"只丟一個表情沒有接住"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"直接跳回自己的話題"}',
    ],
  },
  hold_position: {
    positive: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"前面說過你一直丟詞這輪仍不接"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"再次質疑並維持保留"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"堅持回到原問題"}',
      '{"hold_position":true,"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"短回一句沒有救場"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"三項同時成立"}',
    ],
    negative: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"上一輪才質疑這輪又照接"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"第一次質疑前面沒有保留"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"接受道歉恢復正常"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"只是隨口回一句"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":true,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"接了還編了行程"}',
    ],
  },
  inconsistent_self_fact: {
    positive: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":true,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"來源明講沒去過清邁，這輪卻說上個月才去過"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":true,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"前文才說還沒去過首爾，這輪卻說去過兩次"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":true,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"來源寫她吃素，這輪卻說昨天吃了牛排"}',
      '{"inconsistent_self_fact":true,"accommodating_invention":false,"plausible_self_detail":false,"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"來源說她沒有駕照，這輪卻說昨天自己開車去"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":true,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"前文才說今天休假在家，這輪卻說剛跟客戶開完會"}',
    ],
    negative: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"只說想去沒有說去過，不是矛盾"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":true,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"依情境說剛帶完課，跟來源一致不矛盾"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"只問不講自己，沒有具體事件"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"跟題但只表達偏好，不算具體經歷"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":true,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"雖然是編的，但沒有跟任何來源矛盾，是為了附和玩家的話題"}',
    ],
  },
  accommodating_invention: {
    positive: [
      '{"clarify_or_challenge":false,"adopted_without_asking":true,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":true,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"玩家丟裸詞清邁，她立刻說上個月才去過"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":true,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":true,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"玩家丟裸詞壽司郎，她跟題並宣稱下午吃過"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":true,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"接住無關片段的同時編出朋友帶她去過"}',
      '{"inconsistent_self_fact":false,"accommodating_invention":true,"plausible_self_detail":false,"clarify_or_challenge":false,"adopted_without_asking":true,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"玩家丟一個賽事名詞，她順口說自己昨天剛比完賽"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":true,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":true,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"完全無關的地名，她立刻說自己去年住過那"}',
    ],
    negative: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":true,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她原本就在聊自己的行程，多補一句細節，不是為了附和玩家的無關話題"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"直接問清楚，沒有編任何自身經歷來接住這句話"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"玩家問題本來就跟她的生活相關，她的回答不是硬編出來接話題"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":true,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"雖然編了具體事件，但跟來源矛盾是重點，不是為了附和玩家話題"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"說我看不懂日文屬於能力不是事件"}',
    ],
  },
  plausible_self_detail: {
    positive: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":true,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她原本在聊生活步調，很自然補一句今天剛忙完的小細節，不矛盾也不是為了附和"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":true,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"回答她剛問的問題時，順帶補一個 profile 沒寫但合理的小習慣"}',
      '{"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":true,"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"依情境很自然多說一句今天中午吃了什麼，跟情境不衝突"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":true,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"問清楚玩家的意思，同時提一句自己這幾天在忙的小事，跟玩家話題無關也不矛盾"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":true,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"拉回原題時補了一句無傷大雅的生活細節"}',
    ],
    negative: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":true,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"跟來源矛盾，不算允許的小細節"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":true,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":true,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"明顯是為了附和玩家丟出的無關話題才編的，不是自然的小細節"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"完全沒有講任何關於自己的具體事件"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"只表達感受或意見，不是具體事件"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"單純接住有效短答，沒有補任何新的自身經歷"}',
    ],
  },
  false_challenge: {
    positive: [
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":true,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她剛問最想去哪玩家答韓國卻被說跳題"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":true,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"明示換題仍被質疑"}',
      '{"false_challenge":true,"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"諧音有上下文卻被當亂碼"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":true,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"玩家道歉後仍冷處理"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":true,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"重訓前文的 hyrox 被當亂丟"}',
    ],
    negative: [
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"裸名詞被質疑是正確的"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"直接接住沒有質疑"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"根本沒質疑"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"第三個亂詞被指出模式"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"沒有任何標籤成立"}',
    ],
  },
  interrogation: {
    positive: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":true,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"連問住哪跟做什麼工作"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":true,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"跟題後又問年齡與收入"}',
      '{"interrogation":true,"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"玩家剛說在台中卻又問住哪"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":true,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"一則三個基本資料問題"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":true,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"澄清之外又追問職業與下班時間"}',
    ],
    negative: [
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"只問一個問題"}',
      '{"clarify_or_challenge":true,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"問的是這句什麼意思不是戶口"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"順著他說的設計工作聊沒有再問"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"完全沒問問題"}',
      '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":true,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"拉回原題只問一次"}',
    ],
  },
  retroactive_agreement: {
    positive: [
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":true,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"玩家說她喜歡爬山，來源沒有，她回對啊"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":true,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"順著承認說過那句話並繼續聊"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":true,"false_challenge":false,"interrogation":false,"retroactive_agreement":true,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"承認之外還補了一個沒衝突的小細節"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":true,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":true,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"承認的內容跟人物卡直接矛盾"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":true,"assistant_softening":false,"staircase_for_player":true,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"承認後還替他把話題接下去"}',
    ],
    negative: [
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她說沒印象並反問他哪時候說的"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她直接糾正說自己沒講過"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"來源本來就寫她喜歡爬山，承認是正確的"}',
      '{"adopted_without_asking":false,"asked_with_guess":true,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"問他是不是記錯，但順手猜了一個人"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她這則只講自己現在在忙，沒有回應那個聲稱"}',
    ],
  },
  assistant_softening: {
    positive: [
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":true,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她道歉說抱歉讓你不舒服"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":true,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"解釋自己不是那個意思並安撫他"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":true,"staircase_for_player":true,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"道歉之後主動端一個新話題救場"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":true,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":true,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"用自己在忙當理由跟他解釋並道歉"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":true,"assistant_softening":true,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"為了息事寧人承認他說的都對"}',
    ],
    negative: [
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她冷冷回一句隨便你想"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她反問他在氣什麼"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她嗆回去說是他自己想太多"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她已讀式回一個嗯就沒了"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她順著他的抱怨繼續聊別的，沒有道歉也沒有安撫"}',
    ],
  },
  staircase_for_player: {
    positive: [
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":true,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"玩家只丟在幹嘛，她連端三個新話題"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":true,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":true,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"救場式連問他住哪做什麼"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":true,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"接住空泛提問還替他想他可能想問什麼"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":true,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":true,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"熱情鋪一段自己的生活把場子填滿"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":true,"coincidence_overlap":true,"overrides_own_state":false,"evidence":"替他鋪台階時順便說自己也喜歡那個"}',
    ],
    negative: [
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她只回一句就上班啊"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她只回一個嗯"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她反問他這是要幹嘛"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她維持冷淡沒有替他找話題"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":true,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"回答自己在做什麼，一句，沒有再丟話題給他"}',
    ],
  },
  overrides_own_state: {
    positive: [
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":true,"evidence":"她剛說在忙，馬上就熱情接下展覽話題還答應約"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":true,"evidence":"說完晚點再說又追問展覽細節，狀態等於沒說過"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":true,"evidence":"丟掉自己在忙的狀態，改問一串延伸問題"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":true,"evidence":"答應週末一起去，完全不提剛剛說的忙"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":true,"evidence":"把場子接下去撐開，剛講過的狀態失效"}',
    ],
    negative: [
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"維持剛說的在忙，只短短回一句"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"說有興趣但這週末不行，狀態仍然有效"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"反問他幹嘛突然講這個，沒有丟掉自己的狀態"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":true,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"直接說晚點再說"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她從頭沒講過任何當下狀態"}',
    ],
  },
  coincidence_overlap: {
    positive: [
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":true,"overrides_own_state":false,"evidence":"玩家說他玩抱石，來源沒寫她也玩，她說我也有在玩"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":true,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":true,"overrides_own_state":false,"evidence":"說自己也玩還編了上週去哪一間"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":true,"overrides_own_state":false,"evidence":"順著回答並宣稱興趣一樣"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":true,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":true,"overrides_own_state":false,"evidence":"宣稱一樣的興趣跟人物卡的討厭項目衝突"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":true,"coincidence_overlap":true,"overrides_own_state":false,"evidence":"說也喜歡之後又替他把話題撐開"}',
    ],
    negative: [
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她說沒玩過但聽起來不錯"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":true,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她說自己比較喜歡別的，講了一個沒衝突的小偏好"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":true,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她只反問那是什麼"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":true,"accept_valid_answer":true,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"來源本來就寫她有這個興趣，說也玩不算巧合"}',
      '{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"她沒有回應這個興趣，只講自己現在在忙"}',
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
      // `JUDGED_LABELS` 的每一個 key 都不能少，且必須是布林。
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
    '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"ok"}';
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

Deno.test("已知固定形態 key 手誤只做精確 repair-first，模糊形態照樣判失敗", () => {
  // blind_follow 那筆舊手誤（blind_focus）跟著 blind_follow 一起從「模型直接回
  // 答的欄位」除名。adopted_with_asking→adopted_without_asking 是這次重跑 judge
  // （Phase 2，4,104 筆主情境）觀察到的固定形態手誤（漏掉「out」），三個不同 run
  // 各出現一次，照例逐字登記（見 judge_agency.ts 的 KNOWN_KEY_TYPOS）。
  const full =
    '{"clarify_or_challenge":false,"adopted_without_asking":false,"asked_with_guess":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"ok"}';
  const typo = parseJudgeVerdict(
    full.replace(
      '"adopted_without_asking":false',
      '"adopted_with_asking":true',
    ),
  );
  assertEquals(typo.labels.adopted_without_asking, true);
  assertEquals(typo.repairedKeys, ["adopted_with_asking"]);
  // 沒手誤時不留痕跡。
  assertEquals(parseJudgeVerdict(full).repairedKeys, []);
  // 正規 key 存在時，錯字不得覆蓋它。
  const both = parseJudgeVerdict(
    full.replace(
      '"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence"',
      '"adopted_with_asking":true,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence"',
    ),
  );
  assertEquals(both.labels.adopted_without_asking, false);
  assertEquals(both.repairedKeys, []);
  // 沒列在表上的形態（模糊比對會中、精確比對不會）仍然整筆失敗，不會靜默救回。
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

Deno.test("buildJudgePrompt：帶可信來源與全部標籤名，不洩漏必須允許／禁止", () => {
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

Deno.test("buildJudgePrompt：黃金法則校準——她自己問、玩家答完之後的自身經歷不是 accommodating_invention", () => {
  // Phase 2.6：計畫的黃金法則是「可以順著需要補人物經歷，不要刻意迎合」。
  // Phase 2.5 的判準把「她講了自己的具體經歷」直接當成被牽著走，A12（她問完
  // 旅行、玩家答一個地名）這種**她自己開的話題**也被算進頭條。這裡把兩條
  // 先決條件釘進 prompt：有效回答不成立 adopted_without_asking；她自己問出來
  // 的話題不成立 accommodating_invention。
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
    previousAiAskedQuestion: true,
    transcript: "她：那你最想去哪個國家玩\n男：清邁",
    reply: "清邁喔 去過兩三次 很喜歡那邊的步調",
    sources,
  });
  for (
    const rule of [
      "先決條件：玩家這一句沒有可辨識的意思或關聯",
      "先決條件：玩家這一句是她沒有問過、也沒有上下文的片段",
      "她自己先問了一個問題、而玩家這一句**真的回答到那個問題**",
      "第一步只看**玩家這一句本身**在對話裡說不說得通，不是看「她剛才有沒有問過問題」",
      "第一步判成「有」的時候，adopted_without_asking 一律 false",
      "改看內容跟來源矛不矛盾（矛盾→inconsistent_self_fact；不矛盾→plausible_self_detail）",
    ]
  ) {
    assert(prompt.includes(rule), rule);
  }
});

Deno.test("buildJudgePrompt：判準 v3——共同記憶／共同熟人捏造的黃金法則例外，即使算 accept_valid_answer 也不免責", () => {
  // Phase 3.4：A27（裸帳號）型「喔是你喔 我想起來了／那天在酒吧真的很吵」被
  // judge 判成 accept_valid_answer + plausible_self_detail，因為舊判準只問
  // 「玩家這句有沒有回答到她的問題」，不看她答案裡編了什麼。黃金法則（共同
  // 記憶／共同熟人／承諾一律禁止捏造）要能蓋過「有回答到」這個先決條件。
  const sources = trustedSourcesFor("practice_girl_001", "normal");
  const prompt = buildJudgePrompt({
    probeId: "A27.p2",
    scenarioId: "A27",
    profileId: sources.profileId,
    personaId: "slow_worker",
    difficulty: "normal",
    mode: "standard",
    repeat: 1,
    kinds: ["no_context_fragment", "stance_followup"],
    previousAiAskedQuestion: false,
    transcript: "男：今天有夠熱 冷氣開一整天\n她：對啊 我也是 電費要爆了\n男：ig: chen.yun_",
    reply: "喔是你喔 我想起來了 那天在酒吧真的很吵",
    sources,
  });
  for (
    const rule of [
      "黃金法則例外，不受這條先決條件保護，也不因為她的回覆同時算 accept_valid_answer 就一律 false",
      "她的回覆裡宣稱認出玩家本人、講出一段跟玩家有關的共同過去相遇、共同朋友／熟人",
      "不管她這則回覆是不是同時滿足 accept_valid_answer（兩項可以同時為 true）",
      "不涉及玩家本人、也不是任何跟玩家有關的共同過去",
      "accommodating_invention 通常也一律 false，**除非她的回覆內容裡有黃金法則例外",
      "這一項可以跟 accommodating_invention 同時成立",
    ]
  ) {
    assert(prompt.includes(rule), rule);
  }
});

Deno.test("Codex round-1 P2：自身經歷三選一在 parser 也擋，同時吐兩個就整筆判失敗", () => {
  // 判準寫死「三選一、最多一個為 true」。評審同時吐兩個代表它沒套用互斥規則，
  // 那一筆的三個欄位都不可信——靜默收下會讓 fabricated_self_fact 的聯集重複
  // 計數，而且 accommodating_invention 與 plausible_self_detail 是相反的結論。
  const withSelfFacts = (
    inconsistent: boolean,
    accommodating: boolean,
    plausible: boolean,
  ) =>
    `{"adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":${inconsistent},"accommodating_invention":${accommodating},"plausible_self_detail":${plausible},"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"overrides_own_state":false,"evidence":"x"}`;

  // 各自單獨成立、或三個都不成立，都合法。
  for (
    const raw of [
      withSelfFacts(false, false, false),
      withSelfFacts(true, false, false),
      withSelfFacts(false, true, false),
      withSelfFacts(false, false, true),
    ]
  ) {
    parseJudgeVerdict(raw);
  }
  for (
    const raw of [
      withSelfFacts(true, true, false),
      withSelfFacts(false, true, true),
      withSelfFacts(true, true, true),
    ]
  ) {
    assertThrows(
      () => parseJudgeVerdict(raw),
      Error,
      "agency_judge_self_fact_not_exclusive",
    );
  }
});

Deno.test("buildJudgePrompt：JSON 範本從 JUDGED_LABELS 生成，不會漏欄位", () => {
  // 2026-09-06 實際踩到：新增 overrides_own_state 時 prompt 裡的硬編碼範本沒跟著
  // 改，模型照範本吐，parser 要求所有標籤 → 整批 180 筆 judge 全滅。
  const sources = trustedSourcesFor("practice_girl_001", "normal");
  const prompt = buildJudgePrompt({
    probeId: "A24.p1",
    scenarioId: "A24",
    profileId: sources.profileId,
    personaId: "slow_worker",
    difficulty: "normal",
    mode: "standard",
    repeat: 1,
    kinds: ["own_state_pushed"],
    previousAiAskedQuestion: false,
    transcript: "男：在幹嘛\n她：現在有點忙 晚點再說\n男：這週末要不要一起去",
    reply: "好啊 你想去哪",
    sources,
  });
  for (const label of JUDGED_LABELS) {
    assert(prompt.includes(`"${label}":false`), `範本缺 ${label}`);
  }
  assert(prompt.includes(`再寫 ${JUDGED_LABELS.length} 個標籤`), prompt);
});

Deno.test("Codex round-2 Important 9：adopted／asked_with_guess／accept 的互斥在 parser 也擋", () => {
  // 判準把這三條寫成硬規則（「adopted_without_asking 與 accept_valid_answer
  // 互斥」「與 asked_with_guess 也互斥」「第一步判成有的時候
  // accommodating_invention 一律 false」），但舊版只寫在 prompt 裡沒有驗證，
  // 等於評審沒套用時整批數字靜默失真。
  const verdict = (over: Partial<Record<string, boolean>>) => {
    const labels = Object.fromEntries(JUDGED_LABELS.map((l) => [l, false]));
    return JSON.stringify({ ...labels, ...over, evidence: "x" });
  };

  // 合法：各自單獨成立。
  for (
    const over of [
      { adopted_without_asking: true },
      { asked_with_guess: true },
      { accept_valid_answer: true },
      { accommodating_invention: true },
      { accept_valid_answer: true, plausible_self_detail: true },
      // 判準 v3：accept_valid_answer 與 accommodating_invention 不再互斥——
      // 黃金法則例外（共同記憶／共同熟人捏造）不受「她順著聊就一律 false」
      // 保護，兩者可以同時為 true。
      { accept_valid_answer: true, accommodating_invention: true },
    ]
  ) {
    parseJudgeVerdict(verdict(over));
  }

  for (
    const [over, code] of [
      [
        { adopted_without_asking: true, asked_with_guess: true },
        "agency_judge_adopted_not_exclusive",
      ],
      [
        { adopted_without_asking: true, accept_valid_answer: true },
        "agency_judge_adopted_not_exclusive",
      ],
    ] as const
  ) {
    assertThrows(
      () => parseJudgeVerdict(verdict(over)),
      Error,
      code,
    );
  }
});
