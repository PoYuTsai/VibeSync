import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/coach_scope.dart';
import '../widgets/coach_surface.dart';

/// 批 A：全域教練頁（首頁「問教練」卡直達）。不綁對象、不注入任何
/// conversation/partner 資料，掛統一教練介面 CoachSurface（global scope）。
///
/// 引導問句 chips 點擊只「預填」進輸入框（prefill＋focus token 遞增），
/// 絕不自動送出——送出永遠是用戶按鈕行為（quota 安全）。
class GlobalCoachScreen extends StatefulWidget {
  const GlobalCoachScreen({super.key});

  /// 引導問句（計畫拍板三句；widget 測試字面對齊）。
  static const guideQuestions = <String>[
    '不知道怎麼開啟話題，給我一點方向？',
    '對方回得很短，我該怎麼判斷？',
    '怎麼把聊天推進到約出來？',
  ];

  @override
  State<GlobalCoachScreen> createState() => _GlobalCoachScreenState();
}

class _GlobalCoachScreenState extends State<GlobalCoachScreen> {
  String? _prefill;
  int _focusToken = 0;

  void _onGuideTap(String question) {
    setState(() {
      _prefill = question;
      _focusToken += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                scope: const CoachScope.global(),
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
