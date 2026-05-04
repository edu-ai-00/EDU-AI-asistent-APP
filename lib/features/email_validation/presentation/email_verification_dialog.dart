import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/email_validation_providers.dart';

/// Dialog for email verification with support for two flows:
/// 1. Guest users (email is empty): Enter email → Send code → Enter PIN → Verify
/// 2. Registered users (email exists): Show email → Send code → Enter PIN → Verify
class EmailVerificationDialog extends ConsumerStatefulWidget {
  final String email;

  const EmailVerificationDialog({
    super.key,
    required this.email,
  });

  @override
  ConsumerState<EmailVerificationDialog> createState() => _EmailVerificationDialogState();
}

class _EmailVerificationDialogState extends ConsumerState<EmailVerificationDialog> {
  final List<TextEditingController> _pinControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final TextEditingController _emailController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();

  late bool _isGuest;
  late String _activeEmail;

  @override
  void initState() {
    super.initState();
    _isGuest = widget.email.isEmpty;
    _activeEmail = widget.email;
    _emailController.text = widget.email;
    // Reset provider state so the dialog always starts fresh
    // (e.g. after a previous successful verification left state as Success).
    ref.read(emailVerificationProvider.notifier).reset();
  }

  @override
  void dispose() {
    for (final controller in _pinControllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    _emailController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  String get _pin => _pinControllers.map((c) => c.text).join();

  bool get _isEmailValid {
    final email = _emailController.text.trim();
    return email.contains('@') && email.contains('.');
  }

  void _onPinChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
  }

  void _handleKeyPress(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _pinControllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  void _clearPinFields() {
    for (final controller in _pinControllers) {
      controller.clear();
    }
    _focusNodes[0].requestFocus();
  }

  void _handleSendCode() {
    _activeEmail = _emailController.text.trim();
    ref.read(emailVerificationProvider.notifier).sendCode(_activeEmail);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(emailVerificationProvider);

    // Listen for state changes
    ref.listen(emailVerificationProvider, (previous, current) {
      if (current is EmailVerificationSuccess) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isGuest
                  ? AppStrings.dialogRegistrationSuccess
                  : AppStrings.dialogEmailVerified,
              style: AppTextStyles.bodySmall(),
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: AppDecorations.radiusS,
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      } else if (current is EmailVerificationError) {
        // Clear PIN fields on error for retry
        if (current.type == EmailVerificationErrorType.invalidCode) {
          _clearPinFields();
        }
      }
    });

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: AppDecorations.radiusXL,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.bannerOrange16,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_add_outlined,
                    color: AppColors.bannerOrangeDark,
                    size: 24,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    ref.read(emailVerificationProvider.notifier).reset();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.close),
                  color: AppColors.primaryDark48,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              _isGuest ? AppStrings.dialogRegistration : AppStrings.dialogEmailVerification,
              style: AppTextStyles.heading3(),
            ),
            const SizedBox(height: 8),

            // Subtitle — only show email for non-guests when not in initial state
            if (!_isGuest && state is! EmailVerificationInitial)
              Text(
                _activeEmail,
                style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
              ),
            if (!_isGuest && state is! EmailVerificationInitial)
              const SizedBox(height: 24),

            // Content based on state
            _buildContent(state),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(EmailVerificationState state) {
    return switch (state) {
      EmailVerificationInitial() => _isGuest
          ? _buildEmailInputStep()
          : _buildSendCodeStep(),
      EmailVerificationLoading(:final message) => _buildLoadingStep(message),
      EmailVerificationCodeSent() => _buildEnterCodeStep(),
      EmailVerificationError(:final type, :final message) => _buildErrorStep(type, message),
      EmailVerificationSuccess() => const SizedBox.shrink(),
    };
  }

