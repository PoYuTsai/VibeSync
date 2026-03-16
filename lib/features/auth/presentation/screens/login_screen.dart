import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/platform_info.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
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

  StreamSubscription<AuthState>? _authSubscription;

  bool _isLoading = false;
  bool _isSignUp = false;
  String? _errorMessage;
  String? _noticeMessage;
  String? _pendingVerificationEmail;

  bool get _isIOS => isIOSPlatform;
  bool get _hasPendingVerification =>
      (_pendingVerificationEmail ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _authSubscription = SupabaseService.authStateChanges.listen((_) {
      if (!mounted) return;
      ref.invalidate(subscriptionProvider);
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String value) {
    return _emailRegex.hasMatch(value.trim());
  }

  bool _isStrongSignupPassword(String value) {
    return value.length >= 8 &&
        RegExp(r'[A-Za-z]').hasMatch(value) &&
        RegExp(r'\d').hasMatch(value);
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
      return 'Email and password are required.';
    }

    if (!_isValidEmail(email)) {
      return 'Please enter a valid email address.';
    }

    if (isSignUp && !_isStrongSignupPassword(password)) {
      return 'Use at least 8 characters with both letters and numbers.';
    }

    return null;
  }

  String _mapAuthError(
    AuthException error, {
    required bool isSignUp,
    String? providerLabel,
  }) {
    final message = error.message.toLowerCase();
    final email = _emailController.text.trim();

    if (message.contains('invalid login credentials')) {
      return 'Invalid email or password.';
    }

    if (message.contains('email not confirmed') ||
        message.contains('email_not_confirmed')) {
      if (_isValidEmail(email)) {
        _pendingVerificationEmail = email;
      }
      return 'Please verify your email before signing in.';
    }

    if (message.contains('user already registered')) {
      if (_isValidEmail(email)) {
        _pendingVerificationEmail = email;
      }
      return isSignUp
          ? 'This email is already registered. Try signing in or resend verification email.'
          : 'This email is already registered.';
    }

    if (message.contains('weak password')) {
      return 'Password must be at least 8 characters and include letters and numbers.';
    }

    if (message.contains('rate limit') || error.statusCode == '429') {
      return 'Too many attempts. Please wait a moment and try again.';
    }

    if (message.contains('invalid callback url')) {
      return 'Sign-in callback failed. Please try again.';
    }

    if (providerLabel != null) {
      return '$providerLabel sign-in failed. Please try again.';
    }

    return isSignUp
        ? 'Could not create your account. Please try again.'
        : 'Sign-in failed. Please try again.';
  }

  Future<void> _handleSuccessfulLogin(User user) async {
    await SupabaseService.ensureSubscriptionExists(user.id);
    if (!mounted) return;

    setState(() {
      _pendingVerificationEmail = null;
    });
    ref.invalidate(subscriptionProvider);
    context.go('/');
  }

  Future<void> _resendVerificationEmail() async {
    final email = (_pendingVerificationEmail ?? _emailController.text).trim();

    if (!_isValidEmail(email)) {
      _setError('Enter a valid email before resending verification.');
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
      _setNotice('Verification email sent again. Please check your inbox.');
    } on AuthException catch (e) {
      if (!mounted) return;
      _setError(_mapAuthError(e, isSignUp: true));
    } catch (_) {
      if (!mounted) return;
      _setError('Could not resend verification email. Please try again.');
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
      _setError('Google sign-in failed. Please try again.');
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
      _setError('Apple sign-in failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submit() async {
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

        if (response.user != null && response.session != null) {
          await _handleSuccessfulLogin(response.user!);
          return;
        }

        if (!mounted) return;
        setState(() {
          _pendingVerificationEmail = email;
          _isSignUp = false;
        });
        _setNotice('Verification email sent. Please check your inbox.');
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
        _isSignUp
            ? 'Could not create your account. Please try again.'
            : 'Sign-in failed. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      'Sharpen every conversation with more confidence.',
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.onBackgroundSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    if (_isIOS && !_isSignUp) ...[
                      _buildGoogleSignInButton(),
                      const SizedBox(height: 12),
                      _buildAppleSignInButton(),
                      const SizedBox(height: 24),
                      _buildDivider(),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      _isSignUp ? 'Create account' : 'Sign in with email',
                      style: AppTypography.titleLarge.copyWith(
                        color: AppColors.onBackgroundPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildLabeledTextField(
                      label: 'Email',
                      controller: _emailController,
                      hintText: 'you@example.com',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    _buildLabeledTextField(
                      label: 'Password',
                      controller: _passwordController,
                      hintText: _isSignUp
                          ? 'At least 8 characters with letters and numbers'
                          : 'Enter your password',
                      obscureText: true,
                    ),
                    if (_isSignUp) ...[
                      const SizedBox(height: 12),
                      Text(
                        'We support email verification links, so use an inbox you can access on this device.',
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
                        child: const Text('Resend verification email'),
                      ),
                      const SizedBox(height: 8),
                    ],
                    GradientButton(
                      text: _isSignUp ? 'Create account' : 'Sign in',
                      onPressed: _isLoading ? null : _submit,
                      isLoading: _isLoading,
                    ),
                    const SizedBox(height: 12),
                    if (!_isSignUp)
                      TextButton(
                        onPressed: _isLoading ? null : _resendVerificationEmail,
                        child: const Text('Need a new verification email?'),
                      ),
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
                        _isSignUp
                            ? 'Already have an account? Sign in'
                            : 'Need an account? Create one',
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
              'Continue with Apple',
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
              'Continue with Google',
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
            'or',
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
            const TextSpan(text: 'By continuing, you agree to the '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => _launchUrl('https://vibesyncai.app/terms'),
                child: Text(
                  'Terms of Service',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const TextSpan(text: ' and '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => _launchUrl('https://vibesyncai.app/privacy'),
                child: Text(
                  'Privacy Policy',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const TextSpan(text: '.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
