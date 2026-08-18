import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/formula_reply_section.dart';
import '../../../../shared/widgets/more_below_hint.dart';
import '../../../../shared/widgets/stream_progress_ticker.dart';
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
import '../../../../shared/widgets/brand/app_sheet.dart';
import '../../../../core/services/app_haptics.dart';

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
  // 2026-08-18 呈現精修：完成後定格在「新話題建議」標題，不再捲到底
  // 略過 5 張題卡；公式區 key 給右下滑動提示 pill 當目標。
  final _resultsSectionKey = GlobalKey();
  final _formulaSectionKey = GlobalKey();
  final _requestSession = NewTopicRequestSession();

  String? _selectedPartnerId;
  String? _situation;
  // 真串流進度（server 事件文字）；每次生成開始清空。空＝還沒收到事件
  //（或 server 降級 legacy），顯示本地輪播 fallback。
  final List<String> _streamProgress = [];
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

    final selected = await showAppSheet<String>(
      context: context,
      backgroundColor: AppColors.coachSurfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => PartnerPickerSheet(
        selectedId: _selectedPartnerId,
        onSelected: (partner) => Navigator.pop(sheetContext, partner.id),
      ),
    );
    if (!mounted || selected == null || selected == _selectedPartnerId) return;

    if (!await _confirmClearResultIfNeeded()) return;
    if (!mounted) return;
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
    if (!mounted) return;
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
        backgroundColor: AppColors.coachSurfaceRaised,
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
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onBackgroundSecondary,
            ),
            child: const Text('先不要'),
          ),
          TextButton(
            onPressed: AppHaptics.onPress(
                () => Navigator.pop(dialogContext, true)),
            style: TextButton.styleFrom(foregroundColor: AppColors.ctaStart),
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
      _streamProgress.clear();
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
      // 2026-08-18 真串流：進度事件即時上牆；server flag off／舊 Edge
      // 回一般 JSON 時 service 內自動降級。
      final result = await service.generateTopicsStreaming(
        requestId: attempt.requestId,
        partnerSummary: attempt.partnerSummary,
        effectiveStyleContext: attempt.effectiveStyleContext,
        situation: attempt.situation,
        expectedTier: expectedTier,
        revenueCatAppUserId: revenueCatAppUserId,
        onProgress: (label) {
          if (!mounted || !_isGenerating) return;
          setState(() => _streamProgress.add(label));
        },
      );
      _requestSession.markSuccess();

      if (!mounted) return;
      setState(() {
        _result = result;
        _isGenerating = false;
      });

      // 先排定格再做額度 refresh：refresh 是網路呼叫，擋在前面會造成
      // 「結果出現 → 停 1~2 秒 → 突然捲動」的體感。定格錨結果區頂部
      //（新話題建議標題），不捲到底略過題卡。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final targetContext = _resultsSectionKey.currentContext;
        if (targetContext == null || !mounted) return;
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.04,
          duration: AppMotion.scroll,
          curve: AppMotion.easeOut,
        );
      });

      try {
        await ref.read(subscriptionScreenRefreshProvider)();
      } catch (_) {
        // 結果已成功；usage UI 下次 refresh 補上即可。
      }
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
        _error =
            hasChinese && message.isNotEmpty ? message : '新話題暫時生成失敗，請稍後再試。';
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
    AppHaptics.light();
    Clipboard.setData(ClipboardData(text: idea.openingLine));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('已複製這句話，貼到聊天室送出試試。')),
      );
  }

  /// 公式新話題複製：只複製 openingLine，沿用既有 snackbar 語氣。
  void _copyFormulaOpeningLine(FormulaReplyEntry entry) {
    AppHaptics.light();
    Clipboard.setData(ClipboardData(text: entry.openingLine));
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
    final partner = validPartnerId == null
        ? null
        : ref.watch(partnerByIdProvider(validPartnerId));
    final hadInvalidInitialPartner =
        _selectedPartnerId != null && validPartnerId == null;

    final scrollBody = SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '新話題',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.coachAccentBright,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            partner != null ? '為 ${partner.name} 想新話題' : '聊天卡住？AI 幫你想新台階',
            style: AppTypography.headlineLarge.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 24),
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
                  tone: BrandVisualTone.coach,
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
            _streamProgress.isNotEmpty
                ? StreamProgressTicker(labels: _streamProgress)
                : const Center(
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
            KeyedSubtree(
              key: _resultsSectionKey,
              child: NewTopicResultsSection(
                result: _result!,
                onCopyIdeaOpeningLine: _copyOpeningLine,
                onCopyFormulaOpeningLine: _copyFormulaOpeningLine,
                onUpgrade: _showPaywallAndRefresh,
                formulaSectionKey: _formulaSectionKey,
              ),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );

    // 滑動提示 pill：公式新話題還在視口下方時提示；進入視口即收起。
    // StackFit.expand：預設 loose 會讓捲動區縮成內容寬（版面漂移＋pill 定位壞）。
    return Stack(
      fit: StackFit.expand,
      children: [
        scrollBody,
        if (_result != null && _result!.formulaTopics.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 16,
            child: MoreBelowHint(
              controller: _scrollController,
              targetKey: _formulaSectionKey,
              label: '往下還有公式新話題',
              resetToken: _result,
            ),
          ),
      ],
    );
  }

  Widget _buildPartnerCard(Partner? partner, bool hadInvalidInitialPartner) {
    if (partner == null) {
      return BrandSurfaceCard(
        tone: BrandVisualTone.coach,
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
              label:
                  ref.watch(partnerListProvider).isEmpty ? '先建立一位對象' : '選擇對象',
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
      tone: BrandVisualTone.coach,
      elevated: false,
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
                    color: AppColors.coachAccentBright,
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
                      color: AppColors.coachAccent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.coachAccent.withValues(alpha: 0.20),
                      ),
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
          if (hasNote) ...[
            const SizedBox(height: 8),
            Text(
              '已加入你的備註',
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.8),
              ),
            ),
          ],
          if (!partnerContext.hasActionableSignals) ...[
            const SizedBox(height: 4),
            Text(
              '這位對象的紀錄還很少，建議可能會比較通用。',
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.72),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isGenerating ? null : _pickPartner,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.coachAccentBright,
              ),
              child: const Text('更換對象'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 結果區（抽成公開 widget 供 widget test 直接驗證排序與可見性；
/// 計畫 §10.3）：推薦理由 → 原 topics → 公式新話題 → Free upsell。
class NewTopicResultsSection extends StatelessWidget {
  const NewTopicResultsSection({
    super.key,
    required this.result,
    required this.onCopyIdeaOpeningLine,
    required this.onCopyFormulaOpeningLine,
    required this.onUpgrade,
    this.formulaSectionKey,
  });

  final NewTopicResult result;
  final ValueChanged<NewTopicIdea> onCopyIdeaOpeningLine;
  final ValueChanged<FormulaReplyEntry> onCopyFormulaOpeningLine;
  final VoidCallback onUpgrade;

  /// 滑動提示 pill 的捲動目標（公式新話題區）。
  final Key? formulaSectionKey;

  @override
  Widget build(BuildContext context) {
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                size: 18,
                color: AppColors.coachRecommendation,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI 推薦理由：${result.recommendation.reason}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        for (final idea in result.topics) ...[
          NewTopicIdeaCard(
            idea: idea,
            isRecommended: idea.id == recommendedId,
            onCopyOpeningLine: () => onCopyIdeaOpeningLine(idea),
          ),
          const SizedBox(height: 12),
        ],
        // 公式新話題（公式回覆計畫 §10.3）：原 topics 之後、Free upsell
        // 之前——Free 使用者清楚看到公式本來就可用，CTA 只鎖另外四題。
        // 空清單整區不渲染。
        if (result.formulaTopics.isNotEmpty) ...[
          const SizedBox(height: 8),
          FormulaReplySection(
            key: formulaSectionKey,
            title: '公式新話題',
            entries: [
              for (final formula in result.formulaTopics)
                FormulaReplyEntry(
                  openingLine: formula.openingLine,
                  whyItWorks: formula.whyItWorks,
                ),
            ],
            onCopyOpeningLine: onCopyFormulaOpeningLine,
          ),
          const SizedBox(height: 12),
        ],
        // Free：一張完整推薦卡＋compact upsell，不渲染四張空鎖卡（§13.6）。
        if (result.access.isFree)
          BrandSurfaceCard(
            tone: BrandVisualTone.coach,
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
                  onPressed: onUpgrade,
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
