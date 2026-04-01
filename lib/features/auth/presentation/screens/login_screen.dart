import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/usage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/platform_info.dart';
import '../../../../shared/services/link_launch_service.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../subscription/data/providers/subscription_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  StreamSubscription<AuthState>? _authSubscription;

  bool _isLoading = false;
  bool _isSignUp = false;
  bool _isPasswordRecoveryMode = SupabaseService.isPasswordRecoveryInProgress;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  String? _errorMessage;
  String? _noticeMessage;
  String? _pendingVerificationEmail;

  bool get _isIOS => isIOSPlatform;
  bool get _hasPendingVerification =>
      (_pendingVerificationEmail ?? '').trim().isNotEmpty;

  void _invalidateSessionScopedProviders() {
    ref.invalidate(subscriptionProvider);
    ref.invalidate(conversationsProvider);
    ref.invalidate(usageDataProvider);
  }

  @override
  void initState() {
    super.initState();
    if (_isPasswordRecoveryMode) {
      _noticeMessage = '已驗證重設連結，請輸入新密碼完成設定。';
    }
    _authSubscription =
        SupabaseService.authStateChanges.listen(_handleAuthStateChange);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleAuthStateChange(AuthState authState) {
    if (!mounted) return;

    _invalidateSessionScopedProviders();

    if (authState.event == AuthChangeEvent.passwordRecovery) {
      _passwordController.clear();
      _confirmPasswordController.clear();

      setState(() {
        _isLoading = false;
        _isSignUp = false;
        _isPasswordRecoveryMode = true;
        _errorMessage = null;
        _noticeMessage = '已驗證重設連結，請輸入新密碼完成設定。';
        _pendingVerificationEmail = null;
      });
      return;
    }

    if (authState.event == AuthChangeEvent.signedOut &&
        _isPasswordRecoveryMode) {
      setState(() {
        _isPasswordRecoveryMode = false;
      });
    }
  }

  bool _isValidEmail(String value) {
    return _emailRegex.hasMatch(value.trim());
  }

  bool _isStrongSignupPassword(String value) {
    return value.length >= 8 &&
        RegExp(r'[A-Za-z]').hasMatch(value) &&
        RegExp(r'\d').hasMatch(value);
  }

  String? _validateRecoveryForm({
    required String password,
    required String confirmPassword,
  }) {
    if (password.isEmpty || confirmPassword.isEmpty) {
      return '請輸入並再次確認新密碼。';
    }

    if (!_isStrongSignupPassword(password)) {
      return '請使用至少 8 個字元，且同時包含英文字母與數字。';
    }

    if (password != confirmPassword) {
      return '兩次輸入的密碼不一致。';
    }

    return null;
  }

  bool _isCancellationError(Object error) {
    final normalized = error.toString().toLowerCase();
    return normalized.contains('cancel') ||
        normalized.contains('canceled') ||
        normalized.contains('cancelled');
  }

  void _setError(String message) {
    setState(() {
      _errorMessage = message;
      _noticeMessage = null;
    });
  }

  void _setNotice(String message) {
    setState(() {
      _noticeMessage = message;
      _errorMessage = null;
    });
  }

  String? _validateForm({
    required String email,
    required String password,
    required bool isSignUp,
  }) {
    if (email.isEmpty || password.isEmpty) {
      return '請輸入 Email 和密碼。';
    }

    if (!_isValidEmail(email)) {
      return '請輸入有效的 Email。';
    }

    if (isSignUp && !_isStrongSignupPassword(password)) {
      return '請使用至少 8 個字元，且同時包含英文字母與數字。';
    }

    return null;
  }

  String _mapAuthError(
    AuthException error, {
    required bool isSignUp,
    String? providerLabel,
    String? fallbackMessage,
  }) {
    final message = error.message.toLowerCase();
    final email = _emailController.text.trim();

    if (message.contains('invalid login credentials')) {
      return 'Email 或密碼錯誤。';
    }

    if (message.contains('email not confirmed') ||
        message.contains('email_not_confirmed')) {
      if (_isValidEmail(email)) {
        _pendingVerificationEmail = email;
      }
      return '請先完成 Email 驗證再登入。';
    }

    if (message.contains('user already registered')) {
      if (_isValidEmail(email)) {
        _pendingVerificationEmail = email;
      }
      return isSignUp ? '這個 Email 已註冊，請直接登入或重新寄送驗證信。' : '這個 Email 已註冊。';
    }

    if (message.contains('weak password')) {
      return '密碼至少 8 個字元，且需包含英文字母與數字。';
    }

    if (message.contains('same_password') ||
        message.contains('same password') ||
        message.contains('password should be different')) {
      return '請改用最近未使用過的新密碼。';
    }

    if (message.contains('rate limit') || error.statusCode == '429') {
      return '嘗試次數過多，請稍候再試。';
    }

    if (message.contains('invalid callback url')) {
      return '登入回呼失敗，請再試一次。';
    }

    if (providerLabel != null) {
      return '$providerLabel 登入失敗，請再試一次。';
    }

    return fallbackMessage ?? (isSignUp ? '建立帳號失敗，請再試一次。' : '登入失敗，請再試一次。');
  }

  Future<void> _handleSuccessfulLogin(User user) async {
    await SupabaseService.ensureSubscriptionExists(user.id);
    if (!mounted) return;

    SupabaseService.clearPasswordRecoveryState();
    setState(() {
      _isPasswordRecoveryMode = false;
      _pendingVerificationEmail = null;
      _errorMessage = null;
      _noticeMessage = null;
    });
    _passwordController.clear();
    _confirmPasswordController.clear();
    _invalidateSessionScopedProviders();
    context.go('/');
  }

  Future<void> _resendVerificationEmail() async {
    final email = (_pendingVerificationEmail ?? _emailController.text).trim();

    if (!_isValidEmail(email)) {
      _setError('請先輸入有效的 Email 再重新寄送驗證信。');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      await SupabaseService.resendSignUpConfirmation(email: email);
      if (!mounted) return;
      setState(() {
        _pendingVerificationEmail = email;
      });
      _setNotice(
        '驗證信已重新寄出，請到信箱查看，並用安裝 App 的手機開啟連結。',
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      _setError(_mapAuthError(e, isSignUp: true));
    } catch (_) {
      if (!mounted) return;
      _setError('重新寄送驗證信失敗，請再試一次。');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    final email = _emailController.text.trim();

    if (!_isValidEmail(email)) {
      _setError('請先輸入有效的 Email 再重設密碼。');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      await SupabaseService.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      _setNotice(
        '如果這個 Email 已註冊，我們已寄出重設密碼連結；請在這台裝置上開啟。',
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      final message = e.message.toLowerCase();
      if (message.contains('rate limit') || e.statusCode == '429') {
        _setError('重設密碼請求過多，請稍候再試。');
      } else {
        _setNotice(
          '如果這個 Email 已註冊，我們已寄出重設密碼連結；請在這台裝置上開啟。',
        );
      }
    } catch (_) {
      if (!mounted) return;
      _setError('寄送重設密碼信失敗，請再試一次。');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _completePasswordRecovery() async {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final validationError = _validateRecoveryForm(
      password: password,
      confirmPassword: confirmPassword,
    );

    if (validationError != null) {
      _setError(validationError);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      await SupabaseService.updatePassword(password: password);
      final user = SupabaseService.currentUser;

      if (user != null) {
        await _handleSuccessfulLogin(user);
        return;
      }

      SupabaseService.clearPasswordRecoveryState();
      if (!mounted) return;
      context.go('/');
    } on AuthException catch (e) {
      if (!mounted) return;
      _setError(
        _mapAuthError(
          e,
          isSignUp: true,
          fallbackMessage: '更新密碼失敗，請再試一次。',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _setError('更新密碼失敗，請再試一次。');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      final response = await SupabaseService.signInWithGoogle();
      if (response.user != null) {
        await _handleSuccessfulLogin(response.user!);
      }
    } on AuthException catch (e) {
      if (_isCancellationError(e)) {
        return;
      }
      if (!mounted) return;
      _setError(
        _mapAuthError(
          e,
          isSignUp: false,
          providerLabel: 'Google',
        ),
      );
    } catch (e) {
      if (_isCancellationError(e)) {
        return;
      }
      if (!mounted) return;
      _setError('Google 登入失敗，請再試一次。');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      final response = await SupabaseService.signInWithApple();
      if (response.user != null) {
        await _handleSuccessfulLogin(response.user!);
      }
    } on AuthException catch (e) {
      if (_isCancellationError(e)) {
        return;
      }
      if (!mounted) return;
      _setError(
        _mapAuthError(
          e,
          isSignUp: false,
          providerLabel: 'Apple',
        ),
      );
    } catch (e) {
      if (_isCancellationError(e)) {
        return;
      }
      if (!mounted) return;
      _setError('Apple 登入失敗，請再試一次。');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_isPasswordRecoveryMode) {
      await _completePasswordRecovery();
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final validationError = _validateForm(
      email: email,
      password: password,
      isSignUp: _isSignUp,
    );

    if (validationError != null) {
      _setError(validationError);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      if (_isSignUp) {
        final response = await SupabaseService.signUpWithEmail(
          email: email,
          password: password,
        );
        final identities = response.user?.identities ?? const [];
        final looksLikeExistingPendingUser =
            response.user != null &&
            response.session == null &&
            identities.isEmpty;

        if (response.user != null && response.session != null) {
          await _handleSuccessfulLogin(response.user!);
          return;
        }

        if (!mounted) return;
        setState(() {
          _pendingVerificationEmail = email;
          _isSignUp = false;
        });
        _setNotice(
          looksLikeExistingPendingUser
              ? '這個 Email 可能已經註冊，或之前的驗證流程還沒完成。請先到信箱找驗證信；如果沒收到，可以點下方重新寄送。驗證連結請用安裝 App 的手機開啟。'
              : '驗證信已寄出，請到信箱查看，並用安裝 App 的手機開啟連結。若 1-2 分鐘內沒收到，可以點下方重新寄送驗證信。',
        );
        return;
      }

      final response = await SupabaseService.signInWithEmail(
        email: email,
        password: password,
      );

      if (response.user != null) {
        await _handleSuccessfulLogin(response.user!);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      _setError(_mapAuthError(e, isSignUp: _isSignUp));
    } catch (_) {
      if (!mounted) return;
      _setError(
        _isSignUp ? '建立帳號失敗，請再試一次。' : '登入失敗，請再試一次。',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final launched = await LinkLaunchService.open(url);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前無法開啟連結，請稍後再試。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final headline = _isPasswordRecoveryMode
        ? '設定新密碼'
        : _isSignUp
            ? '建立帳號'
            : 'Email 登入';
    final primaryButtonText = _isPasswordRecoveryMode
        ? '更新密碼'
        : _isSignUp
            ? '建立帳號'
            : '登入';

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    Text(
                      'VibeSync',
                      style: AppTypography.headlineLarge.copyWith(
                        color: AppColors.onBackgroundPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '讓每段對話更有節奏，也更有自信。',
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.onBackgroundSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    if (_isIOS && !_isSignUp && !_isPasswordRecoveryMode) ...[
                      _buildGoogleSignInButton(),
                      const SizedBox(height: 12),
                      _buildAppleSignInButton(),
                      const SizedBox(height: 24),
                      _buildDivider(),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      headline,
                      style: AppTypography.titleLarge.copyWith(
                        color: AppColors.onBackgroundPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_isPasswordRecoveryMode) ...[
                      _buildLabeledTextField(
                        label: 'Email',
                        controller: _emailController,
                        hintText: 'you@example.com',
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildLabeledTextField(
                      label: _isPasswordRecoveryMode ? '新密碼' : '密碼',
                      controller: _passwordController,
                      hintText: _isPasswordRecoveryMode || _isSignUp
                          ? '至少 8 個字元，需包含英文字母與數字'
                          : '請輸入密碼',
                      obscureText: !_isPasswordVisible,
                      onToggleObscureText: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                    if (_isPasswordRecoveryMode) ...[
                      const SizedBox(height: 16),
                      _buildLabeledTextField(
                        label: '確認新密碼',
                        controller: _confirmPasswordController,
                        hintText: '再次輸入新密碼',
                        obscureText: !_isConfirmPasswordVisible,
                        onToggleObscureText: () {
                          setState(() {
                            _isConfirmPasswordVisible =
                                !_isConfirmPasswordVisible;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '請設定一組這台裝置上也方便記住的新密碼。',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.onBackgroundSecondary,
                        ),
                      ),
                    ] else if (_isSignUp) ...[
                      const SizedBox(height: 12),
                      Text(
                        '我們會寄送 Email 驗證連結，請使用這台裝置可存取的信箱。',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.onBackgroundSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (_errorMessage != null) ...[
                      _buildMessageCard(
                        message: _errorMessage!,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_noticeMessage != null) ...[
                      _buildMessageCard(
                        message: _noticeMessage!,
                        color: AppColors.success,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_hasPendingVerification && !_isSignUp) ...[
                      TextButton(
                        onPressed: _isLoading ? null : _resendVerificationEmail,
                        child: const Text('重新寄送驗證信'),
                      ),
                      const SizedBox(height: 8),
                    ],
                    GradientButton(
                      text: primaryButtonText,
                      onPressed: _isLoading ? null : _submit,
                      isLoading: _isLoading,
                    ),
                    const SizedBox(height: 12),
                    if (!_isSignUp && !_isPasswordRecoveryMode)
                      TextButton(
                        onPressed: _isLoading ? null : _sendPasswordResetEmail,
                        child: const Text('忘記密碼？'),
                      ),
                    if (!_isSignUp && !_isPasswordRecoveryMode)
                      TextButton(
                        onPressed: _isLoading ? null : _resendVerificationEmail,
                        child: const Text('需要重新寄送驗證信？'),
                      ),
                    if (!_isPasswordRecoveryMode)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isSignUp = !_isSignUp;
                            _errorMessage = null;
                            _noticeMessage = null;
                            if (_isSignUp) {
                              _pendingVerificationEmail = null;
                            }
                          });
                        },
                        child: Text(
                          _isSignUp ? '已經有帳號了？登入' : '還沒有帳號？建立帳號',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.onBackgroundSecondary,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    _buildLegalDisclaimer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageCard({
    required String message,
    required Color color,
  }) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(12),
      child: Text(
        message,
        style: AppTypography.bodyMedium.copyWith(color: color),
      ),
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
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.onBackgroundPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder, width: 1.5),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            autocorrect: false,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextPrimary,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextHint,
              ),
              suffixIcon: onToggleObscureText == null
                  ? null
                  : IconButton(
                      onPressed: onToggleObscureText,
                      icon: Icon(
                        obscureText ? Icons.visibility : Icons.visibility_off,
                        color: AppColors.glassTextHint,
                      ),
                    ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppleSignInButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signInWithApple,
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
              '使用 Apple 繼續',
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

  Widget _buildGoogleSignInButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
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
              '使用 Google 繼續',
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
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.glassBorder,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '或',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.glassBorder,
          ),
        ),
      ],
    );
  }

  Widget _buildLegalDisclaimer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text.rich(
        TextSpan(
          style: AppTypography.caption.copyWith(
            color: AppColors.onBackgroundSecondary,
          ),
          children: [
            const TextSpan(text: '繼續即表示你同意 '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => _launchUrl('https://vibesyncai.app/terms'),
                child: Text(
                  '服務條款',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const TextSpan(text: ' 與 '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => _launchUrl('https://vibesyncai.app/privacy'),
                child: Text(
                  '隱私權政策',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const TextSpan(text: '。'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
