import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../partner/domain/entities/partner.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../domain/entities/coach_scope.dart';
import '../widgets/coach_surface.dart';

/// 批 A：全域教練頁（首頁「問教練」卡直達），掛統一教練介面 CoachSurface。
///
/// 2026-08-07 Bruce feedback：預設 general 串教練不知道你在問誰。頂部加
/// 「問誰」chips（有對象卡才渲染）：選對象＝切到該對象的 partner scope，
/// 跟對象頁「跟進」共用同一條聊天串（同一份脈絡與歷史）；選「一般」＝
/// 原本的 global 串。切換只換 scope（CoachSurface 不加 key、State 不重建），
/// 輸入框草稿跨切換保留。
///
/// 引導問句 chips 點擊只「預填」進輸入框（prefill＋focus token 遞增），
/// 絕不自動送出——送出永遠是用戶按鈕行為（quota 安全）。
class GlobalCoachScreen extends ConsumerStatefulWidget {
  const GlobalCoachScreen({super.key});

  /// 引導問句（計畫拍板三句；widget 測試字面對齊）。
  static const guideQuestions = <String>[
    '不知道怎麼開啟話題，給我一點方向？',
    '對方回得很短，我該怎麼判斷？',
    '怎麼把聊天推進到約出來？',
  ];

  @override
  ConsumerState<GlobalCoachScreen> createState() => _GlobalCoachScreenState();
}

class _GlobalCoachScreenState extends ConsumerState<GlobalCoachScreen> {
  String? _prefill;
  int _focusToken = 0;
  CoachScope _scope = const CoachScope.global();

  void _onGuideTap(String question) {
    setState(() {
      _prefill = question;
      _focusToken += 1;
    });
  }

  void _onScopeTap(CoachScope scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
  }

  /// 「問誰」chips：沒有任何對象卡就整排不渲染（新用戶畫面同現狀，
  /// 不出現只有「一般」的孤兒選項）。
  Widget _buildScopeChips(List<Partner> partners) {
    if (partners.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '問誰',
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.onBackgroundSecondary),
              ),
            ),
            _scopeChip(
              key: const Key('coach_scope_general'),
              label: '一般',
              selected: _scope.isGlobal,
              onTap: () => _onScopeTap(const CoachScope.global()),
            ),
            for (final partner in partners)
              _scopeChip(
                key: Key('coach_scope_partner_${partner.id}'),
                label: partner.name,
                selected: _scope == CoachScope.partner(partner.id),
                onTap: () => _onScopeTap(CoachScope.partner(partner.id)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _scopeChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: key,
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final partners = ref.watch(partnerListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('問教練')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/images/coach/sydney_greeting.png',
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '隨時問我，聊天卡住我來接',
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              _buildScopeChips(partners),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: GlobalCoachScreen.guideQuestions.map((question) {
                  return ActionChip(
                    label: Text(question),
                    onPressed: () => _onGuideTap(question),
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 16),
              CoachSurface(
                scope: _scope,
                focusRequestToken: _focusToken,
                prefillText: _prefill,
                onQuotaExceeded: () => context.push('/paywall'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
