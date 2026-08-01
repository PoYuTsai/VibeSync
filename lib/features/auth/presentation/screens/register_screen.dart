// lib/features/auth/presentation/screens/register_screen.dart
//
// 批 B 訪客模式：訪客轉正頁（identity linking，uid 不變、資料零搬移）。
// 三路轉正：Apple / Google（即時）與 email＋密碼（寄確認信，點連結前仍是訪客）。
// 「登入已有帳號」uid 會換、訪客資料不帶過去——動線上必先彈警告 dialog 明講。
// 非訪客誤入由 redirect matrix 擋（/register → /），頁內不重複防。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/funnel_tracker.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/usage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/platform_info.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../subscription/data/providers/subscription_providers.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.source});

  /// 進頁來源（funnel `guest_register_view` 的 source 屬性；字典 enum 之外
  /// 一律送 `unknown`）。
  final String? source;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  static final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static const _knownSources = {
    'quota_strip',
    'quota_exhausted',
    'follow_up',
    'settings',
    'paywall',
  };

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _emailConfirmationSent = false;
  String? _errorMessage;

  bool get _isIOS => isIOSPlatform;

  @override
  void initState() {
    super.initState();
    final source = _knownSources.contains(widget.source)
        ? widget.source!
        : 'unknown';
    unawaited(
      ref
          .read(funnelTrackerProvider)
          .track('guest_register_view', properties: {'source': source}),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _invalidateSessionScopedProviders() {
    ref.invalidate(subscriptionProvider);
    ref.invalidate(conversationsProvider);
    ref.invalidate(usageDataProvider);
  }

  bool _isValidEmail(String value) => _emailRegex.hasMatch(value.trim());

  bool _isStrongPassword(String value) =>
      value.length >= 8 &&
      RegExp(r'[A-Za-z]').hasMatch(value) &&
      RegExp(r'\d').hasMatch(value);

  bool _isCancellationError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('cancel') || message.contains('cancelled');
  }

  bool _isIdentityTakenError(AuthException e) {
    // 先比對結構化 error code（GoTrue 文案會變，code 穩定），message 當 fallback。
    final code = (e.code ?? '').toLowerCase();
    if (code == 'identity_already_exists' ||
        code == 'email_exists' ||
        code == 'user_already_exists') {
      return true;
    }
    final message = e.message.toLowerCase();
    return message.contains('identity is already linked') ||
        message.contains('identity_already_exists') ||
        message.contains('already been registered') ||
        message.contains('already registered');
  }

  void _setError(String message) {
    setState(() {
      _errorMessage = message;
      _isLoading = false;
    });
  }

  Future<void> _trackRegisterSuccess(String method) async {
    unawaited(
      ref
          .read(funnelTrackerProvider)
          .track('guest_register_success', properties: {'method': method}),
    );
  }

  Future<void> _handleLinkSuccess(String method) async {
    await _trackRegisterSuccess(method);
    if (!mounted) return;
    _invalidateSessionScopedProviders();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('註冊完成！每月 30 則免費額度已解鎖。')),
    );
    context.go('/');
  }

  Future<void> _linkWith(
    String method,
    Future<AuthResponse> Function() link,
  ) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await link();
      if (response.user != null) {
        await _handleLinkSuccess(method);
      } else {
        if (!mounted) return;
        _setError('註冊沒有完成，請再試一次。');
      }
    } on AuthException catch (e) {
      if (_isCancellationError(e)) return;
      if (!mounted) return;
      if (_isIdentityTakenError(e)) {
        setState(() => _isLoading = false);
        await _showIdentityTakenDialog();
        return;
      }
      _setError('註冊失敗，請再試一次。');
    } catch (e) {
      if (_isCancellationError(e)) return;
      if (!mounted) return;
      _setError('註冊失敗，請再試一次。');
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitEmailRegistration() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!_isValidEmail(email)) {
      _setError('請輸入有效的 Email。');
      return;
    }
    if (!_isStrongPassword(password)) {
      _setError('密碼至少 8 個字元，且需包含英文字母與數字。');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await SupabaseService.registerGuestWithEmail(
        email: email,
        password: password,
      );
      await _trackRegisterSuccess('email');
      if (!mounted) return;
      setState(() {
        _emailConfirmationSent = true;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      if (_isIdentityTakenError(e)) {
        setState(() => _isLoading = false);
        await _showIdentityTakenDialog();
        return;
      }
      _setError('註冊失敗，請再試一次。');
    } catch (_) {
      if (!mounted) return;
      _setError('註冊失敗，請再試一次。');
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Apple/Google/email 已被其他帳號註冊過：只能改用登入（訪客資料不帶過去）。
  Future<void> _showIdentityTakenDialog() async {
    final shouldLogin = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('這個帳號已經註冊過'),
        content: const Text(
          '要改用它登入嗎？\n\n注意：訪客期間的紀錄綁在目前的訪客帳號，'
          '登入其他帳號後不會帶過去。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('改用登入'),
          ),
        ],
      ),
    );
    if (shouldLogin == true) {
      await _signOutToLogin();
    }
  }

  Future<void> _confirmSwitchToLogin() async {
    final shouldLogin = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('改用既有帳號登入？'),
        content: const Text(
          '訪客期間的紀錄綁在目前的訪客帳號，登入其他帳號後不會帶過去。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('前往登入'),
          ),
        ],
      ),
    );
    if (shouldLogin == true) {
      await _signOutToLogin();
    }
  }

  Future<void> _signOutToLogin() async {
    setState(() => _isLoading = true);
    try {
      await SupabaseService.signOut();
      // redirect matrix 會自動把未登入導回 /login。
    } catch (_) {
      if (!mounted) return;
      _setError('登出失敗，請再試一次。');
      return;
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: BackButton(
            color: AppColors.onBackgroundPrimary,
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/'),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: _emailConfirmationSent
                    ? _buildEmailSentState()
                    : _buildRegisterForm(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '免費註冊，解鎖完整額度',
          style: AppTypography.headlineLarge.copyWith(
            color: AppColors.onBackgroundPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '註冊解鎖每月 30 則免費額度，訪客期間的紀錄全部保留。',
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.onBackgroundSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        if (_errorMessage != null) ...[
          BrandSurfaceCard(
            elevated: false,
            padding: const EdgeInsets.all(12),
            borderRadius: 18,
            child: Text(
              _errorMessage!,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.error,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_isIOS) ...[
          _buildGoogleLinkButton(),
          const SizedBox(height: 12),
          _buildAppleLinkButton(),
          const SizedBox(height: 24),
          _buildDivider(),
          const SizedBox(height: 24),
        ],
        _buildLabeledTextField(
          label: 'Email',
          controller: _emailController,
          hintText: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        _buildLabeledTextField(
          label: '密碼',
          controller: _passwordController,
          hintText: '至少 8 個字元，含英文字母與數字',
          obscureText: !_isPasswordVisible,
          onToggleObscureText: () {
            setState(() => _isPasswordVisible = !_isPasswordVisible);
          },
        ),
        const SizedBox(height: 24),
        BrandPrimaryButton(
          label: '免費註冊',
          onPressed: _isLoading ? null : _submitEmailRegistration,
          isLoading: _isLoading,
        ),
        const SizedBox(height: 12),
        TextButton(
          key: const Key('register_switch_to_login_button'),
          onPressed: _isLoading ? null : _confirmSwitchToLogin,
          child: Text(
            '已有帳號？改用登入',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailSentState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          size: 56,
          color: AppColors.onBackgroundPrimary,
        ),
        const SizedBox(height: 16),
        Text(
          '確認信已寄出',
          style: AppTypography.headlineLarge.copyWith(
            color: AppColors.onBackgroundPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '請到 ${_emailController.text.trim()} 收信，'
          '用這支手機點擊信中連結完成註冊。\n\n'
          '完成前帳號仍是訪客身分（額度不變）；完成後即解鎖每月 30 則免費額度。',
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.onBackgroundSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        BrandPrimaryButton(
          label: '回首頁繼續使用',
          onPressed: () => context.go('/'),
        ),
      ],
    );
  }

  Widget _buildAppleLinkButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        key: const Key('register_apple_button'),
        onPressed:
            _isLoading ? null : () => _linkWith('apple', SupabaseService.linkWithApple),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.black54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.apple, size: 24),
            const SizedBox(width: 12),
            Text(
              '使用 Apple 註冊',
              style: AppTypography.bodyLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleLinkButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        key: const Key('register_google_button'),
        onPressed: _isLoading
            ? null
            : () => _linkWith('google', SupabaseService.linkWithGoogle),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          side: const BorderSide(color: Colors.grey, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/images/google_logo.svg',
              width: 20,
              height: 20,
            ),
            const SizedBox(width: 12),
            Text(
              '使用 Google 註冊',
              style: AppTypography.bodyLarge.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    final ruleColor = Colors.white.withValues(alpha: 0.16);
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: ruleColor)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '或用 Email',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: ruleColor)),
      ],
    );
  }

  Widget _buildLabeledTextField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    TextInputType? keyboardType,
    bool obscureText = false,
    VoidCallback? onToggleObscureText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.bodyMedium.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          autocorrect: false,
          cursorColor: AppColors.ctaStart,
          style: AppTypography.bodyMedium.copyWith(color: Colors.white),
          decoration: brandInputDecoration(
            hintText: hintText,
            suffixIcon: onToggleObscureText == null
                ? null
                : IconButton(
                    onPressed: onToggleObscureText,
                    icon: Icon(
                      obscureText ? Icons.visibility : Icons.visibility_off,
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.7),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
