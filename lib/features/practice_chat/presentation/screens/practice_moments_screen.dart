// 練習室「模擬社群動態」：已抽到的角色今天發了什麼。
//
// **版面參照是 Threads，不是 WeChat 朋友圈（D5b）**：文字優先、緊湊列表、
// 頭像靠左、配圖單張且次要。刻意不做九宮格、不做全寬大圖、不把每則包成
// 帶陰影的卡片——卡片流會把密度殺光。驗收條件是可以在截圖上直接量的：
// **一屏至少看得到 3 則純文字貼文**。
//
// 唯讀：這一版只有瀏覽（D4 不做按讚／留言）。v1 不做離線快取（D7），
// 每次進畫面打一次 API。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/providers/practice_chat_providers.dart';
import '../../domain/entities/practice_moment_post.dart';
import '../../domain/entities/practice_profile.dart';
import '../widgets/practice_moment_tile.dart';
import '../widgets/practice_moments_debug_fixtures.dart';

class PracticeMomentsScreen extends ConsumerStatefulWidget {
  const PracticeMomentsScreen({super.key});

  @override
  ConsumerState<PracticeMomentsScreen> createState() =>
      _PracticeMomentsScreenState();
}

class _PracticeMomentsScreenState
    extends ConsumerState<PracticeMomentsScreen> {
  /// D3 debug 情境索引。型別刻意是 `int`（不是 fixtures 檔的 enum），
  /// release 端連型別參照都不指向 fixtures。0＝走真實 provider。
  int _debugScenario = 0;

  @override
  Widget build(BuildContext context) {
    var feed = ref.watch(practiceMomentsProvider);
    // 相對時間的基準取一次，整屏一致（每則各自 DateTime.now() 會讓同一批
    // 貼文的「N 分鐘前」互相打架）。
    final now = DateTime.now();

    // ── D3：debug-only 假資料 ───────────────────────────────────────────
    // kDebugMode 是 const bool，release AOT 把整段連同 fixtures 檔一起
    // tree-shake 掉（編譯期消除，不是 runtime 判斷）。
    Widget? debugBar;
    if (kDebugMode) {
      final override = practiceMomentsDebugFeed(_debugScenario, now);
      if (override != null) feed = override;
      debugBar = PracticeMomentsDebugBar(
        scenario: _debugScenario,
        onChanged: (next) => setState(() => _debugScenario = next),
      );
    }
    // ───────────────────────────────────────────────────────────────────

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: AppColors.onBackgroundPrimary,
          ),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: Text(
          '她們的動態',
          style: AppTypography.titleLarge.copyWith(
            color: AppColors.onBackgroundPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
      ),
      body: BrandPageBackground(
        child: SafeArea(
          child: Column(
            children: [
              if (debugBar != null) debugBar,
              const _MomentsAiDisclosure(),
              Expanded(
                child: RefreshIndicator(
                  key: const ValueKey('moments-refresh'),
                  color: AppColors.ctaStart,
                  backgroundColor: AppColors.brandSurface,
                  onRefresh: () =>
                      ref.read(practiceMomentsProvider.notifier).refresh(),
                  child: _MomentsBody(
                    feed: feed,
                    now: now,
                    onRetry: () =>
                        ref.read(practiceMomentsProvider.notifier).refresh(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AI 模擬內容揭露（2026-08-24 複審 P1）。
///
/// 這一頁長得像真的社群動態——頭像、相對時間、第一人稱口吻——**這正是它的
/// 目的，也正是它需要揭露的理由**。少了這一行，使用者可能誤認成真人動態，
/// 且是 App Review 的實際風險（模擬人類生成內容須明示）。
///
/// 刻意放在列表**外面**：跟著捲動的揭露等於捲一下就消失，形同沒有。
/// 三種狀態（載入／空／錯誤）下都在場，因為誤認風險與有沒有貼文無關。
class _MomentsAiDisclosure extends StatelessWidget {
  const _MomentsAiDisclosure();

  static const disclosureKey = ValueKey('moments-ai-disclosure');

  /// 固定文案。不做成參數也不隨情境變化——揭露一旦可變就會有某條路徑漏掉。
  static const text = 'AI 模擬練習內容，不是真人動態';

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: disclosureKey,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 13,
            color: AppColors.onBackgroundSecondary.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.75),
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 三態：載入中／空／錯誤。有資料時就是那條緊湊列表。
class _MomentsBody extends StatelessWidget {
  const _MomentsBody({
    required this.feed,
    required this.now,
    required this.onRetry,
  });

  static const loadingKey = ValueKey('moments-loading');
  static const emptyKey = ValueKey('moments-empty');
  static const errorKey = ValueKey('moments-error');
  static const listKey = ValueKey('moments-list');

  final AsyncValue<List<PracticeMomentPost>> feed;
  final DateTime now;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // 錯誤優先於「有舊資料」：連不上就要講，不能靜靜顯示過期的一屏。
    if (feed.hasError && !feed.isLoading) {
      return _MomentsMessage(
        stateKey: errorKey,
        icon: Icons.wifi_off_rounded,
        title: '連不上，動態先顯示不出來',
        message: '下拉重整，或按下面的按鈕再試一次。',
        onRetry: onRetry,
      );
    }
    if (feed.isLoading && !feed.hasValue) {
      return const _MomentsMessage(
        stateKey: loadingKey,
        icon: Icons.hourglass_empty_rounded,
        title: '正在讀她們的動態…',
        message: '第一次進來可能要等一下，她們正在寫。',
      );
    }
    final posts = feed.valueOrNull ?? const <PracticeMomentPost>[];
    if (posts.isEmpty) {
      return const _MomentsMessage(
        stateKey: emptyKey,
        icon: Icons.filter_drama_outlined,
        title: '今天還沒有人發動態',
        message: '動態只會出現在你已經抽到的角色身上，去圖鑑多認識幾位吧。',
      );
    }

    return ListView.separated(
      key: listKey,
      // 下拉重整需要永遠可捲動，否則貼文不滿一屏時拉不動。
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: posts.length,
      separatorBuilder: (_, __) => const PracticeMomentDivider(),
      itemBuilder: (context, index) {
        final post = posts[index];
        return PracticeMomentTile(
          post: post,
          profile: girlProfileById(post.profileId),
          now: now,
        );
      },
    );
  }
}

/// 載入／空／錯誤共用的一屏訊息。永遠可捲動，讓下拉重整在三態下都有效。
class _MomentsMessage extends StatelessWidget {
  const _MomentsMessage({
    required this.stateKey,
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final Key stateKey;
  final IconData icon;
  final String title;
  final String message;

  /// null＝這一態不給重試鈕（載入中／空畫面）。
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          key: stateKey,
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 40,
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundSecondary,
                        height: 1.5,
                      ),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const ValueKey('moments-retry'),
                        onPressed: onRetry,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.ctaStart,
                          foregroundColor: AppColors.onCta,
                        ),
                        child: const Text('重試'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
