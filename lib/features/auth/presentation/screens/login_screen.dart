// lib/features/auth/presentation/screens/login_screen.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isSignUp = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _isIOS => !kIsWeb && Platform.isIOS;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await SupabaseService.signInWithGoogle();

      if (response.user != null) {
        // Ensure subscription exists for new users
        await SupabaseService.ensureSubscriptionExists(response.user!.id);

        if (mounted) {
          context.go('/');
        }
      }
    } on AuthException catch (e) {
      if (e.message.contains('cancel')) {
        // User cancelled, don't show error
        return;
      }
      setState(() => _error = 'Google 登入失敗：${e.message}');
    } catch (e) {
      setState(() => _error = 'Google 登入失敗，請稍後再試');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await SupabaseService.signInWithApple();

      if (response.user != null) {
        // Ensure subscription exists for new users
        await SupabaseService.ensureSubscriptionExists(response.user!.id);

        if (mounted) {
          context.go('/');
        }
      }
    } on AuthException catch (e) {
      if (e.message.contains('canceled') || e.message.contains('cancelled')) {
        // User cancelled, don't show error
        return;
      }
      setState(() => _error = 'Apple 登入失敗：${e.message}');
    } catch (e) {
      setState(() => _error = '登入失敗，請稍後再試');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = '請填寫 Email 和密碼');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_isSignUp) {
        await SupabaseService.signUpWithEmail(
          email: email,
          password: password,
        );
        setState(() {
          _error = '註冊成功！請查收驗證郵件後登入';
          _isSignUp = false;
        });
      } else {
        await SupabaseService.signInWithEmail(
          email: email,
          password: password,
        );
        if (mounted) {
          context.go('/');
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
                      '提升你的社交對話技巧',
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.onBackgroundSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // Third-party Sign In Buttons (iOS only, login mode)
                    if (_isIOS && !_isSignUp) ...[
                      _buildAppleSignInButton(),
                      const SizedBox(height: 12),
                      _buildGoogleSignInButton(),
                      const SizedBox(height: 24),
                      _buildDivider(),
                      const SizedBox(height: 24),
                    ],

                    Text(
                      _isSignUp ? '建立帳號' : '使用 Email ${_isSignUp ? '註冊' : '登入'}',
                      style: AppTypography.titleLarge.copyWith(
                        color: AppColors.onBackgroundPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Email 輸入框
                    _buildLabeledTextField(
                      label: 'Email',
                      controller: _emailController,
                      hintText: 'your@email.com',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),

                    // 密碼輸入框
                    _buildLabeledTextField(
                      label: '密碼',
                      controller: _passwordController,
                      hintText: '至少 6 個字元',
                      obscureText: true,
                    ),
                    const SizedBox(height: 24),

                    if (_error != null) ...[
                      GlassmorphicContainer(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          style: AppTypography.bodyMedium.copyWith(
                            color: _error!.contains('成功')
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    GradientButton(
                      text: _isSignUp ? '註冊' : '登入',
                      onPressed: _isLoading ? null : _submit,
                      isLoading: _isLoading,
                    ),
                    const SizedBox(height: 16),

                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isSignUp = !_isSignUp;
                          _error = null;
                        });
                      },
                      child: Text(
                        _isSignUp ? '已有帳號？登入' : '沒有帳號？註冊',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.onBackgroundSecondary,
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                    GlassmorphicContainer(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🧪 沙盒測試帳號',
                            style: AppTypography.titleMedium.copyWith(
                              color: AppColors.glassTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Email: vibesync.test@gmail.com\n密碼: test123456',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.glassTextHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
        Text(label, style: AppTypography.bodyMedium.copyWith(color: AppColors.onBackgroundPrimary)),
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
            style: AppTypography.bodyMedium.copyWith(color: AppColors.glassTextPrimary),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextHint,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              '使用 Apple 登入',
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
            // Official Google logo
            const FaIcon(
              FontAwesomeIcons.google,
              size: 20,
              color: Color(0xFF4285F4), // Google Blue
            ),
            const SizedBox(width: 12),
            Text(
              '使用 Google 登入',
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
}