  /// Step for guest users: enter email address first
  Widget _buildEmailInputStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.dialogEmailInputPrompt,
          style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailController,
          focusNode: _emailFocusNode,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: AppTextStyles.bodyLarge(),
          decoration: InputDecoration(
            hintText: AppStrings.dialogEmailHint,
            hintStyle: AppTextStyles.bodyLarge(color: AppColors.primaryDark32),
            prefixIcon: Icon(
              Icons.mail_outline,
              color: AppColors.primaryDark48,
            ),
            border: OutlineInputBorder(
              borderRadius: AppDecorations.radiusM,
              borderSide: BorderSide(
                color: AppColors.primaryDark16,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppDecorations.radiusM,
              borderSide: BorderSide(
                color: AppColors.primaryDark16,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppDecorations.radiusM,
              borderSide: BorderSide(
                color: AppColors.primaryDark,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: _isEmailValid ? (_) => _handleSendCode() : null,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isEmailValid ? _handleSendCode : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primaryDark32,
              disabledForegroundColor: Colors.white.withValues(alpha: 0.48),
              shape: RoundedRectangleBorder(
                borderRadius: AppDecorations.radiusM,
              ),
              elevation: 0,
            ),
            child: Text(
              AppStrings.actionContinue,
              style: AppTextStyles.buttonLarge(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSendCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _activeEmail,
          style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.dialogSendCodePrompt,
          style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: () {
              ref.read(emailVerificationProvider.notifier).sendCode(_activeEmail);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: AppDecorations.radiusM,
              ),
              elevation: 0,
            ),
            child: Text(
              AppStrings.dialogSendCode,
              style: AppTextStyles.buttonLarge(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingStep(String message) {
    return Column(
      children: [
        const SizedBox(height: 24),
        CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryDark),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildEnterCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.dialogEnterCode,
          style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
        ),
        const SizedBox(height: 16),

        // PIN input fields
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 44,
              height: 52,
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) => _handleKeyPress(index, event),
                child: TextField(
                  controller: _pinControllers[index],
                  focusNode: _focusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: AppTextStyles.cardTitleAlt(),
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: AppDecorations.radiusS,
                      borderSide: BorderSide(
                        color: AppColors.primaryDark16,
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppDecorations.radiusS,
                      borderSide: BorderSide(
                        color: AppColors.primaryDark16,
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppDecorations.radiusS,
                      borderSide: BorderSide(
                        color: AppColors.primaryDark,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (value) => _onPinChanged(index, value),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),

        // Verify button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _pin.length == 6
                ? () {
                    ref.read(emailVerificationProvider.notifier).verifyCode(_pin);
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primaryDark32,
              disabledForegroundColor: Colors.white.withValues(alpha: 0.48),
              shape: RoundedRectangleBorder(
                borderRadius: AppDecorations.radiusM,
              ),
              elevation: 0,
            ),
            child: Text(
              AppStrings.emailVerificationVerify,
              style: AppTextStyles.buttonLarge(color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Resend code link
        Center(
          child: TextButton(
            onPressed: () {
              ref.read(emailVerificationProvider.notifier).resendCode();
            },
            child: Text(
              AppStrings.emailVerificationResend,
              style: AppTextStyles.bodySmall(color: AppColors.primaryDark64).copyWith(
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorStep(EmailVerificationErrorType type, String message) {
    final showRetryCodeEntry = type == EmailVerificationErrorType.invalidCode;
    final showResendOption = type == EmailVerificationErrorType.codeExpired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Error message
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error08,
            borderRadius: AppDecorations.radiusS,
          ),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: AppTextStyles.bodySmall(color: AppColors.error),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Show code entry if invalid code
        if (showRetryCodeEntry) ...[
          Text(
            AppStrings.dialogEnterCode,
            style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
          ),
          const SizedBox(height: 16),

          // PIN input fields
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              return SizedBox(
                width: 44,
                height: 52,
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) => _handleKeyPress(index, event),
                  child: TextField(
                    controller: _pinControllers[index],
                    focusNode: _focusNodes[index],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    style: AppTextStyles.cardTitleAlt(),
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: AppDecorations.radiusS,
                        borderSide: BorderSide(
                          color: AppColors.error32,
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppDecorations.radiusS,
                        borderSide: BorderSide(
                          color: AppColors.error32,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: AppDecorations.radiusS,
                        borderSide: BorderSide(
                          color: AppColors.primaryDark,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (value) => _onPinChanged(index, value),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),

          // Verify button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _pin.length == 6
                  ? () {
                      ref.read(emailVerificationProvider.notifier).verifyCode(_pin);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.primaryDark32,
                disabledForegroundColor: Colors.white.withValues(alpha: 0.48),
                shape: RoundedRectangleBorder(
                  borderRadius: AppDecorations.radiusM,
                ),
                elevation: 0,
              ),
              child: Text(
                AppStrings.emailVerificationRetry,
                style: AppTextStyles.buttonLarge(color: Colors.white),
              ),
            ),
          ),
        ],

        // Show resend option if code expired
        if (showResendOption) ...[
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                ref.read(emailVerificationProvider.notifier).resendCode();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: AppDecorations.radiusM,
                ),
                elevation: 0,
              ),
              child: Text(
                AppStrings.dialogSendNewCode,
                style: AppTextStyles.buttonLarge(color: Colors.white),
              ),
            ),
          ),
        ],

        // Show general retry for other errors
        if (!showRetryCodeEntry && !showResendOption) ...[
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                ref.read(emailVerificationProvider.notifier).reset();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: AppDecorations.radiusM,
                ),
                elevation: 0,
              ),
              child: Text(
                AppStrings.emailVerificationRetry,
                style: AppTextStyles.buttonLarge(color: Colors.white),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
