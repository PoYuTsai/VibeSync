import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../opener/presentation/widgets/opener_generation_progress.dart';
import '../../../partner/domain/entities/partner.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../partner/presentation/widgets/partner_picker_sheet.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../subscription/domain/services/subscription_tier_helper.dart';
import '../../data/providers/new_topic_providers.dart';
import '../../data/services/new_topic_request_session.dart';
import '../../data/services/new_topic_service.dart';
import '../../domain/entities/new_topic_result.dart';
import 'new_topic_idea_card.dart';

/// 新話題（破冰腦力）分頁（計畫 §13）。掛在 OpeningRescueScreen 的
/// IndexedStack 內：切換模式不 unmount，結果/錯誤/requestId 全保留。
class NewTopicView extends ConsumerStatefulWidget {
  const NewTopicView({super.key, this.initialPartnerId});

  /// 從 partner-scoped 入口帶進來的初選對象；必須先驗證存在
  /// owner-scoped partner list 才預選（missing/deleted 顯示重新選擇）。
  final String? initialPartnerId;

  /// 四個可 deselect 的情境 chips（不提供自由輸入）。
  static const situationOptions = [
    (label: '冷掉了', value: 'went_cold'),
    (label: '剛約完', value: 'after_date'),
    (label: '聊著但卡住', value: 'stuck'),
    (label: '想升溫', value: 'warm_up'),
  ];

  /// New Topic 專用 staged 進度文案。
  static const progressPhrases = [
    '正在整理她的作戰板…',
    '從你們的互動找新切入點…',
    '把你的風格放進話題裡…',
    '打磨可以直接送出的第一句…',
    '還在整理最適合先試的方向，請保持連線…',
  ];

  static const freeUpsellHeadline = '免費版先看最推薦的 1 個完整方案';
  static const freeUpsellBody = '升級可再解鎖另外 4 個話題';

  @override
  ConsumerState<NewTopicView> createState() => _NewTopicViewState();
}

class _NewTopicViewState extends ConsumerState<NewTopicView> {
  final _scrollController = ScrollController();
  final _requestSession = NewTopicRequestSession();

  String? _selectedPartnerId;
  String? _situation;
  NewTopicResult? _result;
  String? _error;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _selectedPartnerId = widget.initialPartnerId?.trim();
    if (_selectedPartnerId?.isEmpty ?? false) _selectedPartnerId = null;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// route 帶進來的 partnerId 每次 build 都對 owner-scoped list 驗證；
  /// missing/deleted 視同未選（顯示重新選擇），不能只信未驗證 lookup。
  String? _validatedPartnerId() {
    final id = _selectedPartnerId;
    if (id == null) return null;
    final partners = ref.read(partnerListProvider);
    return partners.any((p) => p.id == id) ? id : null;
  }

  Future<void> _pickPartner() async {
    if (_isGenerating) return;
    final partners = ref.read(partnerListProvider);
    if (partners.isEmpty) {
      context.push('/partner/new');
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1D1030),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => PartnerPickerSheet(
        selectedId: _selectedPartnerId,
        onSelected: (partner) => Navigator.pop(sheetContext, partner.id),
      ),
    );
    if (!mounted || selected == null || selected == _selectedPartnerId) return;

