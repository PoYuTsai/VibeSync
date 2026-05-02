// Spec 5 C23 — phase input sheet (3 phase variants).
//
// Implements design §1.2 Click-First Input Flow. Each phase has its own
// Q1/Q2/Q3 option set; Q1 is always required, Q2 is required only for
// postDateReflection, Q3 is always free-text optional 80 chars.
//
// Stable-key discipline: option values are English keys (`fuzzy`,
// `concrete`, ...) stored internally and forwarded to the wire. 繁中 labels
// only render at the chip surface — Edge function never receives the
// localized strings (locked by C19's wire shape).

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/services/coach_follow_up_api_service.dart';
import '../../domain/entities/coach_follow_up_phase.dart';

// ── Option records (stable key, 繁中 label) ────────────────────────────────
//
// Records syntax matches the implementation-plan example. The first slot is
// the wire key; the second is what the user sees. Translations stay here so
// a future i18n pass can swap labels without touching the wire contract.

const _q1PrepareInvite = <(String, String)>[
  ('fuzzy', '模糊邀約（看看她要不要）'),
  ('concrete', '具體邀約（時間 + 活動都明確）'),
  ('undecided', '還沒想好'),
];

const _q2PrepareInvite = <(String, String)>[
  ('fearRejection', '被拒絕'),
  ('fearTooEager', '顯得太急'),
  ('noReason', '找不到合適理由'),
  ('noOpener', '不知道怎麼開口'),
];

const _q1PreDateReminder = <(String, String)>[
  ('today', '今天 / 今晚'),
  ('tomorrow', '明天'),
  ('withinThreeDays', '三天內'),
  ('withinWeek', '一週內'),
];

const _q2PreDateReminder = <(String, String)>[
  ('meal', '吃飯'),
  ('drink', '喝東西 / 咖啡'),
  ('activity', '一起做某件事（電影 / 展覽 / 運動）'),
  ('undecided', '還沒定'),
];

const _q1PostDateReflection = <(String, String)>[
  ('betterThanExpected', '比預期好'),
  ('okay', '還可以'),
  ('awkward', '卡卡的'),
  ('unsure', '不確定'),
];

const _q2PostDateReflection = <(String, String)>[
  ('proactive', '有（主動找下一次 / 主動延續話題）'),
  ('polite', '還在禮貌回應'),
  ('cooling', '變慢或變淡'),
  ('stillUnclear', '還看不出來（剛結束 / 訊息還沒回 / 太早判斷不出）'),
];

class _PhaseSpec {
  final String q1Question;
  final List<(String, String)> q1Options;
  final String q2Question;
  final List<(String, String)> q2Options;
  final bool q2Required;
  final String q3Hint;

  const _PhaseSpec({
    required this.q1Question,
    required this.q1Options,
    required this.q2Question,
    required this.q2Options,
    required this.q2Required,
    required this.q3Hint,
  });
}

const _specs = <CoachFollowUpPhase, _PhaseSpec>{
  CoachFollowUpPhase.prepareInvite: _PhaseSpec(
    q1Question: '你想用什麼方式邀？',
    q1Options: _q1PrepareInvite,
    q2Question: '你最擔心的是？',
    q2Options: _q2PrepareInvite,
    q2Required: false,
    q3Hint: '補充想說的（選填）',
  ),
  CoachFollowUpPhase.preDateReminder: _PhaseSpec(
    q1Question: '什麼時候見？',
    q1Options: _q1PreDateReminder,
    q2Question: '見面活動？',
    q2Options: _q2PreDateReminder,
    q2Required: false,
    q3Hint: '你現在最緊張 / 想練的點（選填）',
  ),
  CoachFollowUpPhase.postDateReflection: _PhaseSpec(
    q1Question: '整體感覺？',
    q1Options: _q1PostDateReflection,
    q2Question: '對方有沒有主動延續？',
    q2Options: _q2PostDateReflection,
    q2Required: true,
    q3Hint: '哪個瞬間最想復盤（選填）',
  ),
};

// ── Sheet widget ─────────────────────────────────────────────────────────

class CoachFollowUpInputSheet extends StatefulWidget {
  final CoachFollowUpPhase phase;
  final bool isLoading;
  final ValueChanged<CoachFollowUpAnswers> onSubmit;

  const CoachFollowUpInputSheet({
    super.key,
    required this.phase,
    required this.onSubmit,
    this.isLoading = false,
  });

  @override
  State<CoachFollowUpInputSheet> createState() =>
      _CoachFollowUpInputSheetState();
}

class _CoachFollowUpInputSheetState extends State<CoachFollowUpInputSheet> {
  String? _q1;
  String? _q2;
  final TextEditingController _q3Ctrl = TextEditingController();

  @override
  void dispose() {
    _q3Ctrl.dispose();
    super.dispose();
  }

  _PhaseSpec get _spec => _specs[widget.phase]!;

  bool get _canSubmit {
    if (widget.isLoading) return false;
    if (_q1 == null) return false;
    if (_spec.q2Required && _q2 == null) return false;
    return true;
  }

  void _submit() {
    if (!_canSubmit) return;
    final q3 = _q3Ctrl.text.trim();
    widget.onSubmit(CoachFollowUpAnswers(
      q1: _q1!,
      q2: _q2,
      q3: q3.isEmpty ? null : q3,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.phase.displayLabel,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.onBackgroundPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _QuestionGroup(
              question: _spec.q1Question,
              required: true,
              options: _spec.q1Options,
              selectedKey: _q1,
              onSelected: (k) => setState(() {
                _q1 = (_q1 == k) ? null : k;
              }),
            ),
            const SizedBox(height: 16),
            _QuestionGroup(
              question: _spec.q2Question,
              required: _spec.q2Required,
              options: _spec.q2Options,
              selectedKey: _q2,
              onSelected: (k) => setState(() {
                _q2 = (_q2 == k) ? null : k;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _q3Ctrl,
              maxLength: 80,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: _spec.q3Hint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSubmit ? _submit : null,
                child: const Text('產生跟進建議'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionGroup extends StatelessWidget {
  final String question;
  final bool required;
  final List<(String, String)> options;
  final String? selectedKey;
  final ValueChanged<String> onSelected;

  const _QuestionGroup({
    required this.question,
    required this.required,
    required this.options,
    required this.selectedKey,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                question,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onBackgroundPrimary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              required ? '（必選）' : '（選填）',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final (key, label) = opt;
            return ChoiceChip(
              label: Text(label),
              selected: selectedKey == key,
              showCheckmark: false,
              onSelected: (_) => onSelected(key),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }
}
