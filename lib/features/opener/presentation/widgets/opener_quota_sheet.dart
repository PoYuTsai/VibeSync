import 'package:flutter/material.dart';
import '../../../../core/services/app_haptics.dart';
import '../../../new_topic/data/services/new_topic_service.dart';
import '../../domain/opener_flow_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/brand/app_sheet.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../../shared/widgets/brand/opener_home_components.dart';

Future<void> showOpenerQuotaSheet(BuildContext context,
        {required bool newTopic, bool legacy = false}) =>
    showAppSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      backgroundColor: OpenerHomeStyle.canvas,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _QuotaSheet(newTopic: newTopic, legacy: legacy),
    );

class _QuotaSheet extends ConsumerStatefulWidget {
  const _QuotaSheet({required this.newTopic, required this.legacy});
  final bool newTopic;
  final bool legacy;
  @override
  ConsumerState<_QuotaSheet> createState() => _QuotaSheetState();
}

class _QuotaSheetState extends ConsumerState<_QuotaSheet> {
  bool _loading = false;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      await ref.read(subscriptionScreenRefreshProvider)();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usage = ref.watch(subscriptionProvider);
    return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Expanded(
                    child: Text('額度說明', style: OpenerHomeStyle.title)),
                IconButton(
                    tooltip: '關閉額度說明',
                    onPressed: AppHaptics.onPress(() => Navigator.pop(context)),
                    icon: const Icon(Icons.close, color: OpenerHomeStyle.icon))
              ]),
              Text(widget.newTopic ? '新話題' : '開場白',
                  style: OpenerHomeStyle.body),
              const SizedBox(height: 16),
              Text(
                  widget.newTopic
                      ? '每次成功生成使用 $kNewTopicQuotaCost 則額度。回看與複製已取得的話題不另扣則；相同作業的重試不重複扣費。'
                      : widget.legacy
                          ? '目前使用一般生成：每次成功生成開場白使用 ${OpenerFlowContract.firstGenerationCost} 則額度。'
                          : '目前會話在第一次成功生成回覆時使用 ${OpenerFlowContract.firstGenerationCost} 則額度，這一局包含 ${OpenerFlowContract.includedGenerationCount} 組。後續生成依這一局剩餘權益處理；實際費用以分析後、生成前顯示的本局資訊為準。',
                  style: OpenerHomeStyle.body),
              const SizedBox(height: 16),
              if (_loading || usage.isLoading)
                const Text('正在載入額度…', style: OpenerHomeStyle.body)
              else if (_failed || usage.error != null) ...[
                const Text('暫時無法載入額度說明', style: OpenerHomeStyle.body),
                TextButton(
                    onPressed: AppHaptics.onPress(_refresh),
                    child: const Text('重試')),
              ] else ...[
                Text('目前方案：${usage.tier}', style: OpenerHomeStyle.body),
                Text(
                    '訊息額度：本月可用 ${usage.monthlyRemaining} 則，今日可用 ${usage.dailyRemaining} 則。',
                    style: OpenerHomeStyle.body),
                TextButton(
                    onPressed: AppHaptics.onPress(_refresh),
                    child: const Text('更新額度')),
              ],
            ]));
  }
}