    if (!await _confirmClearResultIfNeeded()) return;
    setState(() {
      _selectedPartnerId = selected;
      _error = null;
    });
  }

  Future<void> _selectSituation(String? value) async {
    if (_isGenerating) return;
    final next = _situation == value ? null : value;
    if (next == _situation) return;
    if (!await _confirmClearResultIfNeeded()) return;
    setState(() {
      _situation = next;
      _error = null;
    });
  }

  /// 已有結果時要換 Partner／情境，先確認會清除舊結果（§13.7）。
  /// 確認後只清 New Topic result；Opener result 完全不受影響。
  Future<bool> _confirmClearResultIfNeeded() async {
    if (_result == null) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1D1030),
        title: Text(
          '更換條件會清除目前結果',
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
        ),
        content: Text(
          '目前這批新話題不會保存，確定要更換嗎？',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onBackgroundSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('先不要'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清除並更換'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    if (mounted) setState(() => _result = null);
    return true;
  }

  Future<void> _generate() async {
    if (_isGenerating) return;
    final partnerId = _validatedPartnerId();
    if (partnerId == null) {
      setState(() => _error = '請先選擇一位對象。');
      return;
    }

    final readiness = ref.read(newTopicReadinessProvider(partnerId));
    if (readiness == NewTopicReadiness.dataQualityBlocked) {
      setState(
        () => _error = '這位對象的資料需要先確認（資料品質提醒），暫時無法生成新話題。',
      );
      return;
    }
    if (readiness == NewTopicReadiness.missingPartner) {
      setState(() => _error = '找不到這位對象，請重新選擇。');
      return;
    }

    // await 讓 style 快照在 beginAttempt 前定案（同 opener Codex R1 P2）。
    String? styleContext;
    try {
      styleContext =
          await ref.read(newTopicStyleContextProvider(partnerId).future);
    } catch (e) {
      debugPrint('NewTopicView style context failed: $e');
    }
    if (!mounted) return;

    final partnerContext = ref.read(newTopicPartnerContextProvider(partnerId));
    if (!canGenerateNewTopic(
      readiness: readiness,
      styleContext: styleContext,
      situation: _situation,
    )) {
      // 三類素材全空：client 不送出（server 也會 422）。
      setState(
        () => _error = '目前素材不足：先補一點對象紀錄、填「關於我」，或選一個目前狀況。',
      );
      return;
    }

    final consented = await AiDataSharingConsent.ensure(
      context,
      featureLabel: '新話題',
    );
    if (!consented || !mounted) return;

    // 提示性 preflight：快照已載入且月/日剩餘都看得出 <3 才先擋；
    // 未載入交給 server，不誤擋首次使用（§13.5-5）。
    final subscriptionSnapshot = ref.read(subscriptionProvider);
    if (!subscriptionSnapshot.isLoading &&
        (subscriptionSnapshot.monthlyRemaining < 3 ||
            subscriptionSnapshot.dailyRemaining < 3)) {
      setState(() => _error = '額度不足（需要 3 點），升級方案可取得更多額度。');
      await _showPaywallAndRefresh();
      return;
    }

    setState(() {
      _isGenerating = true;
      _error = null;
      _result = null;
    });

    try {
      var expectedTier = subscriptionSnapshot.tier;
      String? revenueCatAppUserId;
      try {
        final customerInfo = await RevenueCatService.getCustomerInfo();
        final revenueCatTier =
            RevenueCatService.getTierFromCustomerInfo(customerInfo);
        revenueCatAppUserId =
            RevenueCatService.getRevenueCatAppUserId(customerInfo);
        if (SubscriptionTierHelper.rankOf(revenueCatTier) >
            SubscriptionTierHelper.rankOf(expectedTier)) {
          expectedTier = revenueCatTier;
        }
      } catch (e) {
        debugPrint('NewTopicView RevenueCat hint failed: $e');
      }
      if (!mounted) return;

      final attempt = _requestSession.beginAttempt(
        partnerId: partnerId,
        partnerSummary: partnerContext.promptText,
        effectiveStyleContext: styleContext,
        situation: _situation,
      );

      final service = NewTopicService();
      // payload 全取 frozen envelope，不用呼叫端新解析值（§12.4）。
      final result = await service.generateTopics(
        requestId: attempt.requestId,
        partnerSummary: attempt.partnerSummary,
        effectiveStyleContext: attempt.effectiveStyleContext,
        situation: attempt.situation,
        expectedTier: expectedTier,
        revenueCatAppUserId: revenueCatAppUserId,
      );
      _requestSession.markSuccess();

      if (!mounted) return;
      setState(() {
        _result = result;
        _isGenerating = false;
      });

      try {
        await ref.read(subscriptionScreenRefreshProvider)();
      } catch (_) {
        // 結果已成功；usage UI 下次 refresh 補上即可。
      }
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } on NewTopicQuotaExceededException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isGenerating = false;
      });
      await _showPaywallAndRefresh();
    } on NewTopicRequestInProgressException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isGenerating = false;
      });
    } on NewTopicException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isGenerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      final hasChinese = RegExp(r'[一-鿿]').hasMatch(message);
      setState(() {
        _error = hasChinese && message.isNotEmpty
            ? message
            : '新話題暫時生成失敗，請稍後再試。';
        _isGenerating = false;
      });
    }
  }

  Future<void> _showPaywallAndRefresh() async {
    if (!mounted) return;
    await context.push<String>('/paywall');
    if (!mounted) return;
    try {
      await ref.read(subscriptionScreenRefreshProvider)();
    } catch (e) {
      debugPrint('NewTopicView paywall refresh failed: $e');
    }
    if (!mounted) return;
    final subscription = ref.read(subscriptionProvider);
    if (_error != null && subscription.isPremium) {
      setState(() => _error = null);
    }
  }

  void _copyOpeningLine(NewTopicIdea idea) {
    Clipboard.setData(ClipboardData(text: idea.openingLine));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('已複製這句話，貼到聊天室送出試試。')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final validPartnerId = _validatedPartnerId();
    final partner =
        validPartnerId == null ? null : ref.watch(partnerByIdProvider(validPartnerId));
    final hadInvalidInitialPartner =
        _selectedPartnerId != null && validPartnerId == null;

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '新話題',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.ctaStart,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            partner != null ? '為 ${partner.name} 想新話題' : '聊天卡住？AI 幫你想新台階',
            style: AppTypography.headlineLarge.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 20),

          _buildPartnerCard(partner, hadInvalidInitialPartner),
          const SizedBox(height: 16),

          Text(
            '目前狀況（選填）',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in NewTopicView.situationOptions)
                BrandChoiceChip(
                  label: option.label,
                  selected: _situation == option.value,
                  onTap: () => unawaited(_selectSituation(option.value)),
                ),
            ],
          ),
          const SizedBox(height: 16),

          Center(
            child: Text(
              _result != null ? '已生成，不會重複扣額度' : '將使用 3 則額度',
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
          ),
          const SizedBox(height: 12),

          BrandPrimaryButton(
            label: _result != null ? '已生成新話題' : '生成新話題',
            isLoading: _isGenerating,
            onPressed:
                (_isGenerating || _result != null || validPartnerId == null)
                    ? null
                    : _generate,
          ),
          const SizedBox(height: 16),

          if (_isGenerating)
            const Center(
              child: OpenerGenerationProgress(
                phrases: NewTopicView.progressPhrases,
              ),
            ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  _error!,
                  style:
                      AppTypography.bodyMedium.copyWith(color: AppColors.error),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          if (_result != null) ...[
            const SizedBox(height: 24),
            _buildResults(_result!),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildPartnerCard(Partner? partner, bool hadInvalidInitialPartner) {
    if (partner == null) {
      return BrandSurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hadInvalidInitialPartner ? '原本的對象已不存在，請重新選擇' : '選擇對象',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.onBackgroundPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '新話題會根據這位對象的作戰板來想切入點。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
            const SizedBox(height: 12),
            BrandSecondaryButton(
              label: ref.watch(partnerListProvider).isEmpty ? '先建立一位對象' : '選擇對象',
              onPressed: _isGenerating ? null : _pickPartner,
            ),
          ],
        ),
      );
    }

    final aggregate = ref.watch(partnerAggregateProvider(partner.id));
    final partnerContext =
        ref.watch(newTopicPartnerContextProvider(partner.id));
    final chips = <String>[
      ...aggregate.unionInterests,
      ...aggregate.unionTraits,
    ].take(3).toList();
    final hasNote = (partner.customNote?.trim().isNotEmpty ?? false);

    return BrandSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  partner.name,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
              ),
              if (aggregate.latestHeat != null)
                Text(
                  '熱度 ${aggregate.latestHeat}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.ctaStart,
                  ),
                ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      chip,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onBackgroundSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            hasNote ? '已加入你的備註' : '沒有備註',
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.8),
            ),
          ),
          if (!partnerContext.hasActionableSignals) ...[
            const SizedBox(height: 4),
            Text(
              '這位對象的紀錄還很少，建議可能會比較通用。',
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.72),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isGenerating ? null : _pickPartner,
              style: TextButton.styleFrom(foregroundColor: AppColors.ctaStart),
              child: const Text('更換對象'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(NewTopicResult result) {
    final recommendedId = result.recommendation.topicId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '新話題建議',
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
        ),
        if (result.recommendation.reason != null) ...[
          const SizedBox(height: 8),
          Text(
            'AI 推薦理由：${result.recommendation.reason}',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ],
        const SizedBox(height: 12),
        for (final idea in result.topics) ...[
          NewTopicIdeaCard(
            idea: idea,
            isRecommended: idea.id == recommendedId,
            onCopyOpeningLine: () => _copyOpeningLine(idea),
          ),
          const SizedBox(height: 12),
        ],
        // Free：一張完整推薦卡＋compact upsell，不渲染四張空鎖卡（§13.6）。
        if (result.access.isFree)
          BrandSurfaceCard(
            padding: const EdgeInsets.all(16),
            elevated: false,
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  color: AppColors.onBackgroundSecondary.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        NewTopicView.freeUpsellHeadline,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.onBackgroundPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        NewTopicView.freeUpsellBody,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onBackgroundSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _showPaywallAndRefresh,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.ctaStart,
                  ),
                  child: const Text('升級解鎖'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
