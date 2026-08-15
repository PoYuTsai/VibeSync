// 對象頁「問教練」CTA（2026-08-15 拍板：三入口共用獨立聊天視窗）。
//
// 內嵌 CoachSurface 時代（Phase E Task 6 薄 wrapper）整段退場：三情境
// chip、知識庫連結與 lifecyclePhase 種入都搬進問教練 Sydney 視窗
// （GlobalCoachScreen 鎖定模式）。本 widget 只剩一張 CTA 卡，點了導
// `/coach?partnerId=`——對象已知，視窗不渲染「問誰」。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../coach_chat/presentation/widgets/coach_cta_card.dart';

class CoachFollowUpSection extends StatelessWidget {
  final String partnerId;

  const CoachFollowUpSection({super.key, required this.partnerId});

  @override
  Widget build(BuildContext context) {
    return CoachCtaCard(
      buttonKey: const Key('coach_follow_up_cta'),
      onTap: () => context.push('/coach?partnerId=$partnerId'),
    );
  }
}
