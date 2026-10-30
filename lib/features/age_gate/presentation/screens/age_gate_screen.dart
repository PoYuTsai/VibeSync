// lib/features/age_gate/presentation/screens/age_gate_screen.dart
//
// 18+ 年齡確認頁（AGE-01）：登入、看完 onboarding 之後，帳號還沒確認成年就只能
// 待在這頁（resolveAppRedirect）。問出生年月、不預選、不寫門檻數字；送出前再確認
// 一次（未成年會鎖住帳號）。未成年：只提供給成年人、填錯聯絡客服，可以去設定頁
// 登出或刪除帳號。連不上就請他再按一次，不放行。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/support_contact.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/services/link_launch_service.dart';
import '../../../../shared/widgets/brand/brand_dialog.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/age_gate_repository.dart';
import '../../domain/age_gate.dart';

const kAgeGateBlockedTitle = 'VibeSync 只提供給成年人使用。';
const kAgeGateRecordFailedMessage = '目前連不上，請確認網路後再按一次。';

class AgeGateScreen extends ConsumerStatefulWidget {
  const AgeGateScreen({super.key, this.blocked = false, this.now});

  /// 帳號已經記成未成年（路由從帳號紀錄判斷）。
  final bool blocked;

  /// 測試用：固定「現在」。
  final DateTime Function()? now;

  @override
  ConsumerState<AgeGateScreen> createState() => _AgeGateScreenState();
}

class _AgeGateScreenState extends ConsumerState<AgeGateScreen> {
  int? _year;
  int? _month;
  bool _submitting = false;
  bool _failed = false;
  bool _blocked = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  bool get _isFuture =>
      _year != null &&
      _month != null &&
      isFutureBirthMonth(birthYear: _year!, birthMonth: _month!, now: _now);

  Future<void> _submit() async {
    final year = _year;
    final month = _month;
    if (year == null || month == null || _isFuture || _submitting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => BrandAlertDialog(
        title: const Text('確認出生年月'),
        content: Text('你選的是 $year 年 $month 月。送出後不能自己修改，確定嗎？'),
        actions: [
          TextButton(
            key: const ValueKey('age-gate-confirm-back'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回修改'),
          ),
          TextButton(
            key: const ValueKey('age-gate-confirm-submit'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('確定送出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _failed = false;
    });
    final result = isAdultByBirthMonth(
      birthYear: year,
      birthMonth: month,
      now: _now,
    )
        ? AgeGateResult.adult
        : AgeGateResult.minor;
    try {
      final outcome = await ref.read(ageGateRepositoryProvider).record(result);
      if (!mounted) return;
      if (outcome.result == AgeGateResult.minor) {
        setState(() {
          _submitting = false;
          _blocked = true;
        });
        return;
      }
      if (!outcome.sessionUpdated) {
        // 伺服器已經記下成年，但 session 還沒帶到這筆紀錄（路由只看 session）：
        // 請他再按一次，伺服器不會重寫，只是再換一次 token。
        setState(() {
          _submitting = false;
          _failed = true;
        });
        return;
      }
      context.go('/');
    } catch (error) {
      debugPrint('Age gate record failed: $error');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _failed = true;
      });
    }
  }

  void _openSettings() => context.push('/settings');

  Future<void> _emailSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: kSupportEmail,
      queryParameters: {'subject': 'VibeSync 年齡確認'},
    );
    final launched = await LinkLaunchService.open(uri.toString());
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前無法開啟郵件，請直接寫信到 $kSupportEmail。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      title: '年齡確認',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.blocked || _blocked) _buildBlocked() else _buildForm(),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final now = _now;
    final years = [for (var y = now.year; y >= now.year - 100; y--) y];
    final canSubmit =
        _year != null && _month != null && !_isFuture && !_submitting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrandSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '請選擇你的出生年月',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '只用來確認你是否已成年，不會保存你的生日。',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _Picker(
                      key: const ValueKey('age-gate-year'),
                      hint: '年',
                      value: _year,
                      options: years,
                      label: (y) => '$y 年',
                      onChanged: _submitting
                          ? null
                          : (y) => setState(() {
                                _year = y;
                                _failed = false;
                              }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Picker(
                      key: const ValueKey('age-gate-month'),
                      hint: '月',
                      value: _month,
                      options: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
                      label: (m) => '$m 月',
                      onChanged: _submitting
                          ? null
                          : (m) => setState(() {
                                _month = m;
                                _failed = false;
                              }),
                    ),
                  ),
                ],
              ),
              if (_isFuture) ...[
                const SizedBox(height: 8),
                Text(
                  '這個年月還沒到，請重新選擇。',
                  key: const ValueKey('age-gate-future'),
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error),
                ),
              ],
              if (_failed) ...[
                const SizedBox(height: 8),
                Text(
                  kAgeGateRecordFailedMessage,
                  key: const ValueKey('age-gate-failed'),
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error),
                ),
              ],
              const SizedBox(height: 16),
              BrandPrimaryButton(
                key: const ValueKey('age-gate-submit'),
                label: '確認',
                isLoading: _submitting,
                onPressed: canSubmit ? _submit : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('age-gate-settings'),
          onPressed: _submitting ? null : _openSettings,
          child: Text(
            '登出或刪除帳號',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBlocked() {
    return BrandSurfaceCard(
      key: const ValueKey('age-gate-blocked'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: BrandIconBadge(icon: Icons.lock_outline),
          ),
          const SizedBox(height: 16),
          Text(
            kAgeGateBlockedTitle,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '這個帳號無法使用 VibeSync 的功能。如果出生年月填錯了，請寫信給客服，'
            '我們會協助處理。',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            kSupportEmail,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
            ),
          ),
          const SizedBox(height: 16),
          BrandPrimaryButton(
            key: const ValueKey('age-gate-email-support'),
            label: '寫信給客服',
            onPressed: _emailSupport,
          ),
          const SizedBox(height: 12),
          BrandSecondaryButton(
            key: const ValueKey('age-gate-blocked-settings'),
            label: '登出或刪除帳號',
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }
}

/// 年、月下拉選單：一開始沒有選，提示字是「年」「月」。
class _Picker extends StatelessWidget {
  const _Picker({
    super.key,
    required this.hint,
    required this.value,
    required this.options,
    required this.label,
    required this.onChanged,
  });

  final String hint;
  final int? value;
  final List<int> options;
  final String Function(int) label;
  final ValueChanged<int?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      menuMaxHeight: 320,
      dropdownColor: AppColors.brandSurface2,
      hint: Text(
        hint,
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.onBackgroundSecondary,
        ),
      ),
      style: AppTypography.bodyMedium.copyWith(
        color: AppColors.onBackgroundPrimary,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
      ),
      items: [
        for (final option in options)
          DropdownMenuItem<int>(value: option, child: Text(label(option))),
      ],
      onChanged: onChanged,
    );
  }
}
